extends RefCounted
class_name PressureSpawns
## Extra encounters use the production actors, maps and physical perception.
## Every call is bounded; unavailable terrain simply defers the encounter.
const RAKER_SCENE := preload("res://enemies/raker.tscn")
const GIANT_SCENE := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const MAX_CANDIDATES := 24
const RAKER_CAP := 8
const NAV_TOLERANCE := 1.5
const POI_CLEARANCE := 12.0
const SUPPORT_EPSILON := 0.003

static func raker_count(owner: Node3D) -> int:
	var count := 0
	if not is_instance_valid(owner) or not owner.is_inside_tree(): return count
	for actor in owner.get_tree().get_nodes_in_group(Groups.MONSTERS):
		if actor is Raker and WorldEntities.same_world(owner, actor) and not actor.is_dead and not actor.is_queued_for_deletion(): count += 1
	return count

static func giant_present(owner: Node3D) -> bool:
	if not is_instance_valid(owner) or not owner.is_inside_tree(): return false
	# Ambient spawning reserves the slot for any nonqueued giant, including
	# a disabled/restored one. Pressure spawning shares exactly that slot.
	for actor in owner.get_tree().get_nodes_in_group("slender_speaker"):
		if actor is Node3D and WorldEntities.same_world(owner, actor) and not actor.is_queued_for_deletion(): return true
	return false

static func try_spawn(owner: Node3D, kind: String, sample: Dictionary, rng: RandomNumberGenerator) -> bool:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or rng == null or kind not in ["raker", "giant"]: return false
	var giant := kind == "giant"
	if giant_present(owner) if giant else raker_count(owner) >= RAKER_CAP: return false
	var generator := owner.get_node_or_null("WorldGenerator")
	var player := sample.get("target", owner.get_node_or_null("Player")) as Node3D
	if generator == null or generator.get("field") == null or not WorldEntities.same_world(owner, player): return false
	var field: WorldField = generator.field
	var anchor: Vector3 = sample.get("point", player.global_position)
	var danger: Vector3 = sample.get("danger_direction", Vector3.ZERO)
	danger = danger.slide(Vector3.UP).normalized()
	if not anchor.is_finite() or danger.length_squared() < .5: return false
	var map: RID = generator.giant_navigation_map if giant else owner.get_world_3d().navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0: return false
	var camera := owner.get_viewport().get_camera_3d()
	if camera == null: return false
	var scene: PackedScene = GIANT_SCENE if giant else RAKER_SCENE
	var template := scene.instantiate() as Monster
	var collision := template.get_node("CollisionShape") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D
	var local_bounds := mesh_bounds(template)
	var foot := collision.position.y - capsule.height * .5
	var targets := _contact_targets(owner, player)
	var destinations := _destinations(owner, player, targets, map, capsule.radius)
	var fog_end := effective_fog_end(owner)
	var space := owner.get_world_3d().direct_space_state
	for attempt in MAX_CANDIDATES:
		var direction := danger.rotated(Vector3.UP, rng.randf_range(-deg_to_rad(75.0), deg_to_rad(75.0)))
		var candidate := anchor + direction * rng.randf_range(120.0 if giant else 20.0, 160.0 if giant else 24.0)
		candidate.y = field.height_at(candidate.x, candidate.z)
		if not static_valid(field, candidate, capsule.radius) or not _band_ready(generator, candidate, giant): continue
		var projected := NavigationServer3D.map_get_closest_point(map, candidate)
		if planar_distance(projected, candidate) > NAV_TOLERANCE or not static_valid(field, projected, capsule.radius): continue
		if not _band_ready(generator, projected, giant) or (projected - anchor).slide(Vector3.UP).dot(danger) <= 0.0: continue
		var ground := support(space, projected, capsule.radius, foot)
		if ground.is_empty(): continue
		var point: Vector3 = ground.point
		var distance := planar_distance(point, anchor)
		if distance < (120.0 if giant else 20.0) or distance > (160.0 if giant else 24.0): continue
		if not _spacing(owner, point, 12.0 if giant else 3.0): continue
		var facing := (player.global_position - point).slide(Vector3.UP)
		if facing.length_squared() < .001: continue
		var transform := Transform3D(Basis.looking_at(facing.normalized(), Vector3.UP), point)
		if not hidden_bounds(camera, transform * local_bounds, fog_end): continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = transform * collision.transform
		query.collision_mask = template.collision_mask
		query.margin = 0.0
		if not space.intersect_shape(query, 1).is_empty(): continue
		if not connected_path(map, projected, destinations): continue
		if not _potential_sight(space, point, targets, giant): continue
		# No asynchronous gap between the shared slot check and insertion.
		if giant_present(owner) if giant else raker_count(owner) >= RAKER_CAP: break
		var actor := scene.instantiate() as Monster
		var container := WorldEntities.get_container(owner)
		actor.transform = container.global_transform.affine_inverse() * transform
		if giant: actor.set_giant_navigation_map(map)
		container.add_child(actor)
		var sensed := false
		if giant:
			sensed = actor.can_see_player(player)
			for target in targets:
				if target is Chassis and actor._visible_vehicle_point(target) != Vector3.INF: sensed = true
		else:
			for target in targets:
				if point.distance_to(target.global_position) <= actor.detection_range and actor._has_attack_line_of_sight_to_target(target): sensed = true
		if not sensed:
			actor.free()
			continue
		actor.set_meta("pressure_spawn", true)
		template.free()
		return true
	template.free()
	return false

static func planar_distance(a: Vector3, b: Vector3) -> float:
	return a.slide(Vector3.UP).distance_to(b.slide(Vector3.UP))

static func static_valid(field: WorldField, point: Vector3, radius: float) -> bool:
	if not point.is_finite() or absf(point.x) + radius >= field.profile.terrain_half_width: return false
	if field.normal_at(point.x, point.z).y < cos(deg_to_rad(35.0)): return false
	var road := field.road_query(point.x, point.z)
	if road.distance < road.width * .5 + radius + 1.0: return false
	for site in field.sites_near_z(point.z, 400.0):
		if _site_clearance(point, site, radius): return false
	return true

static func _site_clearance(point: Vector3, site: Dictionary, radius: float) -> bool:
	# Course terrain bounds can be hundreds of metres wide. Only the actual
	# authored POI footprint and its real approach/trail reserve spawn space.
	if site.get("kind", "") not in ["entrance", "walk_in"] and not site.has("definition_id"): return false
	var definition := POIConfig.definition_for_site(site)
	if definition == null or not site.get("building") is Transform3D: return false
	var building: Transform3D = site.building
	var local := building.affine_inverse() * Vector3(point.x, building.origin.y, point.z)
	var box := definition.site_bounds
	var nearest := Vector3(clampf(local.x, box.position.x, box.end.x), local.y, clampf(local.z, box.position.z, box.end.z))
	var clearance := POI_CLEARANCE + radius
	if planar_distance(local, nearest) <= clearance: return true
	if not site.get("road") is Transform3D: return false
	var road: Transform3D = site.road
	if site.get("route") is PackedVector3Array:
		var route: PackedVector3Array = site.route
		if ExplorationSite.route_distance(point, route) <= clearance: return true
		if not route.is_empty() and RoutePressureSample._segment_distance(point, road.origin, route[0]) <= clearance: return true
	elif site.get("frame") is Transform3D:
		var frame: Transform3D = site.frame
		if RoutePressureSample._segment_distance(point, road.origin, frame.origin) <= clearance or RoutePressureSample._segment_distance(point, frame.origin, building.origin) <= clearance: return true
	return false

static func _band_ready(generator: Node, point: Vector3, giant: bool) -> bool:
	var band := floori(-point.z / generator.field.profile.chunk_length)
	for entry in generator.active_chunks:
		if int(entry.index) != band: continue
		var chunk: Node = entry.node
		var region: NavigationRegion3D = chunk.giant_navigation if giant else chunk.navigation
		return is_instance_valid(chunk) and chunk.navigation_ready and (not giant or chunk.giant_navigation_ready) and region != null and region.enabled and NavigationServer3D.region_get_iteration_id(region.get_region_rid()) > 0
	return false

static func support(space: PhysicsDirectSpaceState3D, point: Vector3, radius: float, foot: float) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 6.0, point - Vector3.UP * 8.0, 1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < cos(deg_to_rad(35.0)): return {}
	# Floor height comes from the physical floor, never a simplified nav mesh.
	# The lower capsule hemisphere rests tangent to the physical slope.
	var floor_point: Vector3 = hit.position
	return {"point": floor_point + Vector3.UP * (-foot + radius * (1.0 / hit.normal.y - 1.0) + SUPPORT_EPSILON), "floor": floor_point}

static func connected_path(map: RID, from: Vector3, destinations: Array[Vector3]) -> bool:
	for destination in destinations:
		var path := NavigationServer3D.map_get_path(map, from, destination, true)
		if path.size() >= 2 and planar_distance(path[0], from) <= NAV_TOLERANCE and planar_distance(path[-1], destination) <= NAV_TOLERANCE: return true
	return false

static func hidden_bounds(camera: Camera3D, bounds: AABB, fog_end: float) -> bool:
	if camera == null or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size == Vector3.ZERO: return false
	# Reject only when one plane excludes every corner: corner-only point
	# visibility can miss a large box that crosses the camera frustum.
	var corners: Array[Vector3] = []
	for index in 8: corners.append(bounds.get_endpoint(index))
	for plane in camera.get_frustum():
		var outside := true
		for corner in corners:
			if plane.distance_to(corner) <= 0.0:
				outside = false
				break
		if outside: return true
	if fog_end < 0.0 or not is_finite(fog_end): return false
	# Depth fog is measured along camera forward; Euclidean distance can
	# wrongly hide a model beside the camera whose nearest edge is visible.
	for corner in corners:
		if (-camera.global_basis.z).dot(corner - camera.global_position) <= fog_end + 10.0: return false
	return true

static func effective_fog_end(owner: Node3D) -> float:
	var clock := owner.get_node_or_null("WorldClock") as WorldClock
	if clock == null or clock.environment == null: return -1.0
	var environment := clock.environment
	if not environment.fog_enabled or environment.fog_mode != Environment.FOG_MODE_DEPTH or environment.fog_density < .999: return -1.0
	return environment.fog_depth_end

static func mesh_bounds(actor: Node3D) -> AABB:
	# The giant's presentation loads the authored rig at ready time. Read
	# that same model here without adding a temporary actor to the world.
	if actor is SlenderSpeaker and actor.find_children("*", "MeshInstance3D", true, false).is_empty():
		var model := load("res://assets/models/slender_speaker/slender_speaker_rigged.glb").instantiate() as Node3D
		var bounds := mesh_bounds(model)
		model.free()
		return actor.get_node("BodyMesh").transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * bounds
	var result := AABB()
	var first := true
	for child in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or not mesh.visible: continue
		var transform := mesh.transform
		var parent := mesh.get_parent()
		while parent != actor:
			if parent is Node3D: transform = parent.transform * transform
			parent = parent.get_parent()
		var box := transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	# Include pose/render uncertainty, especially the large speaker head.
	return result.grow(1.0) if not first else AABB()

static func _contact_targets(owner: Node3D, player: Node3D) -> Array[Node3D]:
	var targets: Array[Node3D] = [player]
	var vehicle: Node3D
	for key in ["seated_in", "active_climb_rv"]:
		var attached: Node = player.get(key)
		if is_instance_valid(attached): vehicle = RVConnection.resolve(attached)
	var support_state = player.get("rv_support")
	if support_state != null and is_instance_valid(support_state.rv): vehicle = support_state.rv
	if vehicle == null or not WorldEntities.same_world(owner, vehicle): return targets
	targets.append(vehicle)
	for node in owner.get_tree().get_nodes_in_group(Groups.MONSTER_DAMAGEABLE):
		if node is RVStructurePanel and RVConnection.resolve(node) == vehicle and CombatTargeting.is_live_target(node): targets.append(node)
	return targets

static func _destinations(owner: Node3D, player: Node3D, targets: Array[Node3D], map: RID, radius: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var vehicle: Node3D
	for target in targets:
		if target is Chassis: vehicle = target
	if vehicle == null:
		var ground := support(owner.get_world_3d().direct_space_state, player.global_position, 0.0, 0.0)
		if not ground.is_empty(): points.append(ground.floor)
	else:
		# Sample actual vehicle collision perimeter; its cabin center may be
		# excluded from the navigation mesh and cannot prove a usable route.
		for child in vehicle.find_children("*", "CollisionShape3D", true, false):
			var shape := child as CollisionShape3D
			if shape.disabled or not shape.shape is BoxShape3D: continue
			var half: Vector3 = shape.shape.size * .5
			for side in [Vector3(half.x + radius + .5, 0, 0), Vector3(-half.x - radius - .5, 0, 0), Vector3(0, 0, half.z + radius + .5), Vector3(0, 0, -half.z - radius - .5)]:
				points.append(shape.global_transform * side)
	var destinations: Array[Vector3] = []
	for point in points:
		var projected := NavigationServer3D.map_get_closest_point(map, point)
		if planar_distance(point, projected) <= NAV_TOLERANCE: destinations.append(projected)
	return destinations

static func _spacing(owner: Node3D, point: Vector3, minimum: float) -> bool:
	for actor in owner.get_tree().get_nodes_in_group(Groups.MONSTERS):
		if actor is Node3D and WorldEntities.same_world(owner, actor) and not actor.is_queued_for_deletion() and planar_distance(actor.global_position, point) < minimum: return false
	return true

static func _potential_sight(space: PhysicsDirectSpaceState3D, point: Vector3, targets: Array[Node3D], giant: bool) -> bool:
	var origin := point + Vector3.UP * (14.0 if giant else 1.0)
	for target in targets:
		if not giant and point.distance_to(target.global_position) > 25.0: continue
		var ray := PhysicsRayQueryParameters3D.create(origin, target.global_position + Vector3.UP, 0xFFFFFFFF)
		ray.hit_from_inside = true
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or CombatTargeting.related(hit.collider, target): return true
	return false

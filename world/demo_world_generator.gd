extends "res://world/world_generator.gd"
## One guaranteed encounter after a short drive, using the production giant AI.
const DEPARTURE_DISTANCE := 60.0
const ENCOUNTER_LEAD := 170.0
const SHOULDER_OFFSET := 2.0
var _demo_spawned := false
var _next_spawn_attempt_ms := 0

func protected_bands(anchor: Vector3) -> Array[int]:
	var bands := super.protected_bands(anchor)
	# A pursuing giant can lag behind the player's two retained bands while
	# still inside the 450m actor range. Keep its floor and adjoining nav seams.
	for node in get_tree().get_nodes_in_group("slender_speaker"):
		var giant := node as Node3D
		if giant == null or giant.is_queued_for_deletion() or not WorldEntities.same_world(self, giant): continue
		if absf(giant.global_position.z - anchor.z) > RoadSpawns.SAFE_DISTANCE: continue
		var band := floori(-giant.global_position.z / profile.chunk_length)
		for neighbour in range(band - 1, band + 2):
			if neighbour not in bands: bands.append(neighbour)
	return bands

func _spawn_giant_segments(anchor: Vector3) -> void:
	# This demo owns its single encounter instead of the production random rolls.
	if _demo_spawned or not get_parent().get("play_ready"): return
	var now := Time.get_ticks_msec()
	if now < _next_spawn_attempt_ms: return
	_next_spawn_attempt_ms = now + 250
	var run: StartRun = get_parent().get_node("StartRun")
	if run.phase not in ["started", "closing", "sealed"]: return
	var vehicle: Chassis = get_parent().get_node("NewRv/Chassis")
	var road := field.road_query(vehicle.global_position.x, vehicle.global_position.z)
	if float(road.s) < float(field.stop(0).s) + DEPARTURE_DISTANCE: return
	if float(road.distance) > float(road.width) * 0.5 + 5.0: return
	if not _giant_weather_allows_spawn() or not giant_navigation_map.is_valid(): return
	if NavigationServer3D.map_get_iteration_id(giant_navigation_map) == 0: return
	if get_tree().get_nodes_in_group("slender_speaker").any(func(n): return WorldEntities.same_world(self, n) and not n.is_queued_for_deletion()):
		_demo_spawned = true
		return
	var container := WorldEntities.get_container(self)
	if container == null: return
	# Trees begin 5m beyond the road edge. Keep the entire 1.1m body inside
	# that clear strip, and require a complete route back to the departure road.
	var destination := NavigationServer3D.map_get_closest_point(giant_navigation_map, road.frame.origin)
	if destination.slide(Vector3.UP).distance_to(Vector3(road.frame.origin).slide(Vector3.UP)) > 1.0: return
	for lead in [ENCOUNTER_LEAD, ENCOUNTER_LEAD + 15.0, ENCOUNTER_LEAD + 30.0]:
		var distance := float(road.s) + float(lead)
		var frame := field.road_frame(distance)
		for side in [-1.0, 1.0]:
			var point := frame.origin + frame.basis.x * float(side) * (field.road_width(distance) * 0.5 + SHOULDER_OFFSET)
			point.y = field.height_at(point.x, point.z)
			var band := floori(-point.z / profile.chunk_length)
			if not _demo_corridor_ready(band, floori(-destination.z / profile.chunk_length)): continue
			var nav_point := NavigationServer3D.map_get_closest_point(giant_navigation_map, point)
			if nav_point.slide(Vector3.UP).distance_to(point.slide(Vector3.UP)) > 0.5: continue
			var route := NavigationServer3D.map_get_path(giant_navigation_map, nav_point, destination, true)
			if route.is_empty() or route[route.size() - 1].distance_to(destination) > 0.5: continue
			# Navigation height is simplified. Place the real feet on the physical
			# floor instead of spawning above/below it using the polygon's height.
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4.0, point - Vector3.UP * 4.0, 1)
			var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if floor_hit.is_empty() or floor_hit.normal.y < cos(deg_to_rad(35.0)): continue
			var spawn_point: Vector3 = floor_hit.position + Vector3.UP * 0.1
			if not _demo_location_clear(spawn_point, anchor): continue
			var giant: SlenderSpeaker = load(SlenderSpeakerSpawns.SCENE).instantiate()
			giant.transform = container.global_transform.affine_inverse() * Transform3D(Basis.looking_at((vehicle.global_position - spawn_point).slide(Vector3.UP).normalized()), spawn_point)
			giant.set_giant_navigation_map(giant_navigation_map)
			_demo_spawned = true
			container.add_child(giant)
			run.register_actor(giant)
			print("DEMO_SLENDER_SPAWN band=%d point=%s" % [band, giant.global_position])
			return

func _demo_corridor_ready(first: int, last: int) -> bool:
	for band in range(mini(first, last), maxi(first, last) + 1):
		if not active_chunks.any(func(entry): return int(entry.index) == band and entry.node.giant_navigation_ready): return false
	return true

func _demo_location_clear(point: Vector3, anchor: Vector3) -> bool:
	if not point.is_finite() or point.distance_to(anchor) < SlenderSpeakerSpawns.PLAYER_CLEARANCE: return false
	var road := field.road_query(point.x, point.z)
	if float(road.distance) > float(road.width) * 0.5 + 5.0 - SlenderSpeakerSpawns.RADIUS: return false
	if field.normal_at(point.x, point.z).y < cos(deg_to_rad(35.0)): return false
	for site in field.sites_near_z(point.z, 400.0):
		if field.court_distance(point.x, point.z, site) < 20.0: return false
		if site.has("bounds") and site.bounds.grow(SlenderSpeakerSpawns.RADIUS + 3.0).has_point(point): return false
	var shape := CapsuleShape3D.new()
	shape.height = SlenderSpeakerSpawns.HEIGHT
	shape.radius = SlenderSpeakerSpawns.RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = point + Vector3.UP * (SlenderSpeakerSpawns.HEIGHT * 0.5)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

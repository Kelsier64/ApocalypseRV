extends RefCounted
class_name RearWreckLayout
## Saved static rear scenery, independent of road encounters and forest identities.
const VERSION := 1
const MAX_WRECKS := 28
const WALK_WIDTH := 1.5
const ATTEMPTS := 48

static func plan(field: WorldField, exclusions: Array[AABB] = []) -> Dictionary:
	var path_rng := field.rng_for(-1, "rear_wreck_walkway")
	var walkway := PackedVector3Array()
	for i in range(7):
		var x := 0.0 if i == 0 or i == 6 else path_rng.randf_range(-4.0, 4.0)
		walkway.append(Vector3(x, field.height_at(x, i * 20.0), i * 20.0))
	var placements: Array[Dictionary] = []
	var footprints: Array[PackedVector2Array] = []
	for id in range(MAX_WRECKS):
		var rng := field.rng_for(id, "rear_wreck_slot")
		for attempt in range(ATTEMPTS):
			var x := rng.randf_range(-24.0, 24.0)
			var z := rng.randf_range(10.0, 110.0)
			var pose := RoadSpawns._pose(field, -z, x, rng.randf_range(0.0, TAU))
			var bounds := RoadSpawns._wreck_bounds(pose)
			var footprint := RoadSpawns._wreck_footprint(pose)
			if not placement_valid(field, pose, bounds, footprint, walkway, footprints, exclusions): continue
			placements.append({"id": id, "transform": pose})
			footprints.append(footprint)
			break
	return {"version": VERSION, "placements": placements, "walkway": walkway}

static func placement_valid(field: WorldField, pose: Transform3D, bounds: AABB, footprint: PackedVector2Array, walkway: PackedVector3Array, occupied: Array[PackedVector2Array], exclusions: Array[AABB]) -> bool:
	if field.normal_at(pose.origin.x, pose.origin.z).y < 0.96: return false
	for exclusion in exclusions:
		if RoadSpawns._flat_intersects(bounds, exclusion, 0.75): return false
	for previous in occupied:
		if RoadSpawns._footprints_overlap(footprint, previous): return false
	if not clears_walkway(footprint, walkway): return false
	for site in field.sites_near_z(pose.origin.z, 400.0):
		var definition := POIConfig.definition_for_site(site)
		if definition != null and RoadSpawns._flat_intersects(bounds, site.building * definition.site_bounds, 2.0): return false
	for point in footprint:
		if absf(field.height_at(point.x, point.y) - field.height_at(pose.origin.x, pose.origin.z)) > 0.35: return false
	for band in [-2, -1, 0]:
		var trees := ForestScenery.trees(field, band)
		for index in range(trees.size()):
			if field.destroyed_trees.has(TreeImpact.forest_id(band, index)): continue
			var point := Vector2(trees[index].point.x, trees[index].point.z)
			if polygon_distance(point, footprint) < 0.9: return false
	return true

static func polygon_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, polygon): return 0.0
	var distance := INF
	for i in range(polygon.size()):
		distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])))
	return distance

static func clears_walkway(footprint: PackedVector2Array, walkway: PackedVector3Array) -> bool:
	# Segment-to-polygon distance protects a real 1.5m corridor, not a point gap.
	for i in range(1, walkway.size()):
		var a := Vector2(walkway[i - 1].x, walkway[i - 1].z)
		var b := Vector2(walkway[i].x, walkway[i].z)
		if polygon_distance(a, footprint) < WALK_WIDTH * 0.5 or polygon_distance(b, footprint) < WALK_WIDTH * 0.5: return false
		for j in range(footprint.size()):
			var c: Vector2 = footprint[j]
			var d: Vector2 = footprint[(j + 1) % footprint.size()]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null: return false
			if c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)) < WALK_WIDTH * 0.5: return false
	return true

static func build(chunk: Node3D, data: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "RearWrecks"
	chunk.add_child(holder)
	for placement: Dictionary in data.placements:
		var wreck: Node3D = load(RoadSpawns.WRECK_SCENE).instantiate()
		wreck.name = "Wreck_%02d" % placement.id
		wreck.transform = chunk.global_transform.affine_inverse() * placement.transform
		holder.add_child(wreck)

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.is_empty(): return true # The rear band has not been visited yet.
	if data.get("version") != VERSION or not data.get("version") is int: return false
	if not data.get("placements") is Array or data.placements.size() > MAX_WRECKS: return false
	if not data.get("walkway") is PackedVector3Array or data.walkway.size() != 7: return false
	for i in range(7):
		var point: Vector3 = data.walkway[i]
		if not point.is_finite() or absf(point.x) > 4.001 or absf(point.y) > 100.0 or not is_equal_approx(point.z, float(i * 20)): return false
	if not is_zero_approx(data.walkway[0].x) or not is_zero_approx(data.walkway[6].x): return false
	var identities := {}
	var footprints: Array[PackedVector2Array] = []
	for placement in data.placements:
		if not placement is Dictionary or not placement.get("id") is int or placement.id < 0 or placement.id >= MAX_WRECKS or identities.has(placement.id): return false
		if not CheckpointSchema.valid_transform(placement.get("transform")): return false
		var pose: Transform3D = placement.transform
		if absf(pose.origin.x) > 24.001 or absf(pose.origin.y) > 100.0 or pose.origin.z < 10.0 or pose.origin.z > 110.0: return false
		if not pose.basis.is_equal_approx(pose.basis.orthonormalized()) or pose.basis.determinant() < 0.99 or pose.basis.y.y < 0.96: return false
		var footprint := RoadSpawns._wreck_footprint(pose)
		if not clears_walkway(footprint, data.walkway): return false
		for previous in footprints:
			if RoadSpawns._footprints_overlap(footprint, previous): return false
		footprints.append(footprint)
		identities[placement.id] = true
	return true

static func valid_checkpoint(data: Dictionary) -> bool:
	var layout: Variant = data.get("rear_wreck_layout")
	if not valid_state(layout): return false
	if layout.is_empty(): return true
	var profile := WorldProfile.new()
	for key in data.get("profile", {}):
		if key in profile and key != "terrain_half_width": profile.set(key, data.profile[key])
	profile.generation_version = 10
	var field := WorldField.new(data.seed, profile)
	for point: Vector3 in layout.walkway:
		if absf(point.y - field.height_at(point.x, point.z)) > 0.001: return false
	for placement: Dictionary in layout.placements:
		var pose: Transform3D = placement.transform
		if absf(pose.origin.y - RoadSpawns._surface_height(field, pose.origin) - 0.08) > 0.001: return false
		if pose.basis.y.dot(field.normal_at(pose.origin.x, pose.origin.z)) < 0.99999: return false
		for point in RoadSpawns._wreck_footprint(pose):
			if absf(field.height_at(point.x, point.y) - field.height_at(pose.origin.x, pose.origin.z)) > 0.35001: return false
	return true

static func exclusions_for_checkpoint(data: Dictionary) -> Array[AABB]:
	var result: Array[AABB] = []
	if data.has("player"):
		_append_scene_bounds("res://player/player.tscn", data.player.transform, result)
	for actor: Dictionary in data.get("actors", []):
		_append_scene_bounds(actor.scene, actor.transform, result)
	for band in data.get("dormant_items", {}):
		for actor: Dictionary in data.dormant_items[band]: _append_scene_bounds(actor.scene, actor.transform, result)
	for vehicle: Dictionary in data.get("vehicles", []):
		_append_scene_bounds("res://rv/chassis.tscn", vehicle.transform, result)
		# Structure slots are built at ready, so include their full cabin envelope.
		result.append(vehicle.transform * AABB(Vector3(-2.5, -1.5, -6.5), Vector3(5, 6.5, 13)))
		for item: Dictionary in vehicle.get("mounted_items", []):
			_append_scene_bounds(item.scene, vehicle.transform * item.transform, result)
	for site in data.get("outdoor_sites", {}).values():
		for actor: Dictionary in site.get("actors", []): _append_scene_bounds(actor.scene, actor.transform, result)
	return result

static func _append_scene_bounds(path: String, pose: Transform3D, result: Array[AABB]) -> void:
	# Read scene collision transforms off-tree; never ready or simulate a clone.
	var scene := load(path) as PackedScene
	if scene == null: return
	var instance := scene.instantiate()
	var base := pose
	if instance is Node3D: base = pose * instance.transform.affine_inverse()
	_collect_shapes(instance, base, result)
	instance.free()

static func _collect_shapes(node: Node, pose: Transform3D, result: Array[AABB]) -> void:
	if node is Node3D: pose *= node.transform
	if node is CollisionShape3D and not node.disabled and node.shape != null:
		result.append(pose * node.shape.get_debug_mesh().get_aabb())
	for child in node.get_children(): _collect_shapes(child, pose, result)

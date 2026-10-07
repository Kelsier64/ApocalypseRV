extends RefCounted
class_name RoadSpawns
## Pure, versioned road encounters. No loaded-node queries or global RNG.
const WRECK_SCENE := "res://world/starting_shelter/reused_wreck.tscn"
const RAKER_SCENE := "res://enemies/raker.tscn"
const BARREL_MAN_SCENE := "res://enemies/barrel_man.tscn"
const OIL_BARREL_SCENE := "res://props/oil_barrel.tscn"
# v9 rolls these independently, never as replacements for Raker slots.
const BARREL_CHANCE := 0.20
const BARREL_MAN_CHANCE := 0.08
const RAKER_ROAD_CHANCE := 0.40
const BARREL_RADIUS := 0.33
const CHANCES := {"strips": 0.15, "wrecks": 0.25, "monsters": 0.35}
const BLOCK_CHANCE := 0.15
const ATTEMPTS := 4
const SAFE_DISTANCE := 450.0
const SEAM_MARGIN := 5.0
const PASSAGE_WIDTH := 5.0
# Includes wheels, bumpers and the authored model's intrinsic +0.2 rad yaw.
const WRECK_SIZE := Vector3(4.0, 2.3, 5.3)
const WRECK_BOUNDS := AABB(Vector3(-2.0, -0.1, -2.4), WRECK_SIZE)
const WRECK_MODEL_YAW := 0.2
const MONSTER_SIZE := Vector3(2.0, 2.5, 2.0)

static func plan(field: WorldField, band: int) -> Dictionary:
	if field.profile.generation_version >= 9:
		return _plan_v9(field, band)
	return _plan_v8(field, band)

static func _plan_v8(field: WorldField, band: int) -> Dictionary:
	var result := {"strips": [], "wrecks": [], "monsters": [], "monster_scenes": [], "blocked": false}
	if field.profile.generation_version < 8 or band * field.profile.chunk_length < SAFE_DISTANCE:
		return result
	var occupied: Array[AABB] = []
	# Wrecks have priority when independent candidates need shared clearance.
	var wreck_rng := field.rng_for(band, "road_spawn_wrecks")
	if wreck_rng.randf() < CHANCES.wrecks:
		var blocked := wreck_rng.randf() < BLOCK_CHANCE
		var count := wreck_rng.randi_range(1, 2)
		var side := -1.0 if wreck_rng.randf() < 0.5 else 1.0
		for attempt in range(ATTEMPTS):
			var s := _distance(field, band, wreck_rng)
			var width := field.road_width(s)
			var poses: Array[Dictionary] = []
			var boxes: Array[AABB] = []
			var footprints: Array[PackedVector2Array] = []
			if blocked:
				count = maxi(3, ceili(width / 4.5))
				# Never claim a blockade when a custom road is too wide.
				if count > 4: continue
			for index in range(count):
				var offset := (index - (count - 1) * 0.5) * 5.4 if blocked else side * maxf((width + PASSAGE_WIDTH) * 0.25, PASSAGE_WIDTH * 0.5 + WRECK_SIZE.x * 0.5 + 0.4)
				var along := 0.0 if blocked else index * 9.0
				var yaw := PI * 0.5 if blocked else 0.0
				var pose := _pose(field, s + along, offset, yaw)
				var box := _wreck_bounds(pose)
				poses.append({"transform": pose, "bounds": box, "scene": WRECK_SCENE})
				boxes.append(box)
				footprints.append(_wreck_footprint(pose))
			if not _valid_group(field, band, boxes, occupied, footprints): continue
			if not blocked and not _keeps_passage(field, poses): continue
			result.wrecks = poses
			result.blocked = blocked
			occupied.append_array(boxes)
			break
	var strip_rng := field.rng_for(band, "road_spawn_strips")
	if strip_rng.randf() < CHANCES.strips:
		for attempt in range(ATTEMPTS):
			var s := _distance(field, band, strip_rng)
			var edge := field.road_width(s) * 0.5
			var pose := _pose(field, s, strip_rng.randf_range(-edge, edge), 0.0, false)
			pose.origin += pose.basis.y * 0.04
			var box := pose * AABB(Vector3(-TireSpikeStrip.LENGTH * 0.5, 0, -TireSpikeStrip.DEPTH * 0.5), Vector3(TireSpikeStrip.LENGTH, 0.2, TireSpikeStrip.DEPTH))
			if not _valid_group(field, band, [box], occupied): continue
			result.strips.append({"transform": pose, "bounds": box})
			occupied.append(box)
			break
	var monster_rng := field.rng_for(band, "road_spawn_monsters")
	if monster_rng.randf() < CHANCES.monsters:
		var count := monster_rng.randi_range(1, 3)
		for attempt in range(ATTEMPTS):
			var s := _distance(field, band, monster_rng)
			var points: Array[Vector3] = []
			var boxes: Array[AABB] = []
			for index in range(count):
				var distance := s + index * 4.0
				var edge := field.road_width(distance) * 0.5 + 1.0
				var pose := _pose(field, distance, monster_rng.randf_range(-edge, edge), 0.0, false)
				points.append(pose.origin + Vector3.UP * 0.5)
				boxes.append(AABB(pose.origin - Vector3(1, 0, 1), MONSTER_SIZE))
			if not _valid_group(field, band, boxes, occupied): continue
			result.monsters = points
			break
	# Species selection never consumes candidate/count/position RNG draws.
	var species_rng := field.rng_for(band, "road_monster_species")
	for point in result.monsters:
		result.monster_scenes.append(BARREL_MAN_SCENE if species_rng.randf() < BarrelManSettings.ROAD_CHANCE else RAKER_SCENE)
	return result

static func _v9_raker_count(roll: float) -> int:
	if roll < 0.65: return 0
	if roll < 0.85: return 1
	if roll < 0.95: return 2
	return 3

static func _v9_wreck_count(roll: float) -> int:
	if roll < 0.60: return 0
	if roll < 0.85: return 1
	if roll < 0.95: return 2
	if roll < 0.99: return 3
	return 4

static func _plan_v9(field: WorldField, band: int) -> Dictionary:
	var result := {"strips": [], "wrecks": [], "monsters": [], "monster_scenes": [], "monster_yaws": [], "barrels": [], "blocked": false}
	if band * field.profile.chunk_length < SAFE_DISTANCE: return result
	var occupied := _v9_road_obstacles(field, band)
	var wreck_count := _v9_wreck_count(field.rng_for(band, "road_v9_wreck_count").randf())
	for index in range(wreck_count):
		# Each slot owns a stream: a rejected car cannot move the next car.
		var rng := field.rng_for(band, "road_v9_wreck_%d" % index)
		for attempt in range(ATTEMPTS):
			var s := _v9_distance(field, band, rng)
			var edge := field.road_width(s) * 0.5 + 1.0
			var pose := _pose(field, s, rng.randf_range(-edge, edge), rng.randf_range(0.0, TAU))
			var box := _wreck_bounds(pose)
			var footprint := _wreck_footprint(pose)
			if not _v9_valid(field, band, box, footprint, occupied): continue
			result.wrecks.append({"transform": pose, "bounds": box, "scene": WRECK_SCENE})
			occupied.append({"bounds": box, "footprint": footprint})
			break
	var strip_rng := field.rng_for(band, "road_v9_strips")
	if strip_rng.randf() < CHANCES.strips:
		for attempt in range(ATTEMPTS):
			var s := _v9_distance(field, band, strip_rng)
			var edge := field.road_width(s) * 0.5
			var pose := _pose(field, s, strip_rng.randf_range(-edge, edge), 0.0, false)
			pose.origin += pose.basis.y * 0.04
			var box := pose * AABB(Vector3(-TireSpikeStrip.LENGTH * 0.5, 0, -TireSpikeStrip.DEPTH * 0.5), Vector3(TireSpikeStrip.LENGTH, 0.2, TireSpikeStrip.DEPTH))
			var footprint := _box_footprint(box)
			if not _v9_valid(field, band, box, footprint, occupied): continue
			result.strips.append({"transform": pose, "bounds": box})
			occupied.append({"bounds": box, "footprint": footprint})
			break
	if field.rng_for(band, "road_v9_barrel_count").randf() < BARREL_CHANCE:
		var rng := field.rng_for(band, "road_v9_barrel_0")
		for attempt in range(ATTEMPTS):
			var s := _v9_distance(field, band, rng)
			var edge := field.road_width(s) * 0.25
			var pose := _pose(field, s, rng.randf_range(-edge, edge), rng.randf_range(0.0, TAU), false)
			pose.origin += pose.basis.y * 0.5
			var box := pose * AABB(Vector3(-BARREL_RADIUS, -0.5, -BARREL_RADIUS), Vector3(BARREL_RADIUS * 2.0, 1.0, BARREL_RADIUS * 2.0))
			var footprint := _box_footprint(box)
			if not _v9_valid(field, band, box, footprint, occupied): continue
			result.barrels.append({"transform": pose, "bounds": box, "scene": OIL_BARREL_SCENE})
			occupied.append({"bounds": box, "footprint": footprint})
			break
	var raker_count := _v9_raker_count(field.rng_for(band, "road_v9_raker_count").randf())
	for index in range(raker_count):
		_v9_monster(field, band, result, occupied, field.rng_for(band, "road_v9_raker_%d" % index), RAKER_SCENE)
	if field.rng_for(band, "road_v9_barrel_man_count").randf() < BARREL_MAN_CHANCE:
		_v9_monster(field, band, result, occupied, field.rng_for(band, "road_v9_barrel_man_0"), BARREL_MAN_SCENE)
	return result

static func _v9_monster(field: WorldField, band: int, result: Dictionary, occupied: Array[Dictionary], rng: RandomNumberGenerator, scene: String) -> void:
	for attempt in range(ATTEMPTS):
		var s := _v9_distance(field, band, rng)
		var edge := field.road_width(s) * 0.5
		var offset: float
		if scene == BARREL_MAN_SCENE:
			offset = rng.randf_range(-edge * 0.5, edge * 0.5)
		elif rng.randf() < RAKER_ROAD_CHANCE:
			offset = rng.randf_range(-edge, edge)
		else:
			offset = (edge + rng.randf_range(0.5, 2.5)) * (-1.0 if rng.randf() < 0.5 else 1.0)
		var point := _pose(field, s, offset, 0.0, false).origin
		var yaw := rng.randf_range(0.0, TAU)
		var size := _v9_monster_size(scene)
		var box := AABB(point - Vector3(size.x * 0.5, 0, size.z * 0.5), size)
		var footprint := _box_footprint(box)
		if not _v9_valid(field, band, box, footprint, occupied): continue
		result.monsters.append(point + Vector3.UP * 0.5)
		result.monster_scenes.append(scene)
		result.monster_yaws.append(yaw)
		occupied.append({"bounds": box, "footprint": footprint})
		return

static func _v9_monster_size(scene: String) -> Vector3:
	return Vector3(BARREL_RADIUS * 2.0, 2.5, BARREL_RADIUS * 2.0) if scene == BARREL_MAN_SCENE else Vector3(0.8, 2.616, 0.8)

static func _v9_distance(field: WorldField, band: int, rng: RandomNumberGenerator) -> float:
	return band * field.profile.chunk_length + rng.randf_range(SEAM_MARGIN, field.profile.chunk_length - SEAM_MARGIN)

static func _box_footprint(box: AABB) -> PackedVector2Array:
	return PackedVector2Array([Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z), Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z)])

static func _v9_road_obstacles(field: WorldField, band: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Mirror ChunkGenerator._build_road's deterministic guardrails. A road-side
	# actor may be close to another actor, but cannot start inside a real rail.
	if posmod(band, 6) != 3: return result
	for index in range(12):
		var s := band * 150.0 + 40.0 + index * 5.0
		var road := field.road_frame(s)
		var point: Vector3 = road * Vector3(-field.road_width(s) * 0.5 - 1.2, 0, 0)
		var near_site := false
		for site in field.sites_near_z(point.z):
			if field.court_distance(point.x, point.z, site) < 20.0:
				near_site = true
				break
		if near_site: continue
		point.y = field.height_at(point.x, point.z)
		var pose := Transform3D(road.basis, point)
		# rail.tscn: two posts plus a 0.16 x 0.35 x 5 metre beam.
		var box := pose * AABB(Vector3(-0.08, 0, -2.5), Vector3(0.16, 1.025, 5.0))
		var footprint := PackedVector2Array()
		for corner in [Vector3(-0.08, 0, -2.5), Vector3(0.08, 0, -2.5), Vector3(0.08, 0, 2.5), Vector3(-0.08, 0, 2.5)]:
			var world_point: Vector3 = pose * corner
			footprint.append(Vector2(world_point.x, world_point.z))
		result.append({"bounds": box, "footprint": footprint})
	return result

static func _v9_valid(field: WorldField, band: int, box: AABB, footprint: PackedVector2Array, occupied: Array[Dictionary]) -> bool:
	# Reuse terrain/site/seam constraints, without the legacy group's spacing.
	if not _valid_group(field, band, [box], []): return false
	for other in occupied:
		if _flat_intersects(box, other.bounds) and _footprints_overlap(footprint, other.footprint): return false
	return true

static func _distance(field: WorldField, band: int, rng: RandomNumberGenerator) -> float:
	return band * field.profile.chunk_length + rng.randf_range(20.0, field.profile.chunk_length - 30.0)

static func _pose(field: WorldField, s: float, offset: float, yaw: float, wreck := true) -> Transform3D:
	var road := field.road_frame(s)
	var point := road.origin + road.basis.x * offset
	point.y = _surface_height(field, point) + (0.08 if wreck else 0.0)
	var up := field.normal_at(point.x, point.z)
	var right := (road.basis.x - up * road.basis.x.dot(up)).normalized()
	var basis := Basis(right, up, right.cross(up).normalized())
	return Transform3D(basis * Basis(Vector3.UP, yaw - WRECK_MODEL_YAW if wreck else yaw), point)

static func _surface_height(field: WorldField, point: Vector3) -> float:
	var road := field.road_query(point.x, point.z)
	return field.height_at(point.x, point.z) + (0.07 if road.distance <= road.width * 0.5 else 0.0)

static func _wreck_bounds(pose: Transform3D) -> AABB:
	return (pose * Transform3D(Basis(Vector3.UP, WRECK_MODEL_YAW), Vector3.ZERO)) * WRECK_BOUNDS

static func _wreck_footprint(pose: Transform3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	var aligned := pose * Transform3D(Basis(Vector3.UP, WRECK_MODEL_YAW), Vector3.ZERO)
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		var point: Vector3 = aligned * (corner * WRECK_SIZE * 0.5 + Vector3(0, 0, WRECK_BOUNDS.get_center().z))
		points.append(Vector2(point.x, point.z))
	return points

static func _footprints_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	# SAT keeps transverse rows separate even on a curving road; their world
	# AABBs overlap although their actual model footprints do not.
	for polygon in [a, b]:
		for index in range(polygon.size()):
			var edge: Vector2 = polygon[(index + 1) % polygon.size()] - polygon[index]
			var axis := Vector2(-edge.y, edge.x).normalized()
			var a_min := INF
			var a_max := -INF
			var b_min := INF
			var b_max := -INF
			for point in a:
				a_min = minf(a_min, point.dot(axis))
				a_max = maxf(a_max, point.dot(axis))
			for point in b:
				b_min = minf(b_min, point.dot(axis))
				b_max = maxf(b_max, point.dot(axis))
			if a_max <= b_min or b_max <= a_min: return false
	return true

static func _flat_intersects(a: AABB, b: AABB, margin := 0.0) -> bool:
	return a.position.x - margin < b.end.x and a.end.x + margin > b.position.x and a.position.z - margin < b.end.z and a.end.z + margin > b.position.z

static func _valid_group(field: WorldField, band: int, boxes: Array, occupied: Array[AABB], footprints: Array[PackedVector2Array] = []) -> bool:
	for index in range(boxes.size()):
		var box: AABB = boxes[index]
		if box.position.z < -(band + 1) * field.profile.chunk_length + SEAM_MARGIN or box.end.z > -band * field.profile.chunk_length - SEAM_MARGIN: return false
		for other in occupied:
			if _flat_intersects(box, other, 1.0): return false
		for previous in range(index):
			if not footprints.is_empty():
				if _footprints_overlap(footprints[index], footprints[previous]): return false
			elif _flat_intersects(box, boxes[previous]): return false
		for site in field.sites_near_z(box.get_center().z, 400.0):
			if absf(float(site.s) + box.get_center().z) < 55.0: return false
			if site.has("bounds") and _flat_intersects(box, site.bounds, 8.0): return false
			for point in _corners(box):
				if field.court_distance(point.x, point.z, site) < 8.0: return false
		for point in _corners(box):
			var road := field.road_query(point.x, point.z)
			# Forest collisions start farther out; stay inside the clear shoulder.
			if road.distance > road.width * 0.5 + 4.0 or field.normal_at(point.x, point.z).y < 0.90: return false
	return true

static func _corners(box: AABB) -> Array[Vector3]:
	return [box.position, Vector3(box.end.x, box.position.y, box.position.z), box.end, Vector3(box.position.x, box.end.y, box.end.z), box.get_center()]

static func _keeps_passage(field: WorldField, poses: Array[Dictionary]) -> bool:
	for data in poses:
		for point in _corners(data.bounds):
			var road := field.road_query(point.x, point.z)
			if road.distance < PASSAGE_WIDTH * 0.5: return false
	return true

static func build_static(chunk: Node3D, data: Dictionary) -> void:
	for placement in data.wrecks:
		var wreck: Node3D = load(placement.scene).instantiate()
		wreck.name = "RoadWreck"
		chunk.add_child(wreck)
		wreck.global_transform = placement.transform
	for placement in data.strips:
		var strip := TireSpikeStrip.new()
		strip.name = "RoadSpikeStrip"
		chunk.add_child(strip)
		strip.global_transform = placement.transform

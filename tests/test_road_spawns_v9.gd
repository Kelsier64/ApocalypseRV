extends SceneTree
## Planner-only checks: actors and navigation are deliberately never loaded.

class FlatField extends WorldField:
	func road_frame(s: float) -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(0, 0, -s))
	func road_width(_s: float) -> float:
		return profile.road_width
	func road_query(x: float, z: float) -> Dictionary:
		return {"s": -z, "distance": absf(x), "height": 0.0, "width": profile.road_width, "frame": road_frame(-z)}
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP
	func sites_near_z(_z: float, _radius: float = 240.0) -> Array[Dictionary]:
		return []

class PerturbedField extends FlatField:
	var changed_domain := ""
	func rng_for(id: int, domain: String) -> RandomNumberGenerator:
		var rng := super.rng_for(id, domain)
		if domain == changed_domain:
			rng.randf()
		return rng

var failures: Array[String] = []
var collision_parts: Array[PackedVector3Array] = []
var reported_wreck_corner := false

func _init() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok and detail not in failures:
		failures.append(detail)
		push_error("FAIL: " + detail)

func profile(version := 9) -> WorldProfile:
	var settings := WorldProfile.new()
	settings.generation_version = version
	return settings

func empty(data: Dictionary) -> bool:
	return data.strips.is_empty() and data.wrecks.is_empty() and data.monsters.is_empty() and data.get("barrels", []).is_empty() and not data.blocked

func run() -> void:
	check_count_boundaries()
	read_wreck_collisions()
	check_flat_distribution()
	check_slot_independence()
	check_world_safety()
	check_legacy_versions()
	if failures.is_empty():
		print("PASS: v9 independent road counts, positions, orientations, geometry, safety and legacy isolation")
	quit(0 if failures.is_empty() else 1)

func check_count_boundaries() -> void:
	for sample in [[0.0, 0], [0.599999, 0], [0.6, 1], [0.849999, 1], [0.85, 2], [0.949999, 2], [0.95, 3], [0.989999, 3], [0.99, 4], [0.999999, 4]]:
		check(RoadSpawns._v9_wreck_count(sample[0]) == sample[1], "Wreck CDF has exact 60/25/10/4/1 boundaries")
	for sample in [[0.0, 0], [0.649999, 0], [0.65, 1], [0.849999, 1], [0.85, 2], [0.949999, 2], [0.95, 3], [0.999999, 3]]:
		check(RoadSpawns._v9_raker_count(sample[0]) == sample[1], "Raker CDF has exact 65/20/10/5 boundaries")

func check_flat_distribution() -> void:
	# A long, broad, flat road removes terrain/site rejection from probability
	# checks; sparse physical collisions can still suppress individual slots.
	var settings := profile()
	settings.chunk_length = 1500.0
	settings.road_width = 80.0
	var wreck_hist := [0, 0, 0, 0, 0]
	var raker_hist := [0, 0, 0, 0]
	var categories := {"barrels": 0, "barrel_man": 0, "strips": 0}
	var raker_positions := {"road": 0, "shoulder": 0}
	var combinations: Dictionary = {}
	var observations := {"wreck_spread": false, "raker_spread": false, "near_rakers": false, "mixed_sides": false, "mixed_road_shoulder": false, "central_wreck": false, "adjacent_wrecks": false, "adjacent_rakers": false, "yaw_quadrants": 0, "early": false, "late": false}
	var trials := 4096
	for seed_value in range(trials):
		var field := FlatField.new(seed_value, settings)
		var band := 3 + seed_value % 4
		var data := RoadSpawns.plan(field, band)
		var rakers := 0
		var barrel_men := 0
		for scene in data.monster_scenes:
			rakers += int(scene == RoadSpawns.RAKER_SCENE)
			barrel_men += int(scene == RoadSpawns.BARREL_MAN_SCENE)
		var wreck_roll := field.rng_for(band, "road_v9_wreck_count").randf()
		var raker_roll := field.rng_for(band, "road_v9_raker_count").randf()
		check(data.wrecks.size() <= RoadSpawns._v9_wreck_count(wreck_roll), "Wreck count never exceeds its independent count roll")
		check(rakers <= RoadSpawns._v9_raker_count(raker_roll), "Raker count never exceeds its independent count roll")
		check(barrel_men <= int(field.rng_for(band, "road_v9_barrel_man_count").randf() < 0.08), "BarrelMan uses its own eight percent gate without replacing Rakers")
		check(data.barrels.size() <= int(field.rng_for(band, "road_v9_barrel_count").randf() < 0.20), "Ordinary barrel uses its own twenty percent gate")
		check(not data.blocked, "v9 never reports an authored blockade group")
		check(data.monsters.size() == data.monster_scenes.size() and data.monsters.size() == data.monster_yaws.size(), "Every monster has one species and one independent yaw")
		wreck_hist[data.wrecks.size()] += 1
		raker_hist[rakers] += 1
		categories.barrels += int(not data.barrels.is_empty())
		categories.barrel_man += int(barrel_men > 0)
		categories.strips += int(not data.strips.is_empty())
		var mask := int(not data.wrecks.is_empty()) | (int(rakers > 0) << 1) | (int(barrel_men > 0) << 2) | (int(not data.barrels.is_empty()) << 3)
		combinations[mask] = true
		for wreck in data.wrecks:
			observations.central_wreck = observations.central_wreck or absf(wreck.transform.origin.x) < 2.5
		if data.wrecks.size() > 1:
			observations.wreck_spread = observations.wreck_spread or absf(data.wrecks[0].transform.origin.z - data.wrecks[1].transform.origin.z) > 100.0
		if rakers > 1:
			var a: Vector3 = data.monsters[0]
			var b: Vector3 = data.monsters[1]
			observations.raker_spread = observations.raker_spread or absf(a.z - b.z) > 100.0
			observations.near_rakers = observations.near_rakers or absf(a.z - b.z) < 4.0
			observations.mixed_sides = observations.mixed_sides or a.x * b.x < 0.0
			observations.mixed_road_shoulder = observations.mixed_road_shoulder or ((absf(a.x) < 40.0) != (absf(b.x) < 40.0))
		for index in range(data.monsters.size()):
			if data.monster_scenes[index] == RoadSpawns.RAKER_SCENE:
				raker_positions["road" if absf(data.monsters[index].x) <= 40.0 else "shoulder"] += 1
			var yaw: float = data.monster_yaws[index]
			check(yaw >= 0.0 and yaw < TAU, "Monster yaw spans [0, TAU)")
			observations.yaw_quadrants |= 1 << mini(3, floori(yaw / (PI * 0.5)))
			var distance: float = -data.monsters[index].z - band * settings.chunk_length
			observations.early = observations.early or distance < 20.0
			observations.late = observations.late or distance > settings.chunk_length - 30.0
		var next := RoadSpawns.plan(field, band + 1)
		observations.adjacent_wrecks = observations.adjacent_wrecks or (not data.wrecks.is_empty() and not next.wrecks.is_empty())
		observations.adjacent_rakers = observations.adjacent_rakers or (rakers > 0 and RoadSpawns.RAKER_SCENE in next.monster_scenes)
		# Calls to unrelated streams and repeated queries must be harmless.
		field.rng_for(band, "loot").randf()
		field.rng_for(band, "road_v9_wreck_0").randf()
		field.rng_for(band, "road_v9_raker_0").randf()
		check(data == RoadSpawns.plan(field, band), "v9 plan is deterministic after unrelated RNG consumption")
	for count in range(wreck_hist.size()):
		check(absf(wreck_hist[count] / float(trials) - [0.60, 0.25, 0.10, 0.04, 0.01][count]) < 0.025, "Observed wreck count distribution matches the requested probabilities")
	for count in range(raker_hist.size()):
		check(absf(raker_hist[count] / float(trials) - [0.65, 0.20, 0.10, 0.05][count]) < 0.025, "Observed Raker count distribution matches the requested probabilities")
	for category in categories:
		var chance: float = {"barrels": 0.20, "barrel_man": 0.08, "strips": 0.15}[category]
		check(absf(categories[category] / float(trials) - chance) < 0.025, "Independent " + category + " frequency matches its gate")
	for mask in range(16):
		check(combinations.has(mask), "All ordinary barrel/BarrelMan/Raker/wreck presence combinations occur independently")
	check(absf(raker_positions.road / float(raker_positions.road + raker_positions.shoulder) - 0.40) < 0.035, "Rakers independently choose asphalt/shoulder with forty/sixty probability")
	for observation in observations:
		check(observations[observation] == (15 if observation == "yaw_quadrants" else true), "Independent placement scan exercises " + observation)
	print("V9_FLAT_COUNTS wrecks=", wreck_hist, " rakers=", raker_hist, " categories=", categories)

func check_slot_independence() -> void:
	var settings := profile()
	settings.chunk_length = 1500.0
	settings.road_width = 80.0
	var independent_raker_pairs := 0
	var independent_wreck_pairs := 0
	for seed_value in range(256):
		var baseline := RoadSpawns.plan(FlatField.new(seed_value, settings), 3)
		var altered := PerturbedField.new(seed_value, settings)
		altered.changed_domain = "road_v9_raker_0"
		var raker_change := RoadSpawns.plan(altered, 3)
		check(baseline.wrecks == raker_change.wrecks and baseline.strips == raker_change.strips and baseline.barrels == raker_change.barrels, "Changing one Raker position stream leaves static category plans unchanged")
		if baseline.monsters.size() > 1 and baseline.monster_scenes[1] == RoadSpawns.RAKER_SCENE and raker_change.monsters.size() == baseline.monsters.size():
			if baseline.monsters[0] != raker_change.monsters[0] and baseline.monsters.slice(1) == raker_change.monsters.slice(1) and baseline.monster_yaws.slice(1) == raker_change.monster_yaws.slice(1):
				independent_raker_pairs += 1
		altered.changed_domain = "road_v9_wreck_0"
		var wreck_change := RoadSpawns.plan(altered, 3)
		if baseline.wrecks.size() > 1 and wreck_change.wrecks.size() == baseline.wrecks.size():
			if baseline.wrecks[0] != wreck_change.wrecks[0] and baseline.wrecks.slice(1) == wreck_change.wrecks.slice(1):
				independent_wreck_pairs += 1
	check(independent_raker_pairs >= 10, "Changing one Raker stream preserves later Raker positions and headings")
	check(independent_wreck_pairs >= 10, "Changing one wreck stream preserves later wreck positions and headings")

func check_world_safety() -> void:
	var root_children := root.get_child_count()
	var arbitrary_wreck_yaw := false
	for seed_value in range(8):
		var settings := profile()
		var field := WorldField.new(seed_value, settings)
		var reverse := WorldField.new(seed_value, settings)
		var plans: Dictionary = {}
		for band in range(-1, 64):
			plans[band] = RoadSpawns.plan(field, band)
		for band in range(63, -2, -1):
			var data: Dictionary = plans[band]
			check(data == RoadSpawns.plan(reverse, band), "Real-world v9 planning is independent of band query order")
			if band < 3:
				check(empty(data), "v9 preserves the initial 450 m and rear-band safety zone")
			var boxes: Array[AABB] = []
			for placement in data.wrecks + data.strips + data.barrels:
				var box: AABB = placement.bounds
				check_bounds(field, band, box)
				check(CheckpointSchema.valid_transform(placement.transform), "Road prop pose is finite and valid")
				check(placement.transform.basis.y.dot(field.normal_at(placement.transform.origin.x, placement.transform.origin.z)) > 0.99, "Road props follow the surface slope")
			for placement in data.strips + data.barrels:
				boxes.append(placement.bounds)
			for barrel in data.barrels:
				check(barrel.scene == "res://props/oil_barrel.tscn", "Ordinary road barrel is a real Item scene")
			for wreck in data.wrecks:
				check_wreck_bounds(wreck)
				var yaw := absf(wreck.transform.basis.get_euler().y)
				arbitrary_wreck_yaw = arbitrary_wreck_yaw or (yaw > 0.4 and absf(yaw - PI * 0.5) > 0.2)
			for i in range(data.wrecks.size()):
				for j in range(i):
					check(not actual_wrecks_overlap(data.wrecks[i].transform, data.wrecks[j].transform), "Actual authored wreck colliders never overlap at arbitrary yaws")
			var actor_boxes: Array[AABB] = []
			for index in range(data.monsters.size()):
				var point: Vector3 = data.monsters[index]
				var size := RoadSpawns._v9_monster_size(data.monster_scenes[index])
				var box := AABB(point - Vector3(size.x * 0.5, 0.5, size.z * 0.5), size)
				check_bounds(field, band, box)
				for obstacle in boxes:
					check(not flat_overlap(box, obstacle), "Road actors avoid every static road obstacle and ordinary barrel")
				for wreck in data.wrecks:
					for part in collision_parts:
						check(not polygons_overlap(RoadSpawns._box_footprint(box), project_part(wreck.transform, part)), "Road actors avoid actual wreck colliders at arbitrary yaw")
				for previous in actor_boxes:
					check(not flat_overlap(box, previous), "Independently positioned road actors do not physically overlap")
				actor_boxes.append(box)
			check(data.monsters.size() == data.monster_scenes.size() and data.monsters.size() == data.monster_yaws.size(), "Real world monster plan arrays remain aligned")
	check(arbitrary_wreck_yaw, "Real-world scan contains freely rotated wrecks")
	check(root.get_child_count() == root_children, "Pure road planning does not instantiate actors or other scene nodes")

func check_bounds(field: WorldField, band: int, box: AABB) -> void:
	check(box.position.z >= -(band + 1) * field.profile.chunk_length + 5.0 and box.end.z <= -band * field.profile.chunk_length - 5.0, "Every full road footprint clears both band seams by five metres")
	for site in field.sites_near_z(box.get_center().z, 400.0):
		check(absf(float(site.s) + box.get_center().z) >= 55.0, "Road content clears safe-site driveways")
		if site.has("bounds"):
			check(not flat_overlap(box, site.bounds.grow(8.0)), "Road content clears protected site bounds")
		for corner in RoadSpawns._corners(box):
			check(field.court_distance(corner.x, corner.z, site) >= 8.0, "Road content clears actual site courts")
	for corner in RoadSpawns._corners(box):
		var road := field.road_query(corner.x, corner.z)
		check(road.distance <= road.width * 0.5 + 4.0 and field.normal_at(corner.x, corner.z).y >= 0.90, "Road content fits the clear shoulder and valid slope")

func check_legacy_versions() -> void:
	for version in range(2, 8):
		for band in [3, 7, 12, 31]:
			check(empty(RoadSpawns.plan(WorldField.new(42, profile(version)), band)), "v2-v7 receive no new road content")
	for seed_value in range(16):
		var field := WorldField.new(seed_value, profile(8))
		for band in range(3, 12):
			var data := RoadSpawns.plan(field, band)
			check(data.get("barrels", []).is_empty() and data.get("monster_yaws", []).is_empty(), "v8 does not acquire v9 barrels or randomized monster headings")
	check(CheckpointSchema.profile_error({"generation_version": 9}).is_empty(), "Checkpoint profile accepts generation v9")
	check(not CheckpointSchema.profile_error({"generation_version": 11}).is_empty(), "Unsupported future generation versions remain rejected")

func read_wreck_collisions() -> void:
	var wreck: Node3D = load(RoadSpawns.WRECK_SCENE).instantiate()
	for shape_node: CollisionShape3D in wreck.find_children("*", "CollisionShape3D", true, false):
		if shape_node.disabled or not shape_node.shape is BoxShape3D:
			continue
		var shape: BoxShape3D = shape_node.shape
		var relative := shape_node.transform
		var ancestor: Node3D = shape_node.get_parent()
		while ancestor != wreck:
			relative = ancestor.transform * relative
			ancestor = ancestor.get_parent()
		var points := PackedVector3Array()
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					points.append(relative * (shape.size * Vector3(x, y, z) * 0.5))
		collision_parts.append(points)
	wreck.free()
	check(not collision_parts.is_empty(), "Geometry checks use actual authored wreck collision shapes")

func check_wreck_bounds(placement: Dictionary) -> void:
	var box: AABB = placement.bounds.grow(0.001)
	for part in collision_parts:
		for point in part:
			var world_point: Vector3 = placement.transform * point
			if not box.has_point(world_point) and not reported_wreck_corner:
				reported_wreck_corner = true
				print("V9_WRECK_CORNER_DIAGNOSTIC pose=", placement.transform, " local_corner=", point, " world_corner=", world_point, " bounds=", placement.bounds, " grown_bounds=", box)
			check(box.has_point(world_point), "Rotated planner wreck bounds contain every authored collider corner")

func actual_wrecks_overlap(a: Transform3D, b: Transform3D) -> bool:
	for first in collision_parts:
		for second in collision_parts:
			if polygons_overlap(project_part(a, first), project_part(b, second)):
				return true
	return false

func project_part(pose: Transform3D, part: PackedVector3Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for local in part:
		var point := pose * local
		points.append(Vector2(point.x, point.z))
	return Geometry2D.convex_hull(points)

func polygons_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for polygon in [a, b]:
		for index in range(polygon.size() - 1):
			var edge: Vector2 = polygon[index + 1] - polygon[index]
			var axis := Vector2(-edge.y, edge.x).normalized()
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for point in a:
				amin = minf(amin, point.dot(axis))
				amax = maxf(amax, point.dot(axis))
			for point in b:
				bmin = minf(bmin, point.dot(axis))
				bmax = maxf(bmax, point.dot(axis))
			if amax <= bmin or bmax <= amin:
				return false
	return true

func flat_overlap(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x and a.end.x > b.position.x and a.position.z < b.end.z and a.end.z > b.position.z

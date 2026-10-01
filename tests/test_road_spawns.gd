extends SceneTree
## Pure planner invariants; no terrain/navigation scene is needed for seed scans.
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func empty(data: Dictionary) -> bool:
	return data.strips.is_empty() and data.wrecks.is_empty() and data.monsters.is_empty() and not data.blocked

func run() -> void:
	var totals := {"strips": 0, "wrecks": 0, "monsters": 0, "blocked": 0}
	for version in range(2, 8):
		var profile := WorldProfile.new()
		profile.generation_version = version
		for band in [3, 7, 12, 31]:
			check(empty(RoadSpawns.plan(WorldField.new(42, profile), band)), "Old worlds receive no v8 road content")
	for seed_value in range(12):
		var profile := WorldProfile.new()
		profile.generation_version = 8
		var field := WorldField.new(seed_value, profile)
		var reverse := WorldField.new(seed_value, profile)
		var expected: Dictionary = {}
		for band in range(-1, 64):
			expected[band] = RoadSpawns.plan(field, band)
		for band in range(63, -2, -1):
			var data: Dictionary = expected[band]
			check(data == RoadSpawns.plan(reverse, band), "Seed/band plan is independent of query order")
			if band < 3: check(empty(data), "Initial 450 m and rear bands are safe")
			for category in ["strips", "wrecks", "monsters"]:
				if not data[category].is_empty(): totals[category] += 1
			var static_boxes: Array[AABB] = []
			for placement in data.wrecks + data.strips:
				var box: AABB = placement.bounds
				check(box.position.z >= -(band + 1) * 150.0 + 5.0 and box.end.z <= -band * 150.0 - 5.0, "Entire object clears both seams")
				check(CheckpointSchema.valid_transform(placement.transform), "Finite slope-aligned pose")
				check(placement.transform.basis.y.dot(field.normal_at(placement.transform.origin.x, placement.transform.origin.z)) > 0.99, "Pose follows ground slope")
				for site in field.sites_near_z(box.get_center().z, 400):
					check(absf(float(site.s) + box.get_center().z) >= 55.0, "Driveway mouth remains clear")
					if site.has("bounds"):
						var expanded: AABB = site.bounds.grow(8)
						check(not (box.position.x < expanded.end.x and box.end.x > expanded.position.x and box.position.z < expanded.end.z and box.end.z > expanded.position.z), "Buildings and parking bounds remain clear")
				static_boxes.append(box)
			for strip in data.strips:
				for wreck in data.wrecks:
					check(not overlaps(strip.bounds, wreck.bounds), "Spikes never appear under a wreck")
			for i in range(data.wrecks.size()):
				for j in range(i):
					check(not RoadSpawns._footprints_overlap(RoadSpawns._wreck_footprint(data.wrecks[i].transform), RoadSpawns._wreck_footprint(data.wrecks[j].transform)), "Wreck model footprints do not overlap")
			for point: Vector3 in data.monsters:
				var box := AABB(point - Vector3(1, 0.5, 1), RoadSpawns.MONSTER_SIZE)
				check(box.position.z >= -(band + 1) * 150.0 + 5 and box.end.z <= -band * 150.0 - 5, "Monster footprint clears seams")
				for obstacle in static_boxes: check(not overlaps(box, obstacle), "Monster avoids static road obstacles")
			if data.blocked:
				totals.blocked += 1
				check(data.wrecks.size() in [3, 4], "Blockades contain three or four wrecks")
				# Sweep an RV-sized corridor across the actual existing body boxes.
				check(blocks_road(field, data.wrecks), "Blockade leaves no vehicle-width asphalt passage")
			elif not data.wrecks.is_empty():
				check(data.wrecks.size() in [1, 2], "Ordinary encounters contain one or two wrecks")
				for wreck in data.wrecks:
					for point in RoadSpawns._corners(wreck.bounds):
						check(field.road_query(point.x, point.z).distance >= 2.5, "Ordinary wrecks preserve five metre central passage")
			# Consume unrelated streams between repeated queries; no global RNG drift.
			field.rng_for(band, "road_spawn_strips").randf()
			field.rng_for(band, "road_spawn_wrecks").randf()
			field.rng_for(band, "road_spawn_monsters").randf()
			field.loot_plan(band)
			check(data == RoadSpawns.plan(field, band), "Category and loot RNG calls do not perturb planner")
	for category in totals: check(totals[category] > 0, "Seed scan exercises " + category)
	check(totals.strips < 150 and totals.wrecks < 220 and totals.monsters < 300, "Density stays below candidate chances plus sampling tolerance")
	check(CheckpointSchema.profile_error({"generation_version": 8}).is_empty(), "Checkpoint profile accepts v8")
	check(not CheckpointSchema.profile_error({"generation_version": 9}).is_empty(), "Unknown generation version remains rejected")
	print("ROAD_SPAWN_COUNTS ", totals)
	if failures.is_empty(): print("PASS: v8 deterministic road planning, safety, clearance and legacy isolation")
	quit(0 if failures.is_empty() else 1)

func overlaps(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x and a.end.x > b.position.x and a.position.z < b.end.z and a.end.z > b.position.z

func blocks_road(field: WorldField, wrecks: Array) -> bool:
	var center := Vector3.ZERO
	for wreck in wrecks: center += wreck.transform.origin
	center /= wrecks.size()
	var road: Dictionary = field.road_query(center.x, center.z)
	var width: float = road.width
	for lane in range(101):
		var offset := lerpf(-width * 0.5 + 1.0, width * 0.5 - 1.0, lane / 100.0)
		var candidate: Vector3 = road.frame * Vector3(offset, 0, 0)
		var hit := false
		for wreck in wrecks:
			var aligned: Transform3D = wreck.transform * Transform3D(Basis(Vector3.UP, RoadSpawns.WRECK_MODEL_YAW), Vector3.ZERO)
			# Existing body collision: 2.05 x 4.5; account for a 2 m wide vehicle.
			var local: Vector3 = aligned.affine_inverse() * candidate
			if absf(local.z) <= 2.25 + 1.0: hit = true
		if not hit: return false
	return true

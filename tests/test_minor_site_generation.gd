extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok and failures.size() < 30: failures.append(note)

func run() -> void:
	var seen := {}
	var sides := {}
	var count := 0
	var max_gap := 0.0
	var min_gap := INF
	for seed_value in range(1000):
		var field := WorldField.new(seed_value)
		var reverse := WorldField.new(seed_value)
		for cell in range(11, -1, -1): reverse.minor_site(cell)
		var previous: Dictionary = {}
		for cell in range(12):
			var site := field.minor_site(cell)
			check(site == reverse.minor_site(cell), "Layout depends on query order")
			if site.is_empty(): continue
			count += 1
			seen[site.definition_id] = true
			sides[site.side] = true
			check(site.s >= 450 and site.s >= cell * 1200 + 150 and site.s <= cell * 1200 + 1050, "Cell/safe-start bounds")
			var band := floori(site.s / 150.0)
			check(field.stops_in_band(band).filter(func(s): return s.id == site.id).size() == 1, "Exactly one owner band")
			check(field.sites_near_z(site.building.origin.z).any(func(s): return s.id == site.id), "World queries find independent site")
			check(field.stop(cell * 3 + 2).is_empty(), "v6 removed the old minor schedule")
			if not previous.is_empty():
				var gap: float = site.s - previous.s
				max_gap = maxf(max_gap, gap)
				min_gap = minf(min_gap, gap)
				check(gap >= 300 and not site.bounds.intersects(previous.bounds), "Minor sites overlap")
			previous = site
			for major in field.sites_near_z(-site.s, 1100):
				if major.get("minor", false): continue
				check(absf(site.s - major.s) >= 120 and not site.bounds.grow(12).intersects(major.bounds), "Major/minor clearance")
			# Sample real curved-road parking and all four marked loot locations.
			if seed_value < 30:
				for x in [-6, 0, 6]:
					for z in [-12, 0, 12]:
						var p: Vector3 = site.frame * Vector3(x, 0, z)
						check(absf(field.height_at(p.x, p.z) - p.y) < 0.18, "Unsupported parking")
				for x in [-5, 5]:
					for z in [0, 4]:
						var p: Vector3 = site.building * Vector3(x, 0, z)
						check(absf(field.height_at(p.x, p.z) - p.y) < 0.18, "Unsupported supplies")
			var loot_before := field.rng_for(cell, "minor_loot").randi()
			field.rng_for(cell, "minor_art").randi()
			check(loot_before == field.rng_for(cell, "minor_loot").randi(), "Art changed loot RNG")
	var mean := 1000.0 * 12 * 1200 / count
	check(mean >= 1000 and mean <= 1500, "Mean density outside target: " + str(mean))
	check(seen.size() == 18 and sides.size() == 2, "All authored variants and road sides occur")
	check(max_gap - min_gap > 800, "Distribution still feels regularly spaced")
	for version in [2, 3, 4, 5]:
		var profile := WorldProfile.new()
		profile.generation_version = version
		var legacy := WorldField.new(42, profile)
		check(not legacy.stop(2).is_empty() and legacy.minor_site(0).is_empty(), "Legacy minor schedule changed")
	# Captured from the pre-v6 commit a2d9423, including peaceful gas stations.
	var records: Array = []
	var v5 := WorldProfile.new()
	v5.generation_version = 5
	for seed_value in [0, 1, 42, 99]:
		var legacy := WorldField.new(seed_value, v5)
		for index in range(12):
			var site := legacy.stop(index)
			records.append(site)
			records.append(legacy.loot_plan(index))
			records.append(legacy.height_at(site.building.origin.x, site.building.origin.z))
	check(var_to_bytes(records).hex_encode().sha256_text() == "f0ce0e6cb030aba0a9f602665c7548d5161f57268eea0a1dcc2917c27391d157", "v5 site, terrain and loot baseline changed")
	print("MINOR_STATS seeds=1000 sites=%d mean_m=%.1f gap_min=%.1f gap_max=%.1f variants=%d" % [count, mean, min_gap, max_gap, seen.size()])
	if failures.is_empty(): print("PASS: v6 deterministic placement, 18 variants, density, clearance, support and legacy schedules")
	for note in failures: push_error("FAIL: " + note)
	quit(0 if failures.is_empty() else 1)

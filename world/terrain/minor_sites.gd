extends RefCounted
class_name MinorSites
## Bounded, order-independent v6 planning. Only major stops are queried here.
const CELL_LENGTH := 1200.0
const THEMES := ["wreck", "camp", "shed", "checkpoint", "cargo", "rest"]

static func definition_ids() -> Array[String]:
	var ids: Array[String] = []
	for theme in THEMES:
		for variant in range(3): ids.append("roadside_%s_%d" % [theme, variant])
	return ids

static func plan(field: WorldField, cell: int) -> Dictionary:
	var placement := field.rng_for(cell, "minor_placement")
	var theme_rng := field.rng_for(cell, "minor_theme")
	var layout_rng := field.rng_for(cell, "minor_layout")
	var id := "roadside_%s_%d" % [THEMES[theme_rng.randi_range(0, 5)], layout_rng.randi_range(0, 2)]
	for attempt in range(4):
		var s := cell * CELL_LENGTH + placement.randf_range(150, 1050)
		var side := -1.0 if placement.randf() < 0.5 else 1.0
		if s < 450: continue
		var site := {"index": cell, "id": "v%d:%d:minor:%d" % [field.profile.generation_version, field.world_seed, cell], "s": s, "side": side,
			"road": field.road_frame(s), "seed": field.seed_for(cell, "minor_art"), "minor": true}
		WalkInSites.configure(site, id)
		var blocked := false
		var nearest := roundi(s / field.profile.stop_spacing)
		for index in range(maxi(0, nearest - 2), nearest + 3):
			var major := field.stop(index)
			if major.is_empty(): continue
			# Separation protects driveway mouths, including opposite road sides.
			if absf(float(major.s) - s) < 120 or site.bounds.grow(12).intersects(major.bounds):
				blocked = true
				break
		if not blocked: return site
	return {}

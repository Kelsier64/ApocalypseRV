extends RefCounted
class_name SlenderSpeakerSpawns
## A segment owns one roll and one candidate band, independent of every other spawn RNG.
const SCENE := "res://enemies/slender_speaker/slender_speaker.tscn"
const SEGMENT_LENGTH := 1500.0
const CHANCE := 0.25
const PLAYER_CLEARANCE := 160.0
const HEIGHT := 15.0
const RADIUS := 1.1

static func plan(field: WorldField, segment: int) -> Dictionary:
	if field.profile.generation_version < 10 or segment < 1: return {}
	var rng := field.rng_for(segment, "slender_speaker_segment")
	if rng.randf() >= CHANCE: return {"segment": segment, "band": segment * 10, "candidates": []}
	var s := segment * SEGMENT_LENGTH + rng.randf_range(8.0, SEGMENT_LENGTH - 8.0)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var band := floori(s / field.profile.chunk_length)
	var candidates: Array[Vector3] = []
	for attempt in range(24):
		# Retry locally inside the chosen band. No failed roll can turn into a
		# delayed encounter when another chunk is rebuilt or the player returns.
		var distance := s if attempt == 0 else band * field.profile.chunk_length + rng.randf_range(8.0, 142.0)
		var road := field.road_frame(distance)
		var point := road.origin + road.basis.x * side * (field.road_width(distance) * 0.5 + rng.randf_range(40.0, 100.0))
		point.y = field.height_at(point.x, point.z)
		if floori(-point.z / field.profile.chunk_length) != band: continue
		if static_valid(field, point): candidates.append(point)
	return {"segment": segment, "band": band, "candidates": candidates}

static func static_valid(field: WorldField, point: Vector3) -> bool:
	if -point.z < SEGMENT_LENGTH or not point.is_finite(): return false
	var query := field.road_query(point.x, point.z)
	var offset: float = query.distance - query.width * 0.5
	if offset < 40.0 or offset > 100.0 or field.normal_at(point.x, point.z).y < cos(deg_to_rad(35.0)): return false
	for site in field.sites_near_z(point.z, 400.0):
		if field.court_distance(point.x, point.z, site) < 20.0: return false
		if site.has("bounds") and site.bounds.grow(RADIUS + 3.0).has_point(point): return false
	return true

static func forest_valid(field: WorldField, point: Vector3) -> bool:
	var nearby := 0
	var band := floori(-point.z / field.profile.chunk_length)
	for neighbour in [band - 1, band, band + 1]:
		var trees := ForestScenery.trees(field, neighbour)
		for index in range(trees.size()):
			if field.destroyed_trees.has(TreeImpact.forest_id(neighbour, index)): continue
			var tree: Dictionary = trees[index]
			var delta: Vector3 = tree.point - point
			delta.y = 0.0
			if delta.length() < RADIUS + 0.7: return false
			if delta.length() < 30.0: nearby += 1
	return nearby >= 3

static func valid_ledger(value: Variant) -> bool:
	if not value is Array: return false
	var seen := {}
	for segment in value:
		if not segment is int or segment < 1 or seen.has(segment): return false
		seen[segment] = true
	return true

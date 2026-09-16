extends RefCounted
class_name WorldField
## Pure world-coordinate queries. Never depends on global RNG or loaded nodes.
const VERSION := 4
var world_seed: int
var profile: WorldProfile
var macro := FastNoiseLite.new()
var medium := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var clusters := FastNoiseLite.new()
var _phase: float
var _heights: Dictionary = {0: 0.0, 1: 0.0}
var _stops: Dictionary = {}
var forest_cache: Dictionary = {}

func _init(seed_value: int = 42, settings: WorldProfile = null) -> void:
	world_seed = seed_value
	profile = settings if settings != null else WorldProfile.new()
	var noises := [macro, medium, detail, clusters]
	var frequencies := [0.0011, 0.008, 0.07, 0.024]
	for i in range(noises.size()):
		noises[i].seed = seed_for(i, "noise")
		noises[i].noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noises[i].frequency = frequencies[i]
		noises[i].fractal_octaves = 3
	_phase = rng_for(0, "road").randf_range(-PI, PI)

func seed_for(id: int, domain: String) -> int:
	return int(("%d:%d:%d:%s" % [profile.generation_version, world_seed, id, domain]).hash())

func rng_for(id: int, domain: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(id, domain)
	return rng

func region_weights(x: float, z: float) -> Vector3:
	var distance := maxf(0.0, -z + macro.get_noise_2d(x, z) * 90.0)
	var index := floori(distance / profile.region_length)
	var t := fposmod(distance, profile.region_length)
	var weights := Vector3.ZERO
	weights[posmod(index + world_seed, 3)] = 1.0
	var blend := smoothstep(profile.region_length - profile.region_transition, profile.region_length, t)
	weights *= 1.0 - blend
	weights[posmod(index + world_seed + 1, 3)] += blend
	return weights

func raw_height(x: float, z: float) -> float:
	var w := region_weights(x, z)
	var large := macro.get_noise_2d(x, z) * 42.0
	var middle := medium.get_noise_2d(x, z)
	return large + middle * (w.x * 5.0 + w.y * 11.0 + w.z * 26.0) + detail.get_noise_2d(x, z) * 0.7

func road_x(s: float) -> float:
	var fade := smoothstep(150.0, 600.0, s)
	var curve_scale := minf(1.0, 80.0 / maxf(80.0, profile.min_turn_radius))
	return curve_scale * fade * (48.0 * sin(s * TAU / 1200.0 + _phase) + 16.0 * sin(s * TAU / 720.0 - _phase))

func _height_knot(index: int) -> float:
	if index <= 1:
		return 0.0
	if not _heights.has(index):
		# Fill in order even when a far tile is requested first (no load-order drift).
		var begin := _heights.size()
		for i in range(begin, index + 1):
			var s := i * profile.chunk_length
			var target := macro.get_noise_2d(road_x(s), -s) * 32.0
			var previous: float = _heights[i - 1]
			# Smoothstep's peak derivative is 1.5. Narrow sections are level.
			var limit := profile.chunk_length * profile.max_grade / 1.5 * 0.9
			if posmod(i, 6) == 4:
				limit = 0.0
			_heights[i] = clampf(target, previous - limit, previous + limit)
	return _heights[index]

func road_height(s: float) -> float:
	var index := floori(s / profile.chunk_length)
	return lerpf(_height_knot(index), _height_knot(index + 1), smoothstep(0.0, 1.0, fposmod(s, profile.chunk_length) / profile.chunk_length))

func road_frame(s: float) -> Transform3D:
	var forward := Vector3(road_x(s + 0.5) - road_x(s - 0.5), 0.0, -1.0).normalized()
	return Transform3D(Basis.looking_at(forward), Vector3(road_x(s), road_height(s), -s))

func road_width(s: float) -> float:
	if s < 300.0:
		return profile.road_width
	var phase := fposmod(s, profile.chunk_length * 6.0)
	var narrow := smoothstep(455.0, 495.0, phase) * (1.0 - smoothstep(550.0, 595.0, phase))
	return lerpf(profile.road_width, profile.narrow_width, narrow)

func road_query(x: float, z: float) -> Dictionary:
	var s := -z
	for i in range(3):
		var dx := road_x(s)
		var slope := road_x(s + 0.5) - road_x(s - 0.5)
		s -= ((dx - x) * slope + s + z) / (1.0 + slope * slope)
	var frame := road_frame(s)
	var offset := Vector3(x, frame.origin.y, z) - frame.origin
	return {"s": s, "distance": absf(offset.dot(frame.basis.x)), "height": frame.origin.y, "width": road_width(s), "frame": frame}

func stop(index: int) -> Dictionary:
	if index < 0:
		return {}
	if _stops.has(index):
		return _stops[index]
	var rng := rng_for(index, "stop")
	var s := 45.0 if index == 0 else index * profile.stop_spacing + rng.randf_range(-profile.stop_jitter, profile.stop_jitter)
	var side := 1.0 if index == 0 or rng.randf() > 0.5 else -1.0
	var road := road_frame(s)
	var center := road.origin + road.basis.x * side * 33.0
	# Flat parking court and building apron share the adjacent road elevation.
	var frame := Transform3D(road.basis, center)
	var building_pos := road.origin + road.basis.x * side * 49.0
	var facing := (road.origin - building_pos).normalized()
	var building := Transform3D(Basis.looking_at(-facing), building_pos)
	var kind: String = "entrance" if index % 3 == 0 else ["wreck", "camp", "shed"][rng.randi_range(0, 2)]
	var result := {"index": index, "id": "v%d:%d:stop:%d" % [profile.generation_version, world_seed, index], "s": s, "side": side, "frame": frame, "building": building, "road": road, "kind": kind, "seed": seed_for(index, "interior")}
	if profile.generation_version >= 3:
		ExplorationSite.configure(result, self)
	_stops[index] = result
	return result

func stops_in_band(index: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var first := maxi(0, floori(index * profile.chunk_length / profile.stop_spacing) - 1)
	for i in range(first, first + 4):
		var candidate := stop(i)
		if floori(float(candidate.s) / profile.chunk_length) == index:
			found.append(candidate)
	return found

func court_distance(x: float, z: float, site: Dictionary) -> float:
	var local: Vector3 = site.frame.affine_inverse() * Vector3(x, site.frame.origin.y, z)
	# 12x24 parking is wholly clear, with an additional apron for the building.
	var center_x := float(site.side) * 5.0
	var half_width := 7.0 if site.has("route") else 23.0
	var q := Vector2(absf(local.x - center_x) - half_width, absf(local.z) - 18.0)
	var court := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var approach: Vector3 = site.road.affine_inverse() * Vector3(x, site.road.origin.y, z)
	# Flared highway mouth accommodates the 12m RV's swept turning path.
	var driveway := Vector2(absf(approach.x - float(site.side) * 16.5) - 16.5, absf(approach.z) - 20.0)
	return minf(court, Vector2(maxf(driveway.x, 0.0), maxf(driveway.y, 0.0)).length())

func surface(x: float, z: float) -> Dictionary:
	var road := road_query(x, z)
	var height := raw_height(x, z)
	var reserved: bool = road.distance < road.width * 0.5 + 4.0
	var gravel := 0.0
	var nearest := maxi(0, roundi(-z / profile.stop_spacing))
	for i in range(maxi(0, nearest - 1), nearest + 2):
		var site := stop(i)
		if absf(-z - float(site.s)) > (180.0 if profile.generation_version >= 4 else 100.0):
			continue
		if site.has("route"):
			var p: Vector3 = site.road.affine_inverse() * Vector3(x, site.road.origin.y, z)
			p.x *= float(site.side)
			var deep: bool = site.get("deep_forest", false)
			var q := Vector2(maxf(absf(p.x - (199.5 if deep else 99.5)) - (159.5 if deep else 59.5), 0.0), maxf(absf(p.z) - (48 if deep else 42), 0.0))
			var campus := 1.0 - smoothstep(0.0, 16.0, q.length())
			var trail := ExplorationSite.route_distance(Vector3(x, 0, z), site.route)
			var apron := Vector2(p.x - (335.2 if deep else 135), p.z).length() < (15.0 if deep else 13.0)
			var hill := 0.0
			for center in [Vector2(59, -12), Vector2(83, 8), Vector2(122, 26)]:
				hill = maxf(hill, (1.0 - smoothstep(0.0, 13.0, Vector2(p.x, p.z).distance_to(center))) * 3.4)
			hill *= smoothstep(4.0, 10.0, trail)
			if deep:
				# Narrow sunken walks between real banks, with a thin landmark slit.
				hill = smoothstep(4.0, 11.0, trail) * (3.5 + 1.5 * medium.get_noise_2d(x, z)) * smoothstep(5.0, 12.0, absf(p.z))
			if apron: hill = 0.0
			height = lerpf(height, site.frame.origin.y + ExplorationSite.site_rise(site, p.x) + hill, campus)
			gravel = maxf(gravel, (1.0 - smoothstep(1.3, 2.8, trail)) * campus)
			reserved = reserved or trail < (3.1 if deep else 4.5) or apron
			# Keep authored perimeter/baffles clear of random trees and rocks.
			for wall: Dictionary in site.walls:
				var wp: Vector3 = wall.position
				wp.x *= float(site.side)
				if absf(p.x - wp.x) < wall.size.x * 0.5 + 2 and absf(p.z - wp.z) < wall.size.z * 0.5 + 2:
					reserved = true
		var court_distance := court_distance(x, z, site)
		var influence := 1.0 - smoothstep(0.0, 16.0, court_distance)
		height = lerpf(height, site.frame.origin.y, influence)
		gravel = maxf(gravel, influence)
		reserved = reserved or court_distance < 4.0
	# Road wins where the edge of a court approaches the live carriageway.
	var earthwork_width := maxf(profile.road_shoulder, absf(height - float(road.height)) * 2.5)
	var road_blend := 1.0 - smoothstep(float(road.width) * 0.5, float(road.width) * 0.5 + earthwork_width, float(road.distance))
	height = lerpf(height, float(road.height), road_blend)
	# Shared safe spawn apron replaces the old scene's isolated CSG floor.
	var spawn_distance := Vector2(maxf(absf(x) - 14.0, 0.0), maxf(absf(z) - 14.0, 0.0)).length()
	height = lerpf(height, 0.0, 1.0 - smoothstep(0.0, 20.0, spawn_distance))
	reserved = reserved or spawn_distance < 8.0
	return {"height": height, "reserved": reserved, "gravel": gravel, "road": road, "weights": region_weights(x, z)}

func height_at(x: float, z: float) -> float:
	return float(surface(x, z).height)

func normal_at(x: float, z: float) -> Vector3:
	return Vector3(height_at(x - 0.5, z) - height_at(x + 0.5, z), 1.0, height_at(x, z - 0.5) - height_at(x, z + 0.5)).normalized()

func loot_plan(index: int) -> Array[String]:
	var rng := rng_for(index, "loot")
	var result: Array[String] = []
	for i in range(rng.randi_range(1, 2 if profile.generation_version >= 3 else 3)):
		result.append("res://props/gas_can.tscn" if rng.randf() < 0.2 else "res://props/scrap.tscn")
	return result

func enemy_count(index: int) -> int:
	return rng_for(index, "enemies").randi_range(0, 2)

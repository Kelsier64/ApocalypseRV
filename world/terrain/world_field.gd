extends RefCounted
class_name WorldField
## Pure world-coordinate queries. Never depends on global RNG or loaded nodes.
var world_seed: int
var profile: WorldProfile
var macro := FastNoiseLite.new()
var medium := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var clusters := FastNoiseLite.new()
var _stops: Dictionary = {}
var _minor_sites: Dictionary = {}
var _offroad_sites: Dictionary = {}
var _site_queries: Dictionary = {}
var forest_cache: Dictionary = {}
var destroyed_trees: Dictionary = {}
var route: TerrainRoute
var landforms: TerrainLandforms

func _init(seed_value: int = 42, settings: WorldProfile = null) -> void:
	world_seed = seed_value
	profile = settings if settings != null else WorldProfile.new()
	var noises := [macro, medium, detail, clusters]
	var frequencies := [0.0011, 0.008, 0.07, 0.024]
	for i in range(noises.size()):
		noises[i].seed = seed_for(i, "noise", 13)
		noises[i].noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noises[i].frequency = frequencies[i]
		noises[i].fractal_octaves = 3
	route = TerrainRoute.new(self)
	landforms = TerrainLandforms.new(self)

func seed_for(id: int, domain: String, version_override: int = -1) -> int:
	var version := profile.generation_version if version_override < 0 else version_override
	# v16/v17 change the off-road pool and save identity, while retaining the
	# established v15 rolls for placement, roadside content and encounters.
	if version_override < 0 and version in [16, 17]: version = 15
	return int(("%d:%d:%d:%s" % [version, world_seed, id, domain]).hash())

func rng_for(id: int, domain: String, version_override: int = -1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(id, domain, version_override)
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
	return landforms.height(x, z, road_query(x, z))

func road_x(s: float) -> float:
	return route.x(s)

func road_height(s: float) -> float:
	return route.height(s)

func road_frame(s: float) -> Transform3D:
	var forward := Vector3(road_x(s + 0.5) - road_x(s - 0.5), 0.0, -1.0).normalized()
	return Transform3D(Basis.looking_at(forward), Vector3(road_x(s), road_height(s), -s))

func road_width(s: float) -> float:
	return route.width(s)

func road_query(x: float, z: float) -> Dictionary:
	return route.query(x, z)

func stop(index: int) -> Dictionary:
	if index < 0:
		return {}
	if index % 3 == 2:
		return {}
	if _stops.has(index):
		return _stops[index]
	var rng := rng_for(index, "stop")
	var s := 45.0 if index == 0 else index * profile.stop_spacing + rng.randf_range(-profile.stop_jitter, profile.stop_jitter)
	# Crossing banks must remain continuous: no driveway, building pad or POI
	# terrace may fill the river or cut a bridge approach.
	if index > 0 and not landforms.crossing_clearance(s):
		return {}
	var side := 1.0 if index == 0 or rng.randf() > 0.5 else -1.0
	var road := road_frame(s)
	var result := {"index": index, "id": "v%d:%d:stop:%d" % [profile.generation_version, world_seed, index], "s": s, "side": side, "road": road, "seed": seed_for(index, "interior"), "placement": "roadside"}
	if index == 0 or index % 3 == 1:
		result.side = ExplorationSite.select_side(road, side, self)
		WalkInSites.configure(result, profile.opening_shelter_id() if index == 0 else "gas_station")
	else:
		ExplorationSite.configure(result, self)
	if index > 0 and not landforms.site_clear(result):
		_stops[index] = {}
		return {}
	_stops[index] = result
	return result

func stops_in_band(index: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for candidate in sites_near_z(-(index + 0.5) * profile.chunk_length, profile.chunk_length):
		if floori(float(candidate.s) / profile.chunk_length) == index:
			found.append(candidate)
	return found

## All placement pools share one query; consumers never infer sites from stops.
func sites_near_z(z: float, radius: float = 240.0) -> Array[Dictionary]:
	# Terrain rows repeatedly ask the same longitudinal question for different X.
	# Results are read-only, like stop(); bound the cache during long drives.
	radius = maxf(radius, 420.0)
	var key := Vector2(z, radius)
	if _site_queries.has(key): return _site_queries[key]
	var found: Array[Dictionary] = []
	var first := maxi(0, floori((-z - radius - profile.stop_jitter) / profile.stop_spacing))
	var last := maxi(0, ceili((-z + radius + profile.stop_jitter) / profile.stop_spacing))
	for index in range(first, last + 1):
		var site := stop(index)
		if not site.is_empty() and absf(float(site.s) + z) <= radius:
			found.append(site)
	for cell in range(maxi(0, floori((-z - radius) / MinorSites.CELL_LENGTH)), maxi(0, floori((-z + radius) / MinorSites.CELL_LENGTH)) + 1):
		var site := minor_site(cell)
		if not site.is_empty() and absf(float(site.s) + z) <= radius:
			found.append(site)
	for row in range(maxi(0, floori((-z - radius) / OffroadSites.CELL_LENGTH)), maxi(0, floori((-z + radius) / OffroadSites.CELL_LENGTH)) + 1):
		for column in range(OffroadSites.COLUMNS):
			var site := offroad_site(row, column)
			if not site.is_empty() and absf(float(site.s) + z) <= radius:
				found.append(site)
	found.sort_custom(func(a, b): return a.s < b.s)
	if _site_queries.size() >= 256: _site_queries.clear()
	_site_queries[key] = found
	return found

func minor_site(cell: int) -> Dictionary:
	if cell < 0: return {}
	if not _minor_sites.has(cell): _minor_sites[cell] = MinorSites.plan(self, cell)
	return _minor_sites[cell]

func offroad_site(row: int, column: int) -> Dictionary:
	if row < 0 or column < 0 or column >= OffroadSites.COLUMNS: return {}
	var key := Vector2i(row, column)
	if not _offroad_sites.has(key): _offroad_sites[key] = OffroadSites.plan(self, row, column)
	return _offroad_sites[key]

func court_distance(x: float, z: float, site: Dictionary) -> float:
	var point := Vector3(x, site.frame.origin.y, z)
	if site.get("placement", "roadside") == "off_road" or site.kind == "entrance":
		return OffroadSites.court_distance(point, site)
	return WalkInSites.court_distance(point, site)

func surface(x: float, z: float) -> Dictionary:
	var road := road_query(x, z)
	var height := landforms.height(x, z, road)
	var reserved: bool = road.distance < road.width * 0.5 + 4.0
	var gravel := 0.0
	for site in sites_near_z(z):
		if site.has("bounds"):
			var bounds: AABB = site.bounds.grow(25.0)
			if z < bounds.position.z or z > bounds.end.z: continue
		elif absf(-z - float(site.s)) > 180.0:
			continue
		var court_distance := court_distance(x, z, site)
		var influence := 1.0 - smoothstep(0.0, 16.0, court_distance)
		height = lerpf(height, site.frame.origin.y, influence)
		gravel = maxf(gravel, influence)
		reserved = reserved or court_distance < 4.0
	# Road wins where the edge of a court approaches the live carriageway.
	var earthwork_width := clampf(profile.road_shoulder, 8.0, 18.0)
	var water_height := -INF
	var river_bank := 0.0
	var channel_influence := 0.0
	var channel := landforms.channel(x, z, height)
	height = channel.height
	water_height = channel.water_height
	channel_influence = landforms.bridge_gap(float(road.s))
	river_bank = channel.bank
	reserved = reserved or channel.wet
	var road_blend := 1.0 - smoothstep(float(road.width) * 0.5, float(road.width) * 0.5 + earthwork_width, float(road.distance))
	road_blend *= 1.0 - channel_influence
	height = lerpf(height, float(road.height), road_blend)
	# Shared safe spawn apron replaces the old scene's isolated CSG floor.
	var spawn_distance := Vector2(maxf(absf(x) - 14.0, 0.0), maxf(absf(z) - 14.0, 0.0)).length()
	height = lerpf(height, 0.0, 1.0 - smoothstep(0.0, 20.0, spawn_distance))
	reserved = reserved or spawn_distance < 8.0
	if profile.opening_shelter_id() == "orientation_shelter":
		var orientation_surface := _orientation_shelter_surface(x, z, height)
		height = orientation_surface.height
		reserved = reserved or orientation_surface.reserved
	elif z >= -100.0 and z <= 40.0:
		var garage_surface := _starting_shelter_surface(x, z, height)
		height = garage_surface.height
		reserved = reserved or garage_surface.reserved
	var result := {"height": height, "reserved": reserved, "gravel": gravel, "road": road, "weights": region_weights(x, z), "water_height": water_height, "river_bank": river_bank}
	result.appearance = landforms.appearance_at(-z)
	var a: Vector3 = result.appearance
	result.moisture = lerpf(TerrainLandforms.MOISTURE[int(a.x)], TerrainLandforms.MOISTURE[int(a.y)], a.z)
	return result

## Authored opening area: a level garage/forecourt with earth against its sides
## and rear. Applied after the shared road/spawn blending to keep its floor exact.
func _starting_shelter_surface(x: float, z: float, height: float) -> Dictionary:
	var site := stop(0)
	var point := Vector3(x, 0, z)
	var local: Vector3 = site.building.affine_inverse() * point
	var distance := WalkInSites.court_distance(point, site)
	var reserved := distance < 4.0
	if distance <= 0.0:
		height = 0.0
	else:
		# The garage is recessed into low banks; the open +Z frontage stays clear.
		var bounds: AABB = POIConfig.definition(&"starting_shelter").building_bounds
		var half_width := bounds.size.x * 0.5
		var half_depth := bounds.size.z * 0.5
		var side_bank := (1.0 - smoothstep(4.0, 14.0, absf(absf(local.x - bounds.get_center().x) - half_width - 12.0))) * (1.0 - smoothstep(half_depth - 3.0, half_depth + 11.0, absf(local.z - bounds.get_center().z)))
		var rear_bank := (1.0 - smoothstep(4.0, 15.0, absf(local.z - bounds.position.z + 10.0))) * (1.0 - smoothstep(half_width + 4.0, half_width + 20.0, absf(local.x - bounds.get_center().x)))
		var bank := maxf(side_bank, rear_bank) * smoothstep(0.0, 6.0, distance)
		height = lerpf(height, 5.0, bank)
	# Concrete tops are authored at zero. Every grid vertex supporting a slab
	# edge triangle must stay below it, including vertices outside its footprint.
	# Keep a full grid cell of recessed backing, then blend over another cell.
	var garage_edge := maxf(absf(local.x) - 10.4, absf(local.z + 0.2) - 14.2)
	var apron_edge := maxf(absf(local.x) - 16.0, maxf(14.0 - local.z, local.z - 44.0))
	var slab_recess := 1.0 - smoothstep(profile.terrain_step, profile.terrain_step * 2.0, minf(garage_edge, apron_edge))
	height = lerpf(height, -0.08, slab_recess)
	reserved = reserved or slab_recess > 0.0
	# Keep the rear barrier vegetation clear of the garage.
	var ridge := 1.0 - smoothstep(3.0, 16.0, absf(z - 20.0))
	if ridge > 0.0:
		reserved = true
	if absf(x) <= 25.0 and z >= 14.0 and z <= 29.0:
		height = 0.0
		reserved = true
	return {"height": height, "reserved": reserved}

## Keep the orientation shelter floor and apron clear of terrain.
func _orientation_shelter_surface(x: float, z: float, height: float) -> Dictionary:
	var site := stop(0)
	var world_influence: AABB = site.bounds.grow(24.0)
	if x < world_influence.position.x or x > world_influence.end.x or z < world_influence.position.z or z > world_influence.end.z:
		return {"height": height, "reserved": false}
	var point := Vector3(x, 0, z)
	var local: Vector3 = site.building.affine_inverse() * point
	var definition := POIConfig.definition_for_site(site)
	var bounds: AABB = definition.building_bounds
	var influence: AABB = definition.site_bounds.grow(24.0)
	if local.x < influence.position.x or local.x > influence.end.x or local.z < influence.position.z or local.z > influence.end.z:
		return {"height": height, "reserved": false}
	var distance := WalkInSites.court_distance(point, site)
	var reserved := distance < 4.0
	if distance <= 0.0:
		height = 0.0
	else:
		var half_width := bounds.size.x * 0.5
		var half_depth := bounds.size.z * 0.5
		var side_bank := (1.0 - smoothstep(4.0, 14.0, absf(absf(local.x - bounds.get_center().x) - half_width - 12.0))) * (1.0 - smoothstep(half_depth - 3.0, half_depth + 11.0, absf(local.z - bounds.get_center().z)))
		var rear_bank := (1.0 - smoothstep(4.0, 15.0, absf(local.z - bounds.position.z + 10.0))) * (1.0 - smoothstep(half_width + 4.0, half_width + 20.0, absf(local.x - bounds.get_center().x)))
		height = lerpf(height, 5.0, maxf(side_bank, rear_bank) * smoothstep(0.0, 6.0, distance))
	# Recess the full authored corridor and apron, including a terrain cell
	# outside their slab edges, so terrain triangles cannot cover the floor.
	var rear_edge := -46.4
	var corridor_edge := maxf(absf(local.x) - 20.4, maxf(rear_edge - local.z, local.z - 14.0))
	var apron_edge := maxf(absf(local.x) - 22.0, maxf(14.0 - local.z, local.z - 44.0))
	var slab_recess := 1.0 - smoothstep(profile.terrain_step, profile.terrain_step * 2.0, minf(corridor_edge, apron_edge))
	height = lerpf(height, -0.08, slab_recess)
	reserved = reserved or slab_recess > 0.0
	return {"height": height, "reserved": reserved}

func height_at(x: float, z: float) -> float:
	return float(surface(x, z).height)

func normal_at(x: float, z: float) -> Vector3:
	return Vector3(height_at(x - 0.5, z) - height_at(x + 0.5, z), 1.0, height_at(x, z - 0.5) - height_at(x, z + 0.5)).normalized()

func loot_plan(index: int) -> Array[String]:
	var rng := rng_for(index, "loot")
	var result: Array[String] = []
	for i in range(rng.randi_range(1, 2)):
		result.append("res://props/gas_can.tscn" if rng.randf() < 0.2 else "res://props/scrap.tscn")
	return result

func enemy_count(index: int) -> int:
	return rng_for(index, "enemies").randi_range(0, 2)

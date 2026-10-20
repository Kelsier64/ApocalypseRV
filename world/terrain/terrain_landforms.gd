extends RefCounted
class_name TerrainLandforms
## Shared deterministic terrain and crossing plans, independent of loaded bands.
const REGION_LENGTH := 1800.0
const KINDS := ["meadow", "cliff", "wetland", "ridge", "canyon", "basin"]
const COLORS := [Color("747b52"), Color("7e8174"), Color("4d6252"), Color("858478"), Color("927c61"), Color("596b4f")]
var _field: WeakRef
var field: WorldField:
	get: return _field.get_ref()
var offset: int
var _rivers: Dictionary = {}
var rail_cache: Dictionary = {}
const STRUCTURE_STEP := 15.0
var _clearance: Dictionary = {}
var _structure_cells: Dictionary = {}
var relief := FastNoiseLite.new()
const COLORS_V14 := [Color("65724e"), Color("74776c"), Color("414f3e"), Color("797b73"), Color("887259"), Color("424e36")]
const TREE_DENSITY := [0.16, 0.24, 0.13, 0.075, 0.10, 0.70]
const GROUND_DENSITY := [0.82, 0.16, 0.78, 0.24, 0.16, 0.60]
const MOISTURE := [0.25, 0.10, 0.90, 0.04, 0.06, 0.62]
const ROCK_EXPOSURE := [0.10, 0.78, 0.06, 0.85, 0.74, 0.14]

func material_weights(appearance: Vector3) -> Vector2:
	return Vector2(lerpf(ROCK_EXPOSURE[int(appearance.x)], ROCK_EXPOSURE[int(appearance.y)], appearance.z), lerpf(MOISTURE[int(appearance.x)], MOISTURE[int(appearance.y)], appearance.z))

func _init(world_field: WorldField) -> void:
	_field = weakref(world_field)
	offset = field.rng_for(0, "landform_order", 13 if field.profile.generation_version == 14 else -1).randi_range(0, KINDS.size() - 1)
	if field.profile.generation_version >= 14:
		relief.seed = field.seed_for(0, "terrain_relief_v14")
		relief.frequency = 0.016
		relief.fractal_octaves = 2
		relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

func appearance_at(s: float) -> Vector3:
	var t := maxf(0.0, s - 600.0)
	var index := floori(t / REGION_LENGTH)
	return Vector3(posmod(index + offset, KINDS.size()), posmod(index + offset + 1, KINDS.size()), smoothstep(REGION_LENGTH - 360.0, REGION_LENGTH, fposmod(t, REGION_LENGTH)))

func kind_at(s: float) -> String:
	return KINDS[posmod(floori(maxf(0.0, s - 600.0) / REGION_LENGTH) + offset, KINDS.size())]

func color_at(s: float) -> Color:
	if field.profile.generation_version >= 14:
		var a := appearance_at(s)
		return COLORS_V14[int(a.x)].lerp(COLORS_V14[int(a.y)], a.z)
	var t := maxf(0.0, s - 600.0)
	var index := floori(t / REGION_LENGTH)
	var blend := smoothstep(REGION_LENGTH - 360.0, REGION_LENGTH, fposmod(t, REGION_LENGTH))
	return COLORS[posmod(index + offset, KINDS.size())].lerp(COLORS[posmod(index + offset + 1, KINDS.size())], blend)

func _shape(kind: String, x: float, z: float, road: Dictionary) -> float:
	var lateral: float = x - road.frame.origin.x
	var side := -1.0 if posmod(offset, 2) == 0 else 1.0
	var u := lateral * side
	var broad := field.macro.get_noise_2d(x, z)
	var middle := field.medium.get_noise_2d(x, z)
	match kind:
		"cliff":
			# A road cut: high rock wall on one side, a valley on the other.
			return road.height + 48.0 * smoothstep(20.0, 38.0, u) - 34.0 * smoothstep(24.0, 55.0, -u) + middle * 7.0 + broad * 12.0
		"canyon":
			var terrace := smoothstep(35.0, 43.0, absf(lateral)) * 23.0 + smoothstep(90.0, 105.0, absf(lateral)) * 27.0
			return road.height - 14.0 + terrace + middle * 4.0
		"ridge":
			return road.height + 8.0 - smoothstep(15.0, 180.0, absf(lateral)) * 47.0 + absf(middle) * 23.0 + broad * 14.0
		"wetland":
			return road.height - 3.0 + broad * 7.0 + middle * 2.0
		"basin":
			return road.height - 9.0 + smoothstep(65.0, 260.0, absf(lateral)) * 36.0 + middle * 7.0
	return road.height + broad * 18.0 + middle * 6.0

func height(x: float, z: float, road: Dictionary) -> float:
	if field.profile.generation_version >= 14: return _height_v14(x, z, road)
	var s := maxf(0.0, -z - 600.0)
	var index := floori(s / REGION_LENGTH)
	var blend := smoothstep(REGION_LENGTH - 360.0, REGION_LENGTH, fposmod(s, REGION_LENGTH))
	var a: String = KINDS[posmod(index + offset, KINDS.size())]
	var b: String = KINDS[posmod(index + offset + 1, KINDS.size())]
	var target := lerpf(_shape(a, x, z, road), _shape(b, x, z, road), blend)
	var original := field.macro.get_noise_2d(x, z) * 32.0 + field.medium.get_noise_2d(x, z) * 8.0
	return lerpf(original, target, smoothstep(300.0, 850.0, -z)) + field.detail.get_noise_2d(x, z) * 0.35

func _height_v14(x: float, z: float, road: Dictionary) -> float:
	var a := appearance_at(-z)
	var broad := field.macro.get_noise_2d(x, z)
	var middle := field.medium.get_noise_2d(x, z)
	var fault := relief.get_noise_2d(x, z)
	var warp := clampf(fault * 24.0, -12.0, 12.0)
	var lateral := x - float(road.frame.origin.x)
	var first := _shape_v14(int(a.x), lateral, broad, middle, warp, fault)
	var target := first
	if a.z > 0.0: target = lerpf(first, _shape_v14(int(a.y), lateral, broad, middle, warp, fault), a.z)
	var original := broad * 32.0 + middle * 8.0
	return lerpf(original, float(road.height) + target, smoothstep(300.0, 850.0, -z)) + field.detail.get_noise_2d(x, z) * 0.35

func _shape_v14(kind: int, lateral: float, broad: float, middle: float, warp: float, fault: float) -> float:
	var side := -1.0 if posmod(offset, 2) == 0 else 1.0
	var u := lateral * side + warp
	var erosion := clampf(fault * 8.0, -4.0, 4.0)
	match kind:
		0: return broad * 18.0 + middle * 5.0 + erosion * 0.35
		1:
			var wall := 48.0 * smoothstep(19.0, 45.0, u)
			var ledge := 3.0 * smoothstep(27.0, 34.0, u) * (1.0 - smoothstep(43.0, 51.0, u))
			return wall + ledge - 34.0 * smoothstep(24.0, 68.0, -u) + middle * 5.0 + broad * 12.0 + erosion
		2: return -3.0 + broad * 7.0 + middle * 1.7 + erosion * 0.18
		3:
			var ridge := absf(lateral + warp * 0.7)
			return 8.0 - smoothstep(12.0, 180.0, ridge) * 47.0 + absf(middle) * 23.0 + broad * 14.0 + erosion
		4:
			# Variable shelves and weathered scarps follow world-space faults.
			var q := absf(lateral + warp)
			var first := smoothstep(28.0 + warp * 0.25, 48.0 + warp * 0.25, q) * (23.0 + erosion)
			var second := smoothstep(82.0 - warp * 0.4, 111.0 - warp * 0.4, q) * (27.0 - erosion)
			return -14.0 + first + second + middle * 4.0 + erosion * 0.5
		5:
			var basin := absf(lateral + warp) + broad * 20.0
			return -9.0 + smoothstep(65.0, 260.0, basin) * 36.0 + middle * 7.0 + erosion * 0.5
	return 0.0

func flora_weights(x: float, z: float) -> Vector3:
	var a := appearance_at(-z)
	var tree := lerpf(TREE_DENSITY[int(a.x)], TREE_DENSITY[int(a.y)], a.z)
	var ground := lerpf(GROUND_DENSITY[int(a.x)], GROUND_DENSITY[int(a.y)], a.z)
	var wet := lerpf(MOISTURE[int(a.x)], MOISTURE[int(a.y)], a.z)
	var cluster := clampf((field.clusters.get_noise_2d(x, z) + 0.30) * 1.8, 0.0, 1.0)
	return Vector3(tree * lerpf(0.07, 1.0, cluster * cluster), ground * lerpf(0.25, 1.0, cluster), wet)

func tree_choice(x: float, z: float, roll: float) -> int:
	var a := appearance_at(-z)
	var kind := int(a.y) if roll < a.z else int(a.x)
	var r := fposmod(roll * 7.39 + 0.17, 1.0)
	match kind:
		0: return 6 if r < 0.70 else 7
		2: return 4 if r < 0.55 else (5 if r < 0.80 else 7)
		5: return 6 if r < 0.40 else (7 if r < 0.70 else int(r * 4.0) % 4)
		3: return 0 if r < 0.75 else 5
	return 1 if r < 0.70 else 4

func river(index: int) -> Dictionary:
	if index < 0: return {}
	if not _rivers.has(index):
		var rng := field.rng_for(index, "river_crossing", 13 if field.profile.generation_version == 14 else -1)
		var s := 1200.0 + index * REGION_LENGTH + rng.randf_range(-100.0, 100.0)
		_rivers[index] = {"s": s, "half_width": rng.randf_range(17.0, 27.0), "water_height": field.road_height(s) - 12.0,
			"center_x": field.road_x(s), "skew": rng.randf_range(-0.22, 0.22), "phase": rng.randf_range(-PI, PI)}
	return _rivers[index]

func rivers_near(z: float, radius: float = 240.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# River meanders across the full +/-1310m visual strip, not just the road.
	var first := maxi(0, floori((-z - radius - 1600.0) / REGION_LENGTH))
	var last := maxi(0, ceili((-z + radius) / REGION_LENGTH))
	for index in range(first, last + 1):
		var plan := river(index)
		if absf(float(plan.s) + z) < radius + 380.0: result.append(plan)
	return result

func river_z(plan: Dictionary, x: float) -> float:
	var u := x - float(plan.center_x)
	return -float(plan.s) + u * float(plan.skew) + 14.0 * (sin(u / 90.0 + float(plan.phase)) - sin(float(plan.phase)))

func river_half_width(plan: Dictionary, x: float) -> float:
	var u := x - float(plan.center_x)
	return float(plan.half_width) * (1.0 + 0.12 * sin(u / 130.0) + 0.06 * sin(u / 47.0))

func channel(x: float, z: float, height_value: float) -> Dictionary:
	var wet := false
	var influence := 0.0
	var water := -INF
	var bank := 0.0
	for plan in rivers_near(z):
		var distance := absf(z - river_z(plan, x))
		var half := river_half_width(plan, x)
		if distance >= half + 115.0: continue
		var level: float = plan.water_height
		# The waterline is defined by this profile, not a separate rectangular
		# ribbon. The bed reaches the water at +/-half; banks rise above it.
		var depth := 3.4 + field.medium.get_noise_2d(x, river_z(plan, x)) * 0.7
		var bed := level - depth * (1.0 - smoothstep(0.25, 1.0, distance / half))
		if distance > half:
			bed = level + 1.3 * smoothstep(half, half + 16.0, distance)
		var valley := 1.0 - smoothstep(half + 16.0, half + 115.0, distance)
		height_value = lerpf(height_value, bed, valley)
		# Road earthworks resume on dry banks before the bridge span ends.
		influence = maxf(influence, 1.0 - smoothstep(half + 6.0, half + 36.0, distance))
		wet = wet or distance < half + 5.0
		bank = maxf(bank, smoothstep(half - 7.0, half + 1.0, distance) * (1.0 - smoothstep(half + 6.0, half + 24.0, distance)))
		if distance <= half: water = maxf(water, level)
	return {"height": height_value, "wet": wet, "influence": influence, "water_height": water, "bank": bank}

func river_span_at(s: float) -> bool:
	for plan in rivers_near(-s, 0.0):
		if absf(s - float(plan.s)) <= 85.0: return true
	return false

func natural_clearance(s: float) -> float:
	var frame := field.road_frame(s)
	var ground: Array[float] = []
	for fraction: float in [-0.65, 0.0, 0.65]:
		var point := frame * Vector3(field.road_width(s) * 0.5 * fraction, 0, 0)
		var road := field.road_query(point.x, point.z)
		var surface_height := float(channel(point.x, point.z, height(point.x, point.z, road)).height)
		ground.append(surface_height)
	ground.sort()
	return frame.origin.y - ground[1]

func _clearance_knot(index: int) -> float:
	if not _clearance.has(index):
		if _clearance.size() >= 4096: _clearance.clear()
		_clearance[index] = natural_clearance((index + 0.5) * STRUCTURE_STEP)
	return _clearance[index]

func _structure_cell(index: int) -> bool:
	if _structure_cells.has(index): return _structure_cells[index]
	var s := (index + 0.5) * STRUCTURE_STEP
	var elevated := false
	if s >= 450.0:
		for delta in [-1, 0, 1]:
			if _clearance_knot(index + delta) > 4.5 or river_span_at(s + delta * STRUCTURE_STEP):
				elevated = true
				break
		# Driveways remain grounded rather than joining the middle of a span.
		if elevated:
			var frame := field.road_frame(s)
			for site in field.sites_near_z(-s):
				if field.court_distance(frame.origin.x, frame.origin.z, site) < 20.0:
					elevated = false
					break
	if _structure_cells.size() >= 2048: _structure_cells.clear()
	_structure_cells[index] = elevated
	return elevated

func bridge_at(s: float) -> bool:
	return _structure_cell(floori(s / STRUCTURE_STEP))

func bridge_gap(s: float) -> float:
	var index := floori(s / STRUCTURE_STEP)
	if not _structure_cell(index): return 0.0
	var t := fposmod(s, STRUCTURE_STEP) / STRUCTURE_STEP
	var result := 1.0
	if not _structure_cell(index - 1): result *= smoothstep(0.0, 1.0, t)
	if not _structure_cell(index + 1): result *= 1.0 - smoothstep(0.0, 1.0, t)
	return result

func crossing_clearance(s: float, margin: float = 190.0) -> bool:
	for plan in rivers_near(-s, margin):
		if absf(s - float(plan.s)) < margin: return false
	return true

func site_clear(site: Dictionary) -> bool:
	if not site.has("bounds"): return crossing_clearance(float(site.s))
	var box: AABB = site.bounds.grow(25.0)
	for river_plan in rivers_near(box.get_center().z, box.size.z * 0.5):
		# Sample the whole footprint, including the apron influence and turns in
		# the river, rather than only the road-side POI anchor.
		var count := maxi(1, ceili(box.size.x / 12.0))
		for i in range(count + 1):
			var x := lerpf(box.position.x, box.end.x, float(i) / count)
			var z := river_z(river_plan, x)
			var width := river_half_width(river_plan, x) + 115.0
			if z + width >= box.position.z and z - width <= box.end.z: return false
	return true

func vegetation(sample: Dictionary, x: float, z: float) -> bool:
	if sample.reserved: return false
	var kind := kind_at(-z)
	if kind == "canyon" or kind == "ridge":
		return field.clusters.get_noise_2d(x * 1.7, z * 1.7) > 0.12
	if kind == "meadow": return field.clusters.get_noise_2d(x, z) > -0.06
	return true

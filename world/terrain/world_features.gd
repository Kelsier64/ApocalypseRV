extends RefCounted
class_name WorldFeatures
## Ponds, dirt tracks, human-trace pads and the transmission line. They are planned
## on raw terrain before the blended surface exists, then shape that surface.
## A 300 m cell owns its features completely, so a sample only consults one cell.
## Planners here must never call WorldField.surface() or anything built on it.
const CELL := 300.0
const START := 470.0
const SEAM := 6.0
const TRACK_STEP := 4.0
const TRACK_GRADE := 0.16
const TRACK_CUT := 7.0
## Distance at which the terrain's track channel saturates (vertex colour alpha).
const TRACK_REACH := 8.0
const TOWER_SPACING := 150.0
const NONE := {}
# Indexed by TerrainLandforms.KINDS: meadow, cliff, wetland, ridge, canyon, basin.
const TRACK_CHANCE := [0.50, 0.20, 0.32, 0.28, 0.24, 0.55]
const POND_CHANCE := [0.40, 0.05, 0.85, 0.04, 0.05, 0.45]
const FIELD_CHANCE := [0.75, 0.30, 0.45, 0.35, 0.30, 0.45]
const ROADSIDE_CHANCE := 0.6
const LAKE_CHANCE := [0.35, 0.0, 0.7, 0.0, 0.0, 0.35]
## Footprint radius, selection weight and half-length along the road.
const ROADSIDE := {"ditched_car": [3.4, 30, 3.4], "roadworks": [3.0, 20, 9.0], "bus_shelter": [3.2, 18, 3.2], "billboard": [4.6, 17, 5.2], "utility_hut": [3.0, 15, 3.0]}
const FIELD := [["hay_field", "tractor", "fence_run", "fence_run"], ["ruin", "container_dump"], ["fence_run", "tractor", "ruin"],
	["ruin", "container_dump"], ["ruin", "container_dump"], ["ruin", "fence_run", "log_landing"]]
const FIELD_RADIUS := {"hay_field": 15.0, "tractor": 4.5, "ruin": 8.0, "container_dump": 8.0, "log_landing": 9.0, "fence_run": 0.0}
const TRACK_END := [["homestead", "hamlet", "container_dump"], ["container_dump", "homestead"], ["homestead", "log_landing"],
	["container_dump", "homestead"], ["container_dump", "homestead"], ["log_landing", "log_landing", "homestead", "hamlet"]]
const TRACK_END_RADIUS := {"homestead": 11.0, "hamlet": 16.0, "container_dump": 10.0, "log_landing": 11.0}
var _field: WeakRef
var field: WorldField:
	get: return _field.get_ref()
var _cells: Dictionary = {}
var _towers: Dictionary = {}
var _line: Vector3

func _init(world_field: WorldField) -> void:
	_field = weakref(world_field)
	var rng := world_field.rng_for(0, "feature_pylons")
	_line = Vector3(rng.randf_range(170.0, 235.0), rng.randf_range(2400.0, 3400.0), rng.randf_range(-PI, PI))

func cell(index: int) -> Dictionary:
	if _cells.has(index): return _cells[index]
	var plan := {"ponds": [], "tracks": [], "pads": [], "fences": [], "rect": Rect2()}
	if (index + 1) * CELL > START: _plan(index, plan)
	if _cells.size() >= 64: _cells.erase(_cells.keys()[0])
	_cells[index] = plan
	return plan

## Every cell touching a band, for builders that own the features anchored in it.
func cells_for_band(band: int) -> Array[Dictionary]:
	var length := field.profile.chunk_length
	var result: Array[Dictionary] = []
	for index in range(floori(band * length / CELL), floori(((band + 1) * length - 0.001) / CELL) + 1):
		if index >= 0: result.append(cell(index))
	return result

func owns(band: int, z: float) -> bool:
	return floori(-z / field.profile.chunk_length) == band

## Height, reservation, gravel and standing water at a point, or NONE.
func apply(x: float, z: float, height: float) -> Dictionary:
	if -z < START: return NONE
	var plan := cell(floori(-z / CELL))
	var rect: Rect2 = plan.rect
	if not rect.has_point(Vector2(x, z)): return NONE
	var reserved := false
	var gravel := 0.0
	var water := -INF
	var bank := 0.0
	var track_distance := 1.0
	var touched := false
	var point := Vector2(x, z)
	for track: Dictionary in plan.tracks:
		var bounds: Rect2 = track.rect
		if not bounds.has_point(point): continue
		var centre: Vector3 = track.centre
		var radius: float = track.radius
		var hit := _track_sample(track, point)
		if hit.x < 9.0:
			touched = true
			height = lerpf(height, hit.y, 1.0 - smoothstep(2.4, 9.0, hit.x))
			track_distance = minf(track_distance, hit.x / TRACK_REACH)
			reserved = reserved or hit.x < 3.4
		var distance := point.distance_to(Vector2(centre.x, centre.z))
		if distance < radius + 8.0:
			touched = true
			height = lerpf(height, centre.y, 1.0 - smoothstep(radius, radius + 8.0, distance))
			gravel = maxf(gravel, 0.55 * (1.0 - smoothstep(radius - 5.0, radius, distance)))
			reserved = reserved or distance < radius
	for pond: Dictionary in plan.ponds:
		var distance := point.distance_to(Vector2(pond.x, pond.z))
		if distance >= float(pond.r) * 1.35 + 14.0: continue
		var shore := pond_radius(pond, atan2(z - float(pond.z), x - float(pond.x)))
		if distance >= shore + 14.0: continue
		touched = true
		var level: float = pond.level
		if distance <= shore:
			height = level - float(pond.depth) * (1.0 - smoothstep(0.35, 1.0, distance / shore))
			water = level
		else:
			var rim := level + 0.5 * smoothstep(shore, shore + 6.0, distance)
			height = lerpf(height, rim, 1.0 - smoothstep(shore + 4.0, shore + 14.0, distance))
		reserved = reserved or distance < shore + 1.5
		bank = maxf(bank, smoothstep(shore - 3.0, shore + 0.5, distance) * (1.0 - smoothstep(shore + 3.0, shore + 10.0, distance)))
	for pad: Dictionary in plan.pads:
		if point.distance_squared_to(Vector2(pad.x, pad.z)) < float(pad.r) * float(pad.r):
			touched = true
			reserved = true
	if not touched: return NONE
	return {"height": height, "reserved": reserved, "gravel": gravel, "water_height": water, "bank": bank, "track": track_distance}

## Irregular analytic shoreline shared by terrain, water mesh and navigation.
static func pond_radius(pond: Dictionary, angle: float) -> float:
	return float(pond.r) * (1.0 + 0.17 * sin(angle * 2.0 + float(pond.phase)) + 0.10 * sin(angle * 3.0 - float(pond.phase) * 1.7) + 0.06 * sin(angle * 5.0 + float(pond.phase) * 0.6))

static func pond_outline(pond: Dictionary, margin: float, count := 28) -> PackedVector3Array:
	var outline := PackedVector3Array()
	for i in range(count):
		var angle := i * TAU / count
		var radius := pond_radius(pond, angle) + margin
		outline.append(Vector3(float(pond.x) + cos(angle) * radius, float(pond.level), float(pond.z) + sin(angle) * radius))
	return outline

func navigation_obstacles(band: int, source: NavigationMeshSourceGeometryData3D) -> void:
	for plan: Dictionary in cells_for_band(band):
		for pond: Dictionary in plan.ponds:
			if not owns(band, pond.z): continue
			# Remove the submerged bed, exactly like a river channel.
			source.add_projected_obstruction(pond_outline(pond, 0.0), -1000.0, float(pond.level) + 1002.0, false)

func tower(index: int) -> Dictionary:
	if _towers.has(index): return _towers[index]
	var result := {}
	var s := (index + 0.5) * TOWER_SPACING
	if s >= 600.0 and not field.landforms.bridge_at(s):
		var frame := field.road_frame(s)
		var lateral := _line.x * sin(s * TAU / _line.y + _line.z)
		var minimum := field.road_width(s) * 0.5 + 17.0
		if absf(lateral) < minimum: lateral = minimum if lateral >= 0.0 else -minimum
		# A pure x offset keeps the tower at its own station, so it never leaves
		# the cell (and band) that owns it however the road bends.
		var point := Vector3(field.road_x(s) + lateral, 0, -s)
		var probe := _probe(point.x, point.z)
		var low: float = probe.height
		var high: float = probe.height
		var dry: bool = not probe.wet
		for offset: Vector2 in [Vector2(3.5, 3.5), Vector2(-3.5, 3.5), Vector2(3.5, -3.5), Vector2(-3.5, -3.5)]:
			var corner := _probe(point.x + offset.x, point.z + offset.y)
			dry = dry and not corner.wet
			low = minf(low, float(corner.height))
			high = maxf(high, float(corner.height))
		if dry and float(probe.edge) > 14.0 and high - low <= 4.0 and _band_clear(point.z, 6.0) and _site_clear(point.x, point.z, 7.0):
			result = {"type": "pylon", "x": point.x, "z": point.z, "y": low, "r": 5.5, "yaw": atan2(frame.basis.x.x, frame.basis.x.z), "seed": field.seed_for(index, "feature_pylon"), "index": index}
	if _towers.size() >= 128: _towers.erase(_towers.keys()[0])
	_towers[index] = result
	return result

func _plan(index: int, plan: Dictionary) -> void:
	var taken: Array[Vector3] = []
	for tower_index in [index * 2, index * 2 + 1]:
		var pylon := tower(tower_index)
		if pylon.is_empty(): continue
		plan.pads.append(pylon)
		taken.append(Vector3(pylon.x, pylon.z, pylon.r))
	_plan_track(index, plan, taken)
	for slot in range(2): _plan_roadside(index, slot, plan, taken)
	_plan_field(index, plan, taken)
	for slot in range(2): _plan_pond(index, slot, plan, taken)
	var rect := Rect2()
	var first := true
	for track: Dictionary in plan.tracks:
		rect = track.rect if first else rect.merge(track.rect)
		first = false
	for pond: Dictionary in plan.ponds:
		var reach := float(pond.r) * 1.35 + 14.0
		var box := Rect2(float(pond.x) - reach, float(pond.z) - reach, reach * 2.0, reach * 2.0)
		rect = box if first else rect.merge(box)
		first = false
	for pad: Dictionary in plan.pads:
		var box := Rect2(float(pad.x) - float(pad.r), float(pad.z) - float(pad.r), float(pad.r) * 2.0, float(pad.r) * 2.0)
		rect = box if first else rect.merge(box)
		first = false
	plan.rect = rect

func _kind(index: int) -> int:
	return int(field.landforms.appearance_at((index + 0.5) * CELL).x)

func _probe(x: float, z: float) -> Dictionary:
	var road := field.road_query(x, z)
	var base := field.landforms.height(x, z, road)
	var channel := field.landforms.channel(x, z, base)
	var wet: bool = channel.wet or is_finite(float(channel.water_height))
	return {"height": float(channel.height), "edge": float(road.distance) - float(road.width) * 0.5, "wet": wet, "valley": absf(float(channel.height) - base) > 0.02}

func _site_clear(x: float, z: float, radius: float) -> bool:
	if absf(x) + radius > 434.0: return false
	for site: Dictionary in field.sites_near_z(z, 400.0):
		if field.court_distance(x, z, site) < radius + 22.0: return false
		if site.has("bounds"):
			var bounds: AABB = site.bounds.grow(radius + 10.0)
			if x > bounds.position.x and x < bounds.end.x and z > bounds.position.z and z < bounds.end.z: return false
	return true

## Solid content keeps clear of streamed band seams, so no neighbour bake needs it.
func _band_clear(z: float, radius: float) -> bool:
	var length := field.profile.chunk_length
	var offset := fposmod(-z, length)
	return offset > radius + SEAM and offset < length - radius - SEAM

func _cell_clear(index: int, z: float, radius: float) -> bool:
	return -z > maxf(START, index * CELL + radius + 10.0) and -z < (index + 1) * CELL - radius - 10.0

static func _free(taken: Array[Vector3], x: float, z: float, radius: float) -> bool:
	for other in taken:
		if Vector2(x - other.x, z - other.y).length() < radius + other.z + 4.0: return false
	return true

## Largest height difference between a centre and a ring; INF if any probe is unusable.
func _relief(x: float, z: float, radius: float, allow_valley := false) -> float:
	var centre := _probe(x, z)
	if centre.wet or (centre.valley and not allow_valley): return INF
	var low: float = centre.height
	var high: float = centre.height
	for i in range(8):
		var probe := _probe(x + cos(i * TAU / 8.0) * radius, z + sin(i * TAU / 8.0) * radius)
		if probe.wet or (probe.valley and not allow_valley): return INF
		low = minf(low, float(probe.height))
		high = maxf(high, float(probe.height))
	return high - low

func _plan_track(index: int, plan: Dictionary, taken: Array[Vector3]) -> void:
	var rng := field.rng_for(index, "feature_track")
	var kind := _kind(index)
	if rng.randf() >= TRACK_CHANCE[kind]: return
	var options: Array = TRACK_END[kind]
	var content: String = options[rng.randi_range(0, options.size() - 1)]
	var radius: float = TRACK_END_RADIUS[content]
	for attempt in range(12):
		var s := index * CELL + rng.randf_range(70.0, CELL - 70.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var length := rng.randf_range(70.0, 150.0)
		var swing := rng.randf_range(-0.6, 0.6)
		var bend := rng.randf_range(-0.9, 0.9)
		if s < START or not field.landforms.crossing_clearance(s, 150.0):
			continue
		var bridged := false
		for offset: float in [-20.0, 0.0, 20.0]: bridged = bridged or field.landforms.bridge_at(s + offset)
		if bridged:
			continue
		var frame := field.road_frame(s)
		var out := (frame.basis.x * side).slide(Vector3.UP).normalized()
		var point := frame.origin + out * (field.road_width(s) * 0.5 - 0.5)
		var points := PackedVector3Array()
		var raw: Array[float] = []
		var valid := true
		var steps := ceili(length / TRACK_STEP)
		for i in range(steps + 1):
			var direction := out.rotated(Vector3.UP, swing + bend * float(i) / steps)
			if i > 0: point += direction * TRACK_STEP
			var probe := _probe(point.x, point.z)
			var travelled := i * TRACK_STEP
			# A track leaves the road once and never drifts back alongside it.
			if probe.wet or probe.valley or absf(point.x) > 428.0 or -point.z < index * CELL + 14.0 or -point.z > (index + 1) * CELL - 14.0 or (travelled > 16.0 and float(probe.edge) < minf(travelled * 0.6, 30.0)):
				valid = false
				break
			raw.append(frame.origin.y if i == 0 else float(probe.height))
			points.append(Vector3(point.x, 0.0, point.z))
		if not valid: continue
		# Grade the bed from the road outward, cutting through the roadside bank.
		var graded: Array[float] = [raw[0]]
		for i in range(1, raw.size()):
			graded.append(clampf(raw[i], graded[i - 1] - TRACK_STEP * TRACK_GRADE, graded[i - 1] + TRACK_STEP * TRACK_GRADE))
		for i in range(1, graded.size() - 1):
			graded[i] = (graded[i - 1] + graded[i] * 2.0 + graded[i + 1]) * 0.25
		for i in range(raw.size()):
			if absf(graded[i] - raw[i]) > TRACK_CUT:
				valid = false
			points[i].y = graded[i]
		var centre := points[points.size() - 1]
		if not valid: continue
		if not _band_clear(centre.z, radius) or not _cell_clear(index, centre.z, radius + 8.0):
			continue
		if _relief(centre.x, centre.z, radius) > 5.0 or not _free(taken, centre.x, centre.z, radius):
			continue
		for i in range(0, points.size(), 3):
			valid = valid and _site_clear(points[i].x, points[i].z, 5.0)
		if not valid or not _site_clear(centre.x, centre.z, radius + 8.0):
			continue
		var rect := Rect2(centre.x - radius - 8.0, centre.z - radius - 8.0, (radius + 8.0) * 2.0, (radius + 8.0) * 2.0)
		for i in range(points.size()):
			rect = rect.expand(Vector2(points[i].x - 9.0, points[i].z - 9.0)).expand(Vector2(points[i].x + 9.0, points[i].z + 9.0))
			if i % 3 == 0: taken.append(Vector3(points[i].x, points[i].z, 5.0))
		var heading := points[points.size() - 1] - points[points.size() - 2]
		plan.tracks.append({"points": points, "rect": rect, "centre": centre, "radius": radius, "content": content, "seed": rng.randi(), "yaw": atan2(-heading.x, -heading.z), "s": s, "side": side})
		taken.append(Vector3(centre.x, centre.z, radius))
		return

func _plan_roadside(index: int, slot: int, plan: Dictionary, taken: Array[Vector3]) -> void:
	var rng := field.rng_for(index * 4 + slot, "feature_roadside")
	if rng.randf() >= ROADSIDE_CHANCE: return
	var total := 0
	for entry: Array in ROADSIDE.values(): total += int(entry[1])
	var roll := rng.randi_range(0, total - 1)
	var type := ""
	for key: String in ROADSIDE:
		type = key
		roll -= int(ROADSIDE[key][1])
		if roll < 0: break
	var radius: float = ROADSIDE[type][0]
	var reach: float = ROADSIDE[type][2]
	for attempt in range(5):
		var s := index * CELL + rng.randf_range(reach + 12.0, CELL - reach - 12.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var setback := rng.randf_range(4.8, 6.5)
		var skew := rng.randf_range(-0.35, 0.35)
		if s < START or not field.landforms.crossing_clearance(s, 150.0): continue
		var bridged := false
		for offset: float in [-24.0, -8.0, 0.0, 8.0, 24.0]: bridged = bridged or field.landforms.bridge_at(s + offset)
		if bridged: continue
		var frame := field.road_frame(s)
		var lateral := field.road_width(s) * 0.5 + setback + radius
		var point := frame * Vector3(side * lateral, 0, 0)
		if not _band_clear(point.z, reach) or not _cell_clear(index, point.z, reach) or not _free(taken, point.x, point.z, reach): continue
		# The wooden utility poles stand 14 m out on the positive side every 50 m.
		if side > 0.0 and absf(lateral - 14.0) < radius + 1.0 and absf(s - (roundf((s - 20.0) / 50.0) * 50.0 + 20.0)) < reach + 1.0: continue
		var level := _site_clear(point.x, point.z, reach)
		for along: float in [-reach, 0.0, reach]:
			for offset: float in [-radius, 0.0, radius]:
				var sample := frame * Vector3(side * (lateral + offset), 0, along)
				var probe := _probe(sample.x, sample.z)
				level = level and not probe.wet and absf(float(probe.height) - frame.origin.y) <= 2.2
		if not level: continue
		var toward := (-side * frame.basis.x).slide(Vector3.UP).normalized()
		plan.pads.append({"type": type, "x": point.x, "z": point.z, "r": radius, "s": s, "side": side, "seed": rng.randi(), "yaw": atan2(toward.x, toward.z) + (skew if type in ["billboard", "ditched_car"] else 0.0)})
		# Long layouts keep the forest off their whole length, not just the middle.
		var spare := reach - radius
		while spare > 0.5:
			for direction: float in [-1.0, 1.0]:
				var extra := frame * Vector3(side * lateral, 0, direction * (reach - spare + radius))
				plan.pads.append({"type": "reserve", "x": extra.x, "z": extra.z, "r": radius})
			spare -= radius * 1.5
		taken.append(Vector3(point.x, point.z, reach))
		return

func _plan_field(index: int, plan: Dictionary, taken: Array[Vector3]) -> void:
	var rng := field.rng_for(index, "feature_field")
	var kind := _kind(index)
	if rng.randf() >= FIELD_CHANCE[kind]: return
	var options: Array = FIELD[kind]
	var type: String = options[rng.randi_range(0, options.size() - 1)]
	var radius: float = FIELD_RADIUS[type]
	for attempt in range(6):
		var x := rng.randf_range(-400.0, 400.0)
		var z := -(index * CELL + rng.randf_range(radius + 14.0, CELL - radius - 14.0))
		var yaw := rng.randf_range(-PI, PI)
		var seed_value := rng.randi()
		if type == "fence_run":
			var length := rng.randf_range(36.0, 80.0)
			var direction := Vector3(sin(yaw), 0, cos(yaw))
			var open := true
			for t: float in [0.0, 0.5, 1.0]:
				var post := _probe(x + direction.x * length * t, z + direction.z * length * t)
				open = open and not post.wet and float(post.edge) > 12.0 and _cell_clear(index, z + direction.z * length * t, 2.0) and _site_clear(x + direction.x * length * t, z + direction.z * length * t, 3.0)
			if not open: continue
			plan.fences.append({"x": x, "z": z, "yaw": yaw, "length": length, "seed": seed_value})
			return
		var probe := _probe(x, z)
		if float(probe.edge) < 18.0 + radius or float(probe.edge) > 170.0: continue
		if _relief(x, z, radius) > (2.6 if radius <= 9.0 else 4.2): continue
		if not _band_clear(z, radius) or not _cell_clear(index, z, radius) or not _site_clear(x, z, radius) or not _free(taken, x, z, radius): continue
		plan.pads.append({"type": type, "x": x, "z": z, "r": radius, "seed": seed_value, "yaw": yaw})
		taken.append(Vector3(x, z, radius))
		return

func _plan_pond(index: int, slot: int, plan: Dictionary, taken: Array[Vector3]) -> void:
	var rng := field.rng_for(index * 2 + slot, "feature_pond")
	var kind := _kind(index)
	if rng.randf() >= POND_CHANCE[kind] * (1.0 if slot == 0 else 0.5): return
	# The first slot may grow into a lake that fills most of a band; where the
	# ground will not hold one, it settles for an ordinary pond.
	if slot == 0 and rng.randf() < LAKE_CHANCE[kind] and _place_pond(index, rng, plan, taken, true): return
	_place_pond(index, rng, plan, taken, false)

func _place_pond(index: int, rng: RandomNumberGenerator, plan: Dictionary, taken: Array[Vector3], lake: bool) -> bool:
	var length := field.profile.chunk_length
	for attempt in range(14 if lake else 10):
		var x := rng.randf_range(-390.0, 390.0)
		var radius := rng.randf_range(27.0, 37.0) if lake else rng.randf_range(9.0, 23.0)
		var z := -(index * CELL + rng.randf_range(radius + 40.0, CELL - radius - 40.0))
		var depth := rng.randf_range(1.5, 2.3) if lake else rng.randf_range(0.9, 1.6)
		var phase := rng.randf_range(-PI, PI)
		var jetty := rng.randf()
		var seed_value := rng.randi()
		var reach := radius * 1.35 + 14.0
		if lake:
			# Only the middle of a band leaves seam clearance for a shore this wide.
			var slack := length * 0.5 - reach - SEAM - 1.0
			z = -((floori(index * CELL / length) + rng.randi_range(0, 1) + 0.5) * length + rng.randf_range(-slack, slack))
		# Water collects in hollows: walk downhill from the rolled point first.
		var centre := _probe(x, z)
		for step in range(0 if lake else 5):
			var lowest := centre
			var moved := Vector2(x, z)
			for i in range(8):
				var candidate := Vector2(x + cos(i * TAU / 8.0) * 12.0, z + sin(i * TAU / 8.0) * 12.0)
				var probe := _probe(candidate.x, candidate.y)
				if not probe.wet and float(probe.height) < float(lowest.height) - 0.15:
					lowest = probe
					moved = candidate
			if lowest == centre: break
			centre = lowest
			x = moved.x
			z = moved.y
		if centre.wet or centre.valley or float(centre.edge) < radius * 1.35 + 20.0: continue
		var low := INF
		var high := -INF
		var dry := true
		for i in range(8):
			var probe := _probe(x + cos(i * TAU / 8.0) * (radius + 9.0), z + sin(i * TAU / 8.0) * (radius + 9.0))
			dry = dry and not probe.wet and not probe.valley
			low = minf(low, float(probe.height))
			high = maxf(high, float(probe.height))
		# The lowest point of the rim sets the waterline; a taller far bank is fine.
		var level := minf(low, float(centre.height) + depth) - 0.25
		if not dry or high - level > (9.0 if lake else 6.5) or level - float(centre.height) > 4.0: continue
		if not _band_clear(z, reach) or not _cell_clear(index, z, reach) or not _site_clear(x, z, reach) or not _free(taken, x, z, reach): continue
		plan.ponds.append({"x": x, "z": z, "r": radius, "level": level, "depth": depth, "phase": phase, "jetty": lake or jetty < 0.4, "jetty_angle": jetty * 40.0, "seed": seed_value, "lake": lake})
		taken.append(Vector3(x, z, reach))
		return true
	return false

static func _track_sample(track: Dictionary, point: Vector2) -> Vector2:
	var points: PackedVector3Array = track.points
	var best := INF
	var height := 0.0
	for i in range(points.size() - 1):
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		# Segments are 4 m long: skip those that cannot be within the 9 m influence.
		if absf(point.x - a.x) > 13.0 or absf(point.y - a.y) > 13.0: continue
		var ab := b - a
		var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var distance := point.distance_squared_to(a + ab * t)
		if distance < best:
			best = distance
			height = lerpf(points[i].y, points[i + 1].y, t)
	return Vector2(sqrt(best), height)

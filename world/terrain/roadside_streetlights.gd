extends RefCounted
class_name RoadsideStreetlights
## Plan whole rows before distributing their fixtures to the ground bands.
const SCENE := preload("res://world/roadside_kit/streetlight.tscn")
const CELL_LENGTH := 900.0
const CELL_MARGIN := 35.0
const START_DISTANCE := 150.0
const SHOULDER_OFFSET := 3.0
const INNER_SHOULDER_OFFSET := 2.0
const FOOTING_RADIUS := 0.33 # Covers the rotated 0.46 m square footing.
const SEAM_MARGIN := 5.0
const SINGLE_CLEARANCE := 95.0
const MIN_ROW_SIZE := 11
const ROW_SEARCH_STEP := 4.0
const ROAD_STEP := 2.5 # Matches the road mesh's centerline segments.
const WARM_WHITE := Color("ffe3bc")
const AMBER := Color("ffb36b")
const COOL_WHITE := Color("d4e6ff")

static func plan(field: WorldField, band: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := band * field.profile.chunk_length
	var end := start + field.profile.chunk_length
	# A road-normal offset can move a candidate into the next ground band.
	var max_offset := maxf(field.profile.road_width * 1.3, field.profile.narrow_width * 0.72) * 0.5 + SHOULDER_OFFSET
	var first := maxi(0, floori((start - max_offset) / CELL_LENGTH))
	var last := floori((end + max_offset) / CELL_LENGTH)
	for cell in range(first, last + 1):
		if not field.streetlight_cells.has(cell):
			if field.streetlight_cells.size() >= 16:
				field.streetlight_cells.erase(field.streetlight_cells.keys()[0])
			field.streetlight_cells[cell] = _plan_cell(field, cell)
		for lamp: Dictionary in field.streetlight_cells[cell]:
			var pose: Transform3D = lamp.pose
			if floori(-pose.origin.z / field.profile.chunk_length) == band:
				result.append(lamp)
	return result

static func _plan_cell(field: WorldField, cell: int) -> Array[Dictionary]:
	var first := maxf(START_DISTANCE, cell * CELL_LENGTH + CELL_MARGIN)
	var last := (cell + 1) * CELL_LENGTH - CELL_MARGIN
	var row_rng := field.rng_for(cell, "streetlight_row_v3")
	var lamps := _plan_row(field, row_rng, first, last, cell == 0)
	for slot in range(lamps.size()):
		_style(lamps[slot], field, cell, "Row", slot)
	var single_rng := field.rng_for(cell, "streetlight_single_v3")
	if lamps.is_empty():
		_add_single(lamps, field, cell, single_rng, first, last)
	elif single_rng.randf() < 0.70:
		var before := float(lamps.front().s) - SINGLE_CLEARANCE
		var after := float(lamps.back().s) + SINGLE_CLEARANCE
		if before - first > last - after:
			_add_single(lamps, field, cell, single_rng, first, before)
		else:
			_add_single(lamps, field, cell, single_rng, after, last)
	return lamps

static func _style(lamp: Dictionary, field: WorldField, cell: int, mode: String, slot: int) -> void:
	lamp.name = "StreetlightV3%s_%d_%d" % [mode, cell, slot]
	var fixture := field.rng_for(cell, "streetlight_fixture_v3_%s_%d" % [mode, slot])
	var color_roll := fixture.randf()
	lamp.tint = WARM_WHITE
	if mode == "Single":
		if color_roll < 0.025:
			lamp.tint = AMBER
		elif color_roll < 0.05:
			lamp.tint = COOL_WHITE
	var fault_roll := fixture.randf()
	lamp.fault = RoadsideStreetlight.Fault.STEADY
	if fault_roll < 0.04:
		lamp.fault = RoadsideStreetlight.Fault.BURST
	elif fault_roll < 0.12:
		lamp.fault = RoadsideStreetlight.Fault.DIP
	lamp.flicker_seed = fixture.randi()

static func _add_single(lamps: Array[Dictionary], field: WorldField, cell: int, rng: RandomNumberGenerator, first: float, last: float) -> void:
	if last - first < CELL_MARGIN: return
	for attempt in range(6):
		var s := rng.randf_range(first, last)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pose := _placement(field, s, side)
		if pose == Transform3D.IDENTITY: pose = _placement(field, s, -side)
		if pose == Transform3D.IDENTITY: continue
		var lamp := {"s": s, "pose": pose}
		_style(lamp, field, cell, "Single", 0)
		lamps.append(lamp)
		return

static func _plan_row(field: WorldField, rng: RandomNumberGenerator, first: float, last: float, opening: bool) -> Array[Dictionary]:
	var count := rng.randi_range(MIN_ROW_SIZE, 16)
	var preferred_side := -1.0 if rng.randf() < 0.5 else 1.0
	# Parameter s advances along Z. Measure the 3D centerline so the spacing
	# also stays even on sharp bends and hills.
	var lengths: Array[float] = [0.0]
	var previous := field.road_frame(first).origin
	for i in range(1, roundi((last - first) / ROAD_STEP) + 1):
		var point := field.road_frame(first + i * ROAD_STEP).origin
		lengths.append(lengths.back() + point.distance_to(previous))
		previous = point
	var spacing := rng.randf_range(20.0, 28.0)
	var tight_spacing := rng.randf_range(20.0, 22.0)
	for search in range(3):
		var setback := INNER_SHOULDER_OFFSET if search == 2 else SHOULDER_OFFSET
		if search > 0: spacing = tight_spacing
		var slack := float(lengths.back()) - (MIN_ROW_SIZE - 1) * spacing
		if slack <= 0.0: continue
		var steps := ceili(slack / ROW_SEARCH_STEP)
		var phase := rng.randf()
		var start := 0 if opening else rng.randi_range(0, steps - 1)
		for step in range(steps):
			var offset := (posmod(start + step, steps) + phase) * slack / steps
			for side in [preferred_side, -preferred_side]:
				var lamps: Array[Dictionary] = []
				for slot in range(count):
					var distance := offset + slot * spacing
					if distance > lengths.back(): break
					var i := clampi(lengths.bsearch(distance), 1, lengths.size() - 1)
					var s := first + (i - 1 + inverse_lerp(lengths[i - 1], lengths[i], distance)) * ROAD_STEP
					var pose := _placement(field, s, side, setback)
					if pose == Transform3D.IDENTITY: break
					lamps.append({"s": s, "pose": pose})
				# A row can end before an obstruction, with no gaps inside it.
				if lamps.size() >= MIN_ROW_SIZE: return lamps
	return []

static func _placement(field: WorldField, s: float, side: float, setback := SHOULDER_OFFSET) -> Transform3D:
	for distance in [s - 15.0, s, s + 15.0]:
		if field.landforms.bridge_at(distance): return Transform3D.IDENTITY
	# The existing wooden utility poles occupy the positive side every 50 m.
	if side > 0.0 and absf(s - (roundf((s - 20.0) / 50.0) * 50.0 + 20.0)) < 3.0:
		return Transform3D.IDENTITY
	var road := field.road_frame(s)
	var point := road.origin + road.basis.x * side * (field.road_width(s) * 0.5 + setback)
	var band_offset := fposmod(-point.z, field.profile.chunk_length)
	if band_offset < SEAM_MARGIN or band_offset > field.profile.chunk_length - SEAM_MARGIN:
		return Transform3D.IDENTITY
	var sample := field.surface(point.x, point.z)
	if is_finite(float(sample.water_height)) or absf(float(sample.height) - road.origin.y) > 2.5:
		return Transform3D.IDENTITY
	# The inner verge is the last option on a cut slope. The deep footing
	# stays embedded on its downhill side while the post remains vertical.
	var slope_limit := 50.0 if setback == INNER_SHOULDER_OFFSET else 25.0
	if field.normal_at(point.x, point.z).y < cos(deg_to_rad(slope_limit)):
		return Transform3D.IDENTITY
	for site in field.sites_near_z(point.z):
		if field.court_distance(point.x, point.z, site) < 20.0: return Transform3D.IDENTITY
	point.y = sample.height
	return Transform3D(Basis.looking_at(-side * road.basis.x), point)

static func build(field: WorldField, band: int, parent: Node3D) -> void:
	var placements := plan(field, band)
	if placements.is_empty(): return
	var clock: WorldClock
	var ancestor := parent.get_parent()
	while ancestor != null and clock == null:
		clock = ancestor.get_node_or_null("WorldClock") as WorldClock
		ancestor = ancestor.get_parent()
	for placement in placements:
		var lamp := SCENE.instantiate() as RoadsideStreetlight
		lamp.name = placement.name
		lamp.transform = placement.pose
		lamp.configure(clock, placement.tint, placement.fault, placement.flicker_seed)
		parent.add_child(lamp)

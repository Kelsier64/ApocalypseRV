extends RefCounted
class_name RoadsideStreetlights
## Sparse decoration planned in road-distance cells, owned by the ground bands.
const SCENE := preload("res://world/roadside_kit/streetlight.tscn")
const CELL_LENGTH := 600.0
const START_DISTANCE := 150.0
const SHOULDER_OFFSET := 4.25
const SEAM_MARGIN := 5.0
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
		var layout := field.rng_for(cell, "streetlight_layout")
		if layout.randf() >= 0.65: continue
		var distances := [cell * CELL_LENGTH + layout.randf_range(90.0, 340.0)]
		if layout.randf() < 0.20:
			distances.append(float(distances[0]) + layout.randf_range(120.0, 150.0))
		for slot in range(distances.size()):
			var s := float(distances[slot])
			if s < START_DISTANCE or s < start - max_offset or s > end + max_offset: continue
			var fixture := field.rng_for(cell, "streetlight_fixture_%d" % slot)
			var side := -1.0 if fixture.randf() < 0.5 else 1.0
			var pose := _placement(field, s, side)
			if pose == Transform3D.IDENTITY: pose = _placement(field, s, -side)
			if pose == Transform3D.IDENTITY: continue
			var distance := -pose.origin.z
			if distance < start + SEAM_MARGIN or distance > end - SEAM_MARGIN: continue
			var color_roll := fixture.randf()
			var tint := WARM_WHITE
			if color_roll < 0.025:
				tint = AMBER
			elif color_roll < 0.05:
				tint = COOL_WHITE
			var fault_roll := fixture.randf()
			var fault := RoadsideStreetlight.Fault.STEADY
			if fault_roll < 0.04:
				fault = RoadsideStreetlight.Fault.BURST
			elif fault_roll < 0.12:
				fault = RoadsideStreetlight.Fault.DIP
			result.append({"s": s, "pose": pose, "name": "Streetlight_%d_%d" % [cell, slot],
				"tint": tint, "fault": fault, "flicker_seed": fixture.randi()})
	return result

static func _placement(field: WorldField, s: float, side: float) -> Transform3D:
	for distance in [s - 15.0, s, s + 15.0]:
		if field.landforms.bridge_at(distance): return Transform3D.IDENTITY
	# The existing wooden utility poles occupy the positive side every 50 m.
	if side > 0.0 and absf(s - (roundf((s - 20.0) / 50.0) * 50.0 + 20.0)) < 3.0:
		return Transform3D.IDENTITY
	var road := field.road_frame(s)
	var point := road.origin + road.basis.x * side * (field.road_width(s) * 0.5 + SHOULDER_OFFSET)
	var sample := field.surface(point.x, point.z)
	if is_finite(float(sample.water_height)) or absf(float(sample.height) - road.origin.y) > 1.0:
		return Transform3D.IDENTITY
	if field.normal_at(point.x, point.z).y < cos(deg_to_rad(20.0)):
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

extends RefCounted
class_name RoadDetails
## Carriageway dressing: asphalt surface, gravel shoulders, utility poles and
## their lines, curve signage and marker posts. Every plan is a pure function of
## the route, so a band can describe a neighbour's pole without loading it.
const SURFACE = preload("res://world/terrain/road_surface.gdshader")
const STATION := 2.5
const UV_WRAP := 9600.0
const POLE_SPACING := 50.0
const POLE_OFFSET := 20.0
const POLE_LATERAL := 14.0
const POLE_TOP := 8.5
const SIGN_SETBACK := 4.6
const APEX_RADIUS := 62.0
const APEX_STEP := 5.0
const WARNING_LEAD := 75.0
const MARKER_SPACING := 25.0
const GRAVEL := Color("8b8573")
const CABLE := Color("3d3f3d")
static var _surface: ShaderMaterial

static func surface_material() -> ShaderMaterial:
	if _surface == null:
		_surface = ShaderMaterial.new()
		_surface.shader = SURFACE
	return _surface

## The asphalt strip, carrying the lateral/route coordinates the shader paints with.
static func surface_mesh(field: WorldField, band: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := field.profile.chunk_length
	var stations := roundi(length / STATION)
	for i in range(stations + 1):
		var s := band * length + i * STATION
		var frame := field.road_frame(s)
		var half := field.road_width(s) * 0.5
		for side: float in [-1.0, 1.0]:
			var point: Vector3 = frame.origin + frame.basis.x * side * half
			point.y += 0.07
			st.set_color(Color(field.landforms.bridge_gap(s), 0, 0))
			# Wrapped so the shader's hashes keep their precision far down the route.
			st.set_uv(Vector2(side * half, fposmod(s, UV_WRAP) if i < stations or fposmod(s, UV_WRAP) > 0.0 else UV_WRAP))
			st.set_uv2(Vector2(half, 0))
			st.add_vertex(point)
	for i in range(stations):
		var a := i * 2
		for v in [a, a + 2, a + 1, a + 1, a + 2, a + 3]: st.add_index(v)
	st.generate_normals()
	return st.commit()

static func build(chunk: ChunkGenerator) -> void:
	var field := chunk.field
	var band := chunk.band
	_build_shoulders(chunk)
	var lines := PropMesh.new()
	for index in range(band * 3, band * 3 + 3):
		var pose := pole_pose(field, index)
		if pose == Transform3D.IDENTITY: continue
		var pole := RoadsideKit.instantiate_module("pole")
		pole.name = "UtilityPole_%d" % index
		pole.transform = pose
		chunk.add_child(pole)
		_string_lines(field, index, pose, lines)
	if not lines.is_empty():
		var node := lines.instance(chunk, "PowerLines", Transform3D.IDENTITY) as MeshInstance3D
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var furniture: Array[Dictionary] = []
	for marker: Dictionary in markers(field, band):
		furniture.append({"mesh": &"marker_1" if marker.stone else &"marker_0", "pose": _upright(marker.point, marker.yaw, marker.lean)})
	for board: Dictionary in curve_signs(field, band):
		var mesh := &"sign_0"
		if board.kind == "warning": mesh = &"sign_1" if float(board.bend) > 0.0 else &"sign_2"
		furniture.append({"mesh": mesh, "pose": _upright(board.point, board.yaw, board.lean)})
	BreakableProps.build(chunk, "RoadFurniture", furniture)

static func _upright(point: Vector3, yaw: float, lean: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(lean.x, 0, lean.y)), point)

## Wooden utility pole `index` along the route, or IDENTITY where none stands.
static func pole_pose(field: WorldField, index: int) -> Transform3D:
	var s := index * POLE_SPACING + POLE_OFFSET
	if field.landforms.bridge_at(s) or field.road_width(s) > 18.0: return Transform3D.IDENTITY
	var frame := field.road_frame(s)
	var point := frame * Vector3(POLE_LATERAL, 0, 0)
	for site: Dictionary in field.sites_near_z(point.z):
		if field.court_distance(point.x, point.z, site) < 20.0: return Transform3D.IDENTITY
	point.y = field.height_at(point.x, point.z)
	# Decades without maintenance: most lean a little, a few are close to falling.
	var rng := field.rng_for(index, "utility_pole")
	var lean := deg_to_rad(rng.randf_range(0.0, 4.0) if rng.randf() > 0.08 else rng.randf_range(9.0, 17.0))
	var heading := rng.randf_range(0.0, TAU)
	return Transform3D(frame.basis.rotated(Vector3(cos(heading), 0, sin(heading)), lean), point)

static func _string_lines(field: WorldField, index: int, pose: Transform3D, lines: PropMesh) -> void:
	var rng := field.rng_for(index, "utility_line")
	var next := pole_pose(field, index + 1)
	for conductor in range(3):
		var from := pose * Vector3((conductor - 1) * 1.1, POLE_TOP, 0)
		var missing := rng.randf()
		var sag := rng.randf_range(0.7, 1.5)
		if next == Transform3D.IDENTITY or missing < 0.10:
			# A dead end: a third of the loose conductors still trail to the ground.
			if rng.randf() < 0.35:
				var away := -pose.basis.z.slide(Vector3.UP).normalized() * rng.randf_range(2.0, 4.5) + pose.basis.x.slide(Vector3.UP).normalized() * (conductor - 1) * 0.6
				var end := from + away
				end.y = field.height_at(end.x, end.z) + 0.05
				lines.wire(from, end, 0.6, 0.055, CABLE, 6)
			continue
		lines.wire(from, next * Vector3((conductor - 1) * 1.1, POLE_TOP, 0), sag, 0.055, CABLE, 9)

static func _build_shoulders(chunk: ChunkGenerator) -> void:
	var field := chunk.field
	var length := field.profile.chunk_length
	var stations := roundi(length / STATION)
	var shape := PropMesh.new()
	for side: float in [-1.0, 1.0]:
		var previous_inner := Vector3.ZERO
		var previous_outer := Vector3.ZERO
		var previous_valid := false
		for i in range(stations + 1):
			var s := chunk.band * length + i * STATION
			var valid := not field.landforms.bridge_at(s)
			var frame := field.road_frame(s)
			var half := field.road_width(s) * 0.5
			# Ragged width from a route-space wave, identical for both neighbours at a seam.
			var width := 1.5 + 0.55 * sin(s * 0.31 + side) + 0.35 * sin(s * 0.117 - side * 2.0)
			var inner: Vector3 = frame.origin + frame.basis.x * side * (half - 0.12) + Vector3.UP * 0.075
			var outer: Vector3 = frame.origin + frame.basis.x * side * (half + width)
			# The outer edge dives into the terrain so no lip floats above the grid.
			if valid: outer.y = field.height_at(outer.x, outer.z) - 0.14
			if valid and previous_valid:
				var tint := GRAVEL.darkened(0.1 * (0.5 + 0.5 * sin(s * 0.9 + side * 3.0)))
				var below := (inner + previous_outer) * 0.5 + Vector3.DOWN
				shape.facet(previous_inner, inner, previous_outer, below, tint)
				shape.facet(inner, outer, previous_outer, below, tint.darkened(0.05))
			previous_inner = inner
			previous_outer = outer
			previous_valid = valid
	if shape.is_empty(): return
	var node := shape.instance(chunk, "RoadShoulder", Transform3D.IDENTITY) as MeshInstance3D
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Route distances of curvature peaks tighter than APEX_RADIUS, on a global grid.
static func apexes(field: WorldField, from: float, to: float) -> Array[float]:
	var result: Array[float] = []
	for index in range(maxi(ceili(from / APEX_STEP), 100), floori(to / APEX_STEP) + 1):
		var s := index * APEX_STEP
		var here := absf(field.route.curvature(s))
		if here < 1.0 / APEX_RADIUS: continue
		if here >= absf(field.route.curvature(s - APEX_STEP)) and here > absf(field.route.curvature(s + APEX_STEP)): result.append(s)
	return result

static func curve_signs(field: WorldField, band: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var length := field.profile.chunk_length
	for apex in apexes(field, band * length - WARNING_LEAD - 20.0, (band + 1) * length + WARNING_LEAD + 20.0):
		var turn := signf(field.route.curvature(apex))
		# Hazard boards line the outside of the bend.
		for offset: float in [-14.0, 0.0, 14.0]:
			var frame := field.road_frame(apex + offset)
			var toward := (turn * frame.basis.x).slide(Vector3.UP).normalized()
			_offer(field, band, result, {"kind": "hazard", "s": apex + offset, "side": -turn, "yaw": atan2(toward.x, toward.z), "bend": 0.0})
		# One warning per direction of travel, on that driver's right.
		var before := field.road_frame(apex - WARNING_LEAD)
		_offer(field, band, result, {"kind": "warning", "s": apex - WARNING_LEAD, "side": 1.0, "yaw": atan2(before.basis.z.x, before.basis.z.z), "bend": turn})
		var after := field.road_frame(apex + WARNING_LEAD)
		_offer(field, band, result, {"kind": "warning", "s": apex + WARNING_LEAD, "side": -1.0, "yaw": atan2(-after.basis.z.x, -after.basis.z.z), "bend": -turn})
	return result

static func _offer(field: WorldField, band: int, result: Array[Dictionary], board: Dictionary) -> void:
	var s: float = board.s
	if s < 500.0: return
	for offset: float in [-10.0, 0.0, 10.0]:
		if field.landforms.bridge_at(s + offset): return
	var frame := field.road_frame(s)
	var point := frame * Vector3(float(board.side) * (field.road_width(s) * 0.5 + SIGN_SETBACK), 0, 0)
	var offset_in_band := fposmod(-point.z, field.profile.chunk_length)
	if floori(-point.z / field.profile.chunk_length) != band or offset_in_band < 3.0 or offset_in_band > field.profile.chunk_length - 3.0: return
	var sample := field.surface(point.x, point.z)
	if sample.reserved or is_finite(float(sample.water_height)) or absf(float(sample.height) - frame.origin.y) > 2.5: return
	for site: Dictionary in field.sites_near_z(point.z):
		if field.court_distance(point.x, point.z, site) < 20.0: return
	var rng := field.rng_for(roundi(s * 4.0), "road_sign_" + String(board.kind))
	if rng.randf() < 0.14: return # Long since knocked down and overgrown.
	point.y = sample.height
	board.point = point
	board.lean = Vector2(rng.randf_range(-0.09, 0.09), rng.randf_range(-0.09, 0.09))
	result.append(board)

static func markers(field: WorldField, band: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var length := field.profile.chunk_length
	for index in range(ceili(band * length / MARKER_SPACING), ceili((band + 1) * length / MARKER_SPACING)):
		var s := index * MARKER_SPACING + 6.0
		if s < 300.0 or field.landforms.bridge_at(s): continue
		var rng := field.rng_for(index, "road_marker")
		if rng.randf() < 0.3: continue
		var side := -1.0 if index % 2 == 0 else 1.0
		var frame := field.road_frame(s)
		var point := frame * Vector3(side * (field.road_width(s) * 0.5 + 1.25), 0, 0)
		if floori(-point.z / length) != band: continue
		point.y = field.height_at(point.x, point.z)
		result.append({"point": point, "yaw": atan2(frame.basis.z.x, frame.basis.z.z), "stone": index % 20 == 0, "lean": Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))})
	return result

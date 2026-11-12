extends Node3D
## Physical instrument binnacle. Housing, bezels, lenses, needles and lamps are real
## geometry; only the dial print is a texture. Reads the chassis and owns no vehicle state.
## Local units are metres before the scene's scale; +Z faces the driver.
const ART := "res://assets/rv_status/"
const WEAR := "res://assets/materials/industrial/worn_paint.png"
const GEAR_GLYPHS := "RN1234" # Cell order in gear_strip.svg; index is gear + 1.
const SPEED_FULL_SCALE := 140.0 # km/h
const RPM_FULL_SCALE := 5000.0
const DIAL_SWEEP := 4.886922 # 280 degrees, shared by needles and scripts/build_rv_instrument_art.gd.
const LEVEL_SWEEP := 2.094395 # 120 degrees for the fuel and battery gauges.
const INK := Color("d9dfbe")
const OFF := Color("172421")
const UNLIT_PRINT := Color("59625c")
const TILE_OFF := Color(0.17, 0.19, 0.185)
const PLATE := Vector2(1.3, 0.44)
const BIG_DIAL := 0.165
const SMALL_DIAL := 0.07

var speed_needle: Node3D
var rpm_needle: Node3D
var fuel_needle: Node3D
var battery_needle: Node3D
var gear_lamps: Array[StandardMaterial3D] = []
var charge_material: StandardMaterial3D
var warning_lamps: Dictionary = {}
var backlights: Array[StandardMaterial3D] = []
var indicated_speed := 0.0
var indicated_rpm := 0.0
var indicated_fuel := 0.0
var indicated_charge := 0.0
var _status_elapsed := 0.0
var _glow_light: OmniLight3D
var _housing: StandardMaterial3D
var _plate: StandardMaterial3D
var _chrome: StandardMaterial3D
var _tunnel: StandardMaterial3D
var _trim: StandardMaterial3D
var _hub: StandardMaterial3D
var _lens: StandardMaterial3D
var _ring_shadow: StandardMaterial3D
var _face_shade: StandardMaterial3D
var _edge_shadow: StandardMaterial3D
var _lamp_falloff: GradientTexture2D

## Needle rotation about +Z for a 0..1 reading on the speed and RPM dials.
static func dial_rotation(ratio: float) -> float:
	return DIAL_SWEEP * (0.5 - clampf(ratio, 0.0, 1.0))

## Needle rotation about +Z for a 0..1 reading on the fuel and battery gauges.
static func level_rotation(ratio: float) -> float:
	return LEVEL_SWEEP * (0.5 - clampf(ratio, 0.0, 1.0))

func _ready() -> void:
	_housing = _worn(Color(0.11, 0.13, 0.135), 0.92)
	_plate = _worn(Color(0.27, 0.31, 0.315), 0.74)
	# The cab is lit almost only by ambient light, so form is baked in: vertex shades
	# on turned parts and soft shadow overlays where parts meet the plate.
	_chrome = _shaded(Color(0.7, 0.73, 0.72), 0.3)
	_chrome.metallic = 0.3
	_tunnel = _shaded(Color(0.12, 0.13, 0.13), 0.75)
	_hub = _shaded(Color(0.24, 0.25, 0.25), 0.35)
	_trim = _solid(Color(0.03, 0.035, 0.036), 0.42)
	_lens = _overlay(_gradient([Color(1, 1, 1, 0.21), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.02)], [0.0, 0.5, 1.0], false), false)
	_lens.roughness = 0.05
	_ring_shadow = _overlay(_gradient([Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)], [0.0, 0.78, 1.0], true), true)
	_face_shade = _overlay(_gradient([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55)], [0.0, 0.7, 1.0], true), true)
	_edge_shadow = _overlay(_gradient([Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.25), Color(0, 0, 0, 0)], [0.0, 0.45, 1.0], false), true)
	_lamp_falloff = _gradient([Color.WHITE, Color(0.86, 0.86, 0.86), Color(0.5, 0.5, 0.5)], [0.0, 0.5, 1.0], true)
	_build_housing()
	speed_needle = _gauge("Speed", Vector2(-0.44, -0.008), BIG_DIAL, "dial_speed", dial_rotation(0.0))
	rpm_needle = _gauge("RPM", Vector2(0.44, -0.008), BIG_DIAL, "dial_rpm", dial_rotation(0.0))
	fuel_needle = _gauge("Fuel", Vector2(-0.118, -0.105), SMALL_DIAL, "dial_fuel", level_rotation(0.0))
	battery_needle = _gauge("Battery", Vector2(0.118, -0.105), SMALL_DIAL, "dial_battery", level_rotation(0.0))
	_build_annunciator()
	_build_gear_quadrant()
	# Backlight spill on the hood, cheeks and wheel rim; it only matters in the dark.
	_glow_light = OmniLight3D.new()
	_glow_light.name = "BacklightSpill"
	_glow_light.position = Vector3(0, 0.0, 0.16)
	_glow_light.omni_range = 0.7
	_glow_light.light_color = INK
	_glow_light.light_energy = 0.0
	_glow_light.light_specular = 0.0
	add_child(_glow_light)

func update_instruments(rv: Chassis, delta: float) -> void:
	var connected := is_instance_valid(rv)
	var powered := connected and rv.has_usable_power(0.000001)
	var brightness := rv.instrument_brightness if powered else 0.0
	var speed := rv.road_speed() * 3.6 if connected else 0.0
	var rpm := rv.engine_rpm() if connected else 0.0
	var fuel := rv.current_fuel / maxf(rv.max_fuel, 1.0) if connected else 0.0
	# The charge gauge is electrical: without power it drops to empty.
	var charge := rv.current_power / maxf(rv.max_power, 1.0) if powered else 0.0
	indicated_speed = lerpf(indicated_speed, speed, 1.0 - exp(-delta * 10.0))
	indicated_rpm = lerpf(indicated_rpm, rpm, 1.0 - exp(-delta * 8.0))
	indicated_fuel = lerpf(indicated_fuel, fuel, 1.0 - exp(-delta * 3.0))
	indicated_charge = lerpf(indicated_charge, charge, 1.0 - exp(-delta * 3.0))
	speed_needle.rotation.z = dial_rotation(indicated_speed / SPEED_FULL_SCALE)
	rpm_needle.rotation.z = dial_rotation(indicated_rpm / RPM_FULL_SCALE)
	fuel_needle.rotation.z = level_rotation(indicated_fuel)
	battery_needle.rotation.z = level_rotation(indicated_charge)
	var selected := clampi(rv.gear + 1, 0, gear_lamps.size() - 1) if powered else -1
	for i in range(gear_lamps.size()):
		# Every position is faintly backlit; the engaged one burns bright.
		_glow(gear_lamps[i], INK if i == selected else UNLIT_PRINT, brightness * (2.4 if i == selected else 0.12))
	var charging := powered and rv.energy.generated_rate > 0.000001
	light_lamp(charge_material, Color("83c7a0"), brightness if charging else 0.0)
	for mat in backlights:
		mat.emission_energy_multiplier = brightness * 0.7
	_glow_light.light_energy = brightness * 0.3
	# Door/structure traversal only needs a dashboard-rate refresh.
	_status_elapsed -= delta
	if _status_elapsed <= 0.0:
		_status_elapsed = 0.1
		if connected:
			for row in VehicleStatus.read(rv):
				var active: bool = powered and row.level > 0
				light_lamp(warning_lamps[row.id], VehicleStatus.color(row.level), brightness if active else 0.0)
		else:
			for id in warning_lamps: light_lamp(warning_lamps[id], OFF, 0.0)

## Lights one telltale tile in a colour; zero brightness leaves the unlit grey lens.
func light_lamp(tile: StandardMaterial3D, tint: Color, brightness: float) -> void:
	_glow(tile, tint if brightness > 0.0 else TILE_OFF, brightness * 1.25)

func _build_housing() -> void:
	var width := PLATE.x + 0.07
	_box("Housing", Vector3(width, 0.5, 0.16), Vector3(0, 0, -0.085), _housing)
	_box("FacePlate", Vector3(PLATE.x, PLATE.y, 0.006), Vector3(0, 0, -0.003), _plate)
	_box("Hood", Vector3(width, 0.03, 0.13), Vector3(0, 0.24, 0.055), _housing)
	# Padded roll along the hood's leading edge.
	var roll := CylinderMesh.new()
	roll.top_radius = 0.019
	roll.bottom_radius = 0.019
	roll.height = width
	roll.radial_segments = 12
	_mesh("HoodRoll", roll, Vector3(0, 0.241, 0.12), _housing).rotation.z = PI / 2.0
	_box("LowerLip", Vector3(width, 0.03, 0.04), Vector3(0, -0.235, 0.015), _housing)
	# Cheeks taper from the hood down to the lip so the face sits in a shroud.
	var cheek := _prism(PackedVector2Array([Vector2(-0.005, -0.25), Vector2(0.035, -0.25), Vector2(0.125, 0.255), Vector2(-0.005, 0.255)]), 0.035)
	for side: float in [-1.0, 1.0]:
		_mesh("Cheek", cheek, Vector3(side * (PLATE.x * 0.5 + 0.0175) + 0.0175, 0, 0), _housing).rotation.y = -PI / 2.0
		# Shade where the cheek meets the plate.
		var shade := _quad("CheekShadow", Vector2(PLATE.y, 0.09), Vector3(side * (PLATE.x * 0.5 - 0.045), 0, 0.0005), _edge_shadow)
		shade.rotation.z = -side * PI / 2.0
	_quad("HoodShadow", Vector2(PLATE.x, 0.11), Vector3(0, PLATE.y * 0.5 - 0.055, 0.0006), _edge_shadow)
	for at: Vector2 in [Vector2(-0.63, 0.2), Vector2(0.63, 0.2), Vector2(-0.63, -0.2), Vector2(0.63, -0.2), Vector2(-0.262, -0.2), Vector2(0.262, -0.2)]:
		_mesh("Washer", _lathe(_cap_profile(0.0125, 0.002), 14, [0.35, 0.6, 0.8, 0.8]), Vector3(at.x, at.y, 0), _chrome)
		_mesh("Fastener", _lathe(_cap_profile(0.008, 0.0055), 12, [0.45, 0.8, 1.0, 0.85]), Vector3(at.x, at.y, 0.002), _chrome)
		_box("ScrewSlot", Vector3(0.012, 0.0022, 0.001), Vector3(at.x, at.y, 0.0077), _trim).rotation.z = at.x * 7.0 + at.y * 3.0
	_mesh("DimmerKnob", _lathe(_cap_profile(0.015, 0.024), 10, [0.5, 0.9, 1.0, 0.7]), Vector3(0, -0.192, 0), _hub)

## A pod gauge: a chrome-rimmed tube standing off the plate, flaring open toward the
## driver, with the printed face at its bottom behind a lens.
func _gauge(title: String, at: Vector2, radius: float, art: String, rest: float) -> Node3D:
	var depth := radius * 0.3
	var mouth := radius * 1.11
	var outer := radius * 1.2
	var rim := outer - mouth
	var root := Node3D.new()
	root.name = title + "Gauge"
	root.position = Vector3(at.x, at.y, 0)
	add_child(root)
	_mesh("ContactShadow", _disc(outer * 1.22, 32), Vector3(0, -outer * 0.04, 0.0008), _ring_shadow, root)
	var face := _solid(Color.WHITE, 0.62, load(ART + art + ".svg"))
	face.emission_enabled = true
	face.emission = INK
	face.emission_texture = face.albedo_texture
	face.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	backlights.append(face)
	_mesh("Face", _disc(radius, 48), Vector3(0, 0, 0.002), face, root)
	# The tube shades the rim of the face.
	_mesh("FaceShade", _disc(radius, 32), Vector3(0, 0, 0.0032), _face_shade, root)
	_mesh("Tunnel", _lathe(PackedVector2Array([Vector2(mouth, depth * 0.95), Vector2(radius, 0.002)]), 48, [0.75, 0.12]), Vector3.ZERO, _tunnel, root)
	var profile := PackedVector2Array([Vector2(outer, 0), Vector2(outer, depth * 0.6), Vector2(outer - rim * 0.25, depth * 0.93), Vector2(outer - rim * 0.55, depth), Vector2(mouth + rim * 0.12, depth), Vector2(mouth, depth * 0.95)])
	_mesh("Rim", _lathe(profile, 48, [0.22, 0.55, 1.0, 0.9, 0.72, 0.4]), Vector3.ZERO, _chrome, root)
	var pivot := Node3D.new()
	pivot.name = "Needle"
	pivot.position.z = depth * 0.3
	pivot.rotation.z = rest
	root.add_child(pivot)
	var pointer := _solid(Color("f39a52"), 0.5)
	pointer.emission_enabled = true
	pointer.emission = pointer.albedo_color
	backlights.append(pointer)
	var reach := radius * 0.84
	var half := radius * 0.034
	_mesh("Pointer", _prism(PackedVector2Array([Vector2(-half, -radius * 0.14), Vector2(half, -radius * 0.14), Vector2(half * 0.35, reach), Vector2(-half * 0.35, reach)]), radius * 0.015), Vector3.ZERO, pointer, pivot)
	_mesh("Hub", _lathe(_cap_profile(radius * 0.17, depth * 0.34), 20, [0.3, 0.75, 1.0, 0.55]), Vector3(0, 0, depth * 0.24), _hub, root)
	_mesh("Lens", _disc(mouth * 0.995, 32), Vector3(0, 0, depth * 0.9), _lens, root)
	return pivot

## Eight warning tiles in a 4 x 2 annunciator block: a pale lens that lights in the
## warning colour behind a solid black symbol.
func _build_annunciator() -> void:
	var pitch := Vector2(0.1, 0.07)
	var center := Vector2(0, 0.133)
	var size := Vector2(pitch.x * 4.0, pitch.y * 2.0)
	_box("AnnunciatorBase", Vector3(size.x + 0.012, size.y + 0.012, 0.008), Vector3(center.x, center.y, 0.004), _housing)
	for row in range(3):
		_box("AnnunciatorRail", Vector3(size.x + 0.012, 0.007, 0.009), Vector3(center.x, center.y + (row - 1) * pitch.y, 0.0125), _housing)
	for column in range(5):
		_box("AnnunciatorPost", Vector3(0.007, size.y + 0.012, 0.009), Vector3(center.x + (column - 2) * pitch.x, center.y, 0.0125), _housing)
	for i in range(VehicleStatus.IDS.size()):
		var id: String = VehicleStatus.IDS[i]
		var at := Vector3(center.x + (i % 4 - 1.5) * pitch.x, center.y + (0.5 - floorf(i / 4.0)) * pitch.y, 0.008)
		warning_lamps[id] = _telltale(id, at, pitch - Vector2(0.008, 0.008))

## Gear positions printed behind one smoked window, like a column-shift quadrant,
## with the charging lamp in the same row.
func _build_gear_quadrant() -> void:
	var pitch := 0.055
	var window := Vector2(pitch * GEAR_GLYPHS.length(), 0.064)
	var center := Vector2(-0.052, 0.018)
	_frame("Gear", center, window, 0.007, 0.014)
	_box("GearWindow", Vector3(window.x, window.y, 0.004), Vector3(center.x, center.y, 0.002), _solid(Color(0.02, 0.025, 0.026), 0.22))
	var strip: Texture2D = load(ART + "gear_strip.svg")
	for i in range(GEAR_GLYPHS.length()):
		var mat := _solid(UNLIT_PRINT, 0.6, strip)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.uv1_scale.x = 1.0 / GEAR_GLYPHS.length()
		mat.uv1_offset.x = float(i) / GEAR_GLYPHS.length()
		_quad("Gear" + GEAR_GLYPHS[i], Vector2(0.046, 0.0613), Vector3(center.x + (i - 2.5) * pitch, center.y, 0.0056), mat)
		gear_lamps.append(mat)
	var lamp := Vector2(0.084, window.y)
	var lamp_center := Vector2(center.x + window.x * 0.5 + 0.014 + lamp.x * 0.5, center.y)
	_frame("Charge", lamp_center, lamp, 0.007, 0.014)
	charge_material = _telltale("charging", Vector3(lamp_center.x, lamp_center.y, 0.004), lamp)

## Four raised bars around a recessed opening.
func _frame(title: String, center: Vector2, inner: Vector2, bar: float, height: float) -> void:
	for side: float in [-1.0, 1.0]:
		_box(title + "Rail", Vector3(inner.x + bar * 2.0, bar, height), Vector3(center.x, center.y + side * (inner.y + bar) * 0.5, height * 0.5), _housing)
		_box(title + "Post", Vector3(bar, inner.y, height), Vector3(center.x + side * (inner.x + bar) * 0.5, center.y, height * 0.5), _housing)

## A lamp tile sitting at the given base height; returns the lens material that lights up.
func _telltale(id: String, at: Vector3, size: Vector2) -> StandardMaterial3D:
	# The bulb sits behind the middle of the lens, so the tile falls off toward its edges.
	var lens := _solid(TILE_OFF, 0.3, _lamp_falloff)
	_box(id.capitalize() + "Body", Vector3(size.x, size.y, 0.003), at + Vector3(0, 0, 0.0015), _trim)
	_quad(id.capitalize() + "Lens", size, at + Vector3(0, 0, 0.0032), lens)
	var symbol := _solid(Color(0.012, 0.016, 0.016), 0.5, load(ART + id + ".svg"))
	symbol.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var side := minf(size.x, size.y) * 0.9
	_quad(id.capitalize() + "Symbol", Vector2(side, side), at + Vector3(0, 0, 0.0036), symbol)
	return lens

func _glow(mat: StandardMaterial3D, tint: Color, energy: float) -> void:
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_texture = mat.albedo_texture
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY if mat.albedo_texture else BaseMaterial3D.EMISSION_OP_ADD
	mat.emission_energy_multiplier = energy

func _solid(tint: Color, roughness: float, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = texture
	mat.roughness = roughness
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

## Material whose albedo is multiplied by baked vertex shades.
func _shaded(tint: Color, roughness: float) -> StandardMaterial3D:
	var mat := _solid(tint, roughness)
	mat.vertex_color_use_as_albedo = true
	return mat

## Alpha-blended decal: a baked shadow (unshaded black) or a lens highlight (lit white).
func _overlay(texture: Texture2D, unshaded: bool) -> StandardMaterial3D:
	var mat := _solid(Color.WHITE, 0.4, texture)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded: mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

## Top-to-bottom ramp, or centre-to-edge when radial.
func _gradient(colors: Array[Color], offsets: Array[float], radial: bool) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = PackedFloat32Array(offsets)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.5) if radial else Vector2(0.5, 0.0)
	texture.fill_to = Vector2(1.0, 0.5) if radial else Vector2(0.5, 1.0)
	return texture

## Same worn paint as the rest of the cab, so the binnacle belongs to the vehicle.
func _worn(tint: Color, roughness: float) -> StandardMaterial3D:
	var mat := _solid(tint, roughness, load(WEAR))
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 1.4
	return mat

func _box(title: String, dimensions: Vector3, at: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(title, mesh, at, mat)

func _quad(title: String, dimensions: Vector2, at: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = dimensions
	return _mesh(title, mesh, at, mat)

func _mesh(title: String, mesh: Mesh, at: Vector3, mat: StandardMaterial3D, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.position = at
	node.material_override = mat
	parent.add_child(node)
	return node

## Rounded cap profile (radius, height) for hubs, knobs and screw heads.
func _cap_profile(radius: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(radius, 0), Vector2(radius, height * 0.6), Vector2(radius * 0.72, height), Vector2(0, height)])

## Surface of revolution about +Z. The profile lists (radius, z) from the outer base
## over the top to the inner base; each profile edge is one flat-shaded band. Optional
## shades give each profile point a baked brightness for materials from _shaded().
func _lathe(profile: PackedVector2Array, segments: int, shades: Array[float] = []) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in range(profile.size() - 1):
		var a := profile[edge]
		var b := profile[edge + 1]
		var slope := Vector2(b.y - a.y, a.x - b.x).normalized()
		for i in range(segments):
			var t0 := TAU * i / segments
			var t1 := TAU * (i + 1) / segments
			var ring0 := Vector3(cos(t0), sin(t0), 0)
			var ring1 := Vector3(cos(t1), sin(t1), 0)
			var corners: Array[Vector3] = [ring0 * a.x + Vector3(0, 0, a.y), ring1 * a.x + Vector3(0, 0, a.y), ring1 * b.x + Vector3(0, 0, b.y), ring0 * b.x + Vector3(0, 0, b.y)]
			var normals: Array[Vector3] = [ring0 * slope.x + Vector3(0, 0, slope.y), ring1 * slope.x + Vector3(0, 0, slope.y)]
			var low := Color.WHITE if shades.is_empty() else Color(shades[edge], shades[edge], shades[edge])
			var high := Color.WHITE if shades.is_empty() else Color(shades[edge + 1], shades[edge + 1], shades[edge + 1])
			_face(tool, [corners[0], corners[1], corners[2]], [normals[0], normals[1], normals[1]], [], [low, low, high])
			_face(tool, [corners[0], corners[2], corners[3]], [normals[0], normals[1], normals[0]], [], [low, high, high])
	return tool.commit()

## Flat disc facing +Z with the texture mapped once across its diameter.
func _disc(radius: float, segments: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var points: Array[Vector3] = [Vector3.ZERO]
		for step: int in [i, i + 1]:
			var angle := TAU * step / segments
			points.append(Vector3(cos(angle), sin(angle), 0) * radius)
		var uvs: Array[Vector2] = []
		for point in points: uvs.append(Vector2(0.5 + point.x / (radius * 2.0), 0.5 - point.y / (radius * 2.0)))
		_face(tool, points, [Vector3.BACK, Vector3.BACK, Vector3.BACK], uvs)
	return tool.commit()

## Convex outline in XY extruded from z = 0 to z = depth, with its top and side faces.
func _prism(outline: PackedVector2Array, depth: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := outline.size()
	for i in range(1, count - 1):
		for z in [depth, 0.0]:
			var normal := Vector3.BACK if z > 0.0 else Vector3.FORWARD
			_face(tool, [Vector3(outline[0].x, outline[0].y, z), Vector3(outline[i].x, outline[i].y, z), Vector3(outline[i + 1].x, outline[i + 1].y, z)], [normal, normal, normal])
	for i in range(count):
		var a := outline[i]
		var b := outline[(i + 1) % count]
		var side := Vector3(b.y - a.y, a.x - b.x, 0).normalized()
		# Outlines may wind either way; point the wall away from the centroid.
		if side.dot(Vector3(a.x + b.x, a.y + b.y, 0) * 0.5 - _centroid(outline)) < 0.0: side = -side
		_face(tool, [Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), Vector3(b.x, b.y, depth)], [side, side, side])
		_face(tool, [Vector3(a.x, a.y, 0), Vector3(b.x, b.y, depth), Vector3(a.x, a.y, depth)], [side, side, side])
	return tool.commit()

func _centroid(outline: PackedVector2Array) -> Vector3:
	var sum := Vector2.ZERO
	for point in outline: sum += point
	sum /= outline.size()
	return Vector3(sum.x, sum.y, 0)

## Adds one triangle wound so its front faces along the given normals.
func _face(tool: SurfaceTool, points: Array, normals: Array, uvs: Array = [], shades: Array = []) -> void:
	var order := [0, 1, 2]
	# Godot front faces wind clockwise: the geometric cross product points away from the viewer.
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normals[0] + normals[1] + normals[2]) > 0.0: order = [0, 2, 1]
	for index in order:
		tool.set_color(Color.WHITE if shades.is_empty() else shades[index])
		tool.set_normal(normals[index].normalized())
		if not uvs.is_empty(): tool.set_uv(uvs[index])
		tool.add_vertex(points[index])

extends Node3D
## Physical instruments: millimetre-authored artwork and moving parts share one face.
const FACE := preload("res://assets/rv_status/cluster_face.svg")
const GEARS := preload("res://assets/rv_status/cluster_gears.svg")
const INK := Color("d9dfbe")
const OFF := Color("172421")
var speed_needle: Node3D
var rpm_needle: Node3D
var fuel_pointer: MeshInstance3D
var gear_material: StandardMaterial3D
var charge_material: StandardMaterial3D
var battery_cells: Array[MeshInstance3D] = []
var warning_lamps: Dictionary = {}
var backlights: Array[StandardMaterial3D] = []
var indicated_speed := 0.0
var indicated_rpm := 0.0
var _status_elapsed := 0.0

func _ready() -> void:
	var housing := _material(Color("171d1e"))
	housing.roughness = 0.86
	_box("Housing", Vector3(1.24, 0.48, 0.085), Vector3(0, 0, -0.045), housing)
	_box("UpperVisor", Vector3(1.28, 0.025, 0.13), Vector3(0, 0.245, -0.005), housing)
	var face_mat := _material(Color.WHITE, FACE)
	face_mat.emission_enabled = true
	face_mat.emission_texture = FACE
	backlights.append(face_mat)
	_quad("PrintedFace", Vector2(1.2, 0.44), Vector3.ZERO, face_mat)
	for x in [-0.588, 0.588]:
		for y in [-0.202, 0.202]:
			_disc("Fastener", Vector3(x, y, 0.004), 0.006, 0.003, _material(Color("69716e")))
			_box("ScrewSlot", Vector3(0.007, 0.0013, 0.001), Vector3(x, y, 0.006), housing)
	for x in [-0.37, 0.37]:
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.164
		mesh.outer_radius = 0.170
		mesh.rings = 64
		mesh.ring_segments = 8
		ring.mesh = mesh
		ring.position = Vector3(x, -0.008, 0.003)
		ring.rotation.x = PI / 2.0
		ring.material_override = _material(Color("59615f"))
		add_child(ring)
	speed_needle = _needle("SpeedNeedle", -0.37)
	rpm_needle = _needle("RPMNeedle", 0.37)
	gear_material = _material(INK, GEARS)
	gear_material.uv1_scale.x = 1.0 / 7.0
	gear_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_quad("GearDisplay", Vector2(0.064, 0.096), Vector3(0, 0.096, 0.002), gear_material)
	for i in range(10):
		var cell := _box("ChargeCell%d" % i, Vector3(0.018, 0.034, 0.001), Vector3(-0.106 + i * 0.022, -0.014, 0.003), _material(OFF))
		battery_cells.append(cell)
	charge_material = _icon("Charging", "charging", Vector2(0.032, 0.032), Vector3(0, 0.035, 0.003))
	_icon("FuelSymbol", "fuel", Vector2(0.038, 0.038), Vector3(0, -0.134, 0.003), INK)
	var pointer_mat := _material(Color("f1ab60"))
	backlights.append(pointer_mat)
	fuel_pointer = _box("FuelPointer", Vector3(0.006, 0.027, 0.002), Vector3(-0.107, -0.09, 0.004), pointer_mat)
	for i in range(VehicleStatus.IDS.size()):
		var id: String = VehicleStatus.IDS[i]
		warning_lamps[id] = _icon(id, id, Vector2(0.040, 0.040), Vector3(-0.252 + i * 0.074, 0.180, 0.003))

func update_instruments(rv: Chassis, delta: float) -> void:
	var connected := is_instance_valid(rv)
	var powered := connected and rv.has_usable_power(0.000001)
	var brightness := rv.instrument_brightness if powered else 0.0
	var speed := rv.road_speed() * 3.6 if connected else 0.0
	var rpm := rv.engine_rpm() if connected else 0.0
	indicated_speed = lerpf(indicated_speed, speed, 1.0 - exp(-delta * 10.0))
	indicated_rpm = lerpf(indicated_rpm, rpm, 1.0 - exp(-delta * 8.0))
	speed_needle.rotation.z = deg_to_rad(140.0 - clampf(indicated_speed / 140.0, 0.0, 1.0) * 280.0)
	rpm_needle.rotation.z = deg_to_rad(140.0 - clampf(indicated_rpm / 5000.0, 0.0, 1.0) * 280.0)
	var fuel := clampf(rv.current_fuel / maxf(rv.max_fuel, 1.0), 0.0, 1.0) if connected else 0.0
	fuel_pointer.position.x = lerpf(-0.107, 0.107, fuel)
	var charge := clampf(rv.current_power / maxf(rv.max_power, 1.0), 0.0, 1.0) if connected else 0.0
	for i in range(battery_cells.size()):
		var cell := battery_cells[i]
		var lit := powered and charge * 10.0 > float(i)
		var tint := Color("ef6142") if charge <= 0.1 else (Color("e9b559") if charge <= 0.2 else INK)
		_lamp(cell.material_override, tint if lit else OFF, brightness if lit else 0.0)
	var gear := clampi(rv.gear + 1, 0, 5) if connected else 6
	gear_material.uv1_offset.x = float(gear) / 7.0
	_lamp(gear_material, INK if powered else OFF, brightness)
	var charging := powered and rv.energy.generated_rate > 0.000001
	_lamp(charge_material, Color("83c7a0") if charging else OFF, brightness if charging else 0.0)
	for mat in backlights:
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = brightness * 0.7
	# Door/structure traversal only needs a dashboard-rate refresh.
	_status_elapsed -= delta
	if _status_elapsed <= 0.0:
		_status_elapsed = 0.1
		if connected:
			for row in VehicleStatus.read(rv):
				var active: bool = powered and row.level > 0
				_lamp(warning_lamps[row.id], VehicleStatus.color(row.level) if active else OFF, brightness if active else 0.0)
		else:
			for mat in warning_lamps.values(): _lamp(mat, OFF, 0.0)

func _needle(title: String, x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = title
	pivot.position = Vector3(x, -0.008, 0.009)
	add_child(pivot)
	var mat := _material(Color("f39a52"))
	backlights.append(mat)
	var pointer := _box("Pointer", Vector3(0.005, 0.133, 0.003), Vector3(0, 0.052, 0), mat)
	pointer.reparent(pivot, false)
	_disc("NeedleHub", Vector3(x, -0.008, 0.015), 0.017, 0.009, _material(Color("303b3b")))
	pivot.rotation.z = deg_to_rad(140.0)
	return pivot

func _material(tint: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = texture
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY if texture else BaseMaterial3D.EMISSION_OP_ADD
	mat.roughness = 0.68
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

func _lamp(mat: StandardMaterial3D, tint: Color, brightness: float) -> void:
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_texture = mat.albedo_texture
	mat.emission_energy_multiplier = brightness * 1.8

func _icon(title: String, id: String, dimensions: Vector2, at: Vector3, tint: Color = OFF) -> StandardMaterial3D:
	var mat := _material(tint, load("res://assets/rv_status/" + id + ".svg"))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_quad(title, dimensions, at, mat)
	if tint != OFF: backlights.append(mat)
	return mat

func _box(title: String, dimensions: Vector3, at: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(title, mesh, at, mat)

func _quad(title: String, dimensions: Vector2, at: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := QuadMesh.new()
	mesh.size = dimensions
	_mesh(title, mesh, at, mat)

func _disc(title: String, at: Vector3, radius: float, depth: float, mat: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 24
	_mesh(title, mesh, at, mat).rotation.x = PI / 2.0

func _mesh(title: String, mesh: Mesh, at: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.position = at
	node.material_override = mat
	add_child(node)
	return node

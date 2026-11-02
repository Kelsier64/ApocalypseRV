@tool
extends "res://world/megashelter/megashelter_room.gd"
## The lowest landing is the room origin. Two opposing flights share a half landing.

const FLIGHT_END := 2.45
const MID_LEVEL := 2.25
const FLIGHT_WIDTH := 2.6
const TREADS := 14
const FLIGHT_X := 1.7

func _build() -> void:
	if _built: return
	_built = true
	_prepare_room()
	_shell()
	_flight(-FLIGHT_X, MID_LEVEL, -FLIGHT_END, FLIGHT_END)
	_flight(FLIGHT_X, 0, FLIGHT_END, -FLIGHT_END)
	# The open section of the upper landing overlooks the second flight.
	_balustrade(Vector3(-0.43, 4.5, FLIGHT_END), Vector3(3.05, 4.5, FLIGHT_END))
	_balustrade(Vector3(-0.43, MID_LEVEL, -FLIGHT_END), Vector3(0.43, MID_LEVEL, -FLIGHT_END))
	_landings()
	_finish_batches()
	_batches.clear()

func _shell() -> void:
	_box(Vector3(0, -0.125, 0), Vector3(6.6, 0.25, 9.8), 0, true)
	_box(Vector3(0, clear_height + 0.12, 0), Vector3(6.6, 0.24, 9.8), 0, true)
	for side: float in [-1, 1]:
		_box(Vector3(3.18 * side, 3.9, 0), Vector3(0.24, 7.8, 9.8), 0, true)
		# Narrow reveals break up the poured panels and continue up the shaft.
		for z in [-2.52, 0.0, 2.52]:
			_box(Vector3(3.057 * side, 3.9, z), Vector3(0.009, 7.8, 0.023), 4)
	_turn_wall()
	# South wall wraps the lower blast-door socket. Its lintel carries the G landing.
	_box(Vector3(-2.03, 1.52, 4.78), Vector3(2.06, 3.04, 0.24), 0, true)
	_box(Vector3(2.88, 1.52, 4.78), Vector3(0.36, 3.04, 0.24), 0, true)
	_box(Vector3(0, 5.42, 4.78), Vector3(6.12, 4.76, 0.24), 0, true)
	for landing: Vector2 in [Vector2(MID_LEVEL, -1), Vector2(4.5, 1)]:
		var z := landing.y * (FLIGHT_END + 4.66) * 0.5
		var slab_size := Vector3(6.12, 0.24, 4.66 - FLIGHT_END)
		_box(Vector3(0, landing.x - 0.12, z), slab_size, 0, true)
		_box(Vector3(0, landing.x - 0.29, landing.y * (FLIGHT_END + 0.22)), Vector3(6.12, 0.2, 0.34), 0, true)
		if landing.y > 0:
			_box(Vector3(0, landing.x + 0.62, 4.65), Vector3(6.12, 1.24, 0.036), 1)
		for side: float in [-1, 1]:
			_box(Vector3(3.044 * side, landing.x + 0.62, z), Vector3(0.04, 1.24, slab_size.z), 1)

func _turn_wall() -> void:
	var wall := Transform3D(Basis.IDENTITY, Vector3(0, MID_LEVEL, -4.90))
	var fracture := Rect2(0.12, 0.18, 1.62, 0.96)
	var panel := Rect2(-3.06, -MID_LEVEL, 6.12, clear_height)
	_collider(Vector3(0, 3.9, -4.78), Vector3(6.12, 7.8, 0.24))
	_piece_local(wall, Vector3(0, 3.9 - MID_LEVEL, 0.04), Vector3(6.12, 7.8, 0.08), 0)
	for strip in _subtract(panel, fracture):
		var centre := strip.get_center()
		_piece_local(wall, Vector3(centre.x, centre.y, 0.16), Vector3(strip.size.x, strip.size.y, 0.16), 0)
	for strip in _subtract(Rect2(-3.06, 0, 6.12, 1.24), fracture):
		var centre := strip.get_center()
		_piece_local(wall, Vector3(centre.x, centre.y, 0.252), Vector3(strip.size.x, strip.size.y, 0.024), 1)
	_cavity(wall, fracture)

func _flight(x: float, base_y: float, low_z: float, high_z: float) -> void:
	var low := Vector3(x, base_y, low_z)
	var high := Vector3(x, base_y + MID_LEVEL, high_z)
	var along := high - low
	var slope := Basis(Vector3.RIGHT, -atan(along.y / along.z))
	var slab := Transform3D(slope, (low + high) * 0.5 - slope.y * 0.15)
	var size := Vector3(FLIGHT_WIDTH, 0.30, along.length())
	_piece_local(slab, Vector3.ZERO, size, 0)
	# A continuous collision surface makes each direction walkable with cargo.
	_collider(slab.origin, size, slope)
	var run := along.z / TREADS
	var rise := MID_LEVEL / TREADS
	for i in TREADS:
		var toe := low + along * (float(i) / TREADS)
		_box(toe + Vector3(0, rise * 0.28, run * 0.5), Vector3(FLIGHT_WIDTH, rise * 1.45, absf(run)), 0)
		# Recessed steel nosings catch grazing light without bright warning paint.
		_piece(toe + Vector3(0, rise + 0.003, run * 0.085), Vector3(FLIGHT_WIDTH - 0.08, 0.012, 0.037), 2)
	var rail_offset := Vector3(-signf(x) * 1.27, 0, 0)
	_balustrade(low + rail_offset, high + rail_offset)
	var wall_offset := Vector3(signf(x) * 1.22, 0.96, 0)
	var pipes: Array[Dictionary] = []
	FITTINGS.pipe(pipes, low + wall_offset, high + wall_offset, 0.038)
	for t: float in [0.08, 0.46, 0.9]:
		var bracket := low.lerp(high, t) + wall_offset
		FITTINGS.pipe(pipes, bracket, bracket + Vector3(0, -0.13, 0), 0.019)
		FITTINGS.pipe(pipes, bracket + Vector3(0, -0.13, 0), bracket + Vector3(signf(x) * 0.13, -0.13, 0), 0.019)
	_append_pieces(Transform3D.IDENTITY, pipes)
	# Follow the rake with the same worn half-height paint as the landings.
	var a := Vector3(signf(x) * 3.038, base_y, low_z)
	var b := Vector3(a.x, high.y, high_z)
	_batches[1]._face(Transform3D.IDENTITY, Vector3.ZERO, [a, b, b + Vector3.UP * 1.24, a + Vector3.UP * 1.24], Vector3.LEFT * signf(x), 0.91)

func _balustrade(a: Vector3, b: Vector3) -> void:
	var pipes: Array[Dictionary] = []
	var spans := ceili(a.distance_to(b) / 1.5)
	for i in range(spans + 1):
		var foot := a.lerp(b, float(i) / spans)
		_piece(foot + Vector3.UP * 0.03, Vector3(0.16, 0.06, 0.16), 2, "bevel")
		_box(foot + Vector3.UP * 0.52, Vector3(0.054, 1.04, 0.054), 2)
	for height: float in [0.32, 0.65, 1.04]:
		FITTINGS.pipe(pipes, a + Vector3.UP * height, b + Vector3.UP * height, 0.037 if height > 1 else 0.02)
	_append_pieces(Transform3D.IDENTITY, pipes)
	# Keep the player and carried items on the stairs. Match the rail silhouette.
	var delta := b - a
	var longitudinal := Basis.looking_at(delta.normalized(), Vector3.UP)
	_collider((a + b) * 0.5 + Vector3.UP * 0.54, Vector3(0.085, 0.95, delta.length()), longitudinal)

func _landings() -> void:
	var south := Basis(Vector3.UP, PI)
	_append_pieces(Transform3D(south, Vector3(-1.5, 4.5, 4.61)), FITTINGS.pedestrian_door())
	_append_pieces(Transform3D(south, Vector3(0.85, 0, 4.61)), FITTINGS.large_door())
	_sign("GROUND", Vector3(-1.5, 7.17, 4.58), PI, 1.48)
	_sign("B1   /   BUNKER", Vector3(0.85, 3.56, 4.58), PI, 2.22)
	_floor_number("G", Vector3(1.45, 6.12, 4.60), PI)
	_floor_number("B1", Vector3(0.0, 3.77, -4.62), 0)
	_append_pieces(Transform3D(Basis.IDENTITY, Vector3(0, MID_LEVEL, -4.9)), FITTINGS.wall_bay(7.0, 3.4, 2))
	_grate(Vector3(-2.25, MID_LEVEL + 0.012, -4.03), Vector2(0.57, 0.55))
	_grate(Vector3(-1.88, 0.012, 3.85), Vector2(0.34, 1.35))
	_risers()
	_bulkhead_light(Vector3(-1.75, 5.25, -4.59), Basis.IDENTITY, Color("c3cfbf"), 3.8)
	_bulkhead_light(Vector3(0, 7.1, 4.58), south, Color("bdcac7"), 2.9)
	_bulkhead_light(Vector3(-1.66, 2.72, 4.58), south, Color("ddab7f"), 2.5)
	# Recessed under the upper landing, this task light grazes the wheel and locking dogs.
	_bulkhead_light(Vector3(1.65, 4.20, 2.85), Basis(Vector3.RIGHT, PI * 0.5), Color("b4c1b6"), 2.1)

func _risers() -> void:
	# Feed and return lines share a hanger rack beside the turn, clear of the stairs.
	var pipes: Array[Dictionary] = []
	for x: float in [1.91, 2.29]:
		var radius := 0.095 if x < 2.0 else 0.064
		FITTINGS.pipe(pipes, Vector3(x, MID_LEVEL, -4.34), Vector3(x, 7.38, -4.34), radius)
		FITTINGS.pipe(pipes, Vector3(x, 7.38, -4.34), Vector3(x, 7.38, -4.68), radius)
		for y: float in [2.42, 4.32, 4.43, 6.15, 7.3]:
			FITTINGS.pipe(pipes, Vector3(x, y, -4.34), Vector3(x, y + 0.055, -4.34), radius + 0.029)
	for y: float in [3.12, 5.5, 7.1]:
		_box(Vector3(2.1, y, -4.48), Vector3(0.79, 0.065, 0.34), 2)
	_append_pieces(Transform3D.IDENTITY, pipes)

func _floor_number(value: String, at: Vector3, angle: float) -> void:
	var stencil := Label3D.new()
	stencil.text = value
	stencil.transform = Transform3D(Basis(Vector3.UP, angle), at)
	stencil.font_size = 128
	stencil.pixel_size = 0.009
	stencil.outline_size = 0
	stencil.shaded = true
	stencil.modulate = Color("9c9e87")
	_room_visuals.add_child(stencil)

func _bulkhead_light(at: Vector3, facing: Basis, tint: Color, energy: float) -> void:
	var pose := Transform3D(facing, at)
	_piece_local(pose, Vector3.ZERO, Vector3(0.87, 0.3, 0.10), 2, "bevel")
	var lamp := MeshInstance3D.new()
	lamp.name = "LampTube" + str(_room_visuals.get_child_count())
	var diffuser := CapsuleMesh.new()
	diffuser.radius = 0.087
	diffuser.height = 0.73
	diffuser.radial_segments = 10
	diffuser.rings = 4
	lamp.mesh = diffuser
	lamp.transform = pose * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0, 0.09))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = tint
	glow.emission_enabled = true
	glow.emission = tint
	glow.emission_energy_multiplier = 1.8
	lamp.material_override = glow
	_room_visuals.add_child(lamp)
	var cage: Array[Dictionary] = []
	for x: float in [-0.31, -0.16, 0.0, 0.16, 0.31]:
		for side: float in [-1, 1]:
			FITTINGS.pipe(cage, Vector3(x, 0.105 * side, 0.055), Vector3(x, 0.067 * side, 0.195), 0.011)
		FITTINGS.pipe(cage, Vector3(x, -0.067, 0.195), Vector3(x, 0.067, 0.195), 0.011)
	FITTINGS.pipe(cage, Vector3(-0.36, 0, 0.198), Vector3(0.36, 0, 0.198), 0.013)
	_append_pieces(pose, cage)
	var light := OmniLight3D.new()
	light.position = pose * Vector3(0, -0.04, 0.32)
	light.light_color = tint
	light.light_energy = energy
	light.light_size = 0.16
	light.omni_range = 8.5
	light.shadow_enabled = true
	_furnishings.add_child(light)

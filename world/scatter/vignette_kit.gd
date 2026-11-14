extends RefCounted
class_name VignetteKit
## Native compositions for human traces: each fills a PropMesh in the vignette's
## local frame (+Z faces the road for roadside types). Nothing here holds loot,
## spawns actors or carries lettering; boards and plates are blank or symbolic.
const CONCRETE := Color("9a9a90")
const CONCRETE_DARK := Color("7a7b72")
const STEEL := Color("5d6560")
const GALVANISED := Color("8a9089")
const RUST := Color("7a5038")
const RUST_DARK := Color("59392a")
const WOOD := Color("7d6b54")
const WOOD_DARK := Color("5b4e40")
const HEARTWOOD := Color("b3a78c")
const BARK := Color("6e6558")
const BRICK := Color("875646")
const PLASTER := Color("a39f90")
const YELLOW := Color("ad9440")
const WHITE := Color("b8b6a9")
const BLACK := Color("26272a")
const RUBBER := Color("2b2b29")
const HAY := Color("ab9a62")
const ORANGE := Color("a8603a")
const GRAVEL := Color("8b8573")
const FADED := [Color("94a5ad"), Color("b3a68a"), Color("a2b29c"), Color("bcb2ab")]
const CONTAINER := [Color("9a5d4a"), Color("6f858d"), Color("7b8a6d"), Color("a8965f")]

static func compose(type: String, shape: PropMesh, rng: RandomNumberGenerator) -> void:
	match type:
		"bus_shelter": _bus_shelter(shape, rng)
		"billboard": _billboard(shape, rng)
		"utility_hut": _utility_hut(shape, rng)
		"roadworks": _roadworks(shape, rng)
		"ditched_car": _crash_debris(shape, rng)
		"ruin", "homestead": _homestead(shape, rng)
		"hamlet": _hamlet(shape, rng)
		"log_landing": _log_landing(shape, rng)
		"container_dump": _container_dump(shape, rng)
		"hay_field": _hay_field(shape, rng)
		"tractor": _tractor(shape, rng)
		"pylon": _pylon(shape, rng)
		_: push_error("Unknown vignette: " + type)

static func _at(x: float, y: float, z: float, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))

static func _solid(shape: PropMesh, size: Vector3, pose: Transform3D) -> void:
	shape.solids.append({"size": size, "pose": pose})

static func _bus_shelter(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	const FLOOR := 0.15
	shape.block(Vector3(4.8, 1.1, 2.7), Vector3(0, FLOOR - 1.1, 0), CONCRETE, true)
	for x: float in [-2.1, 2.1]:
		for z: float in [-1.05, 1.0]: shape.block(Vector3(0.1, 2.5, 0.1), Vector3(x, FLOOR, z), STEEL)
	var missing := rng.randi_range(0, 4)
	var tone: Color = FADED[rng.randi_range(0, 3)]
	for panel in range(5):
		var x := -1.68 + panel * 0.84
		if panel == missing:
			# The lost sheet lies where it fell.
			shape.box(Vector3(0.8, 0.04, 1.9), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), Vector3(x + 0.3, FLOOR + 0.04, 0.2)), RUST)
			continue
		shape.block(Vector3(0.8, 2.0, 0.05), Vector3(x, FLOOR + 0.4, -1.05), tone.darkened(rng.randf_range(0.0, 0.2)))
	_solid(shape, Vector3(4.2, 2.4, 0.16), _at(0, FLOOR + 1.25, -1.05))
	shape.block(Vector3(0.05, 2.0, 1.7), Vector3(-2.1, FLOOR + 0.4, -0.15), tone.darkened(0.12), true)
	shape.block(Vector3(0.05, 0.9, 1.7), Vector3(2.1, FLOOR + 0.4, -0.15), RUST, true)
	shape.box(Vector3(5.0, 0.1, 2.7), Transform3D(Basis(Vector3.RIGHT, -0.07), Vector3(0, FLOOR + 2.58, -0.05)), RUST_DARK, true)
	shape.block(Vector3(5.0, 0.16, 0.08), Vector3(0, FLOOR + 2.42, 1.26), STEEL)
	shape.block(Vector3(2.7, 0.07, 0.42), Vector3(0, FLOOR + 0.46, -0.7), WOOD)
	shape.block(Vector3(2.7, 0.3, 0.05), Vector3(0, FLOOR + 0.82, -0.93), WOOD_DARK)
	for x: float in [-1.1, 1.1]: shape.block(Vector3(0.08, 0.46, 0.36), Vector3(x, FLOOR, -0.7), STEEL)
	if rng.randf() < 0.5: shape.prism(0.27, 0.3, 0.8, _at(1.8, FLOOR, 0.75), RUST_DARK, 8)
	else: shape.limb(Vector3(1.3, FLOOR + 0.3, 1.9), Vector3(2.1, FLOOR + 0.3, 2.2), 0.27, 0.3, RUST_DARK, 8)
	# Stop flag: a blank faded plate on a leaning pole.
	var pole := Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.14, 0.14)), shape.on_ground(-3.0, 1.3))
	shape.box(Vector3(0.07, 3.2, 0.07), pole * _at(0, 1.3, 0), STEEL, true)
	shape.box(Vector3(0.5, 0.5, 0.03), pole * _at(0, 2.6, 0.05), FADED[0])
	shape.box(Vector3(0.5, 0.1, 0.035), pole * _at(0, 2.42, 0.05), YELLOW)
	shape.rubble(Vector3(1.0, FLOOR, 0.5), 0.9, 6, CONCRETE_DARK, rng, 0.22)

static func _billboard(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	for x: float in [-3.2, 3.2]:
		shape.block(Vector3(0.34, 9.8, 0.3), shape.on_ground(x, 0, -0.9), STEEL, true)
		shape.beam(shape.on_ground(x, -2.8, -0.2), Vector3(x, 4.2, -0.15), 0.16, 0.16, STEEL)
	for y: float in [4.3, 5.5, 6.7, 7.9]: shape.block(Vector3(9.8, 0.16, 0.12), Vector3(0, y, 0.2), STEEL)
	for column in range(6):
		var x := -4.0 + column * 1.6
		var fate := rng.randf()
		var tone: Color = FADED[rng.randi_range(0, 3)].darkened(rng.randf_range(0.0, 0.18))
		if fate < 0.46: shape.block(Vector3(1.56, 3.7, 0.05), Vector3(x, 4.3, 0.3), tone)
		elif fate < 0.66: shape.block(Vector3(1.56, 1.7, 0.05), Vector3(x, 6.3, 0.3), tone)
		elif fate < 0.82:
			# Hanging from one remaining fixing.
			shape.box(Vector3(1.56, 3.3, 0.05), Transform3D(Basis(Vector3.BACK, rng.randf_range(0.25, 0.6)) * Basis(Vector3.RIGHT, 0.12), Vector3(x + 0.5, 4.5, 0.42)), tone.darkened(0.1))
	shape.block(Vector3(9.8, 0.06, 0.7), Vector3(0, 4.0, 0.75), RUST_DARK)
	shape.block(Vector3(9.8, 0.05, 0.05), Vector3(0, 4.95, 1.08), STEEL)
	for x: float in [-4.8, -2.4, 0.0, 2.4, 4.8]: shape.block(Vector3(0.05, 0.92, 0.05), Vector3(x, 4.05, 1.08), STEEL)
	for rung in range(9): shape.block(Vector3(0.42, 0.04, 0.04), Vector3(3.2, 0.5 + rung * 0.42, 0.26), STEEL)
	for sheet in range(2):
		var x := rng.randf_range(-3.5, 3.5)
		var z := rng.randf_range(1.2, 3.2)
		shape.box(Vector3(1.56, 0.05, 2.6), Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)), shape.on_ground(x, z, 0.08)), FADED[rng.randi_range(0, 3)].darkened(0.2))

static func _utility_hut(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	shape.block(Vector3(2.7, 3.5, 3.1), Vector3(0, -0.9, 0), CONCRETE, true)
	shape.block(Vector3(3.1, 0.2, 3.5), Vector3(0, 2.6, 0), CONCRETE_DARK)
	shape.block(Vector3(1.11, 2.1, 0.04), Vector3(-0.35, 0.05, 1.552), STEEL)
	shape.block(Vector3(0.95, 2.0, 0.06), Vector3(-0.35, 0.05, 1.56), RUST)
	shape.block(Vector3(0.05, 0.18, 0.05), Vector3(0.0, 1.0, 1.6), BLACK)
	shape.box(Vector3(0.3, 0.3, 0.02), Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0.78, 1.6, 1.565)), YELLOW)
	for slat in range(5): shape.box(Vector3(0.05, 0.05, 0.9), Transform3D(Basis(Vector3.BACK, 0.5), Vector3(1.37, 1.85 + slat * 0.13, 0)), STEEL)
	shape.post(0.05, 3.0, Vector3(-1.42, -0.3, -0.9), STEEL)
	shape.post(0.06, 1.7, Vector3(0.6, 2.8, -0.9), STEEL)
	for insulator in range(3): shape.prism(0.07, 0.05, 0.28, _at(-0.6 + insulator * 0.4, 2.8, 0.9), WHITE.darkened(0.2), 6)
	shape.block(Vector3(1.3, 0.5, 0.55), Vector3(-0.35, -0.4, 1.8), CONCRETE_DARK)
	# An empty cable drum left on its side.
	var drum := shape.on_ground(2.5, 0.8, 0.55)
	shape.limb(drum + Vector3(0, 0, -0.45), drum + Vector3(0, 0, -0.39), 0.55, 0.55, WOOD, 10)
	shape.limb(drum + Vector3(0, 0, 0.39), drum + Vector3(0, 0, 0.45), 0.55, 0.55, WOOD, 10)
	shape.limb(drum + Vector3(0, 0, -0.39), drum + Vector3(0, 0, 0.39), 0.3, 0.3, WOOD_DARK, 8)
	_solid(shape, Vector3(1.1, 1.1, 0.9), Transform3D(Basis.IDENTITY, drum))
	shape.rubble(shape.on_ground(-2.0, -0.6), 1.0, 7, CONCRETE_DARK, rng, 0.3)
	if rng.randf() < 0.6:
		# A length of mesh fence leaning against the wall.
		var lean := Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -0.28), shape.on_ground(-1.75, 0.2, 0.95))
		shape.box(Vector3(2.2, 0.05, 0.05), lean * _at(0, 0.9, 0), STEEL)
		shape.box(Vector3(2.2, 0.05, 0.05), lean * _at(0, -0.9, 0), STEEL)
		for bar in range(6): shape.box(Vector3(0.04, 1.8, 0.04), lean * _at(-1.08 + bar * 0.43, 0, 0), STEEL)

static func _jersey(shape: PropMesh, pose: Transform3D) -> void:
	shape.box(Vector3(3.0, 0.26, 0.6), pose * _at(0, 0.13, 0), CONCRETE)
	shape.box(Vector3(3.0, 0.3, 0.38), pose * _at(0, 0.41, 0), CONCRETE.darkened(0.05))
	shape.box(Vector3(3.0, 0.32, 0.22), pose * _at(0, 0.72, 0), CONCRETE)
	_solid(shape, Vector3(3.0, 0.88, 0.6), pose * _at(0, 0.44, 0))

static func _cone(shape: PropMesh, pose: Transform3D) -> void:
	shape.box(Vector3(0.36, 0.04, 0.36), pose * _at(0, 0.02, 0), ORANGE.darkened(0.2))
	shape.prism(0.15, 0.1, 0.22, pose * _at(0, 0.04, 0), ORANGE, 7)
	shape.prism(0.1, 0.075, 0.12, pose * _at(0, 0.26, 0), WHITE, 7)
	shape.prism(0.075, 0.03, 0.2, pose * _at(0, 0.38, 0), ORANGE, 7)

static func _drum(shape: PropMesh, pose: Transform3D, tone: Color) -> void:
	shape.prism(0.29, 0.29, 0.88, pose, tone, 9)
	shape.prism(0.3, 0.3, 0.06, pose * _at(0, 0.28, 0), tone.darkened(0.2), 9)
	shape.prism(0.3, 0.3, 0.06, pose * _at(0, 0.58, 0), tone.darkened(0.2), 9)
	_solid(shape, Vector3(0.56, 0.88, 0.56), pose * _at(0, 0.44, 0))

static func _pallet(shape: PropMesh, pose: Transform3D) -> void:
	shape.box(Vector3(1.1, 0.1, 0.9), pose * _at(0, 0.05, 0), WOOD_DARK)
	shape.box(Vector3(1.2, 0.04, 1.0), pose * _at(0, 0.12, 0), WOOD)

static func _roadworks(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	# Local X runs along the road; the barrier row is the side nearest the traffic.
	for index in range(5):
		var x := -6.8 + index * 3.4
		if rng.randf() < 0.18: continue
		var toppled := rng.randf() < 0.22
		_jersey(shape, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.14, 0.14)) * Basis(Vector3.RIGHT, 1.45 if toppled else 0.0), shape.on_ground(x, 1.6, 0.28 if toppled else 0.0)))
	for cone in range(7):
		var x := rng.randf_range(-8.0, 8.0)
		var z := rng.randf_range(2.4, 3.0)
		var fallen := rng.randf() < 0.35
		_cone(shape, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, 1.5 if fallen else 0.0), shape.on_ground(x, z, 0.14 if fallen else 0.0)))
	for drum in range(3):
		var fallen := rng.randf() < 0.3
		var point := shape.on_ground(-1.5 + drum * 1.1 + rng.randf_range(-0.2, 0.2), -0.6 + rng.randf_range(-0.4, 0.4), 0.29 if fallen else 0.0)
		_drum(shape, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, PI * 0.5 if fallen else 0.0), point), RUST if drum != 1 else FADED[0].darkened(0.2))
	var heap := shape.on_ground(-5.0, -1.0, -0.08)
	shape.prism(2.0, 0.3, 1.0, Transform3D(Basis.IDENTITY, heap), GRAVEL, 9)
	_solid(shape, Vector3(2.3, 0.7, 2.3), Transform3D(Basis.IDENTITY, heap + Vector3.UP * 0.35))
	# Three drainage pipes that were never laid.
	var stack := shape.on_ground(3.6, -1.2)
	for pipe in range(3):
		var offset := Vector3(0, 0.5 + (0.86 if pipe == 2 else 0.0), -0.52 + pipe * 1.04 if pipe < 2 else 0.0)
		shape.limb(stack + offset + Vector3(-1.2, 0, 0), stack + offset + Vector3(1.2, 0, 0), 0.5, 0.5, CONCRETE, 10, CONCRETE_DARK)
		shape.limb(stack + offset + Vector3(-1.21, 0, 0), stack + offset + Vector3(1.21, 0, 0), 0.38, 0.38, BLACK, 10)
	_solid(shape, Vector3(2.4, 1.9, 2.1), Transform3D(Basis.IDENTITY, stack + Vector3.UP * 0.95))
	for pallet in range(3): _pallet(shape, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), shape.on_ground(7.0, -1.2, pallet * 0.15)))
	# Folding warning frame: a blank diamond, kicked over as often as not.
	var frame := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, -1.35 if rng.randf() < 0.5 else 0.0), shape.on_ground(-8.2, 2.6, 0.05))
	shape.box(Vector3(0.9, 1.15, 0.04), frame * Transform3D(Basis(Vector3.RIGHT, 0.28), Vector3(0, 0.55, 0.12)), YELLOW)
	shape.box(Vector3(0.9, 1.15, 0.04), frame * Transform3D(Basis(Vector3.RIGHT, -0.28), Vector3(0, 0.55, -0.12)), STEEL)
	shape.box(Vector3(0.94, 0.12, 0.045), frame * Transform3D(Basis(Vector3.RIGHT, 0.28), Vector3(0, 0.25, 0.2)), BLACK)

## Loose parts around a ditched car; the car itself is the existing wreck scene.
static func _crash_debris(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	shape.box(Vector3(1.7, 0.14, 0.2), Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), shape.on_ground(rng.randf_range(-2.5, 2.5), 2.6, 0.08)), STEEL)
	shape.limb(shape.on_ground(-2.4, 1.2, 0.1), shape.on_ground(-2.4, 1.2, 0.3), 0.36, 0.36, RUBBER, 9, RUST_DARK)
	for case in range(2):
		shape.box(Vector3(0.7, 0.24, 0.45), Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), shape.on_ground(rng.randf_range(-3.0, 3.0), rng.randf_range(-2.8, -1.8), 0.12)), FADED[rng.randi_range(0, 3)].darkened(0.25))
	shape.rubble(shape.on_ground(0.5, 2.2), 1.6, 8, BLACK.lightened(0.15), rng, 0.2)

static func _ruin(shape: PropMesh, rng: RandomNumberGenerator, centre: Vector2, turn: float) -> void:
	var width := rng.randf_range(7.0, 10.0)
	var depth := rng.randf_range(5.5, 7.5)
	var tone: Color = BRICK if rng.randf() < 0.5 else PLASTER
	var frame := Transform2D(turn, centre)
	var corners: Array[Vector2] = [Vector2(-width, -depth) * 0.5, Vector2(width, -depth) * 0.5, Vector2(width, depth) * 0.5, Vector2(-width, depth) * 0.5]
	# One corner still stands; the walls fall away from it.
	var survivor := corners[rng.randi_range(0, 3)]
	var span := Vector2(width, depth).length()
	for wall in range(4):
		var a := corners[wall]
		var b := corners[(wall + 1) % 4]
		var segments := maxi(3, floori(a.distance_to(b) / 1.15))
		var piece := a.distance_to(b) / segments
		var door := rng.randi_range(1, segments - 2) if wall == 2 else -1
		var direction := (frame.basis_xform(b - a)).normalized()
		var yaw := atan2(-direction.y, direction.x)
		for index in range(segments):
			var local := a.lerp(b, (index + 0.5) / segments)
			var height := lerpf(3.7, 0.9, clampf(local.distance_to(survivor) / span * 1.15 + rng.randf_range(-0.25, 0.25), 0.0, 1.0))
			var gone := rng.randf() < 0.1
			var window := rng.randf() < 0.3
			if index == door or gone: continue
			if window and height > 2.4: height = 1.0
			var point := frame * local
			var base := shape.on_ground(point.x, point.y, -0.6)
			shape.box(Vector3(piece + 0.02, height + 0.6, 0.3), Transform3D(Basis(Vector3.UP, yaw), base + Vector3.UP * (height + 0.6) * 0.5), tone.darkened(rng.randf_range(0.0, 0.14)), height > 0.6)
			if height > 0.8 and rng.randf() < 0.6:
				shape.jagged(Vector3(piece * 0.6, 0.36, 0.3), Transform3D(Basis(Vector3.UP, yaw), base + Vector3.UP * (height + 0.76)), tone.darkened(0.16), rng, 0.22)
	var hearth := frame * Vector2(rng.randf_range(-width * 0.25, width * 0.25), -depth * 0.5 + 0.55)
	shape.box(Vector3(1.05, 6.6, 0.9), Transform3D(Basis(Vector3.UP, -turn), shape.on_ground(hearth.x, hearth.y, 2.7)), BRICK.darkened(0.12), true)
	shape.jagged(Vector3(0.75, 0.7, 0.65), Transform3D(Basis(Vector3.UP, -turn), shape.on_ground(hearth.x, hearth.y, 6.3)), BRICK.darkened(0.2), rng, 0.25)
	for slab in range(3):
		var point := frame * Vector2(rng.randf_range(-width, width) * 0.3, rng.randf_range(-depth, depth) * 0.3)
		shape.box(Vector3(rng.randf_range(1.5, 2.6), 0.12, rng.randf_range(1.5, 2.4)), Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08)), shape.on_ground(point.x, point.y, 0.04)), CONCRETE_DARK)
	for rafter in range(3):
		var high := frame * (survivor * 0.8 + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		var low := frame * Vector2(rng.randf_range(-width, width) * 0.35, rng.randf_range(-depth, depth) * 0.35)
		shape.beam(shape.on_ground(high.x, high.y, rng.randf_range(2.0, 3.3)), shape.on_ground(low.x, low.y, 0.12), 0.16, 0.16, WOOD_DARK)
	for pile in range(3):
		var point := frame * Vector2(rng.randf_range(-width, width) * 0.55, rng.randf_range(-depth, depth) * 0.55)
		shape.rubble(shape.on_ground(point.x, point.y), 1.4, 12, tone, rng, 0.5)
	var stove := frame * Vector2(width * 0.2, depth * 0.1)
	shape.box(Vector3(0.65, 0.8, 0.5), Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)), shape.on_ground(stove.x, stove.y, 0.36)), RUST_DARK, true)

static func _homestead(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	_ruin(shape, rng, Vector2.ZERO, rng.randf_range(-0.4, 0.4))
	_fence(shape, rng, Vector3(-5.5, 0, 6.0), rng.randf_range(1.3, 1.8), rng.randf_range(8.0, 12.0))

static func _hamlet(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	for house: Vector2 in [Vector2(-8.5, -4.0), Vector2(7.5, -5.5), Vector2(1.5, 8.5)]:
		_ruin(shape, rng, house, rng.randf_range(0, TAU))
	# The shared well, its winding gear long gone.
	var well := shape.on_ground(0, 0, -0.15)
	shape.prism(1.0, 1.0, 0.95, Transform3D(Basis.IDENTITY, well), CONCRETE_DARK, 10)
	shape.prism(0.72, 0.72, 0.97, Transform3D(Basis.IDENTITY, well), BLACK, 10, Color("202a27"))
	for x: float in [-0.95, 0.95]: shape.block(Vector3(0.12, 2.0, 0.12), well + Vector3(x, 0.3, 0), WOOD_DARK)
	shape.beam(well + Vector3(-1.05, 2.25, 0), well + Vector3(1.05, 2.1, 0), 0.12, 0.12, WOOD_DARK)
	_solid(shape, Vector3(2.0, 1.0, 2.0), Transform3D(Basis.IDENTITY, well + Vector3.UP * 0.5))

static func _log_stack(shape: PropMesh, rng: RandomNumberGenerator, centre: Vector2, yaw: float) -> void:
	var radius := rng.randf_range(0.24, 0.3)
	var length := rng.randf_range(4.4, 5.6)
	var pose := Transform3D(Basis(Vector3.UP, yaw), shape.on_ground(centre.x, centre.y))
	var rows := rng.randi_range(2, 3)
	for row in range(rows):
		var count := rows + 1 - row
		for index in range(count):
			var z := (index - (count - 1) * 0.5) * radius * 2.02
			var y := radius + row * radius * 1.74
			var slip := rng.randf_range(-0.3, 0.3)
			shape.limb(pose * Vector3(-length * 0.5 + slip, y, z), pose * Vector3(length * 0.5 + slip, y, z), radius, radius * 0.92, BARK.darkened(rng.randf_range(0.0, 0.12)), 7, HEARTWOOD)
	var half := (rows + 1) * radius + 0.12
	for x: float in [-length * 0.3, length * 0.3]:
		for z: float in [-half, half]: shape.box(Vector3(0.1, 1.5, 0.1), pose * _at(x, 0.55, z), WOOD_DARK)
	_solid(shape, Vector3(length, rows * radius * 1.74 + radius, half * 2.0), pose * _at(0, (rows * radius * 1.74 + radius) * 0.5, 0))

static func _log_landing(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	shape.top_tint = Color(0.42, 0.47, 0.33, 0.25)
	for stack in range(rng.randi_range(2, 3)):
		_log_stack(shape, rng, Vector2(-5.5 + stack * 4.2, rng.randf_range(-3.5, -1.0)), rng.randf_range(-0.25, 0.25))
	for stump in range(6):
		var angle := rng.randf_range(0, TAU)
		var reach := rng.randf_range(6.0, 10.0)
		shape.prism(0.42, 0.32, 0.5, Transform3D(Basis.IDENTITY, shape.on_ground(cos(angle) * reach, sin(angle) * reach, -0.06)), BARK, 8, HEARTWOOD)
	# Flatbed trailer left where the last load was never collected.
	var bed := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.BACK, 0.08), shape.on_ground(3.5, 4.5, 0.95))
	shape.box(Vector3(2.2, 0.16, 5.2), bed, RUST)
	for z: float in [-1.5, 1.6]:
		shape.box(Vector3(2.5, 0.1, 0.1), bed * _at(0, -0.3, z), STEEL)
		for x: float in [-1.2, 1.2]:
			if x > 0.0 and z > 0.0: continue # One wheel was taken; the axle sits on a block.
			shape.limb(bed * Vector3(x - 0.14, -0.42, z), bed * Vector3(x + 0.14, -0.42, z), 0.46, 0.46, RUBBER, 10, RUST_DARK)
	shape.box(Vector3(0.4, 0.5, 0.4), bed * _at(1.15, -0.7, 1.6), WOOD_DARK)
	shape.beam(bed * Vector3(0, -0.1, -2.6), bed * Vector3(0, -0.85, -4.3), 0.12, 0.12, RUST_DARK)
	for x: float in [-1.05, 1.05]:
		for z: float in [-2.2, 0.0, 2.2]: shape.box(Vector3(0.08, 0.9, 0.08), bed * _at(x, 0.5, z), RUST_DARK)
	shape.limb(bed * Vector3(-0.4, 0.36, -2.3), bed * Vector3(-0.3, 0.36, 2.2), 0.27, 0.25, BARK, 7, HEARTWOOD)
	_solid(shape, Vector3(2.2, 1.3, 5.2), bed * _at(0, -0.3, 0))

static func _container(shape: PropMesh, pose: Transform3D, tone: Color, rng: RandomNumberGenerator) -> void:
	shape.box(Vector3(2.44, 2.59, 6.06), pose * _at(0, 1.295, 0), tone.darkened(0.12), true)
	for corner_x: float in [-1.22, 1.22]:
		for corner_z: float in [-3.03, 3.03]: shape.box(Vector3(0.16, 2.64, 0.16), pose * _at(corner_x, 1.3, corner_z), tone.darkened(0.3))
	for side: float in [-1.0, 1.0]:
		# Corrugation: proud ribs lighter than the recessed wall behind them.
		for rib in range(18): shape.box(Vector3(0.07, 2.3, 0.17), pose * _at(side * 1.24, 1.295, -2.8 + rib * 0.33), tone.lightened(0.16))
		for patch in range(4):
			shape.box(Vector3(0.03, rng.randf_range(0.3, 1.1), rng.randf_range(0.4, 1.4)), pose * _at(side * 1.275, rng.randf_range(0.4, 2.2), rng.randf_range(-2.5, 2.5)), RUST.darkened(rng.randf_range(0.0, 0.2)))
	for leaf: float in [-0.59, 0.59]: shape.box(Vector3(1.15, 2.35, 0.05), pose * _at(leaf, 1.295, 3.045), tone.darkened(0.06))
	for rod: float in [-0.85, -0.3, 0.3, 0.85]: shape.box(Vector3(0.04, 2.35, 0.04), pose * _at(rod, 1.295, 3.09), STEEL)
	shape.box(Vector3(2.5, 0.12, 6.1), pose * _at(0, 2.6, 0), tone.darkened(0.22))

static func _container_dump(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	var first := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), shape.on_ground(-2.0, -1.0, -0.08))
	_container(shape, first, CONTAINER[rng.randi_range(0, 3)], rng)
	if rng.randf() < 0.6:
		# A second box dropped askew, one end sunk into soft ground.
		var second := Transform3D(Basis(Vector3.UP, rng.randf_range(0.9, 1.5)) * Basis(Vector3.RIGHT, rng.randf_range(0.04, 0.1)), shape.on_ground(3.4, 2.4, -0.25))
		_container(shape, second, CONTAINER[rng.randi_range(0, 3)], rng)
	for pallet in range(4): _pallet(shape, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), shape.on_ground(-5.6, 3.6, pallet * 0.15)))
	for drum in range(4):
		var fallen := rng.randf() < 0.35
		_drum(shape, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, PI * 0.5 if fallen else 0.0), shape.on_ground(0.6 + drum * 0.75, -4.6 + rng.randf_range(-0.5, 0.5), 0.29 if fallen else 0.0)), RUST if drum % 2 == 0 else FADED[1].darkened(0.2))
	var tyres := shape.on_ground(5.5, -3.4)
	for tyre in range(rng.randi_range(3, 5)):
		var slip := Vector3(rng.randf_range(-0.06, 0.06), tyre * 0.22, rng.randf_range(-0.06, 0.06))
		shape.prism(0.4, 0.4, 0.2, Transform3D(Basis.IDENTITY, tyres + slip), RUBBER, 10)
		shape.prism(0.22, 0.22, 0.205, Transform3D(Basis.IDENTITY, tyres + slip), BLACK.darkened(0.3), 8)
	_solid(shape, Vector3(0.8, 1.0, 0.8), Transform3D(Basis.IDENTITY, tyres + Vector3.UP * 0.5))
	shape.rubble(shape.on_ground(1.5, 5.0), 1.8, 10, RUST_DARK, rng, 0.4)

static func _hay_field(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	# Years in the weather have greyed every upward face.
	shape.top_tint = Color(0.55, 0.53, 0.46, 0.4)
	for bale in range(rng.randi_range(6, 10)):
		var angle := rng.randf_range(0, TAU)
		var reach := 13.0 * sqrt(rng.randf())
		var yaw := rng.randf_range(0, TAU)
		var slumped := rng.randf() < 0.25
		var radius := 0.75
		var centre := shape.on_ground(cos(angle) * reach, sin(angle) * reach, radius * (0.6 if slumped else 0.94))
		var axis := Vector3(cos(yaw), 0, sin(yaw)) * 0.65
		shape.limb(centre - axis, centre + axis, radius, radius * (1.0 if not slumped else 0.9), HAY.darkened(rng.randf_range(0.0, 0.14)), 12, HAY.darkened(0.2))
		_solid(shape, Vector3(1.3, 1.4, 1.3), Transform3D(Basis(Vector3.UP, -yaw), centre))
	_fence(shape, rng, Vector3(-14.0, 0, -13.0), rng.randf_range(-0.2, 0.2), 26.0)

## Post-and-wire run from `start`, heading `yaw`. Every post is a knock-down
## prop carrying the span to the next one, so a breach takes its wires with it.
static func _fence(shape: PropMesh, rng: RandomNumberGenerator, start: Vector3, yaw: float, length: float) -> void:
	var direction := Vector3(sin(yaw), 0, cos(yaw))
	var planks := rng.randf() < 0.4
	var bases: Array[Vector3] = []
	var standing: Array[bool] = []
	for index in range(floori(length / ScatterMeshes.FENCE_SPAN) + 1):
		var flat := start + direction * index * ScatterMeshes.FENCE_SPAN
		bases.append(shape.on_ground(flat.x, flat.z))
		# A rotted post leaves a gap in the run.
		standing.append(rng.randf() > 0.16)
	for index in range(bases.size()):
		var slack := rng.randf() < 0.35
		var lean := rng.randf_range(-0.12, 0.12)
		if not standing[index]: continue
		var linked := index + 1 < bases.size() and standing[index + 1]
		var span := (bases[index + 1] - bases[index]) if linked else direction * ScatterMeshes.FENCE_SPAN
		var forward := span.normalized()
		var right := Vector3.UP.cross(forward).normalized()
		var basis := Basis(right, forward.cross(right), forward).rotated(forward, lean).scaled_local(Vector3(1, 1, span.length() / ScatterMeshes.FENCE_SPAN))
		var mesh := &"fence_3"
		if linked: mesh = &"fence_2" if planks else (&"fence_1" if slack else &"fence_0")
		shape.props.append({"mesh": mesh, "pose": Transform3D(basis, bases[index])})

## Stand-in when the generated tractor model is not installed.
static func _tractor(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	var body := Transform3D(Basis(Vector3.UP, 0.0) * Basis(Vector3.BACK, rng.randf_range(-0.08, 0.08)), shape.on_ground(0, 0, 0.0))
	shape.box(Vector3(0.9, 0.7, 2.0), body * _at(0, 1.05, 0.55), RUST, true)
	shape.box(Vector3(1.0, 0.5, 1.2), body * _at(0, 0.95, -0.8), RUST_DARK, true)
	shape.box(Vector3(0.5, 0.45, 0.5), body * _at(0, 1.5, -0.9), BLACK)
	shape.post(0.05, 1.0, body * Vector3(0.3, 1.4, 1.0), STEEL)
	for x: float in [-0.75, 0.75]:
		shape.limb(body * Vector3(x - 0.2, 0.75, -0.9), body * Vector3(x + 0.2, 0.75, -0.9), 0.75, 0.75, RUBBER, 12, RUST_DARK)
		shape.limb(body * Vector3(x * 0.85 - 0.12, 0.42, 1.2), body * Vector3(x * 0.85 + 0.12, 0.42, 1.2), 0.42, 0.42, RUBBER, 10, RUST_DARK)

## Lattice transmission tower. `shape.ground` resolves each footing separately.
static func _pylon(shape: PropMesh, rng: RandomNumberGenerator) -> void:
	const LEVELS := [0.0, 5.0, 10.0, 15.0, 20.0]
	var legs: Array = []
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var column: Array[Vector3] = []
		for level: float in LEVELS:
			var spread := lerpf(3.0, 0.85, level / 20.0)
			var point := Vector3(corner.x * spread, level, corner.y * spread)
			if level == 0.0: point.y = shape.height(point.x, point.z)
			column.append(point)
		legs.append(column)
		shape.block(Vector3(0.9, 1.4, 0.9), column[0] + Vector3.DOWN * 0.9, CONCRETE, true)
		for level in range(LEVELS.size() - 1): shape.beam(column[level], column[level + 1], 0.22, 0.22, GALVANISED)
	for face in range(4):
		var a: Array[Vector3] = legs[face]
		var b: Array[Vector3] = legs[(face + 1) % 4]
		for level in range(LEVELS.size() - 1):
			shape.beam(a[level + 1], b[level + 1], 0.12, 0.12, GALVANISED.darkened(0.08))
			# A few braces have rusted through and dropped out.
			if rng.randf() > 0.08: shape.beam(a[level], b[level + 1], 0.09, 0.09, GALVANISED.darkened(0.12))
			if rng.randf() > 0.08: shape.beam(b[level], a[level + 1], 0.09, 0.09, GALVANISED.darkened(0.12))
	var apex := Vector3(0, 26.5, 0)
	for column: Array in legs: shape.beam(column[4], apex, 0.16, 0.16, GALVANISED)
	for arm: Vector2 in ARMS:
		shape.beam(Vector3(-arm.x, arm.y, 0), Vector3(arm.x, arm.y, 0), 0.22, 0.22, GALVANISED)
		for side: float in [-1.0, 1.0]:
			shape.beam(Vector3(side * arm.x, arm.y, 0), Vector3(side * 0.5, arm.y + 1.6, 0), 0.1, 0.1, GALVANISED.darkened(0.1))
			shape.prism(0.1, 0.07, 1.1, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(side * arm.x, arm.y, 0)), Color("5a4a40"), 6)

## Cross-arm half-widths and heights; conductors hang 1.1 m below each tip.
const ARMS: Array[Vector2] = [Vector2(5.4, 17.5), Vector2(4.5, 21.0), Vector2(3.4, 24.3)]

## Rotten jetty and a swamped boat on a pond shore. Local +Z points out over the water.
static func jetty(shape: PropMesh, rng: RandomNumberGenerator, level: float) -> void:
	var deck := level + 0.4
	for board in range(12):
		if rng.randf() < 0.2: continue
		shape.box(Vector3(1.5, 0.05, 0.5), _at(rng.randf_range(-0.04, 0.04), deck + rng.randf_range(-0.02, 0.02), -1.5 + board * 0.56, rng.randf_range(-0.05, 0.05)), WOOD.darkened(rng.randf_range(0.0, 0.22)))
	for bent in range(4):
		var z := -1.2 + bent * 1.9
		for x: float in [-0.68, 0.68]: shape.box(Vector3(0.13, 2.6, 0.13), Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))), Vector3(x, deck - 1.1, z)), WOOD_DARK)
		shape.box(Vector3(1.6, 0.1, 0.1), _at(0, deck - 0.08, z), WOOD_DARK)
	_solid(shape, Vector3(1.5, 0.3, 6.8), _at(0, deck - 0.12, 1.6))
	# Half-sunk rowboat tied alongside.
	var hull := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.BACK, rng.randf_range(0.15, 0.3)), Vector3(1.9, level - 0.05, 2.6))
	shape.jagged(Vector3(1.15, 0.42, 3.0), hull, WOOD_DARK, rng, 0.08)
	shape.box(Vector3(0.95, 0.05, 2.7), hull * _at(0, 0.215, 0), BLACK.lightened(0.08))
	for thwart: float in [-0.7, 0.5]: shape.box(Vector3(1.1, 0.05, 0.22), hull * _at(0, 0.24, thwart), WOOD)

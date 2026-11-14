extends RefCounted
class_name FeatureBuilder
## Builds what WorldFeatures planned for one band: pond water, human-trace
## vignettes, fences and the transmission line. The band that contains a
## feature's anchor owns all of its nodes.
const WATER = preload("res://world/terrain/river_water.gdshader")
const WRECK = preload("res://world/starting_shelter/reused_wreck.tscn")
const TRACTOR_PATH := "res://assets/models/field_tractor/field_tractor.tscn"
const CONDUCTOR := Color("3a3c3a")
## Knock-down props gathered from every vignette of the band being built.
static var _loose: Array[Dictionary] = []

static func build(chunk: ChunkGenerator) -> void:
	var field := chunk.field
	var features := field.features
	var count := 0
	_loose = []
	for plan: Dictionary in features.cells_for_band(chunk.band):
		for pond: Dictionary in plan.ponds:
			if features.owns(chunk.band, pond.z):
				_pond(chunk, pond)
				count += 1
		for track: Dictionary in plan.tracks:
			var centre: Vector3 = track.centre
			if not features.owns(chunk.band, centre.z): continue
			_vignette(chunk, track.content, centre.x, centre.z, track.yaw, track.seed)
			count += 1
		for pad: Dictionary in plan.pads:
			if not features.owns(chunk.band, pad.z): continue
			if pad.type == "pylon": _pylon(chunk, pad)
			elif pad.type != "reserve": _vignette(chunk, pad.type, pad.x, pad.z, pad.yaw, pad.seed)
			count += 1
		for fence: Dictionary in plan.fences:
			if not features.owns(chunk.band, fence.z): continue
			var pose := Transform3D(Basis.IDENTITY, Vector3(fence.x, field.height_at(fence.x, fence.z), fence.z))
			var shape := _shape(field, pose)
			var rng := RandomNumberGenerator.new()
			rng.seed = fence.seed
			VignetteKit._fence(shape, rng, Vector3.ZERO, fence.yaw, fence.length)
			_place(chunk, shape, "Fence", pose)
			count += 1
	BreakableProps.build(chunk, "FeatureProps", _loose)
	_loose = []
	if count > 0: print("FEATURES band=%d built=%d" % [chunk.band, count])

## A PropMesh whose ground lookup reads the real terrain under the given pose.
static func _shape(field: WorldField, pose: Transform3D) -> PropMesh:
	var shape := PropMesh.new()
	shape.ground = func(x: float, z: float) -> float:
		var point := pose * Vector3(x, 0, z)
		return field.height_at(point.x, point.z) - pose.origin.y
	return shape

static func _place(chunk: ChunkGenerator, shape: PropMesh, title: String, pose: Transform3D) -> Node3D:
	for prop: Dictionary in shape.props: _loose.append({"mesh": prop.mesh, "pose": pose * prop.pose})
	if shape.is_empty() and shape.solids.is_empty(): return null
	var node := shape.instance(chunk, "%s_%d_%d" % [title, roundi(pose.origin.x), roundi(pose.origin.z)], pose)
	node.set_meta("world_feature", title)
	return node

static func _vignette(chunk: ChunkGenerator, type: String, x: float, z: float, yaw: float, seed_value: int) -> void:
	var field := chunk.field
	var pose := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, field.height_at(x, z), z))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if type == "tractor" and ResourceLoader.exists(TRACTOR_PATH):
		_model(chunk, load(TRACTOR_PATH), pose, field, rng.randf_range(-0.1, 0.1), "FieldTractor")
		return
	var shape := _shape(field, pose)
	VignetteKit.compose(type, shape, rng)
	_place(chunk, shape, type.to_pascal_case(), pose)
	if type == "ditched_car":
		# Nose down the bank, rolled onto one side: it left the road at speed.
		var car := WRECK.instantiate() as Node3D
		car.name = "DitchedCar_%d_%d" % [roundi(x), roundi(z)]
		chunk.add_child(car)
		var normal := field.normal_at(x, z)
		var forward := Basis(Vector3.UP, yaw + PI) * Vector3.FORWARD
		var right := forward.cross(normal).normalized()
		var basis := Basis(right, normal, right.cross(normal)).rotated(right, rng.randf_range(0.06, 0.2)).rotated(forward, rng.randf_range(-0.3, 0.3))
		car.global_transform = Transform3D(basis, pose.origin + Vector3.UP * 0.05)

## Authored or generated model resting on the terrain, tilted to the local slope.
static func _model(chunk: ChunkGenerator, scene: PackedScene, pose: Transform3D, field: WorldField, roll: float, title: String) -> void:
	var node := scene.instantiate() as Node3D
	node.name = "%s_%d_%d" % [title, roundi(pose.origin.x), roundi(pose.origin.z)]
	var normal := field.normal_at(pose.origin.x, pose.origin.z)
	var right := (pose.basis.x - normal * pose.basis.x.dot(normal)).normalized()
	node.transform = Transform3D(Basis(right, normal, right.cross(normal)).rotated(normal, roll), pose.origin)
	node.set_meta("world_feature", title)
	chunk.add_child(node)

static func _pond(chunk: ChunkGenerator, pond: Dictionary) -> void:
	var outline := WorldFeatures.pond_outline(pond, 1.2)
	var centre := Vector3(pond.x, pond.level, pond.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(outline.size()):
		# The water shader shallows towards UV.y 0 and 1; the fan centre is mid-depth.
		var ring := [outline[(index + 1) % outline.size()], outline[index]]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(centre.x * 0.04, 0.5))
		st.add_vertex(centre)
		for point: Vector3 in ring:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(point.x * 0.04, 0.0))
			st.add_vertex(point)
	var water := MeshInstance3D.new()
	water.name = "PondWater_%d_%d" % [roundi(pond.x), roundi(pond.z)]
	water.mesh = st.commit()
	var material := ShaderMaterial.new()
	material.shader = WATER
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(water)
	if not pond.jetty: return
	var angle: float = pond.jetty_angle
	var shore := WorldFeatures.pond_radius(pond, angle)
	var out := Vector3(cos(angle), 0, sin(angle))
	# Starts on the bank and reaches over the water, facing the pond centre.
	var pose := Transform3D(Basis(Vector3.UP, atan2(-out.x, -out.z)), Vector3(float(pond.x) + out.x * (shore + 1.5), 0.0, float(pond.z) + out.z * (shore + 1.5)))
	var shape := PropMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = pond.seed
	VignetteKit.jetty(shape, rng, float(pond.level))
	_place(chunk, shape, "Jetty", pose)

static func _pylon(chunk: ChunkGenerator, pad: Dictionary) -> void:
	var field := chunk.field
	var features := field.features
	var index: int = pad.index
	var next := features.tower(index + 1)
	var pose := _tower_pose(pad, next, features.tower(index - 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = pad.seed
	var shape := _shape(field, pose)
	VignetteKit.compose("pylon", shape, rng)
	_place(chunk, shape, "Pylon", pose)
	if next.is_empty(): return
	var other := _tower_pose(next, features.tower(index + 2), pad)
	var lines := PropMesh.new()
	for arm: Vector2 in VignetteKit.ARMS:
		for side: float in [-1.0, 1.0]:
			var from := pose * Vector3(side * arm.x, arm.y - 1.1, 0)
			# Some spans came down long ago; the stub still hangs from the insulator.
			if rng.randf() < 0.14:
				lines.wire(from, pose * Vector3(side * arm.x + rng.randf_range(-1.5, 1.5), arm.y - rng.randf_range(7.0, 13.0), -rng.randf_range(2.0, 6.0)), 0.8, 0.14, CONDUCTOR, 5)
				continue
			lines.wire(from, other * Vector3(side * arm.x, arm.y - 1.1, 0), rng.randf_range(4.5, 7.5), 0.14, CONDUCTOR, 14)
	var node := lines.instance(chunk, "PylonLines_%d" % index, Transform3D.IDENTITY) as MeshInstance3D
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Cross-arms sit square to the line. Local -Z looks at the next tower, so both
## ends of a span agree on which arm tip is which.
static func _tower_pose(pad: Dictionary, next: Dictionary, previous: Dictionary) -> Transform3D:
	var origin := Vector3(pad.x, pad.y, pad.z)
	var span := Vector3.ZERO
	if not next.is_empty(): span = Vector3(float(next.x) - origin.x, 0, float(next.z) - origin.z)
	elif not previous.is_empty(): span = Vector3(origin.x - float(previous.x), 0, origin.z - float(previous.z))
	if span.length() < 1.0: return Transform3D(Basis(Vector3.UP, pad.yaw), origin)
	span = span.normalized()
	return Transform3D(Basis(Vector3.UP, atan2(-span.x, -span.z)), origin)

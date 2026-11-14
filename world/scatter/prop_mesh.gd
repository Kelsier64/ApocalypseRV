extends RefCounted
class_name PropMesh
## Vertex-coloured box and prism accumulator for native world structures.
## Solid parts are recorded as boxes so visuals and collision share one layout.
static var _material: StandardMaterial3D
var st := SurfaceTool.new()
var solids: Array[Dictionary] = []
## Separate knock-down props placed with this structure: {"mesh", "pose"} in local space.
var props: Array[Dictionary] = []
## Optional local (x, z) -> y lookup, so separate parts follow uneven ground.
var ground := Callable()
## Tint blended onto upward faces (moss, dust); alpha is its strength.
var top_tint := Color(0, 0, 0, 0)
var _vertices := 0

func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		# A light grain only: the vertex colours carry the actual tones.
		var noise := FastNoiseLite.new()
		noise.seed = 2071
		noise.frequency = 0.045
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(0.72, 0.72, 0.7), Color(0.9, 0.9, 0.88), Color(1, 1, 1)])
		ramp.offsets = PackedFloat32Array([0.15, 0.55, 0.9])
		var grain := NoiseTexture2D.new()
		grain.width = 256
		grain.height = 256
		grain.seamless = true
		grain.generate_mipmaps = true
		grain.noise = noise
		grain.color_ramp = ramp
		_material.albedo_texture = grain
		_material.uv1_triplanar = true
		_material.uv1_world_triplanar = true
		_material.uv1_scale = Vector3.ONE * 0.45
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_material.roughness = 0.95
		_material.metallic_specular = 0.1
	return _material

func height(x: float, z: float) -> float:
	return float(ground.call(x, z)) if ground.is_valid() else 0.0

## A point resting on the ground at local (x, z), raised by `lift`.
func on_ground(x: float, z: float, lift := 0.0) -> Vector3:
	return Vector3(x, height(x, z) + lift, z)

func _shade(color: Color, normal: Vector3) -> Color:
	var shade := color.lightened(0.06) if normal.y > 0.6 else (color.darkened(0.16) if normal.y < -0.6 else color.darkened(0.07 * absf(normal.x)))
	if top_tint.a > 0.0 and normal.y > 0.35:
		shade = shade.lerp(Color(top_tint.r, top_tint.g, top_tint.b), top_tint.a * smoothstep(0.35, 0.9, normal.y))
	return shade

func tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	# Godot front faces wind clockwise; derive the order from the wanted normal.
	if (c - a).cross(b - a).dot(normal) < 0.0:
		var swap := b
		b = c
		c = swap
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	_vertices += 3

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	tri(a, b, c, normal, color)
	tri(a, c, d, normal, color)

func box(size: Vector3, pose: Transform3D, color: Color, solid := false) -> void:
	var half := size * 0.5
	for axis in range(3):
		for direction: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = direction
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var centre := n * half
			var normal := (pose.basis * n).normalized()
			quad(pose * (centre - u * half - v * half), pose * (centre + u * half - v * half), pose * (centre + u * half + v * half), pose * (centre - u * half + v * half), normal, _shade(color, normal))
	if solid: solids.append({"size": size, "pose": pose})

## Flat-shaded face oriented away from `inside`; for hand-built irregular solids.
func facet(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.0000001: return
	normal = normal.normalized()
	if normal.dot((a + b + c) / 3.0 - inside) < 0.0: normal = -normal
	tri(a, b, c, normal, _shade(color, normal))

## Irregular box from eight corners indexed by x + 2y + 4z sign bits.
func hull(corners: Array[Vector3], color: Color) -> void:
	var inside := Vector3.ZERO
	for corner in corners: inside += corner / 8.0
	for face: Array in [[0, 2, 6, 4], [1, 3, 7, 5], [0, 1, 5, 4], [2, 3, 7, 6], [0, 1, 3, 2], [4, 5, 7, 6]]:
		facet(corners[face[0]], corners[face[1]], corners[face[2]], inside, color)
		facet(corners[face[0]], corners[face[2]], corners[face[3]], inside, color)

## Box whose corners are pushed around by up to `jitter` of its size.
func jagged(size: Vector3, pose: Transform3D, color: Color, rng: RandomNumberGenerator, jitter := 0.12, solid := false) -> void:
	var corners: Array[Vector3] = []
	for index in range(8):
		var corner := Vector3(1.0 if index & 1 else -1.0, 1.0 if index & 2 else -1.0, 1.0 if index & 4 else -1.0) * size * 0.5
		corner += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * size * jitter
		corners.append(pose * corner)
	hull(corners, color)
	if solid: solids.append({"size": size, "pose": pose})

## Tapered round section between two points (branches, logs, pipes).
func limb(a: Vector3, b: Vector3, radius_a: float, radius_b: float, color: Color, sides := 6, cap := Color(0, 0, 0, 0)) -> void:
	var axis := b - a
	if axis.length() < 0.001: return
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	prism(radius_a, radius_b, axis.length(), Transform3D(Basis(x, y, x.cross(y)), a), color, sides, cap)

## Upright box given by its base centre: the common case for posts and slabs.
func block(size: Vector3, base: Vector3, color: Color, solid := false, yaw := 0.0) -> void:
	box(size, Transform3D(Basis(Vector3.UP, yaw), base + Vector3.UP * size.y * 0.5), color, solid)

func beam(a: Vector3, b: Vector3, width: float, depth: float, color: Color, solid := false) -> void:
	var axis := b - a
	if axis.length() < 0.001: return
	var forward := axis.normalized()
	var up := Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT
	box(Vector3(width, depth, axis.length()), Transform3D(Basis.looking_at(forward, up), (a + b) * 0.5), color, solid)

## Tapered n-gon along the pose's local +Y, starting at its origin.
func prism(bottom: float, top: float, length: float, pose: Transform3D, color: Color, sides := 8, cap := Color(0, 0, 0, 0)) -> void:
	var cap_color := color.darkened(0.12) if cap.a == 0.0 else cap
	var axis := pose.basis.y.normalized()
	var end := pose * (Vector3.UP * length)
	for i in range(sides):
		var first := Vector3(cos(i * TAU / sides), 0, sin(i * TAU / sides))
		var second := Vector3(cos((i + 1) * TAU / sides), 0, sin((i + 1) * TAU / sides))
		var normal := (pose.basis * (first + second)).normalized()
		var shade := _shade(color.darkened(0.06 * (i % 2)), normal)
		var p0 := pose * (first * bottom)
		var p1 := pose * (second * bottom)
		var q0 := pose * (first * top + Vector3.UP * length)
		var q1 := pose * (second * top + Vector3.UP * length)
		if top > 0.0: quad(p0, p1, q1, q0, normal, shade)
		else: tri(p0, p1, end, normal, shade)
		if bottom > 0.0: tri(pose.origin, p0, p1, -axis, cap_color)
		if top > 0.0: tri(end, q0, q1, axis, cap_color)

## Upright cylinder from a base centre.
func post(radius: float, length: float, base: Vector3, color: Color, sides := 6) -> void:
	prism(radius, radius, length, Transform3D(Basis.IDENTITY, base), color, sides)

## Sagging cable drawn as short square segments, thick enough for 540p.
func wire(a: Vector3, b: Vector3, sag: float, thickness: float, color: Color, segments := 8) -> void:
	var previous := a
	for i in range(1, segments + 1):
		var t := float(i) / segments
		var point := a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
		beam(previous, point, thickness, thickness, color)
		previous = point

## Half-buried broken pieces around a ground point.
func rubble(centre: Vector3, radius: float, count: int, color: Color, rng: RandomNumberGenerator, largest := 0.6) -> void:
	for i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var reach := radius * sqrt(rng.randf())
		var x := centre.x + cos(angle) * reach
		var z := centre.z + sin(angle) * reach
		var size := Vector3(rng.randf_range(0.18, largest), rng.randf_range(0.12, largest * 0.6), rng.randf_range(0.18, largest))
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, TAU), rng.randf_range(-0.5, 0.5)))
		# Heap towards the middle so the pile reads as one mound.
		var lift := (1.0 - reach / maxf(radius, 0.01)) * radius * 0.28
		box(size, Transform3D(basis, on_ground(x, z, lift + size.y * 0.15)), color.darkened(rng.randf_range(0.0, 0.2)))

func is_empty() -> bool:
	return _vertices == 0

func commit() -> ArrayMesh:
	var mesh: ArrayMesh = st.commit()
	if mesh.get_surface_count() > 0: mesh.surface_set_material(0, material())
	return mesh

## One visual plus one compound static body, in the parent's local space.
func instance(parent: Node3D, title: String, pose: Transform3D) -> Node3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.transform = pose
	if not is_empty(): node.mesh = commit()
	parent.add_child(node)
	if not solids.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		for index in range(solids.size()):
			var solid: Dictionary = solids[index]
			var shape := CollisionShape3D.new()
			shape.name = "Solid_%d" % index
			var box_shape := BoxShape3D.new()
			box_shape.size = solid.size
			shape.shape = box_shape
			shape.transform = solid.pose
			body.add_child(shape)
		node.add_child(body)
	return node

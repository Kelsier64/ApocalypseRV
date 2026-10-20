extends RefCounted
class_name BridgeBuilder
## Curved structural sections share the road lattice; supports have global owners.
const SHADER = preload("res://world/terrain/bridge_material.gdshader")
static var _materials: Dictionary = {}

static func material(kind: String) -> ShaderMaterial:
	if not _materials.has(kind):
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("base_color", Color("a4a79b") if kind == "concrete" else (Color("65716b") if kind == "steel" else Color("242b29")))
		mat.set_shader_parameter("steel", kind != "concrete")
		_materials[kind] = mat
	return _materials[kind]

static func _mesh(parent: Node3D, title: String, faces: PackedVector3Array, kind: String, solid: bool = false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Godot's front faces wind clockwise. Profiles are assembled with outward
	# mathematical cross products, so reverse them for both rendering and Jolt.
	for i in range(0, faces.size(), 3):
		for index in [i, i + 2, i + 1]: st.add_vertex(faces[index])
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = st.commit()
	node.material_override = material(kind)
	parent.add_child(node)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = node.mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)
	return node

static func _quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append_array(PackedVector3Array([a, b, c, a, c, d]))

static func _cap(faces: PackedVector3Array, ring: PackedVector3Array, reverse: bool) -> void:
	# Profiles are constant in topology; use their local XY projection even
	# when a road's world-space tangent turns nearly across the X axis.
	var u := (ring[1] - ring[0]).normalized()
	var normal := (ring[1] - ring[0]).cross(ring[2] - ring[0]).normalized()
	var v := normal.cross(u)
	var outline := PackedVector2Array()
	for point in ring: outline.append(Vector2((point - ring[0]).dot(u), (point - ring[0]).dot(v)))
	var indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, indices.size(), 3):
		faces.append_array(PackedVector3Array([ring[indices[i]], ring[indices[i + (2 if reverse else 1)]], ring[indices[i + (1 if reverse else 2)]]]))

static func _ring(field: WorldField, s: float, profile: Array[Vector3]) -> PackedVector3Array:
	var frame := field.road_frame(s)
	var half := field.road_width(s) * 0.5
	var ring := PackedVector3Array()
	for point in profile: ring.append(frame * Vector3(point.x * half + point.z, point.y, 0))
	return ring

static func _sweep(parent: Node3D, field: WorldField, band: int, title: String, profile: Array[Vector3], kind: String, solid: bool = false) -> MeshInstance3D:
	var faces := PackedVector3Array()
	for i in range(60):
		var s := band * 150.0 + i * 2.5
		if not field.landforms.bridge_at(s + 1.25): continue
		var a := _ring(field, s, profile)
		var b := _ring(field, s + 2.5, profile)
		for j in range(profile.size()):
			var next := (j + 1) % profile.size()
			_quad(faces, a[j], a[next], b[next], b[j])
		if not field.landforms.bridge_at(s - 0.01): _cap(faces, a, true)
		if not field.landforms.bridge_at(s + 2.51): _cap(faces, b, false)
	if faces.is_empty(): return null
	return _mesh(parent, title, faces, kind, solid)

static func _chamfer_ring(width: float, depth: float, y: float, center: Vector3) -> PackedVector3Array:
	var x := width * 0.5
	var z := depth * 0.5
	var bevel := minf(0.18, minf(x, z) * 0.25)
	var points := PackedVector3Array()
	for point: Vector2 in [Vector2(-x + bevel, -z), Vector2(x - bevel, -z), Vector2(x, -z + bevel), Vector2(x, z - bevel), Vector2(x - bevel, z), Vector2(-x + bevel, z), Vector2(-x, z - bevel), Vector2(-x, -z + bevel)]:
		points.append(center + Vector3(point.x, y, point.y))
	return points

static func _column(parent: Node3D, title: String, pose: Transform3D, bottom: float, top: float, width: float, depth: float, kind: String = "concrete") -> MeshInstance3D:
	var lower := _chamfer_ring(width * 1.12, depth * 1.12, bottom, Vector3.ZERO)
	var upper := _chamfer_ring(width, depth, top, Vector3.ZERO)
	var faces := PackedVector3Array()
	for i in range(lower.size()): _quad(faces, lower[i], upper[i], upper[(i + 1) % upper.size()], lower[(i + 1) % lower.size()])
	_cap(faces, lower, false)
	_cap(faces, upper, true)
	var node := _mesh(parent, title, faces, kind, true)
	node.transform = pose
	return node

static func _box(parent: Node3D, title: String, size: Vector3, pose: Transform3D, kind: String, solid: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(kind)
	parent.add_child(node)
	node.transform = pose
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		node.add_child(body)
	return node

static func build(chunk: ChunkGenerator, gradual: bool) -> void:
	var field := chunk.field
	var slab: Array[Vector3] = [Vector3(-1, -0.08, -0.95), Vector3(1, -0.08, 0.95), Vector3(1, -0.50, 0.95), Vector3(1, -0.85, 0.55), Vector3(-1, -0.85, -0.55), Vector3(-1, -0.50, -0.95)]
	var deck := _sweep(chunk, field, chunk.band, "BridgeDeck", slab, "concrete", true)
	if deck == null: return
	deck.get_child(0).set_meta("bridge_deck", true)
	var root := Node3D.new()
	root.name = "BridgeStructure"
	chunk.add_child(root)
	for fraction: float in [-0.58, 0.0, 0.58]:
		var profile: Array[Vector3] = []
		for point: Vector2 in [Vector2(-0.34, -0.85), Vector2(0.34, -0.85), Vector2(0.34, -1.03), Vector2(0.07, -1.03), Vector2(0.07, -1.93), Vector2(0.34, -1.93), Vector2(0.34, -2.11), Vector2(-0.34, -2.11), Vector2(-0.34, -1.93), Vector2(-0.07, -1.93), Vector2(-0.07, -1.03), Vector2(-0.34, -1.03)]:
			profile.append(Vector3(fraction, point.y, point.x))
		var girder := _sweep(root, field, chunk.band, "MainGirder_%s" % fraction, profile, "steel", true)
		if girder != null: girder.get_child(0).set_meta("bridge_deck", true)
	for side: float in [-1.0, 1.0]:
		var barrier: Array[Vector3] = []
		for point: Vector2 in [Vector2(0.16, -0.04), Vector2(0.96, -0.04), Vector2(0.96, 1.12), Vector2(0.66, 1.12), Vector2(0.59, 0.55), Vector2(0.22, 0.18)]:
			barrier.append(Vector3(side, point.y, point.x * side))
		if side > 0.0: barrier.reverse()
		_sweep(root, field, chunk.band, "Barrier_%s" % side, barrier, "concrete", true)
	for i in range(15):
		var s := chunk.band * 150.0 + i * 10.0 + 5.0
		if not field.landforms.bridge_at(s): continue
		var frame := field.road_frame(s)
		var half := field.road_width(s) * 0.5
		var chord := field.road_frame(s + 0.5).origin - field.road_frame(s - 0.5).origin
		var basis := Basis.looking_at(chord)
		_box(root, "CrossGirder_%d" % i, Vector3(half * 1.45, 0.50, 0.25), Transform3D(basis, frame.origin - Vector3.UP * 1.48), "steel")
		for side: float in [-1.0, 1.0]:
			for diagonal: float in [-1.0, 1.0]:
				var a := frame * Vector3(side * half * 0.58, -1.48 + diagonal * 0.43, 0)
				var b := frame * Vector3(0, -1.48 - diagonal * 0.43, 0)
				_box(root, "CrossBrace_%d_%s_%s" % [i, side, diagonal], Vector3(0.10, 0.12, a.distance_to(b)), Transform3D(Basis.looking_at(b - a), (a + b) * 0.5), "steel")
		for side: float in [-1.0, 1.0]:
			var marker := _box(root, "Reflector_%d_%s" % [i, side], Vector3(0.10, 0.18, 0.22), Transform3D(frame.basis, frame * Vector3(side * (half + 0.52), 0.97, 0)), "concrete")
			marker.material_override = RoadsideKit.material(Color("c6b57d"))
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	for i in range(5):
		var s := chunk.band * 150.0 + i * 30.0 + 15.0
		if not field.landforms.bridge_at(s): continue
		_build_pier(root, field, s)
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	for i in range(11):
		var s := chunk.band * 150.0 + i * 15.0
		var before := field.landforms.bridge_at(s - 0.01)
		var after := field.landforms.bridge_at(s + 0.01)
		if before == after: continue
		if (i == 0 and before) or (i == 10 and after): continue
		_build_abutment(root, field, s, 1.0 if after else -1.0)

static func _build_pier(root: Node3D, field: WorldField, s: float) -> void:
	var frame := field.road_frame(s)
	var half := field.road_width(s) * 0.5
	var cap_top := frame.origin.y - 2.30
	var cap_bottom := cap_top - 0.90
	var feet: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var point := frame * Vector3(side * half * 0.50, 0, 0)
		var ground := field.height_at(point.x, point.z)
		var low := ground
		var high := ground
		for dx: float in [-1.4, 1.4]:
			for dz: float in [-1.55, 1.55]:
				var corner := point + frame.basis * Vector3(dx, 0, dz)
				var value := field.height_at(corner.x, corner.z)
				low = minf(low, value)
				high = maxf(high, value)
		if cap_bottom - high < 0.65: continue
		var pose := Transform3D(frame.basis, Vector3(point.x, 0.0, point.z))
		_column(root, "Pier_%d_%s" % [roundi(s), side], pose, high + 0.20, cap_bottom + 0.03, 1.35, 1.75)
		_column(root, "Foundation_%d_%s" % [roundi(s), side], pose, low - 0.65, high + 0.45, 2.80, 3.10)
		feet.append(point)
	if feet.is_empty(): return
	_box(root, "PierCap_%d" % roundi(s), Vector3(half * 1.55, 0.90, 2.20), Transform3D(frame.basis, Vector3(frame.origin.x, (cap_top + cap_bottom) * 0.5, frame.origin.z)), "concrete", true)
	for fraction: float in [-0.58, 0.0, 0.58]:
		_box(root, "Bearing_%d_%s" % [roundi(s), fraction], Vector3(0.82, 0.24, 0.85), Transform3D(frame.basis, frame * Vector3(half * fraction, -2.20, 0)), "bearing")
	# The expansion strip follows the actual road grade, including curves.
	var basis := Basis.looking_at(field.road_frame(s + 0.5).origin - field.road_frame(s - 0.5).origin)
	_box(root, "ExpansionJoint_%d" % roundi(s), Vector3(half * 2.0, 0.025, 0.10), Transform3D(basis, frame.origin + Vector3.UP * 0.10), "bearing")

static func _build_abutment(root: Node3D, field: WorldField, s: float, direction: float) -> void:
	var frame := field.road_frame(s)
	var half := field.road_width(s) * 0.5
	# End wall is embedded beneath the approach; wing walls flare into soil.
	_box(root, "Abutment_%d" % roundi(s), Vector3(half * 2.0 + 1.8, 2.30, 1.0), Transform3D(frame.basis, frame.origin - Vector3.UP * 1.25), "concrete", true)
	for side: float in [-1.0, 1.0]:
		var pose := Transform3D(frame.basis * Basis(Vector3.UP, side * direction * 0.24), frame * Vector3(side * (half + 1.15), -0.72, direction * 2.0))
		_box(root, "WingWall_%d_%s" % [roundi(s), side], Vector3(0.50, 1.45, 4.30), pose, "concrete", true)

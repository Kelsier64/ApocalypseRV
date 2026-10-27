extends RefCounted
class_name MegashelterKit
class Batch extends RefCounted:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var source: Array

	func _init() -> void:
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		source = cube.get_mesh_arrays()

	func add_box(pose: Transform3D, center: Vector3, size: Vector3, shade: float) -> void:
		var offset := vertices.size()
		var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
		var source_uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
		var tint := Color(shade, shade, shade)
		for index in range(source_vertices.size()):
			vertices.append(pose * (center + source_vertices[index] * size))
			normals.append(pose.basis * source_normals[index])
			uvs.append(source_uvs[index])
			colors.append(tint)
		for index: int in source[Mesh.ARRAY_INDEX]: indices.append(offset + index)

	func mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var result := ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return result

## Eight reusable part families. Components are simple boxes in metres.
## Root lies at floor centre of front face, front +Z; depth extends towards -Z.
static func pieces(kind: String, size: Vector3, variant: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match kind:
		"wall", "rib_wall", "vent":
			_piece(result, Vector3(0, size.y * 0.5, -size.z * 0.5), Vector3(size.x - 0.06, size.y - 0.06, size.z), 1, variant)
			if kind == "rib_wall":
				for x in [-size.x * 0.27, size.x * 0.27]:
					_piece(result, Vector3(x, size.y * 0.5, 0.08), Vector3(0.16, size.y - 0.04, 0.16), 0)
			elif kind == "vent":
				_piece(result, Vector3(0, size.y * 0.5, 0.06), Vector3(2.5, 1.9, 0.12), 2)
				for index in range(5):
					_piece(result, Vector3(0, size.y * 0.5 - 0.7 + index * 0.35, 0.15), Vector3(2.6, 0.12, 0.25), 2)
		"corner":
			_piece(result, Vector3(-size.x * 0.5, size.y * 0.5, 0.1), Vector3(size.x, size.y, 0.2), 0)
			_piece(result, Vector3(0.1, size.y * 0.5, -size.z * 0.5), Vector3(0.2, size.y, size.z), 0)
		"pier", "beam":
			_piece(result, Vector3(0, size.y * 0.5, -size.z * 0.5), size, 2 if variant == 2 else 0)
		"roof":
			_piece(result, Vector3(0, size.y * 0.5, -size.z * 0.5), size, 0)
		"entrance":
			_piece(result, Vector3(-5.5, 4.5, -1.5), Vector3(1, 9, 3), 0)
			_piece(result, Vector3(5.5, 4.5, -1.5), Vector3(1, 9, 3), 0)
			_piece(result, Vector3(0, 8.25, -1.5), Vector3(10, 1.5, 3), 0)
			# Shallow closed leaves sit just ahead of the sealed structural mass.
			_piece(result, Vector3(-0.9, 2.5, -2.88), Vector3(6, 5, 0.24), 2)
			for index in range(3):
				_piece(result, Vector3(-0.9, 1.25 + index * 1.25, -2.70), Vector3(5.94, 0.06, 0.12), 2)
			_piece(result, Vector3(3.55, 1.25, -2.83), Vector3(1.5, 2.5, 0.28), 2)
			_piece(result, Vector3(3.0, 1.05, -2.65), Vector3(0.1, 0.35, 0.1), 2)
	return result

static func _piece(parts: Array[Dictionary], center: Vector3, size: Vector3, material: int, variant: int = 0) -> void:
	parts.append({"center": center, "size": size, "material": material, "shade": 1.0 - variant * 0.035})

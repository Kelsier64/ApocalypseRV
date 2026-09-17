extends RefCounted
class_name RoadsideKit
## Shared primitive art modules; replace individual meshes without changing placement.
static var materials: Dictionary = {}
static var meshes: Dictionary = {}
static var scenes: Dictionary = {}
const BARK := Color(0.22, 0.17, 0.12)
const LEAF := Color(0.19, 0.30, 0.17)
const STEEL := Color(0.27, 0.31, 0.30)
const RUST := Color(0.39, 0.21, 0.12)
const STONE := Color(0.40, 0.41, 0.37)

static func instantiate_module(kind: String) -> Node3D:
	if not scenes.has(kind):
		scenes[kind] = load("res://world/roadside_kit/%s.tscn" % kind)
	return scenes[kind].instantiate()

static func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var mat := IndustrialArt.material("concrete", color)
		materials[color] = mat
	return materials[color]

static func part(parent: Node3D, size: Vector3, position: Vector3, color: Color, solid: bool = false, form: String = "box") -> MeshInstance3D:
	var key := str(size) + form
	if not meshes.has(key):
		var mesh: PrimitiveMesh
		if form == "cone" or form == "trunk":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.0 if form == "cone" else size.x * 0.4
			cylinder.bottom_radius = size.x * 0.5
			cylinder.height = size.y
			cylinder.radial_segments = 7
			mesh = cylinder
		elif form == "rock":
			var sphere := SphereMesh.new()
			sphere.radius = size.x * 0.5
			sphere.height = size.y
			sphere.radial_segments = 7
			sphere.rings = 3
			mesh = sphere
		else:
			var box := BoxMesh.new()
			box.size = size
			mesh = box
		meshes[key] = mesh
	var instance := MeshInstance3D.new()
	instance.mesh = meshes[key]
	instance.material_override = material(color)
	instance.position = position
	parent.add_child(instance)
	if solid:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		instance.add_child(body)
	return instance

static func label(parent: Node3D, words: String, position: Vector3, size: int = 38) -> void:
	var text := Label3D.new()
	text.text = words
	text.position = position
	text.font_size = size
	text.pixel_size = 0.014
	text.modulate = Color(0.92, 0.86, 0.63)
	parent.add_child(text)

static func make(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.to_pascal_case()
	match kind:
		"tree", "dead_tree":
			part(root, Vector3(0.65, 6, 0.65), Vector3(0, 3, 0), BARK, true, "trunk")
			if kind == "tree":
				part(root, Vector3(5, 5, 5), Vector3(0, 6, 0), LEAF, false, "cone")
				part(root, Vector3(3.8, 4, 3.8), Vector3(0, 8, 0), LEAF.lightened(0.08), false, "cone")
			else:
				part(root, Vector3(3.8, 0.22, 0.3), Vector3(0.8, 4.5, 0), BARK).rotation.z = 0.5
				part(root, Vector3(2.5, 0.22, 0.3), Vector3(-0.5, 5.2, 0), BARK).rotation.z = -0.6
		"rock":
			part(root, Vector3(3.5, 2.8, 3.5), Vector3(0, 1, 0), STONE, true, "rock")
		"pole":
			part(root, Vector3(0.25, 9, 0.25), Vector3(0, 4.5, 0), BARK, true)
			part(root, Vector3(3, 0.18, 0.2), Vector3(0, 8, 0), BARK)
			for x in [-1.1, 0.0, 1.1]:
				part(root, Vector3(0.12, 0.4, 0.12), Vector3(x, 8.3, 0), STEEL)
		"sign":
			part(root, Vector3(0.16, 3.7, 0.16), Vector3(0, 1.85, 0), STEEL, true)
			part(root, Vector3(3.6, 1.8, 0.12), Vector3(0, 3.4, 0), Color(0.13, 0.24, 0.20))
		"rail":
			for z in [-2.0, 2.0]:
				part(root, Vector3(0.16, 0.9, 0.16), Vector3(0, 0.45, z), STEEL, true)
			part(root, Vector3(0.16, 0.35, 5), Vector3(0, 0.85, 0), STEEL, true)
		"wreck":
			part(root, Vector3(2.2, 0.85, 4.7), Vector3(0, 0.85, 0), RUST, true)
			part(root, Vector3(1.9, 0.8, 2.2), Vector3(0, 1.6, 0.1), STEEL, true)
			part(root, Vector3(1.75, 0.55, 0.04), Vector3(0, 1.65, 1.22), Color(0.13, 0.20, 0.22))
			for x in [-1.1, 1.1]:
				for z in [-1.5, 1.5]:
					part(root, Vector3(0.35, 0.6, 0.7), Vector3(x, 0.4, z), Color(0.09, 0.09, 0.08))
		"camp":
			part(root, Vector3(5, 3.4, 5), Vector3(0, 1.7, 0), Color(0.42, 0.40, 0.25), true, "cone")
			part(root, Vector3(1.7, 0.5, 1), Vector3(3.5, 0.25, 0), BARK, true)
		"shed":
			for x in [-4.0, 4.0]:
				part(root, Vector3(0.3, 4, 0.3), Vector3(x, 2, 0), STEEL, true)
			part(root, Vector3(9, 0.25, 6), Vector3(0, 4, 0), RUST, true)
			part(root, Vector3(8, 3.7, 0.2), Vector3(0, 1.85, -2.8), STEEL, true)
			part(root, Vector3(2, 1, 1), Vector3(-2, 0.5, -1.5), BARK, true)
	return root

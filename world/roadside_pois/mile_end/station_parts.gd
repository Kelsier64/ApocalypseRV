extends RefCounted
## A component's render meshes and simplified collision share the same local pose.
const FINISH = preload("res://world/roadside_pois/mile_end/weathered.gdshader")
const ENAMEL = preload("res://world/roadside_pois/mile_end/enamel.png")
const PALETTE := {
	"cream": "d1bc93", "green": "40635b", "red": "984a35", "steel": "514f47",
	"tar": "393b38", "stone": "888274", "wood": "887153", "cloth": "777c63", "glass": "495957",
}
static var finishes: Dictionary = {}
static var sign_face: StandardMaterial3D
var visuals: Node3D
var body: StaticBody3D
var draw_meshes: bool

func _init(visual_layer: Node3D, collision_layer: Node3D, show_meshes: bool) -> void:
	visuals = visual_layer
	draw_meshes = show_meshes
	body = StaticBody3D.new()
	body.name = "Structure"
	collision_layer.add_child(body)

func box(label: String, at: Vector3, size: Vector3, finish: String, solid := false, tilt := Vector3.ZERO) -> void:
	if draw_meshes:
		var mesh := BoxMesh.new()
		mesh.size = size
		if not finishes.has(finish):
			var material := ShaderMaterial.new()
			material.shader = FINISH
			material.set_shader_parameter("paint", Color(PALETTE[finish]))
			material.set_shader_parameter("wear", 0.20 if finish in ["stone", "cloth", "cream"] else 0.53)
			finishes[finish] = material
		mesh.material = finishes[finish]
		var part := MeshInstance3D.new()
		part.name = label
		part.mesh = mesh
		part.position = at
		part.rotation = tilt
		visuals.add_child(part, true)
	if solid:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.name = label
		collider.shape = shape
		collider.position = at
		collider.rotation = tilt
		body.add_child(collider, true)

func sign_panel(at: Vector3, width: float, yaw: float) -> void:
	var angle := Vector3(0, yaw, 0)
	box("EnamelFrame", at, Vector3(width + 0.10, width * 0.5 + 0.10, 0.13), "steel", false, angle)
	if not draw_meshes: return
	if sign_face == null:
		sign_face = StandardMaterial3D.new()
		sign_face.albedo_texture = ENAMEL
		sign_face.roughness = 0.68
	for turn: float in [yaw, yaw + PI]:
		var face := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(width, width * 0.5)
		quad.material = sign_face
		face.mesh = quad
		face.rotation.y = turn
		face.position = at + face.basis.z * 0.069
		visuals.add_child(face)

func table(at: Vector3, width: float, depth: float, top: float, finish: String) -> void:
	box("Tabletop", at + Vector3.UP * (top - 0.055), Vector3(width, 0.11, depth), finish, true)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			box("Leg", at + Vector3(x * (width / 2 - 0.08), top / 2, z * (depth / 2 - 0.08)), Vector3(0.09, top, 0.09), "steel", true)

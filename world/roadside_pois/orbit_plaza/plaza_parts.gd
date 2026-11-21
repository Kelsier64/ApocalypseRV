extends RefCounted
## Collect repeated fixtures in material batches. Each room works in its own local frame.
const FINISH = preload("res://world/roadside_pois/orbit_plaza/finish.gdshader")
const SIGNS = preload("res://world/roadside_pois/orbit_plaza/signs.png")
const COLORS := {
	"ink": "#263e48", "aqua": "#72a49b", "gold": "#d79b46", "clay": "#ac624b",
	"milk": "#d8cbaa", "tile": "#adab95", "steel": "#858e89", "chrome": "#abb5ad",
	"coal": "#363b39", "umber": "#72604b", "paper": "#cfbc92", "vinyl": "#9c503a",
	"glass": "#587675", "grit": "#878174", "sage": "#7b8062", "white": "#e2d8c3"
}
var origin := Transform3D.IDENTITY
var layer: Node3D
var body := StaticBody3D.new()
var draw: bool
var batches := {}
var sign_materials := {}

func _init(visuals: Node3D, collisions: Node3D, enabled: bool) -> void:
	layer = visuals
	draw = enabled
	body.name = str(visuals.name) + "Solids"
	collisions.add_child(body)

func frame(at: Vector3, yaw := 0.0) -> void:
	origin = Transform3D(Basis(Vector3.UP, yaw), at)

func box(at: Vector3, size: Vector3, coat: String, solid := false, angles := Vector3.ZERO) -> void:
	var pose := origin * Transform3D(Basis.from_euler(angles), at)
	if draw: _batch("box", coat, pose, size)
	if solid: _collider(pose, size)

func cylinder(at: Vector3, diameter: float, height: float, coat: String, angles := Vector3.ZERO) -> void:
	if draw:
		_batch("round", coat, origin * Transform3D(Basis.from_euler(angles), at), Vector3(diameter, height, diameter))

func block(at: Vector3, size: Vector3) -> void:
	_collider(origin * Transform3D(Basis.IDENTITY, at), size)

func _collider(pose: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = pose
	body.add_child(collider)

func _batch(form: String, coat: String, pose: Transform3D, size: Vector3) -> void:
	var key := form + "/" + coat
	if not batches.has(key): batches[key] = []
	batches[key].append(Transform3D(pose.basis.scaled_local(size), pose.origin))

func sign_face(index: int, at: Vector3, width: float, yaw := 0.0) -> void:
	if not draw: return
	var board := Basis(Vector3.UP, yaw)
	box(at-board.z*0.027, Vector3(width+0.016,width/3.0+0.016,0.05), "ink", false, Vector3(0,yaw,0))
	if not sign_materials.has(index):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = SIGNS
		mat.uv1_scale = Vector3(0.5, 0.20, 1)
		mat.uv1_offset = Vector3((index % 2) * 0.5, floori(index / 2.0) * 0.20, 0)
		mat.roughness = 0.76
		sign_materials[index] = mat
	var face := MeshInstance3D.new()
	var panel := QuadMesh.new()
	panel.size = Vector2(width, width / 3.0)
	panel.material = sign_materials[index]
	face.mesh = panel
	face.transform = origin * Transform3D(Basis(Vector3.UP, yaw), at)
	layer.add_child(face)

func flush() -> void:
	for key: String in batches:
		var form := key.get_slice("/", 0)
		var coat := key.get_slice("/", 1)
		var mesh: PrimitiveMesh
		if form == "box":
			mesh = BoxMesh.new()
		else:
			var tube := CylinderMesh.new()
			tube.radial_segments = 16
			tube.rings = 0
			tube.height = 1
			mesh = tube
		var mat := ShaderMaterial.new()
		mat.shader = FINISH
		mat.set_shader_parameter("pigment", Color(COLORS[coat]))
		mat.set_shader_parameter("glaze", 0.88 if coat in ["chrome", "glass", "steel"] else 0.12)
		mat.set_shader_parameter("tile", coat == "tile")
		mesh.material = mat
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = batches[key].size()
		for i in range(multi.instance_count): multi.set_instance_transform(i, batches[key][i])
		var batch := MultiMeshInstance3D.new()
		batch.name = coat.capitalize() + form.capitalize()
		batch.multimesh = multi
		layer.add_child(batch)
	batches.clear()

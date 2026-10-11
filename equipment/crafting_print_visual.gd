extends Node3D
class_name CraftingPrintVisual
## Mesh-only presentation; the workstation queue owns time and the real output.
const PRINT_SHADER = preload("res://equipment/crafting_print.gdshader")
var progress: float = 0.0
var preview: Node3D
var _job_id: String = ""
var _materials: Array[ShaderMaterial] = []
var _bounds := AABB()

static func output_lift(item: Node3D) -> float:
	var bottom := 0.0
	for collider in item.get_children():
		if collider is CollisionShape3D and collider.shape:
			var bounds: AABB = collider.transform * collider.shape.get_debug_mesh().get_aabb()
			bottom = minf(bottom, bounds.position.y)
	return -bottom + 0.06

func sync_job(job: Dictionary, marker_transform: Transform3D) -> void:
	if job.is_empty():
		clear()
		return
	var recipe := RecipeCatalog.find(job.recipe)
	if recipe == null:
		clear()
		return
	if _job_id != str(job.id):
		clear()
		_job_id = str(job.id)
		_build_preview(recipe.scene_path, marker_transform)
	progress = clampf(1.0 - float(job.remaining) / maxf(recipe.duration, 0.001), 0.0, 1.0)
	var height := lerpf(_bounds.position.y, _bounds.end.y + 0.001, progress)
	for material in _materials:
		material.set_shader_parameter("progress", progress)
		material.set_shader_parameter("cutoff", height)
	_update_machine(height, recipe.duration - float(job.remaining))

func clear() -> void:
	if is_instance_valid(preview):
		remove_child(preview)
		preview.queue_free()
	preview = null
	_materials.clear()
	_job_id = ""
	progress = 0.0
	var rig := get_node_or_null("../Details")
	if rig: rig.set_print_pose(0.75, 0.0, AABB(), false)
	var status := get_node_or_null("../Details/Status") as Label3D
	if status: status.text = "FAB / READY"

func _build_preview(scene_path: String, marker_transform: Transform3D) -> void:
	var source := (load(scene_path) as PackedScene).instantiate() as Node3D
	if source == null: return
	preview = Node3D.new()
	preview.name = "ProductPreview"
	add_child(preview)
	var output := marker_transform
	output.origin += Vector3.UP * output_lift(source)
	_copy_meshes(source, output, true)
	source.queue_free()
	var first := true
	for mesh: MeshInstance3D in preview.get_children():
		var bounds: AABB = mesh.transform * mesh.mesh.get_aabb()
		_bounds = bounds if first else _bounds.merge(bounds)
		first = false

func _copy_meshes(node: Node, parent_transform: Transform3D, root_node: bool = false) -> void:
	var local := parent_transform
	if node is Node3D:
		if not node.visible: return
		if not root_node: local *= node.transform
	if node is MeshInstance3D and node.mesh:
		var copy := MeshInstance3D.new()
		copy.mesh = node.mesh
		copy.transform = local
		preview.add_child(copy)
		for surface in node.mesh.get_surface_count():
			var material := ShaderMaterial.new()
			material.shader = PRINT_SHADER
			material.set_shader_parameter("mesh_to_print", local)
			var original: Material = node.get_active_material(surface)
			if original is BaseMaterial3D:
				material.set_shader_parameter("base_color", original.albedo_color)
				material.set_shader_parameter("surface_metallic", original.metallic)
				material.set_shader_parameter("surface_roughness", original.roughness)
				if original.albedo_texture:
					material.set_shader_parameter("has_texture", true)
					material.set_shader_parameter("base_texture", original.albedo_texture)
				material.set_shader_parameter("uv_scale", original.uv1_scale)
				material.set_shader_parameter("uv_offset", original.uv1_offset)
			copy.set_surface_override_material(surface, material)
			_materials.append(material)
	for child in node.get_children():
		_copy_meshes(child, local)

func _update_machine(height: float, elapsed: float) -> void:
	var rig := get_node_or_null("../Details")
	if rig: rig.set_print_pose(height, elapsed, _bounds, progress < 1.0)
	var status := get_node_or_null("../Details/Status") as Label3D
	if status:
		status.text = "FAB / %03d%%" % roundi(progress * 100.0) if progress < 1.0 else "CLEAR OUTPUT"

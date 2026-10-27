@tool
extends Node3D
class_name ModularMegashelter
const SURFACE = preload("res://world/megashelter/megashelter_surface.gdshader")
@export var preview_seed: int = 42
var exterior_plan: Dictionary = {}
var _configured := false
var _surfaces: Array[MegashelterKit.Batch] = []
var _box := BoxMesh.new()

func _ready() -> void:
	if not _configured: configure_exterior(MegashelterPlan.generate(preview_seed))

func configure_exterior(plan: Dictionary, include_visuals: bool = true) -> void:
	_configured = true
	exterior_plan = plan
	for path in ["Visuals", "Collision", "Furnishings"]:
		for child in get_node(path).get_children():
			get_node(path).remove_child(child)
			child.free()
	get_node("AccessPoints/Front").position = plan.access_point
	set_meta("navigation_solid_geometry", true)
	for index in range(plan.collision_boxes.size()):
		var bounds: AABB = plan.collision_boxes[index]
		var shape := CollisionShape3D.new()
		shape.name = "Solid%02d" % index
		var box_shape := BoxShape3D.new()
		box_shape.size = bounds.size
		shape.shape = box_shape
		shape.position = bounds.get_center()
		shape.set_meta("navigation_solid", true)
		$Collision.add_child(shape)
	if not include_visuals: return
	_begin_visuals(plan)
	for module: Dictionary in plan.modules: _append_module(module)
	_finish_visuals(plan)

func build_visuals_gradual(chunk: ChunkGenerator) -> void:
	_begin_visuals(exterior_plan)
	for module: Dictionary in exterior_plan.modules:
		_append_module(module)
		if chunk.slice_exhausted(): await chunk._pause()
	_finish_visuals(exterior_plan)

func _begin_visuals(plan: Dictionary) -> void:
	_surfaces.clear()
	_box.size = Vector3.ONE
	for index in range(3):
		_surfaces.append(MegashelterKit.Batch.new())
	# Solid backing closes the narrow joints between wall cassettes.
	for bounds: AABB in plan.volumes:
		_append_box(Transform3D.IDENTITY, bounds.get_center(), bounds.size - Vector3(0.12, 0.02, 0.12), 0, 0.76)

func _append_module(module: Dictionary) -> void:
	for piece: Dictionary in MegashelterKit.pieces(module.kind, module.size, module.variant):
		_append_box(module.transform, piece.center, piece.size, piece.material, piece.shade)

func _finish_visuals(plan: Dictionary) -> void:
	for index in range(_surfaces.size()):
		var mesh := _surfaces[index].mesh()
		var material := ShaderMaterial.new()
		material.shader = SURFACE
		material.set_shader_parameter("base_color", [Color("686e6b"), Color("59665e"), Color("343b3a")][index])
		material.set_shader_parameter("surface_kind", float(index))
		material.set_shader_parameter("wear_seed", float(posmod(int(plan.seed), 10000)))
		mesh.surface_set_material(0, material)
		var visual := MeshInstance3D.new()
		visual.name = ["Concrete", "SealedPanels", "OldSteel"][index]
		visual.mesh = mesh
		$Visuals.add_child(visual)
	_surfaces.clear()
	_dress_base(plan)

func _append_box(pose: Transform3D, center: Vector3, size: Vector3, material: int, shade: float = 1.0) -> void:
	_surfaces[material].add_box(pose, center, size, shade)

func _dress_base(plan: Dictionary) -> void:
	# Sparse, non-interactive debris never blocks the central vehicle approach.
	var rng := RandomNumberGenerator.new()
	rng.seed = ("megashelter:wear:%d" % int(plan.seed)).hash()
	var debris := SurfaceTool.new()
	debris.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(18):
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := side * rng.randf_range(9.0, float(plan.width) * 0.5 + 2.0)
		var z := float(plan.depth) * 0.5 + rng.randf_range(1.0, 12.0)
		var size := Vector3(rng.randf_range(0.3, 1.0), rng.randf_range(0.08, 0.35), rng.randf_range(0.3, 0.8))
		debris.append_from(_box, 0, Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(size), Vector3(x, size.y * 0.5, z)))
	var mesh := debris.commit()
	mesh.surface_set_material(0, IndustrialArt.material("concrete", Color("4e534b")))
	var visual := MeshInstance3D.new()
	visual.name = "AbandonedFragments"
	visual.mesh = mesh
	$Furnishings.add_child(visual)

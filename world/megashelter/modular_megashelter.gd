@tool
extends Node3D
class_name ModularMegashelter
const SURFACE = preload("res://world/megashelter/megashelter_surface.gdshader")
const ROOF_PLANT = [preload("res://assets/models/shelter_roof_air_handler/shelter_roof_air_handler.glb"),
	preload("res://assets/models/shelter_roof_filter_bank/shelter_roof_filter_bank.glb")]
@export var preview_seed: int = 42
var exterior_plan: Dictionary = {}
var _configured := false
var _surfaces: Array[MegashelterKit.Batch] = []
var _roof_modules: Array[Dictionary] = []

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
	_roof_modules.clear()
	for index in range(3):
		_surfaces.append(MegashelterKit.Batch.new())
	# Solid backing closes the narrow joints between wall cassettes.
	for bounds: AABB in plan.volumes:
		_append_box(Transform3D.IDENTITY, bounds.get_center(), bounds.size - Vector3(4.3, 0.02, 4.3), 0, 0.62)

func _append_module(module: Dictionary) -> void:
	if module.kind == "roof_plant": _roof_modules.append(module)
	for piece: Dictionary in MegashelterKit.pieces(module.kind, module.size, module.variant):
		if piece.get("visible",true): _surfaces[piece.material].add_piece(module.transform,piece)

func _finish_visuals(plan: Dictionary) -> void:
	for index in range(_surfaces.size()):
		var mesh := _surfaces[index].mesh()
		var material := ShaderMaterial.new()
		material.shader = SURFACE
		var palettes := [[Color("656b65"),Color("47554f"),Color("343d3c")],
			[Color("62666a"),Color("48525a"),Color("343b40")],
			[Color("696a60"),Color("50564b"),Color("383b36")]]
		material.set_shader_parameter("base_color", palettes[int(plan.get("style",0))][index])
		material.set_shader_parameter("surface_kind", float(index))
		material.set_shader_parameter("wear_seed", float(posmod(int(plan.seed), 10000)))
		mesh.surface_set_material(0, material)
		var visual := MeshInstance3D.new()
		visual.name = ["Concrete", "SealedPanels", "OldSteel"][index]
		visual.mesh = mesh
		$Visuals.add_child(visual)
	for module: Dictionary in _roof_modules:
		var wrapper := Node3D.new()
		wrapper.name = module.id
		wrapper.transform = module.transform
		var equipment: Node3D = ROOF_PLANT[module.variant].instantiate()
		equipment.position = Vector3(0,1.36 if module.variant == 0 else 1.11,-module.size.z*0.5)
		wrapper.add_child(equipment)
		$Visuals.add_child(wrapper)
	_roof_modules.clear()
	_surfaces.clear()
	_dress_base(plan)

func _append_box(pose: Transform3D, center: Vector3, size: Vector3, material: int, shade: float = 1.0) -> void:
	_surfaces[material].add_box(pose, center, size, shade)

func _dress_base(plan: Dictionary) -> void:
	# Sparse, non-interactive debris never blocks the central vehicle approach.
	var rng := RandomNumberGenerator.new()
	rng.seed = ("megashelter:wear:%d" % int(plan.seed)).hash()
	var paving := MegashelterKit.Batch.new()
	for row in range(3):
		for column in range(6):
			paving.add_box(Transform3D.IDENTITY,Vector3(-10+column*4,-0.005,float(plan.depth)*0.5+3.8+row*4),Vector3(3.97,0.04,3.97),rng.randf_range(0.78,0.92))
	var floor_visual := MeshInstance3D.new()
	floor_visual.name = "CrackedForecourt"
	floor_visual.mesh = paving.mesh()
	floor_visual.mesh.surface_set_material(0,$Visuals/Concrete.mesh.surface_get_material(0))
	floor_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$Furnishings.add_child(floor_visual)
	var debris := MegashelterKit.Batch.new()
	for index in range(18):
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := side * rng.randf_range(9.0, float(plan.width) * 0.5 + 2.0)
		var z := float(plan.depth) * 0.5 + rng.randf_range(1.0, 12.0)
		var size := Vector3(rng.randf_range(0.3, 1.0), rng.randf_range(0.08, 0.35), rng.randf_range(0.3, 0.8))
		var piece := {"center":Vector3.ZERO,"size":size,"shade":rng.randf_range(0.62,0.88),"shape":"bevel","bevel":0.09}
		debris.add_piece(Transform3D(Basis(Vector3.UP,rng.randf_range(-PI,PI)),Vector3(x,size.y*0.5,z)),piece)
	var mesh := debris.mesh()
	mesh.surface_set_material(0,$Visuals/Concrete.mesh.surface_get_material(0))
	var visual := MeshInstance3D.new()
	visual.name = "AbandonedFragments"
	visual.mesh = mesh
	$Furnishings.add_child(visual)

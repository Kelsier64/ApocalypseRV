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
	for volume_index in range(plan.volumes.size()):
		var bounds: AABB = plan.volumes[volume_index]
		_surfaces[0].set_appearance(("backing:%d" % volume_index).hash(), bounds.end.y)
		_append_box(Transform3D.IDENTITY, bounds.get_center(), bounds.size - Vector3(0.02, 0.02, 0.02), 0, 0.62)

func _append_module(module: Dictionary) -> void:
	if module.kind == "roof_plant": _roof_modules.append(module)
	var pieces := MegashelterKit.pieces(module.kind, module.size, module.variant)
	var ledge_height := float(module.transform.origin.y) + float(module.size.y)
	if module.kind == "beam": ledge_height = module.transform.origin.y
	elif module.kind == "entrance":
		# Water falls from the portal lintel/trim, below the cap's front face.
		for piece: Dictionary in pieces:
			if piece.material == 0 and piece.center.y > module.size.y * 0.75 and piece.size.x > module.size.x * 0.5:
				ledge_height = minf(ledge_height, module.transform.origin.y + piece.center.y - piece.size.y * 0.5)
	for batch: MegashelterKit.Batch in _surfaces:
		batch.set_appearance(str(module.id).hash(), ledge_height)
	# Wall repairs and ground fittings have independent light-to-heavy corrosion.
	# Roof equipment, structural steel and paving retain their existing finish.
	if module.kind in ["wall","rib_wall","service_cabinet","pipe_manifold","intake_hood","wall_salvage"]:
		var corrosion := MegashelterDetails.corrosion_amount(int(exterior_plan.seed),str(module.id))
		for piece: Dictionary in pieces:
			if piece.material == 2: piece["steel_corrosion"] = corrosion
	for piece: Dictionary in pieces:
		if piece.get("visible",true): _surfaces[piece.material].add_piece(module.transform,piece)

func _finish_visuals(plan: Dictionary) -> void:
	# Actual drain endpoints, prioritising the entrance pair at the end of the plan.
	var drains := PackedVector4Array()
	for module_index in range(plan.modules.size() - 1, -1, -1):
		var module: Dictionary = plan.modules[module_index]
		if module.kind != "drain": continue
		var position: Vector3 = module.transform.origin
		drains.append(Vector4(position.x, position.y + float(module.size.y), position.z, position.y))
		if drains.size() == 4: break
	var drain_count := drains.size()
	drains.resize(4)
	# Paving, drains and edge chips use the same three batches as the facade.
	var forecourt_pose := Transform3D(Basis.IDENTITY,Vector3(plan.access_point.x,0,float(plan.depth)*0.5+5.2))
	for batch: MegashelterKit.Batch in _surfaces: batch.set_appearance(int(plan.seed),0.04)
	for piece: Dictionary in MegashelterDetails.forecourt(int(plan.seed)):
		_surfaces[piece.material].add_piece(forecourt_pose,piece)
	var surface_colors := _surface_colors(plan)
	for index in range(_surfaces.size()):
		var mesh := _surfaces[index].mesh()
		var material := ShaderMaterial.new()
		material.shader = SURFACE
		material.set_shader_parameter("base_color", surface_colors[index])
		material.set_shader_parameter("surface_kind", float(index))
		material.set_shader_parameter("wear_seed", float(posmod(int(plan.seed), 10000)))
		material.set_shader_parameter("drain_count", drain_count)
		material.set_shader_parameter("drain_sources", drains)
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

static func _surface_colors(plan: Dictionary) -> Array[Color]:
	# A separate domain keeps colour choices stable without consuming layout RNG.
	var rng := RandomNumberGenerator.new()
	rng.seed = ("megashelter:palette:v1:%d:%d" % [int(plan.seed), int(plan.get("style",0))]).hash()
	# Continuous full-hue sampling generates a new RGB colour, with no swatch list.
	# Match the old grey coats' saturation/value while retaining random hue.
	var paint := Color.from_hsv(rng.randf(),rng.randf_range(0.10,0.16),rng.randf_range(0.50,0.54))
	var concrete_hue := rng.randf_range(0.53,0.62) if rng.randf() < 0.45 else rng.randf_range(0.09,0.17)
	var concrete := Color.from_hsv(concrete_hue,rng.randf_range(0.035,0.10),rng.randf_range(0.61,0.64))
	var steel := Color.from_hsv(fposmod(paint.h + rng.randf_range(-0.035,0.035),1.0),
		rng.randf_range(0.10,0.17),rng.randf_range(0.34,0.36))
	# Only the original coats change hue. The shader still applies physical dirt,
	# exposed cement, mildew and rust colours after the coat, without recolouring them.
	return [concrete,paint,steel]

func _append_box(pose: Transform3D, center: Vector3, size: Vector3, material: int, shade: float = 1.0) -> void:
	_surfaces[material].add_box(pose, center, size, shade)

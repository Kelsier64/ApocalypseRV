extends "res://tests/outdoor_horror_playground.gd"
## Opt-in comparison over the production seed-42 route; no saved-world mutation.
const MAINTENANCE_ART := preload("res://world/art_sample/maintenance_sample.gd")
var styled := true
var comparison: Label
var refresh_time := 0.0
var materials: Array[Dictionary] = []
var forest: Array[Dictionary] = []
var wear: Array[Dictionary] = []
var lamps: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var terrain: Array[Dictionary] = []
var baseline_environment: Environment
var sample_environment: Environment
var baseline_sun: Dictionary
var dressing_ready := false

func _ready() -> void:
	super._ready()
	main.get_node("WorldClock").running = false
	get_window().title = "ApocalypseRV - Industrial Style Sample"
	await get_tree().process_frame
	# Force the same initial comparison settings, without saving a preference.
	main.get_node("OutdoorPresentation").set_retro(true)
	baseline_environment = main.get_node("WorldEnvironment").environment
	sample_environment = baseline_environment.duplicate(true)
	sample_environment.ambient_light_energy = 0.12
	sample_environment.ambient_light_color = Color("84979a")
	sample_environment.fog_light_color = Color("73817f")
	sample_environment.fog_density = 0.009
	sample_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	sample_environment.volumetric_fog_enabled = false
	sample_environment.fog_sky_affect = 0.6
	var sky := ShaderMaterial.new()
	sky.shader = preload("res://world/art_sample/overcast.gdshader")
	sample_environment.sky.sky_material = sky
	var sun: DirectionalLight3D = main.get_node("DirectionalLight3D")
	baseline_sun = {"energy": sun.light_energy, "color": sun.light_color}
	comparison = Label.new()
	comparison.position = Vector2(25, 305)
	comparison.add_theme_font_size_override("font_size", 18)
	label.get_parent().add_child(comparison)
	# Roof wear caches own the source material; update those local copies so
	# health changes continue to compose correctly in either comparison mode.
	for node in main.get_node("NewRv").find_children("*", "Node", true, false):
		if node.get_script() == preload("res://rv/panel_wear.gd"):
			var entries: Array = []
			for entry in node.surfaces:
				entries.append({"entry": entry, "base": entry.source, "sample": _rv_material(entry.source)})
			wear.append({"node": node, "entries": entries})
	for mesh in main.get_node("NewRv").find_children("*", "MeshInstance3D", true, false):
		var source: Material = mesh.get_active_material(0)
		if source is StandardMaterial3D and not source.emission_enabled and source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			materials.append({"node": mesh, "base": mesh.material_override, "sample": _rv_material(source)})
	for light in main.get_node("NewRv").find_children("*", "SpotLight3D", true, false):
		if light.get_parent().name == "CabinLighting":
			lamps.append({"node": light, "energy": light.light_energy, "color": light.light_color})
	dressing_ready = true
	_refresh_assets()
	apply_style()

func _rv_material(source: Material) -> Material:
	if not source is StandardMaterial3D: return source
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.emission_enabled: return source
	var mat := source.duplicate() as StandardMaterial3D
	mat.albedo_texture = preload("res://assets/materials/style_sample/panel.svg")
	mat.uv1_triplanar = false
	mat.uv1_scale = Vector3.ONE
	mat.roughness = 0.82
	mat.metallic_specular = 0.24
	return mat

func _refresh_assets() -> void:
	# Drop streamed-out comparison resources instead of retaining every band.
	forest = forest.filter(func(entry: Dictionary) -> bool: return is_instance_valid(entry.node))
	terrain = terrain.filter(func(entry: Dictionary) -> bool: return is_instance_valid(entry.node))
	var candidates: Array[Node] = []
	for chunk in main.get_node("WorldGenerator").get_children():
		if chunk is ChunkGenerator: candidates.append_array(chunk.get_children())
	for node in candidates:
		if not node is MeshInstance3D or node.name != "Ground": continue
		if node.has_meta("style_sample"): continue
		node.set_meta("style_sample", true)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://world/art_sample/ground.gdshader")
		mat.set_shader_parameter("ground_texture", preload("res://assets/materials/industrial/forest_floor.png"))
		terrain.append({"node": node, "base": node.material_override, "sample": mat})
		if styled: node.material_override = mat
	for node in candidates:
		if not node is MultiMeshInstance3D or not str(node.name).begins_with("Forest"): continue
		if node.has_meta("style_sample"): continue
		node.set_meta("style_sample", true)
		var is_brush := str(node.name).begins_with("ForestBrush")
		var kind := int(node.get_meta("forest_kind", 0))
		# Partition only the sample visuals; production transforms/colliders stay intact.
		var alternate := _forest_cells(node, kind, is_brush)
		forest.append({"node": node, "base": node.multimesh, "sample": alternate})
		node.visible = not styled
		alternate.visible = styled
	for building in get_tree().get_nodes_in_group("poi_entrances"):
		if building.has_meta("style_sample") or building.global_position.distance_to(site.building.origin) > 1: continue
		if building.get("exterior") != "maintenance": continue
		building.set_meta("style_sample", true)
		var detail := Node3D.new()
		detail.name = "StyleSample"
		detail.set_script(MAINTENANCE_ART)
		building.add_child(detail)
		var surface_overrides: Array[Dictionary] = []
		for mesh in building.get_node("Visuals").find_children("*", "MeshInstance3D", true, false):
			var source: Material = mesh.get_active_material(0)
			if source is StandardMaterial3D:
				var tint: Color = source.albedo_color
				var kind := "concrete" if str(mesh.name).begins_with("Wall") else "panel"
				surface_overrides.append({"node": mesh, "base": mesh.material_override, "sample": SampleMaterials.surface(kind, tint.lightened(0.10))})
		var entry := {"base": building.get_node("Visuals/BunkerFacade"), "sample": detail, "surfaces": surface_overrides}
		buildings.append(entry)
		_apply_building(entry)

func _apply_building(entry: Dictionary) -> void:
	entry.base.visible = not styled
	entry.sample.visible = styled
	for surface in entry.surfaces:
		surface.node.material_override = surface.sample if styled else surface.base

func _forest_cells(source: MultiMeshInstance3D, kind: int, is_brush: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = str(source.name) + "Cells"
	source.get_parent().add_child(holder)
	holder.transform = source.transform
	var cells: Dictionary = {}
	for i in range(source.multimesh.instance_count):
		var pose := source.multimesh.get_instance_transform(i)
		var cell := Vector2i(floori(pose.origin.x / 48), floori(pose.origin.z / 48))
		if not cells.has(cell): cells[cell] = []
		cells[cell].append(pose)
	for cell: Vector2i in cells:
		var origin := Vector3(cell.x * 48 + 24, 0, cell.y * 48 + 24)
		var poses: Array = cells[cell]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = SampleForest.tree(kind, is_brush)
		multi.instance_count = poses.size()
		for i in range(poses.size()):
			var pose: Transform3D = poses[i]
			pose.origin -= origin
			multi.set_instance_transform(i, pose)
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = multi
		batch.position = origin
		batch.visibility_range_end = 110.0 if is_brush else 300.0
		batch.visibility_range_end_margin = 12.0
		if is_brush: batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(batch)
	return holder

func apply_style() -> void:
	if not dressing_ready: return
	main.get_node("WorldEnvironment").environment = sample_environment if styled else baseline_environment
	var sun: DirectionalLight3D = main.get_node("DirectionalLight3D")
	sun.light_energy = 0.86 if styled else float(baseline_sun.energy)
	sun.light_color = Color("e0d9ba") if styled else baseline_sun.color
	for entry in forest:
		if not is_instance_valid(entry.node): continue
		entry.node.visible = not styled
		entry.sample.visible = styled
	for entry in terrain:
		if is_instance_valid(entry.node): entry.node.material_override = entry.sample if styled else entry.base
	for entry in materials:
		if is_instance_valid(entry.node): entry.node.material_override = entry.sample if styled else entry.base
	for entry in wear:
		if not is_instance_valid(entry.node): continue
		for surface in entry.entries: surface.entry.source = surface.sample if styled else surface.base
		entry.node.level = -1
	for entry in lamps:
		if not is_instance_valid(entry.node): continue
		entry.node.light_energy = 4.2 if styled else float(entry.energy)
		entry.node.light_color = Color("efe6bc") if styled else entry.color
	for entry in buildings:
		if is_instance_valid(entry.sample): _apply_building(entry)
	comparison.text = "%s | F1 compare | F11 clean image\nSame seed / route / collision | F2 views | F6 RV" % ("STYLE STUDY" if styled else "PREVIOUS ART")
	print("STYLE SAMPLE: ", "study" if styled else "previous", " forest_batches=", forest.size())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			styled = not styled
			apply_style()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F11:
			clean_view = not clean_view
			get_viewport().set_input_as_handled()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_4: return
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F2, KEY_F6]:
		_view()

func _view() -> void:
	super._view()
	if stage == 3:
		# Keep the comparison camera clear of the enlarged near branches.
		camera.global_position = site.building * Vector3(8, 2.2, 19)
		camera.look_at(site.building * Vector3(0, 5.0, 1.5))

func _process(delta: float) -> void:
	super._process(delta)
	if not dressing_ready: return
	# The parent owns its view methods; remove its four-building selector hint.
	if label.text.contains("1-4 building | "): label.text = label.text.replace("1-4 building | ", "")
	label.visible = label.visible and not clean_view
	comparison.visible = label.visible
	refresh_time += delta
	if refresh_time >= 0.5:
		refresh_time = 0
		_refresh_assets()

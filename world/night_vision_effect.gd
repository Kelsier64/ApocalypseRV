extends Node3D
class_name NightVisionEffect
## Native lights render normally; a matched, light-free reference supplies only
## missing gray adaptation. The Curve never attenuates direct light.
const LUT_SIZE := 512
const MAX_VIEWS := 4
const VIEW_SHIFT := 13
const VIEW_MASK := 0xF << VIEW_SHIFT
const LIGHT_LAYER := 1 << 18
const OWNED_LAYERS := VIEW_MASK | LIGHT_LAYER
const LIGHT_OWNER := &"_night_adaptation_owner"
const LIGHT_ORIGINAL_LAYERS := &"_night_adaptation_layers"
var curve_texture := ImageTexture.new()
var curve: Curve
var _materials: Array[ShaderMaterial] = []
var _views: Array[Dictionary] = []
var _lights: Dictionary = {}
var _environment: Environment
var _ambient_energy := 0.06
var _strength := 0.0
var _fade_begin := 0.0
var _fade_end := 60.0

func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)
	RenderingServer.frame_pre_draw.connect(_prepare_views)
	_bind_world.call_deferred()

func _ready() -> void:
	name = "NightVision"
	register_viewport(get_viewport())

func _bind_world() -> void:
	if not is_inside_tree(): return
	# A checkpoint candidate is reparented from staging into the live world.
	for entry in _views:
		entry.reference.world_3d = get_world_3d()
		entry.parent_rid = RID()
		if entry.primary: entry.target = weakref(get_viewport())
	register_viewport(get_viewport())
	for node in get_parent().get_parent().find_children("*", "Light3D", true, false):
		_track_light(weakref(node))

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added): get_tree().node_added.disconnect(_on_node_added)
	if RenderingServer.frame_pre_draw.is_connected(_prepare_views):
		RenderingServer.frame_pre_draw.disconnect(_prepare_views)
	for entry in _views: _release_camera(entry)
	for entry in _lights.values():
		var light: Light3D = entry.node.get_ref()
		_restore_light(light, entry.layers)
	_lights.clear()

func configure(strength: float, fade_begin: float, fade_end: float, profile: Curve, environment: Environment, ambient_energy: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_fade_begin = maxf(0.0, fade_begin)
	_fade_end = maxf(_fade_begin + 0.001, fade_end)
	_environment = environment
	_ambient_energy = ambient_energy
	if curve != profile:
		if curve != null: curve.changed.disconnect(_bake_curve)
		curve = profile
		curve.changed.connect(_bake_curve)
		_bake_curve()
	for material in _materials: _update_material(material)

func register_viewport(viewport: Viewport, active := true) -> void:
	_prune_views()
	for entry in _views:
		if entry.target.get_ref() == viewport:
			entry.active = active
			return
	if not active or _views.size() >= MAX_VIEWS: return
	var reference := SubViewport.new()
	reference.name = "GrayAdaptationReference"
	reference.world_3d = get_world_3d()
	reference.gui_disable_input = true
	reference.render_target_update_mode = SubViewport.UPDATE_DISABLED
	reference.positional_shadow_atlas_size = 0
	add_child(reference)
	var camera := Camera3D.new()
	camera.environment = Environment.new()
	reference.add_child(camera)
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/night_vision.gdshader")
	# Native transparency (glass, rain) follows the gray adaptation.
	material.render_priority = -128
	material.set_shader_parameter("night_reference", reference.get_texture())
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	quad.material_override = material
	var used_layers := 0
	for entry in _views: used_layers |= int(entry.quad.layers)
	for index in range(MAX_VIEWS):
		var candidate := 1 << (VIEW_SHIFT + index)
		if (used_layers & candidate) == 0:
			quad.layers = candidate
			break
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.ignore_occlusion_culling = true
	quad.visible = false
	add_child(quad)
	RenderingServer.instance_set_ignore_culling(quad.get_instance(), true)
	_views.append({"target": weakref(viewport), "active": active, "reference": reference, "primary": viewport == get_viewport(),
		"camera": camera, "quad": quad, "material": material, "source": null, "mask": 0, "parent_rid": RID()})
	_materials.append(material)
	_update_material(material)

func register_weather(material: ShaderMaterial) -> void:
	if _materials.has(material): return
	_materials.append(material)
	_update_material(material)

func unregister_weather(material: ShaderMaterial) -> void:
	_materials.erase(material)

func _on_node_added(node: Node) -> void:
	if node is Light3D: _track_light.call_deferred(weakref(node))

func _track_light(reference: WeakRef) -> void:
	if not is_inside_tree(): return
	var light := reference.get_ref() as Light3D
	if light == null or not light.is_inside_tree() or light.get_world_3d() != get_world_3d(): return
	var id := light.get_instance_id()
	if not _lights.has(id):
		var original_layers: int = light.get_meta(LIGHT_ORIGINAL_LAYERS, light.layers)
		light.set_meta(LIGHT_ORIGINAL_LAYERS, original_layers)
		light.set_meta(LIGHT_OWNER, get_instance_id())
		_lights[id] = {"node": reference, "layers": original_layers}

func _restore_light(light: Light3D, layers: int) -> void:
	if not is_instance_valid(light) or light.get_meta(LIGHT_OWNER, 0) != get_instance_id(): return
	light.layers = layers
	light.remove_meta(LIGHT_OWNER)
	light.remove_meta(LIGHT_ORIGINAL_LAYERS)

func _prune_views() -> void:
	for index in range(_views.size() - 1, -1, -1):
		var entry := _views[index]
		if entry.target.get_ref() != null: continue
		_release_camera(entry)
		_materials.erase(entry.material)
		entry.quad.visible = false
		entry.reference.render_target_update_mode = SubViewport.UPDATE_DISABLED
		entry.quad.queue_free()
		entry.reference.queue_free()
		_views.remove_at(index)

func _release_camera(entry: Dictionary) -> void:
	var source: Camera3D = entry.source.get_ref() if entry.source != null else null
	if is_instance_valid(source):
		source.cull_mask = (source.cull_mask & ~OWNED_LAYERS) | (int(entry.mask) & OWNED_LAYERS)
	entry.source = null

func _prepare_views() -> void:
	if not is_inside_tree(): return
	_prune_views()
	if not can_process():
		for entry in _views: entry.reference.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	for id in _lights.keys():
		var entry: Dictionary = _lights[id]
		var light: Light3D = entry.node.get_ref()
		if not is_instance_valid(light):
			_lights.erase(id)
			continue
		if not light.is_inside_tree() or light.get_world_3d() != get_world_3d():
			_restore_light(light, entry.layers)
			_lights.erase(id)
			continue
		light.layers = LIGHT_LAYER if _strength > 0.0 else int(entry.layers)
	for entry in _views:
		var target := entry.target.get_ref() as Viewport
		var source := target.get_camera_3d() if is_instance_valid(target) else null
		var active: bool = _strength > 0.0 and entry.active and source != null and source.get_world_3d() == get_world_3d()
		entry.quad.visible = active
		entry.reference.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if not active:
			_release_camera(entry)
			continue
		var previous: Camera3D = entry.source.get_ref() if entry.source != null else null
		if previous != source:
			_release_camera(entry)
			entry.source = weakref(source)
			entry.mask = source.cull_mask
		source.cull_mask = (source.cull_mask & ~VIEW_MASK) | int(entry.quad.layers) | LIGHT_LAYER
		_sync_reference(entry, target, source)

func _sync_reference(entry: Dictionary, target: Viewport, source: Camera3D) -> void:
	var reference: SubViewport = entry.reference
	var camera: Camera3D = entry.camera
	var target_rid := target.get_viewport_rid()
	if entry.parent_rid != target_rid:
		# Reference must render before its target, including sibling mirror views.
		RenderingServer.viewport_set_parent_viewport(reference.get_viewport_rid(), target_rid)
		entry.parent_rid = target_rid
	var size := Vector2i(target.get_visible_rect().size)
	if target is SubViewport: size = target.size
	reference.size = size.max(Vector2i.ONE)
	reference.scaling_3d_scale = target.scaling_3d_scale
	reference.msaa_3d = target.msaa_3d
	reference.screen_space_aa = target.screen_space_aa
	camera.global_transform = source.get_camera_transform()
	camera.projection = source.projection
	camera.fov = source.fov
	camera.size = source.size
	camera.frustum_offset = source.frustum_offset
	camera.keep_aspect = source.keep_aspect
	camera.near = source.near
	camera.far = source.far
	camera.cull_mask = source.cull_mask & ~OWNED_LAYERS
	var environment: Environment = camera.environment
	if _environment != null:
		for property in ["background_mode", "background_color", "background_energy_multiplier", "sky",
			"fog_enabled", "fog_mode", "fog_density", "fog_light_color", "fog_light_energy", "fog_depth_begin", "fog_depth_end", "fog_depth_curve", "fog_sky_affect"]:
			environment.set(property, _environment.get(property))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = _ambient_energy
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.adjustment_enabled = false
	environment.volumetric_fog_enabled = false
	if target is SubViewport and target.render_target_update_mode == SubViewport.UPDATE_DISABLED: return
	reference.render_target_update_mode = SubViewport.UPDATE_ONCE

func _bake_curve() -> void:
	# Include both endpoints and never rewrite the authored Curve resource.
	var data := PackedByteArray()
	data.resize(LUT_SIZE * 4)
	for i in range(LUT_SIZE): data.encode_float(i * 4, curve.sample(float(i) / (LUT_SIZE - 1)))
	var image := Image.create_from_data(LUT_SIZE, 1, false, Image.FORMAT_RF, data)
	if curve_texture.get_width() == 0: curve_texture.set_image(image)
	else: curve_texture.update(image)

func _update_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("night_curve", curve_texture)
	material.set_shader_parameter("night_fade_begin", _fade_begin)
	material.set_shader_parameter("night_fade_end", _fade_end)
	material.set_shader_parameter("night_strength", _strength)

extends Node3D
class_name NightVisionEffect
## Per-world display effect. A matched material reference estimates missing light
## locally; neither the clock nor this effect controls the other's state.
const DEFAULT_PROFILE: DarkAdaptationProfile = preload("res://world/dark_adaptation_profile.tres")
const LUT_SIZE := 512
const MAX_VIEWS := 4
const VIEW_SHIFT := 13
const VIEW_MASK := 0xF << VIEW_SHIFT
const LIGHT_LAYER := 1 << 18
const OWNED_LAYERS := VIEW_MASK | LIGHT_LAYER
const LIGHT_OWNER := &"_night_adaptation_owner"
const LIGHT_ORIGINAL_LAYERS := &"_night_adaptation_layers"
const CAMERA_OWNER := &"_dark_adaptation_owner"
const CAMERA_ORIGINAL_LAYERS := &"_dark_adaptation_layers"
var curve_texture := ImageTexture.new()
var curve: Curve
var _materials: Array[ShaderMaterial] = []
var _views: Array[Dictionary] = []
var _lights: Dictionary = {}
@export var enabled := true
@export var profile: DarkAdaptationProfile = DEFAULT_PROFILE:
	set(value):
		if profile != null and profile.changed.is_connected(_on_profile_changed): profile.changed.disconnect(_on_profile_changed)
		profile = value if value != null else DEFAULT_PROFILE
		if is_inside_tree():
			profile.changed.connect(_on_profile_changed)
			_on_profile_changed()

## Look only in the caller's owning hierarchy/World3D, including staged worlds.
static func find_for(node: Node3D) -> NightVisionEffect:
	if not is_instance_valid(node) or not node.is_inside_tree(): return null
	var world := node.get_world_3d()
	var ancestor: Node = node
	while ancestor != null:
		var effect := ancestor.get_node_or_null("DarkAdaptation") as NightVisionEffect
		if effect != null and effect.get_world_3d() == world: return effect
		ancestor = ancestor.get_parent()
	return null

func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)
	RenderingServer.frame_pre_draw.connect(_prepare_views)
	if not profile.changed.is_connected(_on_profile_changed): profile.changed.connect(_on_profile_changed)
	_on_profile_changed()
	_bind_world.call_deferred()

func _ready() -> void:
	name = "DarkAdaptation"
	register_viewport(get_viewport())

func _bind_world() -> void:
	if not is_inside_tree(): return
	# A checkpoint candidate is reparented from staging into the live world.
	for entry in _views:
		entry.reference.world_3d = get_world_3d()
		entry.parent_rid = RID()
		if entry.primary: entry.target = weakref(get_viewport())
	register_viewport(get_viewport())
	for node in get_parent().find_children("*", "Light3D", true, false):
		_track_light(weakref(node))

func _exit_tree() -> void:
	if profile.changed.is_connected(_on_profile_changed): profile.changed.disconnect(_on_profile_changed)
	if get_tree().node_added.is_connected(_on_node_added): get_tree().node_added.disconnect(_on_node_added)
	if RenderingServer.frame_pre_draw.is_connected(_prepare_views):
		RenderingServer.frame_pre_draw.disconnect(_prepare_views)
	for entry in _views: _release_camera(entry)
	for entry in _lights.values():
		var light: Light3D = entry.node.get_ref()
		_restore_light(light, entry.layers)
	_lights.clear()

func _on_profile_changed() -> void:
	curve = profile.effective_curve()
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
	# This camera receives the source's rendered pose, already interpolated.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.environment = Environment.new()
	reference.add_child(camera)
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/night_vision.gdshader")
	# Native transparency (glass, rain) follows the gray adaptation.
	material.render_priority = -128
	material.set_shader_parameter("night_reference", reference.get_texture())
	var quad := MeshInstance3D.new()
	quad.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	quad.extra_cull_margin = 1.0
	quad.visible = false
	add_child(quad)
	_views.append({"target": weakref(viewport), "active": active, "reference": reference, "primary": viewport == get_viewport(),
		"camera": camera, "quad": quad, "material": material, "source": null, "mask": 0, "parent_rid": RID()})
	_materials.append(material)
	_update_material(material)

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
	if is_instance_valid(source) and source.get_meta(CAMERA_OWNER, 0) == get_instance_id():
		source.cull_mask = (source.cull_mask & ~OWNED_LAYERS) | (int(entry.mask) & OWNED_LAYERS)
		source.remove_meta(CAMERA_OWNER)
		source.remove_meta(CAMERA_ORIGINAL_LAYERS)
	entry.source = null

func _prepare_views() -> void:
	if not is_inside_tree(): return
	_prune_views()
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
		light.layers = LIGHT_LAYER if enabled else int(entry.layers)
	if not can_process():
		# Retain a static adapted world behind the pause menu, while an explicit
		# display toggle must still release the camera and native light layers.
		for entry in _views:
			entry.reference.render_target_update_mode = SubViewport.UPDATE_DISABLED
			if not enabled:
				entry.quad.visible = false
				_release_camera(entry)
		return
	for entry in _views:
		var target := entry.target.get_ref() as Viewport
		var source := target.get_camera_3d() if is_instance_valid(target) else null
		var active: bool = enabled and entry.active and source != null and source.get_world_3d() == get_world_3d()
		entry.quad.visible = active
		entry.reference.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if not active:
			_release_camera(entry)
			continue
		var previous: Camera3D = entry.source.get_ref() if entry.source != null else null
		if previous != source:
			_release_camera(entry)
			entry.source = weakref(source)
			# A player camera can enter a POI before the previous world releases it.
			entry.mask = source.get_meta(CAMERA_ORIGINAL_LAYERS, source.cull_mask & OWNED_LAYERS)
			source.set_meta(CAMERA_ORIGINAL_LAYERS, entry.mask)
			source.set_meta(CAMERA_OWNER, get_instance_id())
		source.cull_mask = (source.cull_mask & ~VIEW_MASK) | int(entry.quad.layers) | LIGHT_LAYER
		_sync_reference(entry, target, source)

func _sync_reference(entry: Dictionary, target: Viewport, source: Camera3D) -> void:
	var reference: SubViewport = entry.reference
	var camera: Camera3D = entry.camera
	# Bypass only occlusion, never the view-layer check: ignore_all_culling also
	# renders the composite in its own reference and causes temporal feedback.
	entry.quad.global_position = source.project_position(target.get_visible_rect().size * 0.5, source.near + 1.0)
	entry.quad.global_basis = source.get_camera_transform().basis
	entry.quad.force_update_transform()
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
	# frame_pre_draw is after SceneTree's transform-notification flush. Submit
	# this pose now or the reference renders the previous vehicle/camera pose.
	camera.force_update_transform()
	var environment: Environment = camera.environment
	var native := source.environment if source.environment != null else source.get_world_3d().environment
	if native == null: native = source.get_world_3d().fallback_environment
	# Read the actual view's environment every frame. Local FogVolumes share the
	# World3D, so matching extinction preserves their occlusion too.
	if native != null:
		for property in ["background_mode", "background_color", "background_energy_multiplier", "sky", "sky_rotation", "sky_custom_fov",
			"fog_enabled", "fog_mode", "fog_density", "fog_light_color", "fog_light_energy", "fog_depth_begin", "fog_depth_end", "fog_depth_curve", "fog_sky_affect", "fog_height", "fog_height_density", "fog_aerial_perspective",
			"volumetric_fog_enabled", "volumetric_fog_density", "volumetric_fog_albedo", "volumetric_fog_length", "volumetric_fog_detail_spread", "volumetric_fog_anisotropy", "volumetric_fog_sky_affect",
			"volumetric_fog_temporal_reprojection_enabled", "volumetric_fog_temporal_reprojection_amount", "volumetric_fog_emission", "volumetric_fog_emission_energy"]:
			environment.set(property, native.get(property))
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color.BLACK
		environment.fog_enabled = false
		environment.volumetric_fog_enabled = false
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = profile.reference_energy
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.adjustment_enabled = false
	# Reference ambient illuminates materials, never the fog. Native lamps/scatter
	# remain in the real image; the reference only preserves fog transmission.
	environment.volumetric_fog_ambient_inject = 0.0
	environment.volumetric_fog_gi_inject = 0.0
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
	material.set_shader_parameter("night_fade_begin", profile.distance_begin)
	material.set_shader_parameter("night_fade_end", maxf(profile.distance_begin + 0.001, profile.distance_end))
	material.set_shader_parameter("adaptation_dark_ratio", profile.dark_ratio)
	material.set_shader_parameter("adaptation_lit_ratio", maxf(profile.dark_ratio + 0.001, profile.lit_ratio))

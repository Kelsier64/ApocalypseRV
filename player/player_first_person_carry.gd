extends Node
## Cosmetic projection only. The shared skeleton and held Item still own every
## world pose, shadow, inventory transition and release transform.
const VIEW_LAYER := 1 << 21
const LIGHT_COPY := &"first_person_light_copy"
const MESH_COPY := &"first_person_render_copy"
const CAMERA_OFFSET := Vector3(-.18, .14, .50)
const MAX_LIGHTS := 4
var active := false
var viewport: SubViewport
var camera: Camera3D
var actor: CharacterBody3D
var visual: Node3D
var carry: Node
var image_rect: TextureRect
var arm_meshes: Dictionary = {}
var parts: Dictionary = {}
var original_body: Mesh
var item: Node3D
var item_meshes: Array[Dictionary] = []
var hidden_arms: Dictionary = {}
var light_sources: Array[WeakRef] = []
var light_copies: Dictionary = {}
var next_light_scan := 0

func _enter_tree() -> void:
	get_tree().node_added.connect(_node_added)
	RenderingServer.frame_pre_draw.connect(update_view)
	_scan_lights.call_deferred()

func _ready() -> void:
	visual = get_parent()
	actor = visual.get_parent()
	carry = visual.get_node("Carry")
	original_body = visual.local_body.mesh
	parts = visual.split_first_person_mesh(visual.local_body)
	for side: String in ["R", "L"]:
		var mesh: MeshInstance3D = visual._copy_instance(visual.local_body, "FirstPersonArm_" + side)
		mesh.mesh = parts[side]
		mesh.layers = VIEW_LAYER
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.hide()
		arm_meshes[side] = mesh
	viewport = SubViewport.new()
	viewport.name = "ViewmodelViewport"
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	camera = Camera3D.new()
	camera.name = "ViewmodelCamera"
	camera.cull_mask = VIEW_LAYER
	camera.fov = 70.0
	camera.near = .025
	camera.far = 8.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(camera)
	camera.make_current()
	var canvas := CanvasLayer.new()
	canvas.name = "ViewmodelComposite"
	canvas.layer = -1 # Before the existing video grade (0) and HUD (1+).
	add_child(canvas)
	image_rect = TextureRect.new()
	image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_rect.texture = viewport.get_texture()
	canvas.add_child(image_rect)
	image_rect.hide()

func _process(_delta: float) -> void:
	update_view()

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
	if RenderingServer.frame_pre_draw.is_connected(update_view): RenderingServer.frame_pre_draw.disconnect(update_view)
	_deactivate()
	for entry in light_copies.values():
		if is_instance_valid(entry.copy): entry.copy.queue_free()
	light_copies.clear()
	light_sources.clear()
	if is_instance_valid(viewport): viewport.world_3d = null

func _eligible() -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.is_visible_in_tree(): return false
	if actor.is_player_dead or actor.seated_in != null or actor.is_grabbed() or actor.is_crawling(): return false
	if not actor.camera.is_current() or actor.is_placing_equipment(): return false
	if actor.locomotion_state == actor.LocomotionState.CLIMBING or visual.get_node("Locomotion").climb_exit_remaining > 0.0: return false
	var held: Node3D = actor.held_item_node
	if not is_instance_valid(held) or held.is_queued_for_deletion() or not held.is_visible_in_tree() or carry.item != held: return false
	# Emitters and articulated supports keep their existing world-space view.
	if not held is Item or held is Flashlight or held is Pistol or held.has_method("held_support_center"): return false
	if held.definition != null and held.definition.requires_rv_connection: return false
	var large: bool = actor.inventory.active_item().get("is_large", false)
	return actor.can_use_hands(2 if large else 1) and (large or carry.bounds.size.x <= .70)

func update_view() -> void:
	if not is_instance_valid(viewport) or not _eligible():
		_deactivate()
		return
	if item != actor.held_item_node:
		_clear_item()
		item = actor.held_item_node
		_bind_item()
	active = true
	var large: bool = actor.inventory.active_item().get("is_large", false)
	var mode: String = "both" if large else carry.active_hand
	visual.local_body.mesh = parts["body_" + mode]
	_restore_arm_layers()
	for piece in visual.dismemberment.pieces:
		if piece.role != "Part" or piece.part not in ["left_arm", "right_arm"]: continue
		var side: String = "R" if piece.part == "right_arm" else "L"
		if mode != "both" and side != mode: continue
		var mesh: MeshInstance3D = piece.local
		hidden_arms[mesh] = mesh.layers
		mesh.layers &= ~PlayerModelVisual.LOCAL_VIEW_LAYER
	for side: String in arm_meshes:
		arm_meshes[side].visible = actor.body_state.has_part(&"right_arm" if side == "R" else &"left_arm") and (large or carry.active_hand == side)
	for entry in item_meshes:
		if not is_instance_valid(entry.source): continue
		entry.source.layers = PlayerModelVisual.FULL_BODY_LAYER
		for copy: MeshInstance3D in entry.copies:
			copy.transform = entry.source.transform
			copy.visible = entry.source.visible
			copy.material_override = entry.source.material_override
			copy.material_overlay = entry.source.material_overlay
			for surface in entry.source.mesh.get_surface_count():
				copy.set_surface_override_material(surface, entry.source.get_surface_override_material(surface))
	var parent_view := get_viewport()
	var size := Vector2i(parent_view.get_visible_rect().size).max(Vector2i.ONE)
	if viewport.size != size: viewport.size = size
	image_rect.size = Vector2(size)
	if viewport.world_3d != actor.get_world_3d():
		viewport.world_3d = actor.get_world_3d()
		next_light_scan = 0
	viewport.scaling_3d_scale = parent_view.scaling_3d_scale
	viewport.msaa_3d = parent_view.msaa_3d
	viewport.screen_space_aa = parent_view.screen_space_aa
	viewport.positional_shadow_atlas_size = parent_view.positional_shadow_atlas_size
	camera.environment = actor.camera.environment
	camera.attributes = actor.camera.attributes
	# Ordinary carry follows body yaw and limited arm pitch. The world camera
	# remains freely controllable, including looking straight up or down.
	var basis: Basis = actor.global_basis * Basis(Vector3.RIGHT, clampf(actor.camera.rotation.x, -.45, .45) * .65)
	var offset := CAMERA_OFFSET
	if large:
		# Center bulky props between two forearms entering from opposite corners.
		offset = Vector3(0, 0, .30 + maxf(0.0, carry.bounds.size.y - .50) * .30)
	if carry.active_hand == "L" and not large: offset.x = -offset.x
	camera.global_transform = Transform3D(basis, actor.camera.get_camera_transform().origin + basis * offset)
	camera.force_update_transform()
	_sync_lights()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	image_rect.show()

func _bind_item() -> void:
	for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.is_queued_for_deletion() or mesh.has_meta(MESH_COPY) or mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		var copies: Array[MeshInstance3D] = []
		for shadow in [false, true]:
			if shadow and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
			var copy := MeshInstance3D.new()
			copy.name = "FirstPersonItemShadow" if shadow else "FirstPersonItem"
			copy.set_meta(MESH_COPY, true)
			copy.mesh = mesh.mesh
			copy.skin = mesh.skin
			copy.skeleton = mesh.skeleton
			copy.layers = PlayerModelVisual.LOCAL_VIEW_LAYER if shadow else VIEW_LAYER
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mesh.get_parent().add_child(copy)
			copies.append(copy)
		item_meshes.append({"source": mesh, "layers": mesh.layers, "copies": copies})

func _restore_arm_layers() -> void:
	for mesh: MeshInstance3D in hidden_arms:
		if is_instance_valid(mesh): mesh.layers = hidden_arms[mesh]
	hidden_arms.clear()

func _clear_item() -> void:
	for entry in item_meshes:
		if is_instance_valid(entry.source): entry.source.layers = entry.layers
		for copy in entry.copies:
			if is_instance_valid(copy):
				copy.hide()
				copy.queue_free()
	item_meshes.clear()
	item = null

func _deactivate() -> void:
	active = false
	if is_instance_valid(image_rect): image_rect.hide()
	if is_instance_valid(viewport): viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(visual) and is_instance_valid(visual.local_body) and original_body != null: visual.local_body.mesh = original_body
	_restore_arm_layers()
	for mesh in arm_meshes.values():
		if is_instance_valid(mesh): mesh.hide()
	for entry in light_copies.values():
		if is_instance_valid(entry.copy): entry.copy.hide()
	_clear_item()

func _node_added(node: Node) -> void:
	if node is Light3D and not node.has_meta(LIGHT_COPY):
		light_sources.append(weakref(node))
		next_light_scan = 0

func _scan_lights() -> void:
	if not is_inside_tree(): return
	light_sources.clear()
	for light in get_tree().root.find_children("*", "Light3D", true, false): _node_added(light)

func _sync_lights() -> void:
	# These cosmetic lights have the same settings/positions as nearby world
	# lights, so night-adaptation layer routing cannot extinguish the arms.
	if Time.get_ticks_msec() >= next_light_scan:
		next_light_scan = Time.get_ticks_msec() + 250
		var candidates: Array[Dictionary] = []
		var live_sources: Array[WeakRef] = []
		for reference in light_sources:
			var source := reference.get_ref() as Light3D
			if source != null: live_sources.append(reference)
			if source == null or not source.is_inside_tree() or source.get_world_3d() != actor.get_world_3d() or not source.is_visible_in_tree() or source.light_energy <= 0.0: continue
			var distance := source.global_position.distance_to(actor.camera.global_position)
			if source is DirectionalLight3D: distance = -1.0
			elif source is OmniLight3D and distance > source.omni_range + 1.0: continue
			elif source is SpotLight3D and distance > source.spot_range + 1.0: continue
			candidates.append({"source": source, "distance": distance})
		light_sources = live_sources
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
		var selected: Dictionary = {}
		for entry in candidates.slice(0, MAX_LIGHTS):
			var source: Light3D = entry.source
			var id := source.get_instance_id()
			selected[id] = true
			if light_copies.has(id): continue
			var copy := source.duplicate(0) as Light3D
			for child in copy.get_children(): child.free()
			copy.set_meta(LIGHT_COPY, true)
			copy.layers = VIEW_LAYER
			add_child(copy)
			light_copies[id] = {"source": weakref(source), "copy": copy}
		for id in light_copies.keys():
			if selected.has(id): continue
			light_copies[id].copy.queue_free()
			light_copies.erase(id)
	for entry in light_copies.values():
		var source := entry.source.get_ref() as Light3D
		var copy: Light3D = entry.copy
		if source == null:
			copy.hide()
			continue
		for property in source.get_property_list():
			var key := String(property.name)
			if property.usage & PROPERTY_USAGE_STORAGE and (key.begins_with("light_") or key.begins_with("shadow_") or key.begins_with("omni_") or key.begins_with("spot_") or key.begins_with("directional_")):
				copy.set(key, source.get(key))
		copy.layers = VIEW_LAYER
		copy.light_cull_mask = source.light_cull_mask | VIEW_LAYER
		copy.visible = source.is_visible_in_tree()
		copy.global_transform = source.global_transform

extends Node3D
## Visual inspection of the delivered GLB; deliberately separate from gameplay.

var asset_root := "res://assets/models/player/"
const CLIPS := ["A-pose", "idle", "walk", "jump", "fall_loop", "land", "climb_loop", "hang_idle", "sit_driver", "hold_small", "carry_large", "injured_idle"]
const CUTS := ["none", "shoulder_L", "elbow_L", "shoulder_R", "elbow_R", "hip_L", "knee_L", "hip_R", "knee_R", "neck"]
var model: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var camera: Camera3D
var status: Label
var meshes: Array[Node] = []
var dyes: Array[StandardMaterial3D] = []
var original_tints: Array[Color] = []
var detached: Node3D
var clip_index := 0
var cut_index := 0
var view_index := 0
var paused := false
var ochre := false
var mask_hidden := false
var elapsed := 0.0
var replay := false
var replay_time := 0.0
var full_detail := false
var triangle_count := 0
var lighting_index := 0
var close_detail := false
var review_environment: Environment
var review_lights: Array[DirectionalLight3D] = []

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--asset-root=res://"):
			asset_root = argument.trim_prefix("--asset-root=").trim_suffix("/") + "/"
	DisplayServer.window_set_title("ApocalypseRV | Player GLB inspection")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	review_environment = settings
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.075, 0.09, 0.11)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.82, 0.87, 1.0)
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	for entry in [[Vector3(-38, -30, 0), 1.7], [Vector3(-25, 145, 0), 0.8]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = entry[0]
		light.light_energy = entry[1]
		add_child(light)
		review_lights.append(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16, 0.18, 0.21)
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	model = (load(asset_root + "player_masked_survivor.glb") as PackedScene).instantiate()
	add_child(model)
	animation = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	meshes = model.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		for surface in mesh.mesh.get_surface_count():
			triangle_count += mesh.mesh.surface_get_array_index_len(surface) / 3
	_copy_dyes(model)
	camera = Camera3D.new()
	camera.fov = 36
	add_child(camera)
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(20, 16)
	status.add_theme_font_size_override("font_size", 20)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(status)
	replay = "--replay" in OS.get_cmdline_user_args()
	_set_clip(1)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--clip="):
			var index := CLIPS.find(argument.trim_prefix("--clip="))
			if index >= 0: _set_clip(index)
		if argument.begins_with("--view="):
			view_index = clampi(argument.trim_prefix("--view=").to_int(), 0, 8)
		if argument.begins_with("--lighting="):
			lighting_index = clampi(argument.trim_prefix("--lighting=").to_int(), 0, 2)
	_apply_lighting()
	print("PLAYER_MODEL_READY: actual imported GLB; 11 actions; T tint; D detached; M mask")

func _copy_dyes(target: Node) -> void:
	var cache: Dictionary = {}
	for mesh: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material.resource_name != "suit_dye":
				continue
			if not cache.has(material):
				var copy := material.duplicate() as StandardMaterial3D
				cache[material] = copy
				dyes.append(copy)
				original_tints.append(copy.albedo_color)
			mesh.set_surface_override_material(surface, cache[material])
	_apply_tint()

func _apply_tint() -> void:
	for i in dyes.size():
		dyes[i].albedo_color = Color(0.16, 0.09, 0.035).linear_to_srgb() if ochre else original_tints[i]

func _apply_lighting() -> void:
	# Inspection presets only; imported material resources stay untouched.
	var energy: Vector3 = [Vector3(0.65, 1.7, 0.8), Vector3(0.12, 0.5, 0.12), Vector3(0.8, 2.2, 0.35)][lighting_index]
	review_environment.ambient_light_energy = energy.x
	review_lights[0].light_energy = energy.y
	review_lights[1].light_energy = energy.z
	review_lights[0].light_color = Color(0.72, 0.83, 1.0) if lighting_index == 1 else Color(1.0, 0.96, 0.88)
	print("INSPECT lighting=", ["studio", "dim interior", "daylight"][lighting_index])

func _set_clip(index: int) -> void:
	clip_index = posmod(index, CLIPS.size())
	animation.stop()
	skeleton.reset_bone_poses()
	elapsed = 0.0
	if clip_index > 0:
		animation.play(CLIPS[clip_index])
		animation.advance(0)
		animation.pause()
	print("INSPECT animation=", CLIPS[clip_index])

func _set_cut(index: int) -> void:
	cut_index = posmod(index, CUTS.size())
	if is_instance_valid(detached):
		# Release only detached-material references; keep the main model's dye.
		dyes.resize(1)
		original_tints.resize(1)
		detached.queue_free()
		detached = null
	for mesh: MeshInstance3D in meshes:
		mesh.visible = not (mask_hidden and mesh.name == &"mask_default")
	if cut_index == 0:
		return
	_set_clip(0)
	var cut: String = CUTS[cut_index]
	detached = (load(asset_root + "detached/detached_" + cut + ".glb") as PackedScene).instantiate()
	add_child(detached)
	_copy_dyes(detached)
	# The independent asset contains exactly the meshes to remove from the body.
	for limb: MeshInstance3D in detached.find_children("*", "MeshInstance3D", true, false):
		for mesh: MeshInstance3D in meshes:
			if mesh.name == limb.name:
				mesh.hide()
	var sign_x := 1.0 if cut.ends_with("L") else -1.0
	detached.position = Vector3(sign_x * 0.65, 0.05, 0.12)
	if cut == "neck": detached.position = Vector3(0.65, -0.4, 0.12)
	print("INSPECT independent detached=", cut)

func _process(delta: float) -> void:
	if replay:
		replay_time += delta
		if replay_time >= 4.0:
			replay_time = 0.0
			_set_clip(clip_index + 1)
	if clip_index > 0 and not paused:
		elapsed += delta
		var clip := animation.get_animation(CLIPS[clip_index])
		var sample := fmod(elapsed, clip.length) if clip.loop_mode != Animation.LOOP_NONE else minf(elapsed, clip.length)
		animation.seek(sample, true)
	_update_camera()
	status.text = "PLAYER GLB | %s | %.2fs | %s\nN/P action   Space pause   R rest   V view   T tint   M mask   D cut   F2 replay   Esc quit\nView: %s   Tint: %s   Mask: %s   Cut: %s\nL: full detail = %s | Left/Right: frame | B lighting: %s | Z close: %s\n1.60 m | %d triangles | %d bones | imported GLB" % [CLIPS[clip_index], elapsed, "PAUSED" if paused else "PLAYING", ["front", "side", "back", "3/4", "left hand", "right hand", "head", "fabric front", "hood back"][view_index], "ochre" if ochre else "green", "hidden" if mask_hidden else "visible", CUTS[cut_index], full_detail, ["studio", "dim interior", "daylight"][lighting_index], close_detail, triangle_count, skeleton.get_bone_count()]

func _update_camera() -> void:
	var target := Vector3(0, 0.88, 0)
	var offset: Vector3 = [Vector3(0, 0.1, 3.65), Vector3(3.65, 0.1, 0), Vector3(0, 0.1, -3.65), Vector3(2.5, 0.3, 3.0)][mini(view_index, 3)]
	if view_index in [4, 5]:
		var bone := skeleton.find_bone("hand.L" if view_index == 4 else "hand.R")
		target = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		offset = Vector3(0.38 if view_index == 4 else -0.38, 0.22, 0.62)
	elif view_index == 6:
		target = Vector3(0, 1.6, 0)
		offset = Vector3(0.3, 0.02, 0.8)
	elif view_index == 7:
		target = Vector3(0, 1.3, 0)
		offset = Vector3(0.25, 0.06, 1.4)
	elif view_index == 8:
		target = Vector3(0, 1.57, 0)
		offset = Vector3(0.3, 0.04, -0.85)
	camera.position = target + offset * (0.58 if close_detail else 1.0)
	camera.look_at(target)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_N: _set_clip(clip_index + 1)
		KEY_P: _set_clip(clip_index - 1)
		KEY_SPACE: paused = not paused
		KEY_R:
			_set_cut(0)
			_set_clip(0)
		KEY_V: view_index = (view_index + 1) % 9
		KEY_Z: close_detail = not close_detail
		KEY_B:
			lighting_index = (lighting_index + 1) % 3
			_apply_lighting()
		KEY_T:
			ochre = not ochre
			_apply_tint()
			print("INSPECT tint=", "ochre" if ochre else "green")
		KEY_M:
			mask_hidden = not mask_hidden
			for mesh: MeshInstance3D in meshes:
				if mesh.name == &"mask_default": mesh.visible = not mask_hidden
			print("INSPECT mask_hidden=", mask_hidden)
		KEY_D: _set_cut(cut_index + 1)
		KEY_L:
			full_detail = not full_detail
			get_viewport().mesh_lod_threshold = 0.0 if full_detail else 1.0
			print("INSPECT full_detail=", full_detail)
		KEY_LEFT, KEY_RIGHT:
			if clip_index > 0:
				paused = true
				var direction := 1.0 if event.keycode == KEY_RIGHT else -1.0
				elapsed = clampf(elapsed + direction / 30.0, 0, animation.get_animation(CLIPS[clip_index]).length)
				animation.seek(elapsed, true)
		KEY_F2:
			replay = not replay
			replay_time = 0.0

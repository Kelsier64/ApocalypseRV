extends SceneTree
## Isolated import contract; never instantiates the production player.
const MODEL = preload("res://assets/models/player_test_v020/player_export_test_v020.glb")
const CLIP := &"TEST_v020_POSE_SAMPLES"
var failures: Array[String] = []
var report: Dictionary = {}

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)

func _run() -> void:
	var model: Node3D = MODEL.instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = model.get_node("PLAYER_Rig/Skeleton3D")
	var animation: AnimationPlayer = model.get_node("AnimationPlayer")
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var bone_names: Array[String] = []
	var hierarchy: Dictionary = {}
	for i in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(i))
		bone_names.append(bone_name)
		hierarchy[bone_name] = skeleton.get_bone_parent(i)
		check(not bone_name.begins_with("CTRL") and not bone_name.begins_with("POLE"), "Control bones excluded")
	check(meshes.size() == 11, "All eleven meshes imported")
	check(skeleton.get_bone_count() == 41, "Exactly 41 deform bones imported")
	check(animation.get_animation_list() == PackedStringArray([CLIP]), "Only TEST clip imported")
	check(model.find_children("*", "Camera3D", true, false).is_empty(), "No asset cameras")
	check(model.find_children("*", "Light3D", true, false).is_empty(), "No asset lights")
	for node in model.find_children("*", "Node3D", true, false) + [model]:
		check(node.scale.distance_to(Vector3.ONE) < 0.0001 and node.basis.determinant() > 0.0, "Positive unit node scales")
	var vertices := 0
	var triangles := 0
	var surfaces := 0
	var materials: Dictionary = {}
	var mesh_report: Array = []
	for mesh: MeshInstance3D in meshes:
		check(mesh.skin != null and mesh.skin.get_bind_count() == 41, "Each mesh has complete Skin")
		check(mesh.get_node(mesh.skeleton) == skeleton, "Each mesh resolves to same Skeleton3D")
		for i in mesh.skin.get_bind_count():
			check(skeleton.find_bone(mesh.skin.get_bind_name(i)) >= 0, "All named skin binds resolve")
		mesh_report.append({"name": mesh.name, "skin_binds": mesh.skin.get_bind_count(), "surfaces": mesh.mesh.get_surface_count()})
		for surface in mesh.mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			vertices += verts.size()
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
			check(weights.size() == verts.size() * 4, "Four skin influences per vertex")
			for v in verts.size():
				var total := 0.0
				for k in 4:
					var weight: float = weights[v * 4 + k]
					check(weight >= 0.0 and is_finite(weight), "Weights finite and nonnegative")
					total += weight
				check(absf(total - 1.0) < 0.0001, "Weights normalized")
				check(normals[v].is_finite() and absf(normals[v].length() - 1.0) < 0.001, "Normals finite and normalized")
			var mat := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			check(mat != null, "Standard PBR material imported")
			if mat == null:
				continue
			materials[mat.resource_name] = {
				"roughness": mat.roughness, "metallic": mat.metallic,
				"transparency": mat.transparency, "cull_mode": mat.cull_mode,
				"texture_filter": mat.texture_filter,
				"base_color": [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, mat.albedo_color.a],
				"texture_size": [mat.albedo_texture.get_width(), mat.albedo_texture.get_height()] if mat.albedo_texture else [],
				"normal_map": mat.normal_enabled, "ao_map": mat.ao_enabled
			}
			check(mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Opaque materials")
			check(mat.metallic == 0.0 and not mat.normal_enabled and not mat.ao_enabled, "No added metallic, normal or AO maps")
			if "Mask_PureWhite" in mat.resource_name:
				# v019's approved constant is 0.9 linear RGB, despite its PureWhite name.
				var source_white := Color(0.9, 0.9, 0.9, 1.0).linear_to_srgb()
				check(mat.albedo_texture == null and mat.albedo_color.is_equal_approx(source_white), "Mask preserves approved source constant")
			else:
				check(mat.albedo_texture != null and mat.albedo_texture.get_size() == Vector2(512, 512), "512px base texture")
				check(mat.texture_filter in [BaseMaterial3D.TEXTURE_FILTER_LINEAR, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC], "Linear texture sampling")
	check(materials.size() == 5, "Five materials")
	check(triangles == 16222, "Triangle count preserved")
	var reference: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/player_import_v020/pose_reference.json"))
	var pose_results: Array = []
	animation.play(CLIP)
	for pose: Dictionary in reference:
		animation.seek(pose.time, true)
		skeleton.force_update_all_bone_transforms()
		var bounds := skin_bounds(meshes, skeleton)
		var low := Vector3(pose.min[0], pose.min[1], pose.min[2])
		var high := Vector3(pose.max[0], pose.max[1], pose.max[2])
		var error := maxf(bounds.position.distance_to(low), bounds.end.distance_to(high))
		check(error < 0.0002, "Blender/Godot posed bounds agree: " + pose.name)
		pose_results.append({"name": pose.name, "bounds_min": vec(bounds.position), "bounds_max": vec(bounds.end), "max_bound_error_m": error})
	var max_scale_error := 0.0
	var max_step := 0.0
	var previous: Array[Vector3] = []
	for frame in range(481):
		animation.seek(frame / 60.0, true)
		skeleton.force_update_all_bone_transforms()
		var current: Array[Vector3] = []
		for i in skeleton.get_bone_count():
			var pose := skeleton.get_bone_global_pose(i)
			check(pose.is_finite() and pose.basis.determinant() > 0.0, "Animation transforms remain finite and positive")
			max_scale_error = maxf(max_scale_error, pose.basis.get_scale().distance_to(Vector3.ONE))
			current.append(pose.origin)
			if not previous.is_empty():
				max_step = maxf(max_step, pose.origin.distance_to(previous[i]))
		previous = current
	check(max_scale_error < 0.0001, "No unexpected bone scale")
	check(max_step < 0.04, "No bone jumps in 60Hz TEST playback")
	var original: MeshInstance3D = model.get_node("PLAYER_Rig/Skeleton3D/PLAYER_Mesh")
	var original_resource := original.mesh
	var local_result: Dictionary = preload("res://tests/player_import_v020/local_view.gd").configure(model)
	var local: MeshInstance3D = model.get_node("PLAYER_Rig/Skeleton3D/TEST_LocalBodyView")
	check(original.mesh == original_resource and original.layers == 2, "Full original body retained for observers")
	check(local.skin == original.skin and local.layers == 4, "Local body uses unchanged skin on separate layer")
	check(local_result.local_hidden_head_triangles > 0 and local_result.local_visible_body_triangles + local_result.local_hidden_head_triangles == 11302, "Local view hides only head subset")
	check(original.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and local.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Full original casts shadow without duplicate shadow")
	check(local_result.local_shadow_proxies == 6, "Local camera has six shadow-only full head/body instances")
	report = {"godot": Engine.get_version_info().string, "configured_renderer": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(),
		"physics_backend": ProjectSettings.get_setting("physics/3d/physics_engine"), "bones": bone_names,
		"hierarchy": hierarchy, "meshes": mesh_report, "vertices": vertices, "triangles": triangles,
		"surfaces": surfaces, "materials": materials, "poses": pose_results,
		"animation_samples": 481, "max_bone_scale_error": max_scale_error,
		"max_bone_step_m_at_60hz": max_step, "local_view": local_result, "failures": failures}
	var file := FileAccess.open("res://docs/validation/player-v020/godot_audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	model.free()
	if failures.is_empty():
		print("PASS: player v020 import, materials, skin, pose bounds and 481 animation samples")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func skin_bounds(meshes: Array[Node], skeleton: Skeleton3D) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for mesh: MeshInstance3D in meshes:
		var binds: Array[Transform3D] = []
		for i in mesh.skin.get_bind_count():
			var index := skeleton.find_bone(mesh.skin.get_bind_name(i))
			binds.append(skeleton.get_bone_global_pose(index) * mesh.skin.get_bind_pose(i))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for i in vertices.size():
				var position := Vector3.ZERO
				for k in 4:
					position += (binds[bones[i * 4 + k]] * vertices[i]) * weights[i * 4 + k]
				low = low.min(position)
				high = high.max(position)
	return AABB(low, high - low)

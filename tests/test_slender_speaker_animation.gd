extends SceneTree
## Runtime import contract for the Slender Speaker rig.

const RIGGED_PATH := "res://assets/models/slender_speaker/slender_speaker_rigged.glb"
const ARM_IK := preload("res://enemies/slender_speaker/slender_speaker_arm_ik.gd")
const ARM_POSE_METRICS := preload("res://tests/support/slender_speaker_arm_pose_metrics.gd")
const PLAYER_CHEST_HEIGHT := 1.3596
const PLAYER_HOLD_HEIGHT := 12.48
const CLIP_CONTRACT := {
	"idle_play": {"length": 4.0, "loop": true},
	"scan": {"length": 4.0, "loop": true},
	"walk": {"length": 2.4, "loop": true},
	"run": {"length": 1.0, "loop": true},
	"turn_left": {"length": 1.2, "loop": true},
	"turn_right": {"length": 1.2, "loop": true},
	"smash": {"length": 4.8, "loop": false},
	"grab_miss": {"length": 2.0, "loop": false},
	"grab": {"length": 1.0, "loop": false},
	"hold": {"length": 0.6, "loop": true},
	"lift": {"length": 1.4, "loop": false},
	"crush": {"length": 0.4, "loop": false},
	"retract": {"length": 1.4, "loop": false},
	"review_hand_open": {"length": 1.0, "loop": false},
	"review_hand_fist": {"length": 1.0, "loop": false},
}

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, detail: String) -> void:
	if not condition and detail not in failures:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	check(FileAccess.file_exists(RIGGED_PATH), "Separate rigged GLB is present")
	if not FileAccess.file_exists(RIGGED_PATH):
		_finish()
		return
	var rigged_atlases := _embedded_png_images(RIGGED_PATH)
	check(rigged_atlases.size() == 6, "Runtime GLB embeds six texture atlases")
	for atlas: Image in rigged_atlases.values():
		check(atlas.get_width() == 2048 and atlas.get_height() == 2048,
			"Runtime embedded texture atlases are 2048 × 2048")
	check(_textures_use_nonnegative_texcoords(RIGGED_PATH),
		"Rigged GLB texture bindings use valid nonnegative texture-coordinate sets")

	var packed := load(RIGGED_PATH) as PackedScene
	check(packed != null, "Rigged GLB imports as a PackedScene")
	if packed == null:
		_finish()
		return
	var model := packed.instantiate() as Node3D
	check(model != null, "Rigged import has a Node3D root")
	if model == null:
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(model)
	await process_frame

	check(model.scale.x > 0.0 and model.scale.y > 0.0 and model.scale.z > 0.0 \
		and model.transform.basis.determinant() > 0.0,
		"Rigged model has a positive, non-reflected root scale")
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	check(skeletons.size() == 1, "Rigged import has one Skeleton3D")
	var players := model.find_children("*", "AnimationPlayer", true, false)
	check(players.size() == 1, "Rigged import has one AnimationPlayer")
	if skeletons.size() != 1 or players.size() != 1:
		world.free()
		_finish()
		return
	var skeleton := skeletons[0] as Skeleton3D
	var animation_player := players[0] as AnimationPlayer
	var animations := _animation_names(animation_player)
	var required_bones := _required_bones()
	var bone_indices: Dictionary = {}
	for bone_index in skeleton.get_bone_count():
		bone_indices[String(skeleton.get_bone_name(bone_index))] = bone_index
	for bone_name in required_bones:
		check(bone_indices.has(bone_name), "Required rig bone is imported: " + bone_name)
	for clip_name in CLIP_CONTRACT:
		check(animations.has(clip_name), "Required animation clip is imported: " + clip_name)

	var meshes: Array[MeshInstance3D] = []
	var triangles := 0
	var skinned_surface_count := 0
	var materials: Dictionary = {}
	var nail_mesh_count := 0
	var nail_uvs_valid := true
	var nails_use_keratin := true
	var hand_albedo_sample_count := 0
	var hand_albedo_min_rgb := INF
	var bounds := AABB()
	var has_bounds := false
	for node in _all_nodes(model):
		var groups := node.get_groups()
		for group in groups:
			check(not String(group).to_lower() in ["monster", "monsters", "enemy", "enemies"],
				"Imported visual stays outside gameplay actor groups")
		check(node.get_script() == null, "Imported rig nodes have no gameplay scripts")
		if node is not MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		meshes.append(mesh_instance)
		var is_nail_mesh := String(mesh_instance.name).to_lower().contains("nail")
		if is_nail_mesh:
			nail_mesh_count += 1
		if mesh_instance.mesh == null:
			continue
		for corner in 8:
			var box := mesh_instance.get_aabb()
			var point := mesh_instance.global_transform * (box.position + Vector3(
				box.size.x if (corner & 1) != 0 else 0.0,
				box.size.y if (corner & 2) != 0 else 0.0,
				box.size.z if (corner & 4) != 0 else 0.0))
			check(point.is_finite(), "Imported mesh bounds are finite")
			if not has_bounds:
				bounds = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(point)
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if is_nail_mesh:
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				nail_uvs_valid = nail_uvs_valid and uvs.size() == vertices.size()
				for uv in uvs:
					nail_uvs_valid = nail_uvs_valid and uv.is_finite() \
						and uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0
				var nail_material := mesh_instance.get_active_material(surface) as StandardMaterial3D
				nails_use_keratin = nails_use_keratin and nail_material != null \
					and nail_material.resource_name.contains("Dark_Keratin")
			triangles += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			var material := mesh_instance.get_active_material(surface)
			if material != null:
				materials[material.get_instance_id()] = true
			if String(mesh_instance.name) == "Body_Skin_Fingers":
				var skin_material := material as StandardMaterial3D
				if skin_material != null and skin_material.resource_name == "SS_Decayed_Skin":
					var hand_albedo_metrics := _sample_hand_albedo_uv_centroids(arrays, skin_material.albedo_texture)
					hand_albedo_sample_count += int(hand_albedo_metrics["count"])
					hand_albedo_min_rgb = minf(hand_albedo_min_rgb, float(hand_albedo_metrics["min_rgb"]))
			if mesh_instance.skin == null:
				continue
			skinned_surface_count += 1
			for bind_index in mesh_instance.skin.get_bind_count():
				check(skeleton.find_bone(mesh_instance.skin.get_bind_name(bind_index)) >= 0,
					"Skin bind names resolve against the imported skeleton")
			var bone_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			check(bone_weights.size() == vertices.size() * 4 and bone_ids.size() == vertices.size() * 4,
				"Skinned vertices use at most four influence slots")
			if bone_weights.size() != vertices.size() * 4 or bone_ids.size() != vertices.size() * 4:
				continue
			for vertex in vertices.size():
				var total := 0.0
				for influence in 4:
					var weight := bone_weights[vertex * 4 + influence]
					var bind_index := bone_ids[vertex * 4 + influence]
					check(is_finite(weight) and weight >= -0.0001, "Skin weights are finite and nonnegative")
					check(weight <= 0.0001 or (bind_index >= 0 and bind_index < mesh_instance.skin.get_bind_count()),
						"Every weighted skin slot resolves to a skin bind")
					total += weight
				check(absf(total - 1.0) <= 0.002, "Normalized skin weights sum to one")

	check(not meshes.is_empty(), "Rigged import contains mesh geometry")
	check(skinned_surface_count > 0, "Rigged character surfaces are actually skinned")
	for side in ["L", "R"]:
		_validate_forearm_midshaft_weights(meshes, skeleton, bone_indices, side)
	check(has_bounds and absf(bounds.size.y - 15.0) <= 0.03 and absf(bounds.position.y) <= 0.03,
		"Rigged model rests at Y=0 and measures 15 m tall")
	check(triangles <= 40000, "Rigged mesh stays within the 40,000-triangle budget")
	check(materials.size() <= 6, "Rigged model uses at most six runtime materials")
	check(nail_mesh_count > 0 and nail_uvs_valid,
		"Nail mesh imports with a finite, in-range UV0 for every vertex")
	check(nail_mesh_count > 0 and nails_use_keratin,
		"Nail mesh uses the imported dark-keratin material")
	check(hand_albedo_sample_count >= 1000 and is_finite(hand_albedo_min_rgb) and hand_albedo_min_rgb > 0.005,
		"Skin albedo samples at hand-triangle UV centroids are nonblack")
	print("SLENDER_HAND_ALBEDO_METRICS " + JSON.stringify({"triangle_samples": hand_albedo_sample_count,
		"minimum_max_rgb": hand_albedo_min_rgb}))
	print("SLENDER_RIG_METRICS " + JSON.stringify({"triangles": triangles, "materials": materials.size(),
		"bones": skeleton.get_bone_count(), "skinned_surfaces": skinned_surface_count}))
	check(not _has_gameplay_method(model), "Imported rig exposes no monster or death gameplay methods")
	animation_player.stop()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	_check_default_arm_abduction(model, skeleton, bone_indices, "rest")
	_check_default_hand_orientation(model, skeleton, bone_indices, "rest")

	if animations.size() >= CLIP_CONTRACT.size() and bone_indices.has("root"):
		for clip_name in ["idle_play", "scan", "walk", "run", "turn_left", "turn_right"]:
			if not animations.has(clip_name):
				continue
			var animation: Animation = animation_player.get_animation(animations[clip_name])
			for phase in [0.0, 0.25, 0.5, 0.75]:
				_sample_pose(animation_player, skeleton, animations[clip_name], animation.length * phase)
				_check_default_hand_orientation(model, skeleton, bone_indices,
					"%s@%.2f" % [clip_name, phase])
				if clip_name == "idle_play":
					_check_idle_arm_rest_position(model, skeleton, bone_indices,
						"%s@%.2f" % [clip_name, phase])
		var root_bone: int = bone_indices["root"]
		for clip_name in CLIP_CONTRACT:
			if not animations.has(clip_name):
				continue
			var animation_name: String = animations[clip_name]
			var animation := animation_player.get_animation(animation_name)
			var contract: Dictionary = CLIP_CONTRACT[clip_name]
			check(absf(animation.length - float(contract.length)) <= 0.025,
				"Clip length matches its authored contract: " + clip_name)
			check(animation.loop_mode == (Animation.LOOP_LINEAR if contract.loop else Animation.LOOP_NONE),
				"Clip loop policy matches its authored contract: " + clip_name)
			var sample_count := maxi(2, ceili(animation.length * 20.0))
			for sample in sample_count + 1:
				_sample_pose(animation_player, skeleton, animation_name, animation.length * float(sample) / sample_count)
				var root_pose := skeleton.get_bone_pose_position(root_bone)
				var root_rest := skeleton.get_bone_rest(root_bone).origin
				check(absf(root_pose.x - root_rest.x) <= 0.002 and absf(root_pose.z - root_rest.z) <= 0.002,
					"Root bone has no horizontal travel in " + clip_name)
				for bone_index in skeleton.get_bone_count():
					check(_transform_is_finite(skeleton.get_bone_global_pose(bone_index)),
						"Bone pose stays finite in " + clip_name)
		for pair in [["grab", "lift"], ["lift", "hold"], ["hold", "crush"], ["crush", "retract"]]:
			if not animations.has(pair[0]) or not animations.has(pair[1]):
				continue
			var first_animation: Animation = animation_player.get_animation(animations[pair[0]])
			var second_animation: Animation = animation_player.get_animation(animations[pair[1]])
			_sample_pose(animation_player, skeleton, animations[pair[0]], first_animation.length)
			var end_poses := _local_poses(skeleton)
			_sample_pose(animation_player, skeleton, animations[pair[1]], 0.0)
			var start_poses := _local_poses(skeleton)
			check(_poses_join(end_poses, start_poses, 0.08, 0.12),
				"Grasp sequence joins continuously at " + pair[0] + " → " + pair[1])
			if pair[0] == "grab":
				_print_hand_transition_metrics(animation_player, skeleton, animations, bone_indices, pair[0], pair[1])
		_validate_hand_orientation_continuity(animation_player, skeleton, animations, bone_indices,
			["grab", "lift", "crush", "retract"])
		_validate_grab_waist_and_lift(model, animation_player, skeleton, animations, bone_indices)
		_validate_grasp_joint_alignment(animation_player, skeleton, animations)
		_validate_palm_follow(animation_player, skeleton, animations, bone_indices)
		_print_smash_orientation_metrics(animation_player, skeleton, animations, bone_indices)
		_validate_locomotion_planting(model, animation_player, skeleton, animations, bone_indices,
			"walk", 2.4, 4.0, 0.60)
		_print_locomotion_limb_metrics(model, animation_player, skeleton, animations, bone_indices,
			"walk", 0.60)
		_print_gait_continuity_diagnostics(model, animation_player, skeleton, animations, bone_indices,
			"walk", 0.60)
		_validate_locomotion_planting(model, animation_player, skeleton, animations, bone_indices,
			"run", 1.0, 10.0, 0.50)
		_print_locomotion_limb_metrics(model, animation_player, skeleton, animations, bone_indices,
			"run", 0.50)
		_print_gait_continuity_diagnostics(model, animation_player, skeleton, animations, bone_indices,
			"run", 0.50)
		_validate_turn_planting(model, animation_player, skeleton, animations, bone_indices, "turn_left", 1.0)
		_validate_turn_planting(model, animation_player, skeleton, animations, bone_indices, "turn_right", -1.0)
		if animations.has("grab") and bone_indices.has("socket_grip_R"):
			var grab_animation: Animation = animation_player.get_animation(animations.grab)
			_print_grab_approach_metrics(model, animation_player, skeleton, animations, bone_indices)
			_sample_pose(animation_player, skeleton, animations.grab, grab_animation.length)
			var grip_bone: int = bone_indices["socket_grip_R"]
			var grip_world := skeleton.global_transform * skeleton.get_bone_global_pose(grip_bone)
			var grip_model_space := model.global_transform.affine_inverse() * grip_world
			check(absf(grip_model_space.origin.y - PLAYER_CHEST_HEIGHT) <= 0.025,
				"Right grip socket reaches the production player chest height at grab end")
			_check_palm_facing_target(skeleton, bone_indices, "R", grip_bone, "grab")
			_check_palm_facing_target(skeleton, bone_indices, "L", grip_bone, "grab")
			_check_mirrored_hand_flex(skeleton, bone_indices, "grab")
		if animations.has("hold") and bone_indices.has("socket_grip_R"):
			var hold_animation: Animation = animation_player.get_animation(animations.hold)
			_sample_pose(animation_player, skeleton, animations.hold, hold_animation.length * 0.5)
			_check_palm_facing_target(skeleton, bone_indices, "R", bone_indices["socket_grip_R"], "hold")
			_check_palm_facing_target(skeleton, bone_indices, "L", bone_indices["socket_grip_R"], "hold")
			_check_fingers_curl_toward_palm(skeleton, bone_indices, "R", "hold")
			_check_finger_curl_limits(skeleton, bone_indices, "R", "hold", 0.83, false)
			_check_fingers_curl_toward_palm(skeleton, bone_indices, "L", "hold")
			_check_finger_curl_limits(skeleton, bone_indices, "L", "hold", 0.83, false)
			_check_mirrored_hand_flex(skeleton, bone_indices, "hold")
			_check_left_hand_anatomy(model, skeleton, bone_indices, "hold")
			var held_socket := _world_bone_origin(skeleton, bone_indices["socket_grip_R"])
			var right_wrist := _world_bone_origin(skeleton, bone_indices["hand.R"])
			var right_wrist_to_socket := right_wrist.distance_to(held_socket)
			var right_socket_local := skeleton.get_bone_global_pose(bone_indices["hand.R"]).affine_inverse() \
				* skeleton.get_bone_global_pose(bone_indices["socket_grip_R"]).origin
			check(absf(right_wrist_to_socket - Vector3(0.22, 0.43, -0.70).length()) <= 0.02,
				"Right grip socket stays at its authored wrist offset during hold")
			var held_socket_model := model.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(bone_indices["socket_grip_R"]))
			check(absf(held_socket_model.origin.y - PLAYER_HOLD_HEIGHT) <= 0.025,
				"Held grip socket reaches the raised player chest height")
			print("SLENDER_GRIP_METRICS " + JSON.stringify({"pose": "hold", "wrist_to_socket_m": right_wrist_to_socket,
				"hand_local_socket_offset": [right_socket_local.x, right_socket_local.y, right_socket_local.z],
				"socket_height_m": held_socket_model.origin.y}))
		if animations.has("crush") and bone_indices.has("socket_grip_R"):
			var crush_animation: Animation = animation_player.get_animation(animations.crush)
			_sample_pose(animation_player, skeleton, animations.crush, 0.0)
			var open_wrists := _world_bone_origin(skeleton, bone_indices["hand.R"]).distance_to(_world_bone_origin(skeleton, bone_indices["hand.L"]))
			var open_elbows := _world_bone_origin(skeleton, bone_indices["forearm.R"]).distance_to(_world_bone_origin(skeleton, bone_indices["forearm.L"]))
			_sample_pose(animation_player, skeleton, animations.crush, crush_animation.length)
			var closed_wrists := _world_bone_origin(skeleton, bone_indices["hand.R"]).distance_to(_world_bone_origin(skeleton, bone_indices["hand.L"]))
			var closed_elbows := _world_bone_origin(skeleton, bone_indices["forearm.R"]).distance_to(_world_bone_origin(skeleton, bone_indices["forearm.L"]))
			check(open_wrists - closed_wrists >= 0.16 and open_wrists - closed_wrists <= 0.24,
				"Crush adds modest arm compression beyond finger flexion")
			check(open_elbows - closed_elbows > 0.02,
				"Both elbows close inward with the crushing hands")
			print("SLENDER_CRUSH_COMPRESSION " + JSON.stringify({"wrist_closure_m": open_wrists - closed_wrists, "elbow_closure_m": open_elbows - closed_elbows}))
			_validate_crush_arm_motion(animation_player, skeleton, animations.crush, bone_indices)
			var left_hand_bone: int = bone_indices.get("hand.L", -1)
			var grip_position := _world_bone_origin(skeleton, bone_indices["socket_grip_R"])
			if left_hand_bone >= 0:
				var left_to_grip := grip_position - _world_bone_origin(skeleton, left_hand_bone)
				var left_palm_alignment := _check_palm_facing_target(skeleton, bone_indices, "L",
					bone_indices["socket_grip_R"], "crush")
				_check_palm_facing_target(skeleton, bone_indices, "R", bone_indices["socket_grip_R"], "crush")
				_check_left_hand_anatomy(model, skeleton, bone_indices, "crush")
				_check_fingers_curl_toward_palm(skeleton, bone_indices, "L", "crush")
				_check_finger_curl_limits(skeleton, bone_indices, "L", "crush", 0.94, false)
				_check_fingers_curl_toward_palm(skeleton, bone_indices, "R", "crush")
				_check_finger_curl_limits(skeleton, bone_indices, "R", "crush", 0.94, false)
				_check_mirrored_hand_flex(skeleton, bone_indices, "crush")
				var left_wrist_to_socket := left_to_grip.length()
				print("SLENDER_GRIP_METRICS " + JSON.stringify({"pose": "crush", "left_wrist_to_socket_m": left_wrist_to_socket,
					"left_palm_alignment": left_palm_alignment}))
		if animations.has("review_hand_open") and animations.has("review_hand_fist"):
			var open_animation: Animation = animation_player.get_animation(animations.review_hand_open)
			_sample_pose(animation_player, skeleton, animations.review_hand_open, open_animation.length)
			_check_finger_curl_limits(skeleton, bone_indices, "R", "review_hand_open", 0.0, true)
			_check_finger_curl_limits(skeleton, bone_indices, "L", "review_hand_open", 0.0, true)
			var open_thumb_distance_R := _thumb_to_little_distance(skeleton, bone_indices, "R")
			var open_thumb_distance_L := _thumb_to_little_distance(skeleton, bone_indices, "L")
			var fist_animation: Animation = animation_player.get_animation(animations.review_hand_fist)
			_sample_pose(animation_player, skeleton, animations.review_hand_fist, fist_animation.length)
			var body_hand_mesh := model.find_child("Body_Skin_Fingers", true, false) as MeshInstance3D
			for side in ["R", "L"]:
				_check_full_fist_flex(skeleton, bone_indices, side)
				_check_fingers_curl_toward_palm(skeleton, bone_indices, side, "review_hand_fist")
				var hand_index: int = bone_indices["hand." + side]
				var palm_axis := _anatomical_palm_axis(skeleton, bone_indices, side)
				var palm_plane := Vector3.ZERO
				for finger in ["index", "middle", "ring", "little"]:
					palm_plane += _world_bone_origin(skeleton, bone_indices["finger_%s_01.%s" % [finger, side]])
				palm_plane *= 0.25
				var tip_depths: Array[float] = []
				var distal_lengths: Array[float] = []
				for finger in ["index", "middle", "ring", "little"]:
					var tip_data := _estimate_fingertip(skeleton, bone_indices, body_hand_mesh, finger, side, palm_axis, palm_plane)
					var tip_depth := float(tip_data.depth)
					tip_depths.append(tip_depth)
					distal_lengths.append(float(tip_data.length))
					check(is_finite(tip_depth) and tip_depth > 0.10 and tip_depth < 0.22,
						"%s %s fingertip stays within the full-fist palm-depth envelope" % [side, finger])
				print("SLENDER_FIST_DEPTH_METRICS " + JSON.stringify({"side": side,
					"tip_depth_from_mcp_plane_m": tip_depths, "distal_lengths_m": distal_lengths}))
			var fist_thumb_distance_R := _thumb_to_little_distance(skeleton, bone_indices, "R")
			var fist_thumb_distance_L := _thumb_to_little_distance(skeleton, bone_indices, "L")
			check(open_thumb_distance_R - fist_thumb_distance_R > 0.15,
				"Right thumb opposes across the palm from open hand to fist")
			check(open_thumb_distance_L - fist_thumb_distance_L > 0.15,
				"Left thumb opposes across the palm from open hand to fist")
			print("SLENDER_THUMB_METRICS " + JSON.stringify({"right_open_to_fist_m": [open_thumb_distance_R, fist_thumb_distance_R],
				"left_open_to_fist_m": [open_thumb_distance_L, fist_thumb_distance_L]}))

	world.free()
	await process_frame
	if failures.is_empty():
		print("PASS: Slender Speaker rig import, skin, sockets, animation poses and sequence continuity")
	_finish()

func _required_bones() -> Array[String]:
	var names: Array[String] = ["root", "pelvis", "spine", "chest", "neck", "speaker_center", "speaker_left", "speaker_right",
		"clavicle.L", "clavicle.R", "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R", "hand.L", "hand.R",
		"thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R", "socket_grip_R", "socket_focus", "socket_strike_R"]
	for side in ["L", "R"]:
		for finger in ["index", "middle", "ring", "little", "thumb"]:
			for segment in 3:
				names.append("finger_%s_%02d.%s" % [finger, segment + 1, side])
	return names

func _validate_forearm_midshaft_weights(meshes: Array[MeshInstance3D], skeleton: Skeleton3D,
		bone_indices: Dictionary, side: String) -> void:
	var forearm_name := "forearm." + side
	var forearm_index: int = bone_indices.get(forearm_name, -1)
	var hand_index: int = bone_indices.get("hand." + side, -1)
	if forearm_index < 0 or hand_index < 0:
		check(false, side + " forearm and hand bones exist for midshaft weight audit")
		return
	var forearm_rest := skeleton.get_bone_global_rest(forearm_index)
	var hand_rest := skeleton.get_bone_global_rest(hand_index)
	var shaft_length := forearm_rest.origin.distance_to(hand_rest.origin)
	var local_shaft_axis := (forearm_rest.basis.inverse() * (hand_rest.origin - forearm_rest.origin)).normalized()
	var sample_count := 0
	var max_distal_weight := 0.0
	var max_forearm_weight := 0.0
	for mesh_instance in meshes:
		var skin := mesh_instance.skin
		if skin == null:
			continue
		var forearm_bind := -1
		for bind_index in skin.get_bind_count():
			if String(skin.get_bind_name(bind_index)) == forearm_name:
				forearm_bind = bind_index
				break
		if forearm_bind < 0:
			continue
		var inverse_bind := skin.get_bind_pose(forearm_bind)
		for surface_index in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones.size() != vertices.size() * 4 or weights.size() != vertices.size() * 4:
				continue
			for vertex_index in vertices.size():
				var forearm_local_vertex := inverse_bind * vertices[vertex_index]
				var shaft_fraction := local_shaft_axis.dot(forearm_local_vertex) / shaft_length
				# Exclude shoulder-side and wrist-side blend zones; test only retained midshaft.
				if shaft_fraction < 0.20 or shaft_fraction > 0.75:
					continue
				var forearm_weight := 0.0
				var distal_weight := 0.0
				for slot in 4:
					var influence_index := vertex_index * 4 + slot
					var weight := weights[influence_index]
					if weight <= 0.0:
						continue
					var skin_bind_index := bones[influence_index]
					if skin_bind_index < 0 or skin_bind_index >= skin.get_bind_count():
						continue
					var influence_name := String(skin.get_bind_name(skin_bind_index))
					if influence_name == forearm_name:
						forearm_weight += weight
					elif influence_name == "hand." + side \
						or (influence_name.begins_with("finger_") and influence_name.ends_with("." + side)):
						distal_weight += weight
				if forearm_weight < 0.50:
					continue
				sample_count += 1
				max_forearm_weight = maxf(max_forearm_weight, forearm_weight)
				max_distal_weight = maxf(max_distal_weight, distal_weight)
	check(sample_count >= 8,
		"%s forearm has enough weighted vertices sampled along its retained midshaft" % side)
	check(max_distal_weight <= 0.01,
		"%s forearm midshaft is not influenced by hand or finger bones" % side)
	print("SLENDER_FOREARM_WEIGHT_METRICS " + JSON.stringify({"side": side,
		"shaft_length_m": shaft_length, "sample_count": sample_count,
		"max_forearm_weight": max_forearm_weight, "max_distal_weight": max_distal_weight,
		"shaft_fraction_range": [0.20, 0.75]}))

func _all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_all_nodes(child))
	return result

func _animation_names(player: AnimationPlayer) -> Dictionary:
	var result: Dictionary = {}
	for full_name in player.get_animation_list():
		var short_name := String(full_name).get_slice("/", String(full_name).get_slice_count("/") - 1)
		result[short_name] = String(full_name)
	return result

func _sample_pose(player: AnimationPlayer, skeleton: Skeleton3D, animation_name: String, time: float) -> void:
	player.play(animation_name, 0.0)
	player.seek(time, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()

func _check_default_arm_abduction(model: Node3D, skeleton: Skeleton3D, bone_indices: Dictionary,
		pose_name: String) -> void:
	for side in ["L", "R"]:
		var shoulder := _world_bone_origin(skeleton, bone_indices["upper_arm." + side])
		var elbow := _world_bone_origin(skeleton, bone_indices["forearm." + side])
		var arm_direction := (elbow - shoulder).normalized()
		var down := -model.global_basis.y.normalized()
		var angle := rad_to_deg(acos(clampf(arm_direction.dot(down), -1.0, 1.0)))
		var outward_axis := _torso_outward_axis(model, skeleton, bone_indices, side)
		var outward := arm_direction.dot(outward_axis)
		check(angle >= 30.0 and angle <= 60.0,
			"%s arm stays in a 30–60 degree A-pose abduction at %s" % [side, pose_name])
		check(outward > 0.25, "%s elbow points outward in the A-pose at %s" % [side, pose_name])
		print("SLENDER_A_POSE_METRICS " + JSON.stringify({"pose": pose_name,
			"side": side, "abduction_degrees": angle, "outward_dot": outward}))

func _check_default_hand_orientation(model: Node3D, skeleton: Skeleton3D, bone_indices: Dictionary,
		pose_name: String) -> void:
	for side in ["L", "R"]:
		var palm := _anatomical_palm_axis(skeleton, bone_indices, side)
		var inward := -_torso_outward_axis(model, skeleton, bone_indices, side)
		var inward_dot := palm.dot(inward)
		var radial := _anatomical_radial_axis(skeleton, bone_indices, side)
		var thumb_forward := radial.dot(model.global_basis.z.normalized())
		check(inward_dot > 0.25,
			"%s palm faces inward toward the torso at %s" % [side, pose_name])
		check(thumb_forward > 0.15,
			"%s thumb points generally forward at %s" % [side, pose_name])
		print("SLENDER_DEFAULT_HAND_METRICS " + JSON.stringify({"pose": pose_name, "side": side,
			"palm_inward_dot": inward_dot, "thumb_forward_dot": thumb_forward}))

func _check_idle_arm_rest_position(model: Node3D, skeleton: Skeleton3D, bone_indices: Dictionary,
		pose_name: String) -> void:
	var up := model.global_basis.y.normalized()
	for side in ["L", "R"]:
		var elbow := _world_bone_origin(skeleton, bone_indices["forearm." + side])
		var wrist := _world_bone_origin(skeleton, bone_indices["hand." + side])
		var chest := _world_bone_origin(skeleton, bone_indices["chest"])
		var outward := _torso_outward_axis(model, skeleton, bone_indices, side)
		var wrist_below_elbow := (wrist - elbow).dot(up)
		var wrist_lateral := (wrist - chest).dot(outward)
		var lateral_wrist_to_elbow := absf((wrist - elbow).dot(outward))
		check(wrist_below_elbow < -0.10,
			"%s idle wrist hangs below the elbow at %s" % [side, pose_name])
		check(wrist_lateral > 0.6 and wrist_lateral < 3.2 and lateral_wrist_to_elbow < 1.0,
			"%s idle wrist stays beside the torso at %s" % [side, pose_name])
		print("SLENDER_IDLE_ARM_METRICS " + JSON.stringify({"pose": pose_name, "side": side,
			"wrist_below_elbow_m": wrist_below_elbow, "wrist_lateral_from_chest_m": wrist_lateral,
			"wrist_elbow_lateral_delta_m": lateral_wrist_to_elbow}))

func _torso_outward_axis(model: Node3D, skeleton: Skeleton3D, bone_indices: Dictionary,
		side: String) -> Vector3:
	var shoulder := _world_bone_origin(skeleton, bone_indices["upper_arm." + side])
	var chest := _world_bone_origin(skeleton, bone_indices["chest"])
	var up := model.global_basis.y.normalized()
	var forward := model.global_basis.z.normalized()
	var outward := shoulder - chest
	outward = outward.slide(up).slide(forward)
	return outward.normalized()

func _check_palm_facing_target(skeleton: Skeleton3D, bone_indices: Dictionary, side: String,
		grip_bone: int, clip_name: String) -> float:
	var hand_bone: int = bone_indices.get("hand." + side, -1)
	if hand_bone < 0:
		return 0.0
	var midpoint := _hand_mcp_midpoint(skeleton, bone_indices, side)
	var to_grip := _world_bone_origin(skeleton, grip_bone) - midpoint
	var facing := _anatomical_palm_axis(skeleton, bone_indices, side).dot(to_grip.normalized())
	check(facing > 0.15, side + " palm faces the held target from its finger-root midpoint during " + clip_name)
	return facing

func _hand_mcp_midpoint(skeleton: Skeleton3D, bone_indices: Dictionary, side: String) -> Vector3:
	var midpoint := Vector3.ZERO
	var count := 0
	for finger in ["index", "middle", "ring", "little"]:
		var index: int = bone_indices.get("finger_%s_01.%s" % [finger, side], -1)
		if index >= 0:
			midpoint += _world_bone_origin(skeleton, index)
			count += 1
	return midpoint / float(count) if count > 0 else _world_bone_origin(skeleton, bone_indices.get("hand." + side, -1))

func _check_left_hand_anatomy(model: Node3D, skeleton: Skeleton3D, bone_indices: Dictionary,
		clip_name: String) -> void:
	var wrist := _world_bone_origin(skeleton, bone_indices["hand.L"])
	var index_mcp := _world_bone_origin(skeleton, bone_indices["finger_index_01.L"])
	var middle_mcp := _world_bone_origin(skeleton, bone_indices["finger_middle_01.L"])
	var little_mcp := _world_bone_origin(skeleton, bone_indices["finger_little_01.L"])
	var thumb_root := _world_bone_origin(skeleton, bone_indices["finger_thumb_01.L"])
	var hand_longitudinal := (middle_mcp - wrist).normalized()
	var radial := (index_mcp - little_mcp).slide(hand_longitudinal).normalized()
	var up := model.global_basis.y.normalized()
	var radial_up := radial.dot(up)
	var thumb_up := (thumb_root - _hand_mcp_midpoint(skeleton, bone_indices, "L")).normalized().dot(up)
	check(radial_up > 0.20, "Left index/radial side remains above the little-finger side during " + clip_name)
	check(thumb_up > 0.10, "Left thumb root points generally upward during " + clip_name)
	var roll_degrees := _left_wrist_roll_degrees(skeleton, bone_indices)
	check(is_finite(roll_degrees) and roll_degrees < 30.0,
		"Left wrist follows forearm twist within 30 degrees during " + clip_name)
	print("SLENDER_LEFT_HAND_ANATOMY " + JSON.stringify({"clip": clip_name,
		"radial_up_dot": radial_up, "thumb_up_dot": thumb_up, "wrist_roll_degrees": roll_degrees}))

func _left_wrist_roll_degrees(skeleton: Skeleton3D, bone_indices: Dictionary) -> float:
	return _wrist_roll_degrees(skeleton, bone_indices, "L")

func _wrist_roll_degrees(skeleton: Skeleton3D, bone_indices: Dictionary, side: String) -> float:
	var forearm_index: int = bone_indices["forearm." + side]
	var hand_index: int = bone_indices["hand." + side]
	var forearm_rest := skeleton.get_bone_global_rest(forearm_index)
	var hand_rest := skeleton.get_bone_global_rest(hand_index)
	var forearm_pose := skeleton.get_bone_global_pose(forearm_index)
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	var index_mcp_rest := skeleton.get_bone_global_rest(bone_indices["finger_index_01." + side]).origin
	var middle_mcp_rest := skeleton.get_bone_global_rest(bone_indices["finger_middle_01." + side]).origin
	var little_mcp_rest := skeleton.get_bone_global_rest(bone_indices["finger_little_01." + side]).origin
	var wrist_rest := hand_rest.origin
	var rest_hand_axis := (middle_mcp_rest - wrist_rest).normalized()
	var rest_radial := (index_mcp_rest - little_mcp_rest).slide(rest_hand_axis).normalized()
	var rest_forearm_axis := (hand_rest.origin - forearm_rest.origin).normalized()
	# Transport the rest hand's anatomical radial direction onto the forearm axis,
	# then carry that reference through the animated forearm and wrist bend.
	var rest_transport := Basis(Quaternion(rest_hand_axis, rest_forearm_axis))
	var forearm_radial_local := forearm_rest.basis.inverse() * (rest_transport * rest_radial)
	var posed_forearm_radial := (forearm_pose.basis * forearm_radial_local).normalized()
	var posed_forearm_axis := (hand_pose.origin - forearm_pose.origin).normalized()
	var posed_middle := skeleton.get_bone_global_pose(bone_indices["finger_middle_01." + side]).origin
	var posed_hand_axis := (posed_middle - hand_pose.origin).normalized()
	var wrist_bend := Basis(Quaternion(posed_forearm_axis, posed_hand_axis))
	var transported_radial := (wrist_bend * posed_forearm_radial).slide(posed_hand_axis).normalized()
	var posed_index := skeleton.get_bone_global_pose(bone_indices["finger_index_01." + side]).origin
	var posed_little := skeleton.get_bone_global_pose(bone_indices["finger_little_01." + side]).origin
	var measured_radial := (posed_index - posed_little).slide(posed_hand_axis).normalized()
	return rad_to_deg(acos(clampf(transported_radial.dot(measured_radial), -1.0, 1.0)))

func _arm_frame_roll_degrees(skeleton: Skeleton3D, bone_indices: Dictionary, side: String) -> float:
	var upper_rest := skeleton.get_bone_global_rest(bone_indices["upper_arm." + side])
	var lower_rest := skeleton.get_bone_global_rest(bone_indices["forearm." + side])
	var hand_rest := skeleton.get_bone_global_rest(bone_indices["hand." + side])
	var rest_hand_axis := (skeleton.get_bone_global_rest(bone_indices["finger_middle_01." + side]).origin - hand_rest.origin).normalized()
	var rest_radial := (skeleton.get_bone_global_rest(bone_indices["finger_index_01." + side]).origin
		- skeleton.get_bone_global_rest(bone_indices["finger_little_01." + side]).origin).slide(rest_hand_axis).normalized()
	var rest_lower_axis := (hand_rest.origin - lower_rest.origin).normalized()
	var rest_upper_axis := (lower_rest.origin - upper_rest.origin).normalized()
	var lower_reference := Basis(Quaternion(rest_hand_axis, rest_lower_axis)) * rest_radial
	var upper_reference := Basis(Quaternion(rest_lower_axis, rest_upper_axis)) * lower_reference
	var upper := skeleton.get_bone_global_pose(bone_indices["upper_arm." + side])
	var lower := skeleton.get_bone_global_pose(bone_indices["forearm." + side])
	var hand := skeleton.get_bone_global_pose(bone_indices["hand." + side])
	var upper_axis := (lower.origin - upper.origin).normalized()
	var lower_axis := (hand.origin - lower.origin).normalized()
	var upper_radial := (upper.basis * (upper_rest.basis.inverse() * upper_reference)).slide(upper_axis).normalized()
	var lower_radial := (lower.basis * (lower_rest.basis.inverse() * lower_reference)).slide(lower_axis).normalized()
	var transported := (Basis(Quaternion(upper_axis, lower_axis)) * upper_radial).slide(lower_axis).normalized()
	return rad_to_deg(acos(clampf(transported.dot(lower_radial), -1.0, 1.0)))

func _validate_grasp_joint_alignment(player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary) -> void:
	for clip_name in ["grab", "lift", "hold", "crush", "retract"]:
		if not animations.has(clip_name): continue
		var animation: Animation = player.get_animation(animations[clip_name])
		var samples := maxi(1, ceili(animation.length * 60.0))
		var metrics := ARM_POSE_METRICS.new_metrics()
		for tick in samples + 1:
			_sample_pose(player, skeleton, animations[clip_name], animation.length * float(tick) / samples)
			ARM_POSE_METRICS.observe(metrics, skeleton)
		check(metrics.upper_roll_degrees <= 110.0,
			clip_name + " avoids a shoulder half turn relative to the clavicle throughout the clip")
		check(metrics.elbow_plane_degrees <= 35.0,
			clip_name + " bends both elbows within their authored hinge planes throughout the clip")
		check(metrics.wrist_roll_degrees <= 30.0,
			clip_name + " keeps palm and forearm radial frames within 30 degrees throughout the clip")
		print("SLENDER_GRASP_JOINT_ALIGNMENT ", JSON.stringify({"clip": clip_name, "sample_rate_hz": 60, "maxima": metrics}))

func _validate_palm_follow(player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary) -> void:
	if not animations.has("grab"): return
	var grab: Animation = player.get_animation(animations.grab)
	for side in ["L", "R"]:
		_sample_pose(player, skeleton, animations.grab, grab.length)
		var hand_index: int = bone_indices["hand." + side]
		var hand_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
		hand_world.basis = Basis(Vector3.UP, PI * .5) * hand_world.basis
		var hand_pose := skeleton.global_transform.affine_inverse() * hand_world
		var parent_pose := skeleton.get_bone_global_pose(skeleton.get_bone_parent(hand_index))
		var hand_local := parent_pose.affine_inverse() * hand_pose
		skeleton.set_bone_pose_position(hand_index, hand_local.origin)
		skeleton.set_bone_pose_rotation(hand_index, hand_local.basis.get_rotation_quaternion())
		skeleton.force_update_all_bone_transforms()
		var roll_before := _wrist_roll_degrees(skeleton, bone_indices, side)
		check(roll_before > 45.0, side + " seated palm-follow fixture exercises a substantial wrist twist")
		var snapshot: Dictionary = {}
		for bone_name in bone_indices:
			if bone_name == "hand." + side or (String(bone_name).begins_with("finger_") and String(bone_name).ends_with("." + side)):
				snapshot[bone_name] = skeleton.global_transform * skeleton.get_bone_global_pose(bone_indices[bone_name])
		var shoulder := _world_bone_origin(skeleton, bone_indices["upper_arm." + side])
		var elbow := _world_bone_origin(skeleton, bone_indices["forearm." + side])
		var wrist := _world_bone_origin(skeleton, hand_index)
		var segment_lengths := Vector2(shoulder.distance_to(elbow), elbow.distance_to(wrist))
		ARM_IK.follow_palm(skeleton, side)
		var roll_after := _wrist_roll_degrees(skeleton, bone_indices, side)
		var arm_roll := _arm_frame_roll_degrees(skeleton, bone_indices, side)
		check(roll_after < 1.0 and arm_roll < 1.0,
			side + " palm follow carries the radial frame through wrist, forearm, and upper arm within one degree")
		var maximum_origin_change := 0.0
		var maximum_basis_change := 0.0
		for bone_name in snapshot:
			var before: Transform3D = snapshot[bone_name]
			var after := skeleton.global_transform * skeleton.get_bone_global_pose(bone_indices[bone_name])
			maximum_origin_change = maxf(maximum_origin_change, before.origin.distance_to(after.origin))
			for axis in 3: maximum_basis_change = maxf(maximum_basis_change, before.basis[axis].distance_to(after.basis[axis]))
		check(snapshot.size() >= 16 and maximum_origin_change <= .00002 and maximum_basis_change <= .00002,
			side + " palm follow preserves the hand and every finger world position and basis")
		var after_shoulder := _world_bone_origin(skeleton, bone_indices["upper_arm." + side])
		var after_elbow := _world_bone_origin(skeleton, bone_indices["forearm." + side])
		var after_wrist := _world_bone_origin(skeleton, hand_index)
		var after_lengths := Vector2(after_shoulder.distance_to(after_elbow), after_elbow.distance_to(after_wrist))
		check(shoulder.distance_to(after_shoulder) <= .00002 and elbow.distance_to(after_elbow) <= .00002
			and wrist.distance_to(after_wrist) <= .00002 and segment_lengths.distance_to(after_lengths) <= .00002,
			side + " palm follow rolls around the existing arm joints without changing segment lengths")
		for bone_name in ["upper_arm." + side, "forearm." + side, "hand." + side]:
			var pose := skeleton.get_bone_global_pose(bone_indices[bone_name])
			var scale := pose.basis.get_scale()
			check(_transform_is_finite(pose) and pose.basis.determinant() > 0.0 and scale.x > 0.0 and scale.y > 0.0 and scale.z > 0.0,
				side + " palm follow keeps finite positive arm scales without reflecting the anatomy")
		print("SLENDER_PALM_FOLLOW_METRICS " + JSON.stringify({"side": side, "hand_yaw_degrees": 90,
			"wrist_roll_before_degrees": roll_before, "wrist_roll_after_degrees": roll_after,
			"upper_forearm_roll_degrees": arm_roll, "preserved_hand_and_finger_bones": snapshot.size(),
			"maximum_origin_change_m": maximum_origin_change, "maximum_basis_column_change": maximum_basis_change,
			"maximum_segment_length_change_m": segment_lengths.distance_to(after_lengths)}))

func _validate_crush_arm_motion(player: AnimationPlayer, skeleton: Skeleton3D,
		animation_name: String, bone_indices: Dictionary) -> void:
	var animation := player.get_animation(animation_name)
	var samples := maxi(1, ceili(animation.length * 60.0))
	var first_positions: Dictionary = {}
	var previous_positions: Dictionary = {}
	var previous_rotations: Dictionary = {}
	var closures: Dictionary = {}
	var maximum_outward_step := 0.0
	var maximum_position_step := 0.0
	var maximum_rotation_step := 0.0
	var minimum_wrist_gap := INF
	for sample_index in samples + 1:
		_sample_pose(player, skeleton, animation_name, animation.length * float(sample_index) / samples)
		for side in ["R", "L"]:
			var inward_sign := 1.0 if side == "R" else -1.0
			for part in ["upper_arm", "forearm", "hand"]:
				var bone_name: String = part + "." + side
				var pose := skeleton.get_bone_global_pose(bone_indices[bone_name])
				var position := pose.origin
				var rotation := pose.basis.get_rotation_quaternion().normalized()
				if sample_index == 0:
					first_positions[bone_name] = position
				else:
					maximum_rotation_step = maxf(maximum_rotation_step,
						rad_to_deg(previous_rotations[bone_name].angle_to(rotation)))
					if part != "upper_arm":
						var movement: Vector3 = position - previous_positions[bone_name]
						maximum_outward_step = maxf(maximum_outward_step, -movement.x * inward_sign)
						maximum_position_step = maxf(maximum_position_step, movement.length())
				previous_positions[bone_name] = position
				previous_rotations[bone_name] = rotation
				closures[bone_name] = (position.x - first_positions[bone_name].x) * inward_sign
		minimum_wrist_gap = minf(minimum_wrist_gap,
			previous_positions["hand.L"].x - previous_positions["hand.R"].x)
	check(maximum_outward_step <= 0.001,
		"Both crush wrists and elbows contract monotonically instead of recoiling before impact")
	for side in ["R", "L"]:
		check(closures["hand." + side] >= 0.08 and closures["hand." + side] <= 0.12,
			"Crush moves the " + side + " wrist inward by a modest visible amount")
		check(closures["forearm." + side] > 0.02,
			"Crush brings the " + side + " elbow inward with the palm")
	check(absf(closures["hand.R"] - closures["hand.L"]) < 0.01,
		"Crush uses balanced bilateral wrist pressure")
	check(minimum_wrist_gap > 0.5, "Crush hands remain on opposite sides of the held torso")
	check(maximum_position_step < 0.06 and maximum_rotation_step < 10.0,
		"Crush arm compression stays smooth without an elbow or shoulder flip")
	print("SLENDER_CRUSH_ARM_MOTION " + JSON.stringify({"sample_rate_hz": 60,
		"inward_closure_m": closures, "maximum_outward_step_m": maximum_outward_step,
		"maximum_position_step_m": maximum_position_step, "maximum_rotation_step_degrees": maximum_rotation_step,
		"minimum_wrist_gap_m": minimum_wrist_gap}))

func _validate_hand_orientation_continuity(player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary, clip_names: Array[String]) -> void:
	const MAX_STEP_DEGREES := 45.0
	for clip_name in clip_names:
		if not animations.has(clip_name):
			continue
		var animation: Animation = player.get_animation(animations[clip_name])
		var sample_count := maxi(1, ceili(animation.length * 60.0))
		var max_step := 0.0
		var finite := true
		var bone_steps: Dictionary = {}
		for side_bone in ["forearm.L", "hand.L", "forearm.R", "hand.R"]:
			var bone_index: int = bone_indices.get(side_bone, -1)
			if bone_index < 0:
				continue
			var previous_rotation: Quaternion
			var has_previous := false
			var bone_max_step := 0.0
			var bone_max_step_time := 0.0
			for sample_index in sample_count + 1:
				var time := animation.length * float(sample_index) / float(sample_count)
				_sample_pose(player, skeleton, animations[clip_name], time)
				var transform := skeleton.get_bone_global_pose(bone_index)
				if not _transform_is_finite(transform):
					finite = false
					continue
				var rotation := transform.basis.get_rotation_quaternion().normalized()
				if not (is_finite(rotation.x) and is_finite(rotation.y) and is_finite(rotation.z) and is_finite(rotation.w)):
					finite = false
					continue
				if has_previous:
					var step := rad_to_deg(previous_rotation.angle_to(rotation))
					if not is_finite(step):
						finite = false
					else:
						max_step = maxf(max_step, step)
						if step > bone_max_step:
							bone_max_step = step
							bone_max_step_time = time
				previous_rotation = rotation
				has_previous = true
			bone_steps[side_bone] = {"maximum_step_degrees": bone_max_step,
				"maximum_step_time_s": bone_max_step_time}
		check(finite, "Both hand and forearm transforms stay finite across " + clip_name)
		check(max_step < MAX_STEP_DEGREES,
			"Both hand and forearm avoid abrupt orientation jumps across " + clip_name)
		print("SLENDER_HAND_CONTINUITY_METRICS " + JSON.stringify({"clip": clip_name,
			"sample_rate_hz": 60, "max_step_degrees": max_step, "bones": bone_steps}))

func _print_smash_orientation_metrics(player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary) -> void:
	if not animations.has("smash"):
		return
	var animation: Animation = player.get_animation(animations.smash)
	var sample_count := maxi(1, ceili(animation.length * 120.0))
	var bones := ["clavicle.L", "upper_arm.L", "forearm.L", "hand.L",
		"clavicle.R", "upper_arm.R", "forearm.R", "hand.R"]
	var previous_global: Dictionary = {}
	var previous_local: Dictionary = {}
	var peaks: Dictionary = {}
	for sample_index in sample_count + 1:
		var time := animation.length * float(sample_index) / float(sample_count)
		_sample_pose(player, skeleton, animations.smash, time)
		for bone_name in bones:
			var bone_index: int = bone_indices.get(bone_name, -1)
			if bone_index < 0:
				continue
			var global_rotation := skeleton.get_bone_global_pose(bone_index).basis.get_rotation_quaternion().normalized()
			var local_rotation := skeleton.get_bone_pose_rotation(bone_index).normalized()
			if previous_global.has(bone_name):
				var global_step := rad_to_deg(previous_global[bone_name].angle_to(global_rotation))
				var local_step := rad_to_deg(previous_local[bone_name].angle_to(local_rotation))
				var peak: Dictionary = peaks.get(bone_name,
					{"global_degrees": 0.0, "global_time": 0.0, "local_degrees": 0.0, "local_time": 0.0})
				if global_step > float(peak.global_degrees):
					peak.global_degrees = global_step
					peak.global_time = time
				if local_step > float(peak.local_degrees):
					peak.local_degrees = local_step
					peak.local_time = time
				peaks[bone_name] = peak
			previous_global[bone_name] = global_rotation
			previous_local[bone_name] = local_rotation
	print("SLENDER_SMASH_ORIENTATION_DIAGNOSTICS " + JSON.stringify({"sample_rate_hz": 120,
		"max_step_by_bone": peaks}))
	for bone_name in ["upper_arm.L", "forearm.L", "upper_arm.R", "forearm.R"]:
		var peak: Dictionary = peaks.get(bone_name, {})
		check(float(peak.get("global_degrees", INF)) < 8.0,
			"Smash global %s orientation changes by less than 8° per 120 Hz sample" % bone_name)
		check(float(peak.get("local_degrees", INF)) < 8.0,
			"Smash local %s orientation changes by less than 8° per 120 Hz sample" % bone_name)

func _print_locomotion_limb_metrics(model: Node3D, player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary, clip_name: String, stance_duty: float) -> void:
	if not animations.has(clip_name):
		return
	var animation: Animation = player.get_animation(animations[clip_name])
	var sample_count := 40
	var results: Dictionary = {}
	for side in ["R", "L"]:
		var phase_offset := 0.0 if side == "R" else 0.5
		var side_result: Dictionary = {}
		for phase_name in ["stance", "swing"]:
			side_result[phase_name] = {"wrist_below_elbow_min_m": INF,
				"wrist_below_elbow_max_m": -INF, "elbow_flex_min_degrees": INF,
				"elbow_flex_max_degrees": -INF, "knee_flex_min_degrees": INF,
				"knee_flex_max_degrees": -INF}
		for sample_index in sample_count:
			var root_phase := float(sample_index) / float(sample_count)
			var foot_phase := fposmod(root_phase + phase_offset, 1.0)
			var phase_name := "stance" if foot_phase < stance_duty else "swing"
			_sample_pose(player, skeleton, animations[clip_name], animation.length * root_phase)
			var shoulder := _world_bone_origin(skeleton, bone_indices["upper_arm." + side])
			var elbow := _world_bone_origin(skeleton, bone_indices["forearm." + side])
			var wrist := _world_bone_origin(skeleton, bone_indices["hand." + side])
			var hip := _world_bone_origin(skeleton, bone_indices["thigh." + side])
			var knee := _world_bone_origin(skeleton, bone_indices["shin." + side])
			var ankle := _world_bone_origin(skeleton, bone_indices["foot." + side])
			var wrist_height := (wrist - elbow).dot(model.global_basis.y.normalized())
			var elbow_flex := rad_to_deg(acos(clampf((elbow - shoulder).normalized().dot((wrist - elbow).normalized()), -1.0, 1.0)))
			var knee_flex := 180.0 - rad_to_deg(acos(clampf((hip - knee).normalized().dot((ankle - knee).normalized()), -1.0, 1.0)))
			var data: Dictionary = side_result[phase_name]
			data.wrist_below_elbow_min_m = minf(float(data.wrist_below_elbow_min_m), wrist_height)
			data.wrist_below_elbow_max_m = maxf(float(data.wrist_below_elbow_max_m), wrist_height)
			data.elbow_flex_min_degrees = minf(float(data.elbow_flex_min_degrees), elbow_flex)
			data.elbow_flex_max_degrees = maxf(float(data.elbow_flex_max_degrees), elbow_flex)
			data.knee_flex_min_degrees = minf(float(data.knee_flex_min_degrees), knee_flex)
			data.knee_flex_max_degrees = maxf(float(data.knee_flex_max_degrees), knee_flex)
			side_result[phase_name] = data
		for phase_name in ["stance", "swing"]:
			var phase_metrics: Dictionary = side_result[phase_name]
			var knee_limit := 60.0 if clip_name == "walk" else 80.0
			check(float(phase_metrics.wrist_below_elbow_max_m) < 0.0,
				"%s wrist remains below elbow during %s %s" % [side, clip_name, phase_name])
			check(float(phase_metrics.elbow_flex_max_degrees) < 30.0,
				"%s elbow flex stays below 30° during %s %s" % [side, clip_name, phase_name])
			check(float(phase_metrics.knee_flex_max_degrees) < knee_limit,
				"%s knee flex stays below %.0f° during %s %s" % [side, knee_limit, clip_name, phase_name])
		results[side] = side_result
	print("SLENDER_GAIT_LIMB_DIAGNOSTICS " + JSON.stringify({"clip": clip_name,
		"stance_duty": stance_duty, "sample_count": sample_count, "ranges": results}))

func _print_gait_continuity_diagnostics(model: Node3D, player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary, clip_name: String, stance_duty: float) -> void:
	if not animations.has(clip_name):
		return
	const SAMPLE_RATE := 120.0
	var animation: Animation = player.get_animation(animations[clip_name])
	var duration := animation.length
	var sample_count := maxi(2, ceili(duration * SAMPLE_RATE))
	var dt := 1.0 / SAMPLE_RATE
	var observed_bones: Array[String] = ["root", "pelvis", "chest", "neck", "speaker_center", "foot.L", "foot.R"]
	if bone_indices.has("head"):
		observed_bones.append("head")
	var samples: Dictionary = {}
	var rotations: Dictionary = {}
	for bone_name in observed_bones:
		if bone_indices.has(bone_name):
			samples[bone_name] = []
			rotations[bone_name] = []
	for sample_index in sample_count:
		var time := duration * float(sample_index) / float(sample_count)
		_sample_pose(player, skeleton, animations[clip_name], time)
		for bone_name in samples:
			var index: int = bone_indices[bone_name]
			samples[bone_name].append(_world_bone_origin(skeleton, index))
			rotations[bone_name].append(skeleton.get_bone_global_pose(index).basis.get_rotation_quaternion().normalized())
	var ranges: Dictionary = {}
	for bone_name in samples:
		var points: Array = samples[bone_name]
		var max_speed := 0.0
		var max_acceleration := 0.0
		var max_velocity_delta := 0.0
		var velocities: Array[Vector3] = []
		var angular_velocities: Array[float] = []
		for sample_index in sample_count:
			var previous_index := (sample_index - 1 + sample_count) % sample_count
			var current_position: Vector3 = points[sample_index]
			var previous_position: Vector3 = points[previous_index]
			var velocity: Vector3 = (current_position - previous_position) / dt
			velocities.append(velocity)
			max_speed = maxf(max_speed, velocity.length())
			var current_rotation: Quaternion = rotations[bone_name][sample_index]
			var previous_rotation: Quaternion = rotations[bone_name][previous_index]
			angular_velocities.append(rad_to_deg(previous_rotation.angle_to(current_rotation)) / dt)
		for sample_index in sample_count:
			var previous_index := (sample_index - 1 + sample_count) % sample_count
			var velocity_delta: float = (velocities[sample_index] - velocities[previous_index]).length()
			max_acceleration = maxf(max_acceleration, velocity_delta / dt)
			max_velocity_delta = maxf(max_velocity_delta, velocity_delta)
		var max_angular_speed := 0.0
		var max_angular_acceleration := 0.0
		for sample_index in sample_count:
			var previous_index := (sample_index - 1 + sample_count) % sample_count
			max_angular_speed = maxf(max_angular_speed, angular_velocities[sample_index])
			max_angular_acceleration = maxf(max_angular_acceleration,
				absf(angular_velocities[sample_index] - angular_velocities[previous_index]) / dt)
		var seam_start: Vector3 = points[0]
		var seam_previous: Vector3 = points[sample_count - 1]
		var seam_pose_step: float = seam_start.distance_to(seam_previous)
		var seam_velocity_delta: float = (velocities[1] - velocities[sample_count - 1]).length()
		var seam_angular_velocity_delta := absf(angular_velocities[1] - angular_velocities[sample_count - 1])
		ranges[bone_name] = {"peak_speed_mps": max_speed,
			"peak_frame_acceleration_mps2": max_acceleration,
			"peak_frame_velocity_delta_mps": max_velocity_delta,
			"peak_angular_speed_degrees_per_second": max_angular_speed,
			"peak_frame_angular_acceleration_degrees_per_second2": max_angular_acceleration,
			"last_sample_to_first_sample_m": seam_pose_step,
			"seam_velocity_delta_mps": seam_velocity_delta,
			"seam_angular_velocity_delta_degrees_per_second": seam_angular_velocity_delta}
		if bone_name in ["root", "pelvis", "chest", "speaker_center"]:
			check(seam_velocity_delta <= 0.10,
				"%s stays velocity-continuous across the %s gait loop seam" % [bone_name, clip_name])
		if bone_name.begins_with("foot."):
			var seam_limit := 3.0 if clip_name == "run" else 0.8
			check(seam_velocity_delta <= seam_limit,
				"%s foot velocity stays continuous across the %s gait loop seam" % [clip_name, bone_name])
	var transitions: Array[Dictionary] = []
	var max_foot_transition_jump := 0.0
	var max_body_transition_jump := 0.0
	for side in ["R", "L"]:
		var phase_offset := 0.0 if side == "R" else 0.5
		for boundary_name in ["stance_to_swing", "swing_to_stance"]:
			var foot_phase := stance_duty if boundary_name == "stance_to_swing" else 0.0
			var root_phase := fposmod(foot_phase - phase_offset, 1.0)
			var boundary_time := root_phase * duration
			var foot_index: int = bone_indices["foot." + side]
			var pelvis_index: int = bone_indices["pelvis"]
			var body_index: int = bone_indices["chest"]
			var foot_before := _sample_bone_origin(player, skeleton, animations[clip_name], foot_index,
				fposmod(boundary_time - dt, duration))
			var foot_at := _sample_bone_origin(player, skeleton, animations[clip_name], foot_index, boundary_time)
			var foot_after := _sample_bone_origin(player, skeleton, animations[clip_name], foot_index,
				fposmod(boundary_time + dt, duration))
			var pelvis_before := _sample_bone_origin(player, skeleton, animations[clip_name], pelvis_index,
				fposmod(boundary_time - dt, duration))
			var pelvis_at := _sample_bone_origin(player, skeleton, animations[clip_name], pelvis_index, boundary_time)
			var pelvis_after := _sample_bone_origin(player, skeleton, animations[clip_name], pelvis_index,
				fposmod(boundary_time + dt, duration))
			var chest_before := _sample_bone_origin(player, skeleton, animations[clip_name], body_index,
				fposmod(boundary_time - dt, duration))
			var chest_at := _sample_bone_origin(player, skeleton, animations[clip_name], body_index, boundary_time)
			var chest_after := _sample_bone_origin(player, skeleton, animations[clip_name], body_index,
				fposmod(boundary_time + dt, duration))
			var foot_velocity_before := (foot_at - foot_before) / dt
			var foot_velocity_after := (foot_after - foot_at) / dt
			var pelvis_velocity_before := (pelvis_at - pelvis_before) / dt
			var pelvis_velocity_after := (pelvis_after - pelvis_at) / dt
			var chest_velocity_before := (chest_at - chest_before) / dt
			var chest_velocity_after := (chest_after - chest_at) / dt
			transitions.append({"side": side, "boundary": boundary_name, "phase": foot_phase,
				"time_s": boundary_time,
				"foot_velocity_before_mps": [foot_velocity_before.x, foot_velocity_before.y, foot_velocity_before.z],
				"foot_velocity_after_mps": [foot_velocity_after.x, foot_velocity_after.y, foot_velocity_after.z],
				"foot_velocity_jump_mps": foot_velocity_before.distance_to(foot_velocity_after),
				"pelvis_velocity_jump_mps": pelvis_velocity_before.distance_to(pelvis_velocity_after),
				"chest_velocity_jump_mps": chest_velocity_before.distance_to(chest_velocity_after)})
			max_foot_transition_jump = maxf(max_foot_transition_jump,
				foot_velocity_before.distance_to(foot_velocity_after))
			max_body_transition_jump = maxf(max_body_transition_jump,
				maxf(pelvis_velocity_before.distance_to(pelvis_velocity_after),
					chest_velocity_before.distance_to(chest_velocity_after)))
	var foot_transition_limit := 3.0 if clip_name == "run" else 0.8
	check(max_foot_transition_jump <= foot_transition_limit,
		"%s foot velocity remains smooth at stance/swing boundaries (max delta %.3f m/s)" \
		% [clip_name, max_foot_transition_jump])
	check(max_body_transition_jump <= 0.10,
		"%s pelvis/chest velocity remains continuous at stance/swing boundaries" % clip_name)
	print("SLENDER_GAIT_120HZ_DIAGNOSTICS " + JSON.stringify({"clip": clip_name,
		"duration_s": duration, "sample_rate_hz": SAMPLE_RATE, "stance_duty": stance_duty,
		"body_and_foot_velocity_ranges": ranges, "contact_swing_transitions": transitions,
		"max_foot_transition_velocity_jump_mps": max_foot_transition_jump,
		"max_body_transition_velocity_jump_mps": max_body_transition_jump}))

func _sample_bone_origin(player: AnimationPlayer, skeleton: Skeleton3D, animation_name: String,
		bone_index: int, time: float) -> Vector3:
	_sample_pose(player, skeleton, animation_name, time)
	return _world_bone_origin(skeleton, bone_index)

func _grab_body_angles(model: Node3D, skeleton: Skeleton3D, bone_indices: Dictionary) -> Dictionary:
	var up := model.global_basis.y.normalized()
	var forward := model.global_basis.z.normalized()
	var torso := (_world_bone_origin(skeleton, bone_indices["neck"])
		- _world_bone_origin(skeleton, bone_indices["chest"])).normalized()
	var result := {"torso_forward_degrees": rad_to_deg(atan2(torso.dot(forward), torso.dot(up)))}
	for side in ["L", "R"]:
		var hip := _world_bone_origin(skeleton, bone_indices["thigh." + side])
		var knee := _world_bone_origin(skeleton, bone_indices["shin." + side])
		var ankle := _world_bone_origin(skeleton, bone_indices["foot." + side])
		result["knee_" + side] = rad_to_deg((knee - hip).angle_to(ankle - knee))
		result["hip_" + side] = rad_to_deg(torso.angle_to((hip - knee).normalized()))
	return result

func _validate_grab_waist_and_lift(model: Node3D, player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary) -> void:
	if not animations.has("grab") or not animations.has("lift") or not animations.has("idle_play"):
		return
	var grab: Animation = player.get_animation(animations.grab)
	var lift: Animation = player.get_animation(animations.lift)
	_sample_pose(player, skeleton, animations.idle_play, 0.0)
	var idle_pelvis := skeleton.get_bone_pose_rotation(bone_indices["pelvis"])
	var idle_spine := skeleton.get_bone_pose_rotation(bone_indices["spine"])
	var idle_wrists := {"L": _world_bone_origin(skeleton, bone_indices["hand.L"]),
		"R": _world_bone_origin(skeleton, bone_indices["hand.R"])}
	_sample_pose(player, skeleton, animations.grab, grab.length)
	var bent := _grab_body_angles(model, skeleton, bone_indices)
	var pelvis_bend := rad_to_deg(idle_pelvis.angle_to(skeleton.get_bone_pose_rotation(bone_indices["pelvis"])))
	var spine_bend := rad_to_deg(idle_spine.angle_to(skeleton.get_bone_pose_rotation(bone_indices["spine"])))
	check(bent.torso_forward_degrees >= 45.0 and bent.torso_forward_degrees <= 90.0,
		"Ground grab bends the torso forward at the waist without inverting it")
	check(pelvis_bend >= 35.0 and spine_bend >= 10.0,
		"Ground grab uses both a visible hip hinge and a supporting spine bend")
	for side in ["L", "R"]:
		check(bent["knee_" + side] >= 5.0 and bent["knee_" + side] <= 45.0,
			"Ground grab keeps the " + side + " knee bend modest")
		check(bent["hip_" + side] >= 35.0 and bent["hip_" + side] > bent["knee_" + side],
			"Ground grab bends more at the " + side + " hip than the knee")
		var wrist := _world_bone_origin(skeleton, bone_indices["hand." + side])
		var elbow := _world_bone_origin(skeleton, bone_indices["forearm." + side])
		check((idle_wrists[side] - wrist).dot(model.global_basis.y.normalized()) > 1.0
			and (elbow - wrist).dot(model.global_basis.y.normalized()) > 0.5,
			"Ground grab reaches down with the " + side + " wrist below its elbow")
	var planted_feet: Dictionary = {}
	var maximum_foot_drift := 0.0
	var maximum_foot_rotation := 0.0
	var maximum_position_step := 0.0
	var maximum_rotation_step := 0.0
	var maximum_socket_downstep := 0.0
	var maximum_straightening_backstep := 0.0
	var previous_positions: Dictionary = {}
	var previous_rotations: Dictionary = {}
	var previous_socket_height := 0.0
	var previous_torso_lean := 0.0
	var sampled_angles: Array[Dictionary] = []
	var observed_bones := ["pelvis", "spine", "chest", "neck", "forearm.L", "forearm.R", "hand.L", "hand.R", "socket_grip_R"]
	for clip_name in ["grab", "lift"]:
		var animation: Animation = player.get_animation(animations[clip_name])
		var sample_count := maxi(1, ceili(animation.length * 60.0))
		for sample_index in sample_count + 1:
			var fraction := float(sample_index) / sample_count
			_sample_pose(player, skeleton, animations[clip_name], animation.length * fraction)
			for side in ["L", "R"]:
				var foot := skeleton.global_transform * skeleton.get_bone_global_pose(bone_indices["foot." + side])
				if not planted_feet.has(side):
					planted_feet[side] = foot
				var planted: Transform3D = planted_feet[side]
				maximum_foot_drift = maxf(maximum_foot_drift, planted.origin.distance_to(foot.origin))
				maximum_foot_rotation = maxf(maximum_foot_rotation, rad_to_deg(
					planted.basis.get_rotation_quaternion().angle_to(foot.basis.get_rotation_quaternion())))
			for bone_name in observed_bones:
				var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone_indices[bone_name])
				var rotation := pose.basis.get_rotation_quaternion().normalized()
				if previous_positions.has(bone_name):
					maximum_position_step = maxf(maximum_position_step, pose.origin.distance_to(previous_positions[bone_name]))
					maximum_rotation_step = maxf(maximum_rotation_step,
						rad_to_deg(previous_rotations[bone_name].angle_to(rotation)))
				previous_positions[bone_name] = pose.origin
				previous_rotations[bone_name] = rotation
			var angles := _grab_body_angles(model, skeleton, bone_indices)
			var socket_height: float = (previous_positions["socket_grip_R"] - model.global_position).dot(
				model.global_basis.y.normalized())
			if clip_name == "lift" and sample_index > 0:
				maximum_socket_downstep = maxf(maximum_socket_downstep, previous_socket_height - socket_height)
				maximum_straightening_backstep = maxf(maximum_straightening_backstep,
					angles.torso_forward_degrees - previous_torso_lean)
			previous_socket_height = socket_height
			previous_torso_lean = angles.torso_forward_degrees
			if sample_index in [0, sample_count / 2, sample_count]:
				angles["clip"] = clip_name
				angles["fraction"] = fraction
				angles["socket_height_m"] = socket_height
				sampled_angles.append(angles)
				_check_mirrored_hand_flex(skeleton, bone_indices, "%s@%.2f" % [clip_name, fraction])
	check(maximum_foot_drift <= 0.04 and maximum_foot_rotation <= 3.0,
		"Both feet stay planted and level throughout the waist bend and lift")
	check(maximum_position_step <= 0.40 and maximum_rotation_step <= 10.0,
		"Grab and lift avoid abrupt torso, wrist, or grip motion at 60 Hz")
	check(maximum_socket_downstep <= 0.015,
		"Lift raises the held chest continuously without dropping it between frames")
	check(maximum_straightening_backstep <= 1.0 and absf(previous_torso_lean) <= 15.0,
		"Lift gradually straightens the torso to the raised hold pose")
	var maximum_join_velocity_jump := 0.0
	var join_velocity_jumps: Dictionary = {}
	const VELOCITY_INTERVAL := 0.03
	for bone_name in observed_bones:
		var index: int = bone_indices[bone_name]
		var before := _sample_bone_origin(player, skeleton, animations.grab, index, grab.length - VELOCITY_INTERVAL)
		var contact := _sample_bone_origin(player, skeleton, animations.grab, index, grab.length)
		var after := _sample_bone_origin(player, skeleton, animations.lift, index, VELOCITY_INTERVAL)
		var jump := ((contact - before) / VELOCITY_INTERVAL).distance_to((after - contact) / VELOCITY_INTERVAL)
		join_velocity_jumps[bone_name] = jump
		maximum_join_velocity_jump = maxf(maximum_join_velocity_jump, jump)
	check(maximum_join_velocity_jump <= 1.0,
		"Waist bend and lift join with continuous torso and hand velocity")
	print("SLENDER_WAIST_LIFT_METRICS " + JSON.stringify({"sample_rate_hz": 60,
		"contact_angles_degrees": bent, "pelvis_bend_degrees": pelvis_bend, "spine_bend_degrees": spine_bend,
		"maximum_foot_drift_m": maximum_foot_drift, "maximum_foot_rotation_degrees": maximum_foot_rotation,
		"maximum_position_step_m": maximum_position_step, "maximum_rotation_step_degrees": maximum_rotation_step,
		"maximum_socket_downstep_m": maximum_socket_downstep,
		"maximum_straightening_backstep_degrees": maximum_straightening_backstep,
		"maximum_join_velocity_jump_mps": maximum_join_velocity_jump,
		"join_velocity_jumps_mps": join_velocity_jumps, "samples": sampled_angles}))

func _print_grab_approach_metrics(model: Node3D, player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary) -> void:
	if not animations.has("grab") or not animations.has("idle_play"):
		return
	var grab: Animation = player.get_animation(animations.grab)
	_sample_pose(player, skeleton, animations.idle_play, 0.0)
	var idle_left := _world_bone_origin(skeleton, bone_indices["hand.L"])
	var idle_right := _world_bone_origin(skeleton, bone_indices["hand.R"])
	var rows: Array[Dictionary] = []
	var early_left_displacement := 0.0
	var early_right_displacement := 0.0
	var contact_left_distance := INF
	for fraction in [0.0, 0.05, 0.10, 0.20, 0.35, 0.50, 0.75, 1.0]:
		var time: float = grab.length * float(fraction)
		_sample_pose(player, skeleton, animations.grab, time)
		var grip := _world_bone_origin(skeleton, bone_indices["socket_grip_R"])
		var left := _world_bone_origin(skeleton, bone_indices["hand.L"])
		var right := _world_bone_origin(skeleton, bone_indices["hand.R"])
		if is_equal_approx(float(fraction), 0.10):
			early_left_displacement = left.distance_to(idle_left)
			early_right_displacement = right.distance_to(idle_right)
		if is_equal_approx(float(fraction), 1.0):
			contact_left_distance = left.distance_to(grip)
		rows.append({"fraction": fraction,
			"left_displacement_from_idle_m": left.distance_to(idle_left),
			"right_displacement_from_idle_m": right.distance_to(idle_right),
			"left_wrist_to_grip_m": left.distance_to(grip),
			"right_wrist_to_grip_m": right.distance_to(grip)})
	check(early_left_displacement > 0.10 and early_right_displacement > 0.10,
		"Both hands begin reaching during the first tenth of grab")
	check(absf(early_left_displacement - early_right_displacement) < 0.15,
		"Both hands approach together during the first tenth of grab")
	check(contact_left_distance < 1.2,
		"Left hand reaches the grip area by the end of grab")
	print("SLENDER_GRAB_APPROACH_DIAGNOSTICS " + JSON.stringify({"samples": rows}))

func _print_hand_transition_metrics(player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary, first_name: String, second_name: String) -> void:
	var first: Animation = player.get_animation(animations[first_name])
	var second: Animation = player.get_animation(animations[second_name])
	_sample_pose(player, skeleton, animations[first_name], first.length)
	var end_poses: Dictionary = {}
	for bone_name in ["upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"]:
		var index: int = bone_indices.get(bone_name, -1)
		if index >= 0:
			end_poses[bone_name] = skeleton.get_bone_global_pose(index)
	_sample_pose(player, skeleton, animations[second_name], 0.0)
	var deltas: Dictionary = {}
	for bone_name in end_poses:
		var index: int = bone_indices[bone_name]
		var start: Transform3D = skeleton.get_bone_global_pose(index)
		var finish: Transform3D = end_poses[bone_name]
		deltas[bone_name] = {"position_m": start.origin.distance_to(finish.origin),
			"rotation_degrees": rad_to_deg(start.basis.get_rotation_quaternion().angle_to(finish.basis.get_rotation_quaternion()))}
	print("SLENDER_GRASP_TRANSITION_DIAGNOSTICS " + JSON.stringify({"from": first_name,
		"to": second_name, "bone_deltas": deltas}))

func _check_fingers_curl_toward_palm(skeleton: Skeleton3D, bone_indices: Dictionary,
		side: String, clip_name: String) -> void:
	var hand_bone: int = bone_indices.get("hand." + side, -1)
	if hand_bone < 0:
		return
	var palm_axis := _anatomical_palm_axis(skeleton, bone_indices, side)
	for finger in ["index", "middle", "ring", "little"]:
		var first_bone: int = bone_indices.get("finger_%s_01.%s" % [finger, side], -1)
		var second_bone: int = bone_indices.get("finger_%s_02.%s" % [finger, side], -1)
		if first_bone < 0 or second_bone < 0:
			continue
		var proximal_direction := (_world_bone_origin(skeleton, second_bone)
			- _world_bone_origin(skeleton, first_bone)).normalized()
		var curl_dot := palm_axis.dot(proximal_direction)
		check(curl_dot > 0.0,
			"%s %s finger curls toward the palm during %s" % [side, finger, clip_name])

func _check_mirrored_hand_flex(skeleton: Skeleton3D, bone_indices: Dictionary, clip_name: String) -> void:
	var maximum_difference := 0.0
	var compared_segments := 0
	for finger in ["index", "middle", "ring", "little", "thumb"]:
		var segment_count := 3 if finger != "thumb" else 2
		for segment in range(1, segment_count + 1):
			var right_name := "finger_%s_%02d.R" % [finger, segment]
			var left_name := "finger_%s_%02d.L" % [finger, segment]
			var right_index: int = bone_indices.get(right_name, -1)
			var left_index: int = bone_indices.get(left_name, -1)
			if right_index < 0 or left_index < 0:
				continue
			var right_rest := skeleton.get_bone_rest(right_index).basis.get_rotation_quaternion()
			var left_rest := skeleton.get_bone_rest(left_index).basis.get_rotation_quaternion()
			var right_angle := right_rest.angle_to(skeleton.get_bone_pose_rotation(right_index))
			var left_angle := left_rest.angle_to(skeleton.get_bone_pose_rotation(left_index))
			maximum_difference = maxf(maximum_difference, absf(right_angle - left_angle))
			compared_segments += 1
	check(compared_segments >= 14,
		"Both hands expose the expected mirrored finger chains during " + clip_name)
	check(maximum_difference <= 0.12,
		"Left and right grasp flex stay anatomically mirrored during %s (max %.3f rad)" % [clip_name, maximum_difference])
	print("SLENDER_MIRRORED_HAND_FLEX " + JSON.stringify({"clip": clip_name,
		"segments_compared": compared_segments, "max_angle_difference_rad": maximum_difference}))

func _check_full_fist_flex(skeleton: Skeleton3D, bone_indices: Dictionary, side: String) -> void:
	for finger in ["index", "middle", "ring", "little"]:
		var chain_angle := 0.0
		for segment in range(1, 4):
			var bone_index: int = bone_indices.get("finger_%s_%02d.%s" % [finger, segment, side], -1)
			if bone_index < 0:
				continue
			var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
			var angle := rest_rotation.angle_to(skeleton.get_bone_pose_rotation(bone_index))
			chain_angle += angle
			check(angle > 0.25 and angle < 2.35,
				"%s %s phalanx %d stays flexed without an extreme fold in the full fist" % [side, finger, segment])
		check(chain_angle > 2.75 and chain_angle < 5.9,
			"%s %s finger chain forms a closed curl in the full fist" % [side, finger])

func _check_finger_curl_limits(skeleton: Skeleton3D, bone_indices: Dictionary,
		side: String, clip_name: String, curl: float, is_open: bool) -> void:
	var segment_limits: Array[float] = [1.30, 1.60, 0.85]
	var total_segment_limit := segment_limits[0] + segment_limits[1] + segment_limits[2]
	for finger in ["index", "middle", "ring", "little"]:
		var chain_angle := 0.0
		for segment in range(1, 4):
			var bone_name := "finger_%s_%02d.%s" % [finger, segment, side]
			var bone_index: int = bone_indices.get(bone_name, -1)
			if bone_index < 0:
				continue
			var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
			var pose_rotation := skeleton.get_bone_pose_rotation(bone_index)
			var angle := rest_rotation.angle_to(pose_rotation)
			chain_angle += angle
			if is_open:
				check(angle <= 0.04, "%s %s finger segment %d stays straight in %s" % [side, finger, segment, clip_name])
			else:
				var expected_angle := segment_limits[segment - 1] * curl
				check(absf(angle - expected_angle) <= 0.06,
					"%s %s finger segment %d follows its authored bend in %s" % [side, finger, segment, clip_name])
		if not is_open:
			check(chain_angle <= total_segment_limit * curl + 0.12,
				"%s %s finger chain stays within its bend budget in %s" % [side, finger, clip_name])

func _thumb_to_little_distance(skeleton: Skeleton3D, bone_indices: Dictionary, side: String) -> float:
	var hand_bone: int = bone_indices.get("hand." + side, -1)
	var thumb_bone: int = bone_indices.get("finger_thumb_03." + side, -1)
	var little_bone: int = bone_indices.get("finger_little_01." + side, -1)
	if hand_bone < 0 or thumb_bone < 0 or little_bone < 0:
		return INF
	var hand_inverse := skeleton.get_bone_global_pose(hand_bone).affine_inverse()
	var thumb_local := hand_inverse * skeleton.get_bone_global_pose(thumb_bone).origin
	var little_local := hand_inverse * skeleton.get_bone_global_pose(little_bone).origin
	return thumb_local.distance_to(little_local)

func _estimate_fingertip(skeleton: Skeleton3D, bone_indices: Dictionary, mesh_instance: MeshInstance3D,
		finger: String, side: String, palm_axis: Vector3, palm_plane: Vector3) -> Dictionary:
	if mesh_instance == null or mesh_instance.skin == null:
		return {"depth": -INF, "length": 0.0}
	var distal_name := "finger_%s_03.%s" % [finger, side]
	var second_name := "finger_%s_02.%s" % [finger, side]
	var distal_index: int = bone_indices.get(distal_name, -1)
	var second_index: int = bone_indices.get(second_name, -1)
	if distal_index < 0 or second_index < 0:
		return {"depth": -INF, "length": 0.0}
	var bind_index := -1
	for candidate in mesh_instance.skin.get_bind_count():
		if mesh_instance.skin.get_bind_name(candidate) == distal_name:
			bind_index = candidate
			break
	if bind_index < 0:
		return {"depth": -INF, "length": 0.0}
	var distal_rest := skeleton.get_bone_global_rest(distal_index)
	var second_rest := skeleton.get_bone_global_rest(second_index)
	var local_axis := (distal_rest.basis.inverse() * (distal_rest.origin - second_rest.origin).normalized()).normalized()
	var inverse_bind := mesh_instance.skin.get_bind_pose(bind_index)
	var distal_length := 0.0
	for surface in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		if weights.size() != vertices.size() * 4 or bones.size() != vertices.size() * 4:
			continue
		for vertex_index in vertices.size():
			var influence := vertex_index * 4
			for slot in 4:
				if bones[influence + slot] == bind_index and weights[influence + slot] >= 0.75:
					var bone_local_vertex := inverse_bind * vertices[vertex_index]
					distal_length = maxf(distal_length, local_axis.dot(bone_local_vertex))
	var distal_axis_world := skeleton.global_transform.basis \
		* skeleton.get_bone_global_pose(distal_index).basis * local_axis
	var tip_world := _world_bone_origin(skeleton, distal_index) + distal_axis_world.normalized() * distal_length
	return {"depth": palm_axis.dot(tip_world - palm_plane), "length": distal_length}

func _anatomical_palm_axis(skeleton: Skeleton3D, bone_indices: Dictionary, side: String) -> Vector3:
	var middle := _world_bone_origin(skeleton, bone_indices["finger_middle_01." + side])
	var longitudinal := (middle - _world_bone_origin(skeleton, bone_indices["hand." + side])).normalized()
	var radial := _anatomical_radial_axis(skeleton, bone_indices, side)
	var normal := radial.cross(longitudinal) if side == "R" else longitudinal.cross(radial)
	return normal.normalized()

func _anatomical_radial_axis(skeleton: Skeleton3D, bone_indices: Dictionary, side: String) -> Vector3:
	var wrist := _world_bone_origin(skeleton, bone_indices["hand." + side])
	var middle := _world_bone_origin(skeleton, bone_indices["finger_middle_01." + side])
	var index := _world_bone_origin(skeleton, bone_indices["finger_index_01." + side])
	var little := _world_bone_origin(skeleton, bone_indices["finger_little_01." + side])
	var longitudinal := (middle - wrist).normalized()
	return (index - little).slide(longitudinal).normalized()

func _world_bone_origin(skeleton: Skeleton3D, bone_index: int) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin

func _validate_locomotion_planting(model: Node3D, player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary, clip_name: String, duration: float,
		speed: float, stance_duty: float) -> void:
	if not animations.has(clip_name):
		return
	var root_bone: int = bone_indices.get("root", -1)
	if root_bone < 0:
		return
	var animation_name: String = animations[clip_name]
	var root_rest := skeleton.get_bone_rest(root_bone).origin
	var forward := model.global_basis.z.normalized()
	var margin := minf(0.06, stance_duty * 0.15)
	var sample_phases: Array[float] = []
	var max_horizontal_drift := 0.0
	var max_vertical_drift := 0.0
	var planting_passed := true
	for sample_index in 5:
		sample_phases.append(lerpf(margin, stance_duty - margin, float(sample_index) / 4.0))
	for side: String in ["R", "L"]:
		var foot_name := "foot." + side
		var foot_bone: int = bone_indices.get(foot_name, -1)
		if foot_bone < 0:
			continue
		var phase_offset := 0.0 if side == "R" else 0.5
		var previous_phase := -INF
		var reference_contact := Vector3.ZERO
		var has_reference := false
		for stance_phase in sample_phases:
			var root_phase := stance_phase - phase_offset
			while root_phase < 0.0:
				root_phase += 1.0
			if root_phase < previous_phase:
				root_phase += 1.0
			previous_phase = root_phase
			var unwrapped_time := root_phase * duration
			_sample_pose(player, skeleton, animation_name, fposmod(unwrapped_time, duration))
			var root_position := skeleton.get_bone_pose_position(root_bone)
			var root_fixed := root_position.distance_to(root_rest) <= 0.002
			check(root_fixed,
				"Root remains fixed throughout the " + clip_name + " locomotion cycle")
			planting_passed = planting_passed and root_fixed
			var foot_world := skeleton.global_transform * skeleton.get_bone_global_pose(foot_bone)
			var contact_position := foot_world.origin + forward * speed * unwrapped_time
			var foot_finite := _transform_is_finite(foot_world)
			check(foot_finite, "Foot pose stays finite during " + clip_name + " stance")
			planting_passed = planting_passed and foot_finite
			if not has_reference:
				reference_contact = contact_position
				has_reference = true
			else:
				var horizontal_drift := Vector2(contact_position.x - reference_contact.x,
					contact_position.z - reference_contact.z).length()
				var horizontal_ok := horizontal_drift <= 0.04
				check(horizontal_ok,
					clip_name + " " + side + " foot stays planted within 4 cm")
				max_horizontal_drift = maxf(max_horizontal_drift, horizontal_drift)
				var vertical_drift := absf(contact_position.y - reference_contact.y)
				var vertical_ok := vertical_drift <= 0.025
				check(vertical_ok,
					clip_name + " " + side + " foot stays level within 2.5 cm (observed " \
					+ ("%.4f" % vertical_drift) + " m at stance phase " + ("%.3f" % stance_phase) \
					+ " (y " + ("%.4f" % reference_contact.y) + "→" + ("%.4f" % contact_position.y) + ")")
				max_vertical_drift = maxf(max_vertical_drift, vertical_drift)
				planting_passed = planting_passed and horizontal_ok and vertical_ok
	if planting_passed:
		print("SLENDER_PLANT_METRICS " + JSON.stringify({
			"clip": clip_name,
			"speed_mps": speed,
			"stance_duty": stance_duty,
			"max_horizontal_drift_m": max_horizontal_drift,
			"max_vertical_drift_m": max_vertical_drift
		}))

func _validate_turn_planting(model: Node3D, player: AnimationPlayer, skeleton: Skeleton3D,
		animations: Dictionary, bone_indices: Dictionary, clip_name: String, turn_sign: float) -> void:
	if not animations.has(clip_name):
		return
	var root_bone: int = bone_indices.get("root", -1)
	if root_bone < 0:
		return
	const duration := 1.2
	const turn_rate := deg_to_rad(75.0)
	const stance_duty := 0.5
	const margin := 0.06
	var sample_phases: Array[float] = []
	for sample_index in 5:
		sample_phases.append(lerpf(margin, stance_duty - margin, float(sample_index) / 4.0))
	var animation_name: String = animations[clip_name]
	var root_rest := skeleton.get_bone_rest(root_bone).origin
	var max_drift := 0.0
	var planting_passed := true
	for side: String in ["R", "L"]:
		var foot_bone: int = bone_indices.get("foot." + side, -1)
		if foot_bone < 0:
			continue
		var phase_offset := 0.0 if side == "R" else 0.5
		var reference_contact := Vector3.ZERO
		var has_reference := false
		for stance_phase in sample_phases:
			var root_phase := stance_phase - phase_offset
			while root_phase < 0.0:
				root_phase += 1.0
			var sample_time := root_phase * duration
			_sample_pose(player, skeleton, animation_name, sample_time)
			var root_fixed := skeleton.get_bone_pose_position(root_bone).distance_to(root_rest) <= 0.002
			check(root_fixed, "Root remains fixed throughout " + clip_name)
			planting_passed = planting_passed and root_fixed
			var foot_pose := skeleton.get_bone_global_pose(foot_bone)
			var foot_model_position := (model.global_transform.affine_inverse()
				* skeleton.global_transform * foot_pose).origin
			var controller_basis := Basis(Vector3.UP, turn_sign * turn_rate * sample_time)
			var contact_position := model.global_position + controller_basis * model.global_basis * foot_model_position
			if not has_reference:
				reference_contact = contact_position
				has_reference = true
			else:
				var drift := contact_position.distance_to(reference_contact)
				max_drift = maxf(max_drift, drift)
				var planted := drift <= 0.025
				check(planted, clip_name + " " + side + " foot stays planted within 2.5 cm")
				planting_passed = planting_passed and planted
	if planting_passed:
		print("SLENDER_TURN_METRICS " + JSON.stringify({
			"clip": clip_name,
			"turn_rate_degrees_per_second": 75.0,
			"max_foot_drift_m": max_drift
		}))

func _local_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bone_index in skeleton.get_bone_count():
		poses.append(Transform3D(Basis(skeleton.get_bone_pose_rotation(bone_index)).scaled(
			skeleton.get_bone_pose_scale(bone_index)), skeleton.get_bone_pose_position(bone_index)))
	return poses

func _poses_join(first: Array[Transform3D], second: Array[Transform3D], position_epsilon: float, angle_epsilon: float) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if first[index].origin.distance_to(second[index].origin) > position_epsilon:
			return false
		if first[index].basis.get_rotation_quaternion().angle_to(second[index].basis.get_rotation_quaternion()) > angle_epsilon:
			return false
		if first[index].basis.get_scale().distance_to(second[index].basis.get_scale()) > 0.04:
			return false
	return true

func _transform_is_finite(transform: Transform3D) -> bool:
	return transform.origin.is_finite() and transform.basis.x.is_finite() and transform.basis.y.is_finite() and transform.basis.z.is_finite()

func _embedded_png_images(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 28 or bytes.decode_u32(0) != 0x46546C67:
		return {}
	var json_length := bytes.decode_u32(12)
	if json_length <= 0 or 20 + json_length > bytes.size():
		return {}
	var json_bytes := bytes.slice(20, 20 + json_length)
	while not json_bytes.is_empty() and json_bytes[json_bytes.size() - 1] == 0:
		json_bytes.resize(json_bytes.size() - 1)
	var document: Variant = JSON.parse_string(json_bytes.get_string_from_utf8())
	if not document is Dictionary:
		return {}
	var binary_header := 20 + json_length
	if binary_header + 8 > bytes.size():
		return {}
	var binary_length := bytes.decode_u32(binary_header)
	var binary_start := binary_header + 8
	if binary_start + binary_length > bytes.size():
		return {}
	var views: Array = document.get("bufferViews", [])
	var images: Dictionary = {}
	for image_data: Variant in document.get("images", []):
		if not image_data is Dictionary or image_data.get("mimeType", "") != "image/png":
			continue
		var view_index: int = image_data.get("bufferView", -1)
		if view_index < 0 or view_index >= views.size():
			continue
		var view: Dictionary = views[view_index]
		var start := binary_start + int(view.get("byteOffset", 0))
		var length: int = view.get("byteLength", 0)
		if length <= 0 or start + length > binary_start + binary_length:
			continue
		var image := Image.new()
		if image.load_png_from_buffer(bytes.slice(start, start + length)) != OK:
			continue
		image.convert(Image.FORMAT_RGBA8)
		images[String(image_data.get("name", ""))] = image
	return images

func _sample_hand_albedo_uv_centroids(arrays: Array, texture: Texture2D) -> Dictionary:
	if texture == null:
		return {"count": 0, "min_rgb": INF}
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {"count": 0, "min_rgb": INF}
	# Desktop import may return a GPU-compressed image. Pixel sampling needs
	# decompression before format conversion; keep failures visible as no samples.
	if image.is_compressed() and image.decompress() != OK:
		return {"count": 0, "min_rgb": INF}
	image.convert(Image.FORMAT_RGBA8)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if uvs.size() != vertices.size():
		return {"count": 0, "min_rgb": INF}
	var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	var sample_count := 0
	var min_rgb := INF
	for triangle in triangle_count:
		var i0 := indices[triangle * 3] if not indices.is_empty() else triangle * 3
		var i1 := indices[triangle * 3 + 1] if not indices.is_empty() else triangle * 3 + 1
		var i2 := indices[triangle * 3 + 2] if not indices.is_empty() else triangle * 3 + 2
		var uv := (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
		# Blender's V is bottom-origin; the imported GLTF UVs are flipped into
		# Godot's image sampling coordinates, so the hand patch is y=.09-.22.
		if uv.x < 0.25 or uv.x > 0.465 or uv.y < 0.09 or uv.y > 0.22:
			continue
		var color := _sample_image_bilinear(image, uv)
		var max_rgb := maxf(color.r, maxf(color.g, color.b))
		min_rgb = minf(min_rgb, max_rgb)
		sample_count += 1
	return {"count": sample_count, "min_rgb": min_rgb}

func _sample_image_bilinear(image: Image, uv: Vector2) -> Color:
	# Image.get_pixel uses the same top-left origin and texel filtering convention as Godot's UV sampling.
	var x := uv.x * image.get_width() - 0.5
	var y := uv.y * image.get_height() - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var tx := x - x0
	var ty := y - y0
	var x1 := x0 + 1
	var y1 := y0 + 1
	x0 = clampi(x0, 0, image.get_width() - 1)
	x1 = clampi(x1, 0, image.get_width() - 1)
	y0 = clampi(y0, 0, image.get_height() - 1)
	y1 = clampi(y1, 0, image.get_height() - 1)
	var top := image.get_pixel(x0, y0).lerp(image.get_pixel(x1, y0), tx)
	var bottom := image.get_pixel(x0, y1).lerp(image.get_pixel(x1, y1), tx)
	return top.lerp(bottom, ty)

func _textures_use_nonnegative_texcoords(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20 or bytes.decode_u32(0) != 0x46546C67:
		return false
	var json_length := bytes.decode_u32(12)
	if json_length <= 0 or 20 + json_length > bytes.size():
		return false
	var json_bytes := bytes.slice(20, 20 + json_length)
	while not json_bytes.is_empty() and json_bytes[json_bytes.size() - 1] == 0:
		json_bytes.resize(json_bytes.size() - 1)
	var document: Variant = JSON.parse_string(json_bytes.get_string_from_utf8())
	if not document is Dictionary:
		return false
	for material: Variant in document.get("materials", []):
		if not material is Dictionary:
			continue
		var pbr: Dictionary = material.get("pbrMetallicRoughness", {})
		var texture_infos: Array = [pbr.get("baseColorTexture", {}), pbr.get("metallicRoughnessTexture", {}),
			material.get("normalTexture", {}), material.get("occlusionTexture", {}), material.get("emissiveTexture", {})]
		for texture_info: Variant in texture_infos:
			if texture_info is Dictionary and texture_info.has("texCoord") \
					and int(texture_info.get("texCoord", -1)) != 0:
				return false
	return true

func _has_gameplay_method(node: Node) -> bool:
	var forbidden := ["die", "death", "take_damage", "receive_damage", "attack_player", "monster_attack", "despawn"]
	for method: Dictionary in node.get_method_list():
		if String(method.get("name", "")).to_lower() in forbidden:
			return true
	for child in node.get_children():
		if _has_gameplay_method(child):
			return true
	return false

func _finish() -> void:
	for failure in failures:
		push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

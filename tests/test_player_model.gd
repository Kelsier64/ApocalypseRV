extends SceneTree

var failures: Array[String] = []
var report: Dictionary = {}

func require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed := load("res://assets/models/player/player_masked_survivor.glb") as PackedScene
	require(packed != null, "GLB imports as PackedScene")
	if packed == null:
		quit(1)
		return
	var model := packed.instantiate()
	root.add_child(model)
	await process_frame
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	require(skeletons.size() == 1, "one Skeleton3D")
	require(players.size() == 1, "one AnimationPlayer")
	var skeleton := skeletons[0] as Skeleton3D
	var animation_player := players[0] as AnimationPlayer
	require(skeleton.get_bone_count() == 55, "55 bones")
	var bounds := AABB()
	var first := true
	var triangles := 0
	var materials: Dictionary = {}
	var body_count := 0
	var cap_count := 0
	for item: MeshInstance3D in meshes:
		var box: AABB = item.global_transform * item.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		if str(item.name).begins_with("body_"): body_count += 1
		if str(item.name).begins_with("cap_"): cap_count += 1
		for i in item.mesh.get_surface_count():
			var arrays := item.mesh.surface_get_arrays(i)
			triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var mat := item.get_active_material(i) as StandardMaterial3D
			require(mat != null, "StandardMaterial3D")
			if mat != null: materials[mat.resource_name] = mat
		require(item.transform.basis.get_scale().is_equal_approx(Vector3.ONE), "unit mesh scale " + str(item.name))
	require(body_count == 10, "10 primary pieces")
	require(cap_count == 18, "18 closures")
	require(absf(bounds.size.y - 1.60) < 0.002, "1.60 metre height")
	require(absf(bounds.position.y) < 0.002, "feet at ground")
	require(triangles >= 8000 and triangles <= 12100, "triangle budget including documented shoulder-loop allowance")
	require(materials.size() == 5, "five materials")
	var expected := ["idle", "walk", "jump", "fall_loop", "land", "climb_loop", "hang_idle", "sit_driver", "hold_small", "carry_large", "injured_idle"]
	var animations: Dictionary = {}
	for name in animation_player.get_animation_list():
		var clip := animation_player.get_animation(name)
		animations[str(name)] = {"seconds": clip.length, "tracks": clip.get_track_count(), "loop_mode": clip.loop_mode}
	for name in expected:
		require(animation_player.has_animation(name), "animation " + name)
		if animation_player.has_animation(name):
			var wanted := Animation.LOOP_NONE if name in ["jump", "land"] else Animation.LOOP_LINEAR
			require(animation_player.get_animation(name).loop_mode == wanted, "loop metadata " + name)
	var suit := materials.get("suit_dye") as StandardMaterial3D
	var white := materials.get("mask_default") as StandardMaterial3D
	require(suit != null and suit.albedo_texture != null, "dye texture imports")
	require(white != null and white.albedo_color.is_equal_approx(Color.WHITE), "pure white mask")
	for material_name in ["suit_dye", "equipment_atlas"]:
		var fabric := materials.get(material_name) as StandardMaterial3D
		require(fabric != null and fabric.normal_enabled and fabric.normal_texture != null, material_name + " baked normal imports")
		require(fabric != null and fabric.roughness_texture != null, material_name + " baked roughness imports")
		if fabric and fabric.normal_texture:
			var expected_size := 1024
			require(fabric.normal_texture.get_width() == expected_size and fabric.normal_texture.get_height() == expected_size, material_name + " normal resolution")
	require(white != null and not white.normal_enabled and white.albedo_texture == null, "white mask remains featureless")
	var before: Dictionary = {}
	for name in materials: before[name] = materials[name].albedo_color
	if suit:
		suit.albedo_color = Color(0.19, 0.10, 0.045, 1)
		for name in materials:
			if name != "suit_dye": require(materials[name].albedo_color == before[name], "fixed material unaffected " + str(name))
		suit.albedo_color = before["suit_dye"]
	# Exercise the actual imported skin through every frame of every action.
	var sampled := 0
	for name in animation_player.get_animation_list():
		var clip := animation_player.get_animation(name)
		animation_player.play(name)
		for f in range(ceili(clip.length * 30) + 1):
			animation_player.seek(minf(f / 30.0, clip.length), true)
			for b in skeleton.get_bone_count():
				require(skeleton.get_bone_global_pose(b).is_finite(), "finite bone pose " + str(name))
			# GLB faces +Z: relaxed elbow stays behind the shoulder-to-wrist line,
			# and the forearm points forward. Checking bend magnitude alone missed reversal.
			if name in ["idle", "walk"]:
				for side in ["L", "R"]:
					var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone("upper_arm." + side)).origin
					var elbow := skeleton.get_bone_global_pose(skeleton.find_bone("forearm." + side)).origin
					var wrist := skeleton.get_bone_global_pose(skeleton.find_bone("hand." + side)).origin
					var axis := wrist - shoulder
					var on_axis := shoulder + axis * (elbow - shoulder).dot(axis) / axis.length_squared()
					require(elbow.z < on_axis.z - 0.004, "idle/walk elbow bends backward " + side + " frame " + str(f))
					require(wrist.z > elbow.z + 0.005, "idle/walk forearm flexes forward " + side + " frame " + str(f))
			if name == "walk":
				var pelvis_index := skeleton.find_bone("pelvis")
				var drop := skeleton.get_bone_global_rest(pelvis_index).origin.y - skeleton.get_bone_global_pose(pelvis_index).origin.y
				require(drop > 0.05 and drop < 0.09, "walk stays slightly crouched")
				for side in ["L", "R"]:
					var hip := skeleton.get_bone_global_pose(skeleton.find_bone("thigh." + side)).origin
					var knee := skeleton.get_bone_global_pose(skeleton.find_bone("shin." + side)).origin
					var ankle := skeleton.get_bone_global_pose(skeleton.find_bone("foot." + side)).origin
					var bend := (knee - hip).angle_to(ankle - knee)
					require(bend > deg_to_rad(20) and bend < deg_to_rad(90), "walk knee flexion " + side)
			sampled += 1
	animation_player.stop()
	# Regression: the unused hand in hold_small must retain its relaxed wrist.
	animation_player.play("idle")
	animation_player.seek(0, true)
	var relaxed_left := skeleton.get_bone_global_pose(skeleton.find_bone("hand.L")).basis.get_rotation_quaternion()
	animation_player.play("hold_small")
	animation_player.seek(0, true)
	var passive_left := skeleton.get_bone_global_pose(skeleton.find_bone("hand.L")).basis.get_rotation_quaternion()
	require(relaxed_left.angle_to(passive_left) < deg_to_rad(5), "hold_small unused wrist stays relaxed")
	# Regression: the driving grip cannot fold the wrist back against the forearm.
	animation_player.play("sit_driver")
	animation_player.seek(0, true)
	for side in ["L", "R"]:
		var elbow := skeleton.get_bone_global_pose(skeleton.find_bone("forearm." + side)).origin
		var wrist := skeleton.get_bone_global_pose(skeleton.find_bone("hand." + side)).origin
		var knuckle := skeleton.get_bone_global_pose(skeleton.find_bone("middle_01." + side)).origin
		require((wrist - elbow).angle_to(knuckle - wrist) < deg_to_rad(80), "driving wrist bend below 80 degrees " + side)
	animation_player.stop()
	var detached: Array = []
	for cut in ["neck", "shoulder_L", "elbow_L", "shoulder_R", "elbow_R", "hip_L", "knee_L", "hip_R", "knee_R"]:
		var resource := load("res://assets/models/player/detached/detached_" + cut + ".glb") as PackedScene
		require(resource != null, "detached imports " + cut)
		if resource:
			var node := resource.instantiate()
			root.add_child(node)
			var sk := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			require(sk.find_bone("pelvis") == -1, "detached has no pelvis dependency " + cut)
			detached.append({"cut": cut, "bones": sk.get_bone_count()})
			node.queue_free()
	report = {"engine": Engine.get_version_info().string, "height": bounds.size.y, "floor_y": bounds.position.y, "triangles": triangles, "bones": skeleton.get_bone_count(), "meshes": meshes.size(), "materials": materials.keys(), "animations": animations, "sampled_frames": sampled, "detached": detached, "failures": failures}
	var output := FileAccess.open("res://.godot/test-logs/player_model_asset.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	if failures.is_empty(): print("PASS: player GLB reimport, materials, skeleton, actions and detached skins")
	else: push_error("FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)

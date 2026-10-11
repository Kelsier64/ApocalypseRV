extends SceneTree
## Evaluates real v020 skin with v021 clips; catches destructive curve reduction.
const OUTPUT := "res://.godot/test-logs/player_animation_skin/skinned_bounds.json"
func _init(): run.call_deferred()
func run():
	var actor = load("res://player/player.tscn").instantiate()
	root.add_child(actor)
	actor.set_physics_process(false)
	var visual = actor.get_node("Visuals")
	var driver = visual.get_node("Locomotion")
	driver.set_physics_process(false)
	var skeleton: Skeleton3D = visual.skeleton
	var ap: AnimationPlayer = driver.animation
	var original_crouch: AnimationLibrary = load("res://assets/animations/player/crouch.res")
	ap.add_animation_library("crouch_original", original_crouch)
	var results = []
	var failed := false
	var crouch: AnimationLibrary = ap.get_animation_library("crouch")
	if crouch.resource_path != "res://assets/animations/player/crouch_bent.res" or crouch.get_animation_list() != original_crouch.get_animation_list():
		failed = true
		push_error("Default bent crouch must retain every original directional clip")
	var pelvis := skeleton.find_bone("pelvis")
	var spine := skeleton.find_bone("spine_02")
	var torso_bends := {}
	for clip_name in ap.get_animation_list():
		var clip = ap.get_animation(clip_name)
		var minimum = INF
		var maximum = -INF
		var max_width = 0.0
		var torso_bend_sum := 0.0
		var samples = ceili(clip.length * 60)
		for frame in range(samples + 1):
			ap.play(clip_name,0)
			ap.seek(clip.length * frame / samples,true)
			skeleton.force_update_all_bone_transforms()
			if String(clip_name).begins_with("crouch/") or String(clip_name).begins_with("crouch_original/"):
				var torso := skeleton.get_bone_global_pose(spine).origin - skeleton.get_bone_global_pose(pelvis).origin
				# Imported rig faces +Z; Visuals rotates it into player forward.
				torso_bend_sum += atan2(torso.z, torso.y)
			var low = Vector3(INF,INF,INF)
			var high = Vector3(-INF,-INF,-INF)
			for mesh in visual.source_meshes:
				var binds = []
				for i in mesh.skin.get_bind_count():
					binds.append(skeleton.get_bone_global_pose(skeleton.find_bone(mesh.skin.get_bind_name(i))) * mesh.skin.get_bind_pose(i))
				for surface in mesh.mesh.get_surface_count():
					var arrays = mesh.mesh.surface_get_arrays(surface)
					var vertices = arrays[Mesh.ARRAY_VERTEX]
					var bones = arrays[Mesh.ARRAY_BONES]
					var weights = arrays[Mesh.ARRAY_WEIGHTS]
					for i in vertices.size():
						var point = Vector3.ZERO
						for k in 4: point += (binds[bones[i*4+k]] * vertices[i]) * weights[i*4+k]
						low=low.min(point)
						high=high.max(point)
			minimum=minf(minimum,low.y)
			maximum=maxf(maximum,high.y)
			max_width=maxf(max_width,high.x-low.x)
		failed = failed or minimum < -.002 or maximum > 1.8 or max_width > 1.3
		if String(clip_name).begins_with("crouch/") or String(clip_name).begins_with("crouch_original/"):
			failed = failed or maximum > actor.CROUCH_HEIGHT + .001
			torso_bends[clip_name] = torso_bend_sum / (samples + 1)
		results.append({"clip":clip_name,"samples":samples+1,"min_skinned_y":minimum,"max_skinned_y":maximum,"max_width":max_width})
	for clip_name in original_crouch.get_animation_list():
		var bent_angle: float = torso_bends["crouch/" + clip_name]
		var original_angle: float = torso_bends["crouch_original/" + clip_name]
		results.append({"crouch_clip":clip_name,"bent_torso_degrees":rad_to_deg(bent_angle),"original_torso_degrees":rad_to_deg(original_angle)})
		if bent_angle < original_angle + deg_to_rad(10):
			failed = true
			push_error("Bent crouch must lean its torso forward at least 10 degrees farther than original: " + clip_name)
	# The playground selects variants after Visuals creates its driver in _ready.
	# Switching a ready driver must immediately evaluate the selected crouch pose.
	# AnimationMixer cannot register one library under two names simultaneously.
	ap.remove_animation_library("crouch_original")
	actor.crouching = true
	driver.reset_posture()
	var crouch_camera_position: Vector3 = driver.view_camera.position
	for variant in [original_crouch, crouch, original_crouch]:
		driver.crouch_clips = variant
		skeleton.force_update_all_bone_transforms()
		var torso := skeleton.get_bone_global_pose(spine).origin - skeleton.get_bone_global_pose(pelvis).origin
		var bend := atan2(torso.z, torso.y)
		var expected: float = torso_bends["crouch_original/idle" if variant == original_crouch else "crouch/idle"]
		if ap.get_animation_library("crouch") != variant or ap.current_animation != "crouch/idle" or driver.current_clip != "crouch/idle" \
				or not actor.is_crouching() or not driver.view_camera.position.is_equal_approx(crouch_camera_position) \
				or not torso.is_finite() or absf(bend - expected) > .001:
			failed = true
			push_error("Runtime crouch variant switch must apply its actual idle pose and preserve crouch camera stance: " + variant.resource_path)
		results.append({"runtime_crouch_variant":variant.resource_path,"torso_degrees":rad_to_deg(bend),"camera_y":driver.view_camera.position.y})
	print(JSON.stringify(results))
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE) if directory_error == OK else null
	if output == null:
		failed = true
		push_error("Animated skin audit output could not be written: " + OUTPUT)
	else:
		output.store_string(JSON.stringify(results, "\t"))
		output.close()
	actor.queue_free()
	await process_frame
	if failed: push_error("Animated skin bounds or grounded boot soles failed")
	else: print("PASS: every animation frame retains bounded skin and grounded boot soles; both crouch variants fit crouch height and bent crouch has distinct forward waist bend")
	quit(1 if failed else 0)

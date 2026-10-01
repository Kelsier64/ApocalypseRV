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
	var results = []
	var failed := false
	for clip_name in ap.get_animation_list():
		var clip = ap.get_animation(clip_name)
		var minimum = INF
		var maximum = -INF
		var max_width = 0.0
		var samples = ceili(clip.length * 60)
		for frame in range(samples + 1):
			ap.play(clip_name,0)
			ap.seek(clip.length * frame / samples,true)
			skeleton.force_update_all_bone_transforms()
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
		results.append({"clip":clip_name,"samples":samples+1,"min_skinned_y":minimum,"max_skinned_y":maximum,"max_width":max_width})
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
	else: print("PASS: every imported animation frame retains bounded skin and grounded boot soles")
	quit(1 if failed else 0)

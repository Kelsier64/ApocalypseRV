extends SceneTree
## Bed experiment: raw geometry, equal camera framing, true cardinal views.
## Optional orthonormal rotation rows come from pose.json. Never scales axes independently.

func _init() -> void:
	run.call_deferred()

func bounds_of(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform *= node.transform
	var result := AABB()
	if node is MeshInstance3D and node.mesh != null:
		var initialized := false
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = local_transform * vertex
				if not initialized:
					result = AABB(point, Vector3.ZERO)
					initialized = true
				else:
					result = result.expand(point)
	for child in node.get_children():
		var child_bounds := bounds_of(child, local_transform)
		if child_bounds.size.length_squared() > 0.0:
			result = result.merge(child_bounds) if result.size.length_squared() > 0.0 else child_bounds
	return result

func geometry_stats(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.mesh_instances += 1
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			result.vertices += arrays[Mesh.ARRAY_VERTEX].size()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			result.triangles += int(indices.size() / 3) if not indices.is_empty() else int(arrays[Mesh.ARRAY_VERTEX].size() / 3)
	for child in node.get_children():
		geometry_stats(child, result)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = Vector2i(720, 720)
	for folder_arg in args:
		var folder := ProjectSettings.globalize_path(folder_arg)
		var input := folder.path_join("raw.glb")
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(input, state) != OK:
			push_error("Cannot load " + input)
			quit(1)
			return
		var model: Node3D = doc.generate_scene(state)
		var world := Node3D.new()
		root.add_child(world)
		world.add_child(model)
		if FileAccess.file_exists(folder.path_join("pose.json")):
			var pose: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("pose.json")))
			var rows: Array = pose.rotation_rows
			model.basis = Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]), Vector3(rows[0][2], rows[1][2], rows[2][2])) * model.basis
		var bounds: AABB = bounds_of(model)
		model.position -= bounds.get_center()
		var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.12, 0.14, 0.17)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.8
		world.add_child(environment)
		for rot in [Vector3(-45, -35, 0), Vector3(-20, 135, 0)]:
			var light := DirectionalLight3D.new()
			light.rotation_degrees = rot
			light.light_energy = 1.2
			world.add_child(light)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = extent * 1.3
		camera.near = extent * 0.001
		camera.far = extent * 20.0
		camera.current = true
		world.add_child(camera)
		var out := folder.path_join("review")
		DirAccess.make_dir_recursive_absolute(out)
		var views := {"front": Vector3(0, 0, 1), "side": Vector3(1, 0, 0), "back": Vector3(0, 0, -1), "oblique": Vector3(1, 0.65, 1), "top": Vector3(0, 1, 0.001)}
		for view in views:
			camera.position = views[view].normalized() * extent * 3.0
			camera.look_at(Vector3.ZERO, Vector3.UP)
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(out.path_join(view + ".png")) != OK:
				quit(1)
				return
		var stats := {"input": input, "sha256": FileAccess.get_sha256(input), "mesh_instances": 0, "vertices": 0, "triangles": 0, "display_aabb_size": [bounds.size.x, bounds.size.y, bounds.size.z], "axis_scaling": false, "godot_version": Engine.get_version_info().string}
		geometry_stats(model, stats)
		FileAccess.open(out.path_join("godot_review.json"), FileAccess.WRITE).store_string(JSON.stringify(stats, "\t") + "\n")
		print(JSON.stringify(stats))
		world.queue_free()
		await process_frame
	quit()

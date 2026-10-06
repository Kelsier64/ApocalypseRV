extends SceneTree
## Independent candidate viewer. Source and reduced model share pose and framing.

func _init() -> void:
	run.call_deferred()

func fail(message: String) -> void:
	push_error(message)
	quit(1)

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

func apply_clay(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		apply_clay(child, material)

func write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("Cannot write " + path)
		return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	return true

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		fail("Use review.py to supply a manifest")
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var pose_basis := Basis.IDENTITY
	if manifest.rotation_rows != null:
		var rows: Array = manifest.rotation_rows
		pose_basis = Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]), Vector3(rows[0][2], rows[1][2], rows[2][2]))
		if absf(pose_basis.determinant() - 1.0) > 0.00001 or not pose_basis.is_equal_approx(pose_basis.orthonormalized()):
			fail("Pose must be rigid: no axis scaling, reflection or shear")
			return
	root.size = Vector2i(720, 720)
	var baseline := AABB()
	var extent := 0.0
	for entry in manifest.models:
		var input: String = entry.path
		if FileAccess.get_sha256(input) != entry.sha256:
			fail("Input hash changed: " + input)
			return
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(input, state) != OK:
			fail("Cannot load " + input)
			return
		var model: Node3D = doc.generate_scene(state)
		if model == null:
			fail("Cannot generate scene " + input)
			return
		var world := Node3D.new()
		root.add_child(world)
		world.add_child(model)
		model.basis = pose_basis * model.basis
		var bounds := bounds_of(model)
		if extent == 0.0:
			baseline = bounds
			extent = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			if extent <= 0.0:
				fail("Empty geometry")
				return
			if not write_json(manifest.output.path_join("framing.json"), {"center": [baseline.get_center().x, baseline.get_center().y, baseline.get_center().z], "extent": extent, "rotation_rows": manifest.rotation_rows, "source_sha256": entry.sha256}):
				return
		model.position -= baseline.get_center()
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
		camera.size = extent * 1.65
		camera.near = extent * 0.001
		camera.far = extent * 20.0
		camera.current = true
		world.add_child(camera)
		var views := {"front": Vector3(0, 0, 1), "side": Vector3(1, 0, 0), "back": Vector3(0, 0, -1), "oblique": Vector3(1, 0.65, 1), "top": Vector3(0, 1, 0.001)}
		var output: String = manifest.output.path_join(entry.name)
		for mode in ["textured", "clay"]:
			var out := output.path_join(mode)
			if DirAccess.make_dir_recursive_absolute(out) != OK:
				fail("Cannot create " + out)
				return
			if mode == "clay":
				var clay := StandardMaterial3D.new()
				clay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				clay.albedo_color = Color.WHITE
				clay.cull_mode = BaseMaterial3D.CULL_DISABLED
				apply_clay(model, clay)
			for view in views:
				camera.position = views[view].normalized() * extent * 3.0
				camera.look_at(Vector3.ZERO, Vector3.UP)
				for frame in 8:
					await process_frame
				await RenderingServer.frame_post_draw
				if root.get_texture().get_image().save_png(out.path_join(view + ".png")) != OK:
					fail("Cannot save image " + view)
					return
		var stats := {"input": input, "sha256": FileAccess.get_sha256(input), "mesh_instances": 0, "vertices": 0, "triangles": 0, "display_aabb_size": [bounds.size.x, bounds.size.y, bounds.size.z], "shared_baseline_camera": true, "axis_scaling": false, "godot_version": Engine.get_version_info().string}
		geometry_stats(model, stats)
		if not write_json(output.path_join("godot_review.json"), stats):
			return
		print(JSON.stringify(stats))
		world.queue_free()
		await process_frame
	quit()

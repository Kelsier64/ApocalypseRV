extends SceneTree
## Renders a raw or candidate GLB without running gameplay or changing its mesh.
## godot --path . --script scripts/review_request_model.gd -- model.glb output_dir

func _init() -> void:
	run.call_deferred()

func bounds_of(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform *= node.transform
	var result := AABB()
	if node is MeshInstance3D and node.mesh != null:
		result = local_transform * node.mesh.get_aabb()
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
	var variant := args[1] if args.size() == 2 and args[0].begins_with("--") else ""
	if args.size() >= 1 and args[0] == "--validate-imports":
		validate_imports(variant)
		return
	if args.size() >= 1 and args[0] == "--all":
		var folders := DirAccess.get_directories_at("res://assets/models")
		for folder in folders:
			for filename in DirAccess.get_files_at("res://assets/models/" + folder):
				if not filename.ends_with("_candidate.glb"):
					continue
				if not variant.is_empty() and not filename.ends_with("_" + variant + "_candidate.glb"):
					continue
				var input := "res://assets/models/" + folder + "/" + filename
				var output := "res://art_source/" + folder + "/review_" + filename.trim_suffix("_candidate.glb")
				var old_report_path := output.path_join("godot_review.json")
				if FileAccess.file_exists(old_report_path):
					var old_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(old_report_path))
					if old_report is Dictionary and old_report.get("sha256", "") == FileAccess.get_sha256(input) and old_report.get("level_front_side_back", false):
						continue
				if not await render_model(input, output):
					quit(1)
					return
		quit()
		return
	if args.size() != 2:
		push_error("Expected GLB path and output directory")
		quit(1)
		return
	quit(0 if await render_model(args[0], args[1]) else 1)

func validate_imports(variant: String = "") -> void:
	var count := 0
	for folder in DirAccess.get_directories_at("res://assets/models"):
		for filename in DirAccess.get_files_at("res://assets/models/" + folder):
			if not filename.ends_with("_candidate.glb"):
				continue
			if not variant.is_empty() and not filename.ends_with("_" + variant + "_candidate.glb"):
				continue
			var input := "res://assets/models/" + folder + "/" + filename
			var scene: PackedScene = load(input)
			if scene == null:
				push_error("Imported PackedScene missing: " + input)
				quit(1)
				return
			var instance := scene.instantiate()
			var bounds := bounds_of(instance)
			var preparation_path := "res://art_source/" + folder + "/" + filename.trim_suffix("_candidate.glb") + "_preparation.json"
			var source_variant := variant
			if source_variant.is_empty() and filename.ends_with("_threeview_candidate.glb"):
				source_variant = "threeview"
			if not source_variant.is_empty():
				preparation_path = "res://art_source/" + folder + "/" + source_variant + "/" + filename.trim_suffix("_" + source_variant + "_candidate.glb") + "_preparation.json"
			var preparation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(preparation_path))
			var expected: Array = preparation.candidate_aabb_size
			var expected_min: Array = preparation.candidate_aabb_min
			if not bounds.size.is_equal_approx(Vector3(expected[0], expected[1], expected[2])) or not bounds.position.is_equal_approx(Vector3(expected_min[0], expected_min[1], expected_min[2])):
				push_error("Imported dimensions/origin changed: " + input)
				instance.free()
				quit(1)
				return
			instance.free()
			count += 1
	print("IMPORTED_CANDIDATES_OK count=" + str(count))
	quit(0 if count > 0 else 1)

func render_model(input_path: String, output_path: String) -> bool:
	var output_dir := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(720, 720)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(input_path), state)
	if error != OK:
		push_error("GLB import failed: %s" % error)
		return false
	var model: Node3D = document.generate_scene(state)
	if model == null:
		push_error("GLB scene generation failed")
		return false
	var bounds := bounds_of(model)
	var stats := {"input": input_path, "sha256": FileAccess.get_sha256(input_path), "mesh_instances": 0, "vertices": 0, "triangles": 0, "level_front_side_back": true,
		"aabb_min": [bounds.position.x, bounds.position.y, bounds.position.z],
		"aabb_size": [bounds.size.x, bounds.size.y, bounds.size.z], "godot_version": Engine.get_version_info().string}
	geometry_stats(model, stats)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	world.add_child(model)
	model.position -= bounds.get_center()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.14, 0.17)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	environment.environment.ambient_light_energy = 0.75
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.5
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 135, 0)
	fill.light_energy = 0.6
	world.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent * 1.6
	camera.near = extent * 0.001
	camera.far = extent * 20.0
	camera.current = true
	world.add_child(camera)
	var views := {"front": Vector3(0, 0, 1), "oblique": Vector3(1, 0.65, 1),
		"back": Vector3(0, 0, -1), "side": Vector3(1, 0, 0),
		"top": Vector3(0, 1, 0.01), "bottom": Vector3(0, -1, 0.01)}
	for view in views:
		camera.position = views[view].normalized() * extent * 3.0
		camera.look_at(Vector3.ZERO, Vector3.UP)
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var save_error := root.get_texture().get_image().save_png(output_dir.path_join(view + ".png"))
		if save_error != OK:
			push_error("Render save failed: %s" % save_error)
			return false
	var report := FileAccess.open(output_dir.path_join("godot_review.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(stats, "\t") + "\n")
	print(JSON.stringify(stats))
	world.queue_free()
	await process_frame
	return true

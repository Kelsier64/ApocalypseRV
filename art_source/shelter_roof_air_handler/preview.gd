extends SceneTree
## Render the real shelter extension and check the roof equipment contract.
var failures: Array[String] = []
var output: String
func _init() -> void:
	run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value:
		failures.append(note)
		push_error(note)
func bounds_of(node: Node, pose: Transform3D = Transform3D.IDENTITY) -> AABB:
	if node is Node3D: pose *= node.transform
	var result := AABB()
	var initialized := false
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point := pose * vertex
				result = result.expand(point) if initialized else AABB(point, Vector3.ZERO)
				initialized = true
	for child in node.get_children():
		var other := bounds_of(child, pose)
		if other.size.length_squared() > 0:
			result = result.merge(other) if initialized else other
			initialized = true
	return result
func capture(name: String) -> void:
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Save " + name)
func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var extension: Node3D = load("res://world/starting_shelter/exterior_extension.tscn").instantiate()
	world.add_child(extension)
	var model: Node3D = extension.get_node("Visuals/RoofPlantA")
	var target := Vector3(6,2,4)
	var offset := Vector3(-17.7,10,9.8)
	var bounds := bounds_of(model)
	check(bounds.size.distance_to(target) < .00001, "Imported 6x2x4 dimensions")
	check(bounds.get_center().distance_to(offset) < .00001, "Centered origin and placement applied once")
	check(model.position == offset and model.scale == Vector3.ONE and model.rotation == Vector3.ZERO, "Roof-edge visual placement")
	check(model.scene_file_path == "res://assets/models/shelter_roof_air_handler/shelter_roof_air_handler.glb", "Runtime resource")
	check(model.find_children("*", "CollisionObject3D", true, false).is_empty(), "Visual adds no collision")
	var collider: CollisionShape3D = extension.get_node("Collision/RoofPlantA")
	check(collider.shape is BoxShape3D and collider.shape.size == target, "Original collision dimensions")
	check(collider.position == offset and collider.scale == Vector3.ONE and not collider.disabled, "Collider follows visual placement")
	check(collider.get_meta("navigation_solid") == true, "Navigation marker")
	check(not extension.get_node("Visuals/RoofPlantAGraybox").visible, "Hidden graybox retained")
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(offset+Vector3(0,0,6),offset,1)
	var hit := space.intersect_ray(ray)
	check(hit.get("collider") == extension.get_node("Collision"), "Independent collider blocks +Z ray")
	check((hit.get("position",Vector3.ZERO) as Vector3).distance_to(offset+Vector3(0,0,2)) < .0001, "Ray hits original front collision plane")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.11,.14,.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.82,.87,.9)
	env.environment.ambient_light_energy = .55
	world.add_child(env)
	for setup in [[Vector3(-45,-35,0),1.15],[Vector3(-25,140,0),.55]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setup[0]
		light.light_energy = setup[1]
		light.shadow_enabled = true
		world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 52
	camera.look_at_from_position(Vector3(-10,15,21), offset)
	await capture("roof_close")
	camera.look_at_from_position(Vector3(-17.7,1.78,30),offset)
	await capture("ground_view")
	camera.look_at_from_position(Vector3(-43,32,20),Vector3(0,8,-17))
	await capture("shelter_context")
	var result := {"state":"PASS" if failures.is_empty() else "FAIL", "failures":failures,
		"size_m":[bounds.size.x,bounds.size.y,bounds.size.z],
		"center_m":[bounds.get_center().x,bounds.get_center().y,bounds.get_center().z],
		"godot_version":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_method(),
		"scope":"Actual extension, imported bounds, retained box collision/navigation marker and +Z ray; native daylight renders."}
	var file := FileAccess.open(output.path_join("context.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")+"\n")
	file.close()
	print("PASS: roof-air-handler context" if failures.is_empty() else "FAIL: roof-air-handler context")
	quit(0 if failures.is_empty() else 1)

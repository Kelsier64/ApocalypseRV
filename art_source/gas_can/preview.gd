extends SceneTree
## Actual gameplay wrappers: dimension/placement/collider checks and native render.
var failures: Array[String] = []
var output: String

func _init() -> void:
	run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error(note)

func bounds_of(node: Node, parent_pose: Transform3D = Transform3D.IDENTITY) -> AABB:
	var pose := parent_pose
	if node is Node3D:
		pose *= node.transform
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
	for frame in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Save " + name)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0] if args.size() == 1 else "res://.godot/art-work/gas_can/context_" + str(Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var results: Array = []
	var target := Vector3(0.39759523, 0.84584963, 0.82353514)
	var offset := Vector3(0.0022521876, -0.028735355, -0.0045410395)
	for index in 2:
		var key := "gas_can" if index == 0 else "gas_can_empty"
		var item: Item = load("res://props/" + key + ".tscn").instantiate()
		item.freeze = true
		item.position = Vector3(0, target.y / 2 - offset.y, -.58 if index == 0 else .58)
		world.add_child(item)
		var model: Node3D = item.get_node("gas_can")
		var bounds := bounds_of(model)
		check(bounds.size.distance_to(target) < .00001, key + " imported dimensions")
		check(bounds.get_center().distance_to(offset) < .00001, key + " offset applied exactly once")
		check(model.position.is_equal_approx(offset) and model.scale == Vector3.ONE and model.rotation == Vector3.ZERO, key + " original visual placement")
		check(model.scene_file_path == "res://assets/models/gas_can/gas_can.glb", key + " shared GLB")
		var collision: CollisionShape3D = item.get_node("@CollisionShape3D@7")
		check(collision.shape is BoxShape3D and collision.shape.size.is_equal_approx(target), key + " collision size")
		check(collision.position.is_equal_approx(offset) and not collision.disabled, key + " collision pose and enabled")
		check(item.mass == 5 and item.collision_layer == 1 and item.collision_mask == 1, key + " mass and collision filters")
		check(item.item_name == ("Gasoline Can" if index == 0 else "Gasoline Can (Empty)"), key + " item name")
		check(item.scrap_yields == ({"Metal Parts": Vector2(0, 1), "Unrefined Fuel": Vector2(1, 3)} if index == 0 else {"Metal Parts": Vector2(0, 1)}), key + " scrap data")
		check(model.find_children("*", "CollisionObject3D", true, false).is_empty(), key + " visual adds no actor or collision")
		check(not item.get_node("GasCanGraybox").visible, key + " graybox retained and hidden")
		await physics_frame
		await physics_frame
		var center: Vector3 = item.global_position + offset
		var ray := PhysicsRayQueryParameters3D.create(center + Vector3.RIGHT * 2, center)
		check(world.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == item, key + " +X interaction ray")
		results.append({"scene": item.scene_file_path, "visual_scene": model.scene_file_path,
			"size_m": [bounds.size.x, bounds.size.y, bounds.size.z], "center_m": [bounds.get_center().x, bounds.get_center().y, bounds.get_center().z]})
		var label := Label3D.new()
		label.text = "FULL" if index == 0 else "EMPTY"
		label.font_size = 42
		label.pixel_size = .0014
		label.position = item.position + Vector3(0, .56, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(label)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(.16, .18, .17)
	concrete.roughness = 1
	plane.material = concrete
	floor.mesh = plane
	world.add_child(floor)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.035, .045, .04)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.75, .8, .72)
	environment.environment.ambient_light_energy = .6
	world.add_child(environment)
	for setup in [[Vector3(-50, -40, 0), 1.2], [Vector3(-30, 150, 0), .65]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setup[0]
		light.light_energy = setup[1]
		light.shadow_enabled = true
		world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(2.4, 1.45, 1.5)
	camera.look_at_from_position(camera.position, Vector3(0, .5, 0))
	camera.fov = 50
	camera.current = true
	await capture("full_empty_context")
	# Show the actual production held item with the actor's existing pose/camera.
	var actor: CharacterBody3D = load("res://player/player.tscn").instantiate()
	actor.position = Vector3(0, .05, 5)
	world.add_child(actor)
	actor.set_physics_process(false)
	check(actor.add_item("Gasoline Can", false, "res://props/gas_can.tscn"), "Real player receives full can")
	var held_camera: Camera3D = actor.get_node("Camera3D")
	held_camera.current = true
	await capture("held_full_can")
	var result := {"state": "PASS" if failures.is_empty() else "FAIL", "failures": failures,
		"scenes": results, "dimension_tolerance_m": .00001,
		"godot_version": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"scope": "Actual gameplay scenes, imported geometry, original box collision/rays, native render and production held visual; gameplay transitions separately tested."}
	var file := FileAccess.open(output.path_join("context.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("PASS: gas-can context" if failures.is_empty() else "FAIL: gas-can context")
	quit(0 if failures.is_empty() else 1)

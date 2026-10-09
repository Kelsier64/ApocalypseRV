extends SceneTree
func _init() -> void:
	run.call_deferred()
func run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	var world: Node3D = load("res://world/main_world.tscn").instantiate()
	world.get_node("WorldGenerator").world_seed = 42
	root.add_child(world)
	current_scene = world
	assert(await world.wait_for_play(),"Main world ready")
	var shelter: Node3D = world.get_node("StartRun").shelter
	var extension: Node3D = shelter.get_node("ExteriorExtension")
	var model: Node3D = extension.get_node("Visuals/RoofPlantA")
	assert(model.position.is_equal_approx(Vector3(-17.7,10,9.8)))
	world.get_node("WorldClock").set_time(1,15.0)
	var player: CharacterBody3D = world.get_node("Player")
	player.set_physics_process(false)
	player.global_position = shelter.to_global(Vector3(-17.7,0,30))
	var camera: Camera3D = player.get_node("Camera3D")
	camera.current = true
	camera.look_at(model.global_position)
	await physics_frame
	var target: Vector3 = model.global_position+extension.global_basis*Vector3(0,.7,1.8)
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position,target,1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	assert(hit.get("collider") == extension.get_node("Collision"),"Ground sight ray hits equipment collider")
	var local_hit := extension.to_local(hit.position)
	assert(local_hit.y > 10.5 and local_hit.z > 11.7,"Ground sight ray reaches upper intake face, not the wall")
	for frame in 90: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join("main_world_ground.png")) == OK)
	var file := FileAccess.open(output.path_join("main_ground.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"state":"PASS","camera_height_m":camera.position.y,
		"player_shelter_position":[-17.7,0,30],"model_shelter_position":[-17.7,10,9.8],
		"sight_hit_local":[local_hit.x,local_hit.y,local_hit.z],
		"scope":"Production main world, actual player camera, day 1 at 15:00, upper front collider line of sight and native screenshot."},"\t"))
	file.close()
	print("PASS: main-world ground view")
	world.free()
	quit()

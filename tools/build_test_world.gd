extends SceneTree

func _init():
	print("--- Generating Test World ---")
	var root = Node3D.new()
	root.name = "TestWorld"
	
	# Light & Environment
	var light = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.position = Vector3(0, 10, 0)
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	root.add_child(light)
	light.owner = root
	
	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	world_env.environment = env
	root.add_child(world_env)
	world_env.owner = root
	
	# Ground
	var ground = CSGBox3D.new()
	ground.name = "Ground"
	ground.use_collision = true
	ground.size = Vector3(100, 1, 100)
	ground.position = Vector3(0, -0.5, 0)
	root.add_child(ground)
	ground.owner = root
	
	# RV
	var rv_scene = load("res://scenes/rv.tscn")
	if rv_scene:
		var rv = rv_scene.instantiate()
		rv.position = Vector3(0, 0.5, 0)
		root.add_child(rv)
		rv.owner = root
		
		# Player INSIDE RV
		var player_scene = load("res://scenes/player.tscn")
		if player_scene:
			var player = player_scene.instantiate()
			# Floor is at y=1.5, thickness 0.2 means floor top is y=1.6 relative to RV.
			# Player spawn position relative to world: RV base is at y=0.5 -> floor top is y=2.1
			player.position = Vector3(0, 2.2, 0) # Place carefully inside
			# Make player a child of the TestWorld, not the RV itself, to test true physics interactions
			root.add_child(player)
			player.owner = root
		
	# Reference House
	var house_scene = load("res://scenes/house.tscn")
	if house_scene:
		var house = house_scene.instantiate()
		house.position = Vector3(15, 0, 15) # Place it 15 meters away diagonally
		root.add_child(house)
		house.owner = root

	# Items to Pick Up
	var scrap_scene = load("res://scenes/scrap.tscn")
	var barrel_scene = load("res://scenes/oil_barrel.tscn")
	
	if scrap_scene:
		for i in range(5):
			var scrap = scrap_scene.instantiate()
			# Scatter around the front of the house
			scrap.position = Vector3(15 + randf_range(-2, 2), 2.0, 10 + randf_range(-2, 2))
			root.add_child(scrap)
			scrap.owner = root
			
	if barrel_scene:
		var barrel = barrel_scene.instantiate()
		barrel.position = Vector3(12, 5.0, 15)
		root.add_child(barrel)
		barrel.owner = root
		
	var packed = PackedScene.new()
	if packed.pack(root) == OK:
		ResourceSaver.save(packed, "res://scenes/test_world.tscn")
		print("-> Created: res://scenes/test_world.tscn")
	else:
		printerr("Failed to pack TestWorld scene")
		
	print("--- Generation Complete ---")
	quit()

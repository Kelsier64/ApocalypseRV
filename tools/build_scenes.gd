extends SceneTree

func _init():
	print("--- Starting Scene Generation via CLI ---")
	_generate_player_scene()
	_generate_driver_seat_scene()
	_generate_rv_scene()
	print("--- Scenes Generated Successfully! ---")
	quit()

func _generate_player_scene():
	var root = CharacterBody3D.new()
	root.name = "Player"
	
	var script = load("res://player/player.gd")
	if script:
		root.set_script(script)
	
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape = CapsuleShape3D.new() 
	shape.radius = 0.4 # Slightly thinner player to fit in the RV easier
	col.shape = shape
	col.position.y = 1.0
	root.add_child(col)
	col.owner = root
	
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position.y = 1.6 
	root.add_child(cam)
	cam.owner = root
	
	var ray = RayCast3D.new()
	ray.name = "InteractRay"
	ray.target_position = Vector3(0, 0, -2.0) # 2 meters reach
	ray.collide_with_areas = true # IMPORTANT: Driver seat is an Area3D
	var ray_script = load("res://player/player_interact.gd")
	if ray_script:
		ray.set_script(ray_script)
	cam.add_child(ray)
	ray.owner = root
	
	var packed_scene = PackedScene.new()
	if packed_scene.pack(root) == OK:
		ResourceSaver.save(packed_scene, "res://player/player.tscn")
		print("-> Created: res://player/player.tscn")
	else:
		printerr("Failed to pack player scene")

func _generate_driver_seat_scene():
	var root = Area3D.new()
	root.name = "DriverSeat"
	
	var script = load("res://rv/driver_seat.gd")
	if script:
		root.set_script(script)
		
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	col.shape = shape
	col.position.y = 0.5
	root.add_child(col)
	col.owner = root
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "SeatMesh"
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.6, 0.8, 0.6)
	mesh_inst.mesh = mesh
	mesh_inst.position.y = 0.4
	root.add_child(mesh_inst)
	mesh_inst.owner = root
	
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 1.5, -0.2)
	root.add_child(cam)
	cam.owner = root
	
	var packed_scene = PackedScene.new()
	if packed_scene.pack(root) == OK:
		ResourceSaver.save(packed_scene, "res://rv/driver_seat.tscn")
		print("-> Created: res://rv/driver_seat.tscn")
	else:
		printerr("Failed to pack driver seat scene")

func _generate_rv_scene():
	var root = VehicleBody3D.new()
	root.name = "RV"
	root.mass = 2000.0
	
	var script = load("res://rv/rv.gd")
	if script:
		root.set_script(script)
		
	# Body Parts (Hollow RV) - Floor at y=1.5
	# Body Parts (Hollow RV) - Exterior dimensions: approx 3.0 x 2.0 x 8.0
	# Interior floor space: 2.6 x 7.6
	_add_wall(root, "Floor", Vector3(3.0, 0.2, 8.0), Vector3(0, 1.5, 0))
	_add_wall(root, "Ceiling", Vector3(3.0, 0.2, 8.0), Vector3(0, 3.5, 0))
	_add_wall(root, "WallLeft", Vector3(0.2, 1.8, 8.0), Vector3(1.4, 2.5, 0))
	_add_wall(root, "WallRight", Vector3(0.2, 1.8, 8.0), Vector3(-1.4, 2.5, 0))
	_add_wall(root, "WallFront", Vector3(2.6, 1.8, 0.2), Vector3(0, 2.5, 3.9))
	_add_wall(root, "WallBack", Vector3(2.6, 0.8, 0.2), Vector3(0, 2.0, -3.9)) # Low back wall
	
	# Wheels (x: width/2, y: ground clearance, z: length/2)
	# Wheels are pushed wider to match 3.0 width and further apart for 8.0 length
	_add_wheel(root, "Wheel_FL", Vector3(1.6, 0.0, 2.8), true, false)
	_add_wheel(root, "Wheel_FR", Vector3(-1.6, 0.0, 2.8), true, false)
	
	_add_wheel(root, "Wheel_RL", Vector3(1.6, 0.0, -2.8), false, true)
	_add_wheel(root, "Wheel_RR", Vector3(-1.6, 0.0, -2.8), false, true)
	
	# Add Driver Seat
	var seat_scene = load("res://rv/driver_seat.tscn")
	if seat_scene:
		var seat = seat_scene.instantiate()
		seat.name = "DriverSeat"
		seat.position = Vector3(0.5, 1.5, 1.0) # Placed inside cabin, towards the front left
		root.add_child(seat)
		seat.owner = root
		
		# For nested nodes inside the instanced scene, ownership doesn't need to be reassigned 
		# unless we want to edit them in the RV scene. But we don't.
	
	var packed_scene = PackedScene.new()
	if packed_scene.pack(root) == OK:
		ResourceSaver.save(packed_scene, "res://rv/rv.tscn")
		print("-> Created: res://rv/rv.tscn")
	else:
		printerr("Failed to pack RV scene")

func _add_wall(root: Node, node_name: String, size: Vector3, pos: Vector3):
	var col = CollisionShape3D.new()
	col.name = node_name + "Col"
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	root.add_child(col)
	col.owner = root
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = node_name + "Mesh"
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh_inst.mesh = mesh
	mesh_inst.position = pos
	root.add_child(mesh_inst)
	mesh_inst.owner = root

func _add_wheel(root: Node, node_name: String, pos: Vector3, is_steering: bool, is_traction: bool):
	var wheel = VehicleWheel3D.new()
	wheel.name = node_name
	wheel.position = pos
	wheel.use_as_steering = is_steering
	wheel.use_as_traction = is_traction
	wheel.wheel_radius = 0.5 
	wheel.suspension_travel = 0.5 # Increase travel distance
	wheel.suspension_stiffness = 30.0 # Make it slightly softer so it settles
	wheel.suspension_max_force = 10000.0 # Ensure it has enough force to hold the RV up
	wheel.wheel_friction_slip = 10.5
	root.add_child(wheel)
	wheel.owner = root
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "WheelMesh"
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.4 
	mesh_inst.mesh = mesh
	mesh_inst.rotation_degrees.x = 90
	mesh_inst.rotation_degrees.z = 90
	wheel.add_child(mesh_inst)
	mesh_inst.owner = root

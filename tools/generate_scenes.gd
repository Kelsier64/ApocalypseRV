@tool
extends EditorScript

# EditorScript to automatically generate the Player and RV scenes
# How to use:
# 1. Select this script `generate_scenes.gd` in the Godot FileSystem dock.
# 2. Right-click and choose "Run". or Click "File -> Run" in the script editor.
# 3. `player.tscn` and `rv.tscn` will appear in your project folder!

func _run():
	print("--- Starting Scene Generation ---")
	_generate_player_scene()
	_generate_rv_scene()
	print("--- Scenes Generated Successfully! ---")
	print("Please check your FileSystem dock for player.tscn and rv.tscn.")

func _generate_player_scene():
	var root = CharacterBody3D.new()
	root.name = "Player"
	
	# Load and attach script
	var script = load("res://player/player.gd")
	if script:
		root.set_script(script)
	
	# Add CollisionShape for Character
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape = CapsuleShape3D.new() # Default height 2.0, radius 0.5
	col.shape = shape
	col.position.y = 1.0 # Lift it so bottom is at y=0
	root.add_child(col)
	col.owner = root
	
	# Add Camera
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position.y = 1.6 # Typical eye height
	root.add_child(cam)
	cam.owner = root
	
	# Save Scene
	var packed_scene = PackedScene.new()
	if packed_scene.pack(root) == OK:
		ResourceSaver.save(packed_scene, "res://player/player.tscn")
		print("-> Created: res://player/player.tscn")
	else:
		printerr("Failed to pack player scene")

func _generate_rv_scene():
	var root = VehicleBody3D.new()
	root.name = "RV"
	root.mass = 2000.0 # Make it a heavy vehicle
	
	# Load and attach script
	var script = load("res://rv/rv.gd")
	if script:
		root.set_script(script)
		
	# Body Collision
	var body_col = CollisionShape3D.new()
	body_col.name = "BodyCollision"
	var body_shape = BoxShape3D.new()
	var rv_size = Vector3(2.5, 2.0, 5.0)
	body_shape.size = rv_size
	body_col.shape = body_shape
	body_col.position.y = 1.5 # Lift off the ground to make room for wheels
	root.add_child(body_col)
	body_col.owner = root
	
	# Body Mesh (using simple CSG for placeholder visuals)
	# For script-generated simple visuals, MeshInstance3D with BoxMesh is safer to pack
	var body_mesh_inst = MeshInstance3D.new()
	body_mesh_inst.name = "BodyMesh"
	var body_box = BoxMesh.new()
	body_box.size = rv_size
	body_mesh_inst.mesh = body_box
	body_mesh_inst.position.y = 1.5
	root.add_child(body_mesh_inst)
	body_mesh_inst.owner = root
	
	# Wheels (x: width/2, y: ground clearance, z: length/2)
	# Front Wheels (Steering)
	_add_wheel(root, "Wheel_FL", Vector3(1.4, 0.5, 1.8), true, false)
	_add_wheel(root, "Wheel_FR", Vector3(-1.4, 0.5, 1.8), true, false)
	
	# Rear Wheels (Traction/Driving)
	_add_wheel(root, "Wheel_RL", Vector3(1.4, 0.5, -1.8), false, true)
	_add_wheel(root, "Wheel_RR", Vector3(-1.4, 0.5, -1.8), false, true)
	
	# Save Scene
	var packed_scene = PackedScene.new()
	if packed_scene.pack(root) == OK:
		ResourceSaver.save(packed_scene, "res://rv/rv.tscn")
		print("-> Created: res://rv/rv.tscn")
	else:
		printerr("Failed to pack RV scene")

func _add_wheel(root: Node, node_name: String, pos: Vector3, is_steering: bool, is_traction: bool):
	var wheel = VehicleWheel3D.new()
	wheel.name = node_name
	wheel.position = pos
	wheel.use_as_steering = is_steering
	wheel.use_as_traction = is_traction
	wheel.wheel_radius = 0.5 # Match the cylinder radius
	wheel.suspension_travel = 0.2
	wheel.suspension_stiffness = 50.0 # Stiffer suspension for heavy vehicle
	wheel.wheel_friction_slip = 10.5
	root.add_child(wheel)
	wheel.owner = root
	
	# Visual for wheel
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "WheelMesh"
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.4 # Wheel width
	mesh_inst.mesh = mesh
	# Cylinder is upright by default, rotate to face sideways like a wheel
	mesh_inst.rotation_degrees.x = 90
	mesh_inst.rotation_degrees.z = 90
	wheel.add_child(mesh_inst)
	mesh_inst.owner = root # The owner of EVERYTHING inside packed scene must be the root Node

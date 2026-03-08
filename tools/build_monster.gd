extends SceneTree

func _init():
	print("--- Generating Zombie Monster ---")
	
	var root = CharacterBody3D.new()
	root.name = "Zombie"
	
	var script = load("res://enemies/monster.gd")
	if script:
		root.set_script(script)
		root.set("monster_name", "Zombie")
		root.set("max_health", 80.0)
		root.set("move_speed", 2.5)
		root.set("contact_damage", 15.0)
		root.set("loot_drops", {
			"Unknown Material": Vector2(1, 3),
			"Metal Parts": Vector2(0, 1)
		})
		root.set("loot_scene", "res://props/scrap.tscn")
	else:
		printerr("Could not load monster.gd!")
		quit()
		return
	
	# Body Mesh (Red capsule)
	var body_mesh = MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	body_mesh.mesh = capsule
	body_mesh.position.y = 0.9 # Stand on ground
	
	var red_mat = StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.8, 0.15, 0.1)
	red_mat.roughness = 0.7
	body_mesh.material_override = red_mat
	
	root.add_child(body_mesh)
	body_mesh.owner = root
	
	# Main Collision Shape (for CharacterBody3D physics)
	var col = CollisionShape3D.new()
	col.name = "CollisionShape"
	var col_capsule = CapsuleShape3D.new()
	col_capsule.radius = 0.4
	col_capsule.height = 1.8
	col.shape = col_capsule
	col.position.y = 0.9
	root.add_child(col)
	col.owner = root
	
	# HitBox Area3D (for detecting vehicle collisions)
	var hitbox = Area3D.new()
	hitbox.name = "HitBox"
	hitbox.position.y = 0.9
	
	var hitbox_col = CollisionShape3D.new()
	hitbox_col.name = "HitBoxShape"
	var hitbox_shape = CapsuleShape3D.new()
	hitbox_shape.radius = 0.6 # Slightly larger than body for generous hit detection
	hitbox_shape.height = 2.0
	hitbox_col.shape = hitbox_shape
	hitbox.add_child(hitbox_col)
	
	# Set collision layers: HitBox should detect vehicles (layer 1) but not block things
	hitbox.collision_layer = 0 # Don't physically block
	hitbox.collision_mask = 1 # Detect layer 1 (default physics bodies like RV)
	hitbox.monitoring = true
	hitbox.monitorable = false
	
	root.add_child(hitbox)
	hitbox.owner = root
	hitbox_col.owner = root  # Must be set AFTER hitbox is added to root
	
	# Save Scene
	var packed = PackedScene.new()
	if packed.pack(root) == OK:
		ResourceSaver.save(packed, "res://enemies/zombie.tscn")
		print("-> Created: res://enemies/zombie.tscn")
	else:
		printerr("Failed to pack zombie scene!")
	
	quit()

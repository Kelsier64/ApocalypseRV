extends RefCounted

static func ground(world: Node3D, slope: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.rotation.z = slope
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(220.0, 1.0, 220.0)
	collision.shape = box
	collision.position.y = -0.5
	body.add_child(collision)
	world.add_child(body)
	return body

static func vehicle(world: Node3D, origin: Vector3, roll: float = 0.0) -> Chassis:
	var shell := preload("res://rv/new_rv.tscn").instantiate() as Node3D
	shell.transform = Transform3D(Basis(Vector3.BACK, roll), origin)
	world.add_child(shell)
	return shell.get_node("Chassis")

static func player(world: Node3D, point: Vector3) -> CharacterBody3D:
	var actor := preload("res://player/player.tscn").instantiate() as CharacterBody3D
	actor.position = point
	world.add_child(actor)
	return actor

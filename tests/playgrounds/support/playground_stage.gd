class_name PlaygroundStage
extends RefCounted
## Shared set dressing for playgrounds that need no generated world.


## Daylight, flat collidable ground and a painted lane line along z at x = 4.
static func flat_lot(parent: Node3D, size := Vector2(400, 400)) -> void:
	parent.set_meta("entity_domain", true)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.17, 0.23, 0.26)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.78, 0.85, 0.90)
	environment.environment.ambient_light_energy = 0.65
	parent.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	parent.add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 0.2, size.y)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.1
	parent.add_child(ground)
	RoadsideKit.part(parent, box.size, ground.position, Color(0.17, 0.19, 0.19))
	for z in range(-int(size.y / 2.0) + 5, int(size.y / 2.0) - 5, 5):
		RoadsideKit.part(parent, Vector3(0.12, 0.012, 2.0), Vector3(4.0, 0.012, z), Color("c8ba83"))


## The production RV, parked: handbrake on, neutral, part fuel and power.
static func parked_rv(parent: Node3D, at := Vector3(0, 1.6, 0)) -> Chassis:
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = at
	parent.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.current_fuel = rv.max_fuel * 0.65
	rv.current_power = rv.max_power * 0.72
	rv.handbrake = true
	rv.set_gear(0)
	return rv


## The production player under normal input, facing yaw (radians, 0 looks along -z).
static func player(parent: Node3D, at: Vector3, yaw := 0.0) -> CharacterBody3D:
	var body: CharacterBody3D = load("res://player/player.tscn").instantiate()
	body.position = at
	body.rotation.y = yaw
	parent.add_child(body)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return body

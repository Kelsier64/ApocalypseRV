extends SceneTree
var failures: Array[String] = []
var actor: Raker
var player: CharacterBody3D
var rv: Chassis
var world: Node3D

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)

func tick(speed: float) -> void:
	rv.position.z -= speed / 60.0
	rv._road_speed = speed
	rv.linear_velocity = Vector3(0, 0, -speed)
	player.position = rv.to_global(Vector3(0, 2.5, 0))
	await physics_frame
	actor._physics_process(1.0 / 60.0)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, .2, 1000)
	collision.shape = shape
	ground.add_child(collision)
	world.add_child(ground)
	ground.position.y = -.1
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(vehicle)
	rv = vehicle.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.position.y = .95
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	actor = load("res://enemies/raker.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.position = Vector3(0, -.25, 22)
	actor.target_player = player
	actor.ai_state = Monster.State.CHASE
	actor.loot_drops = {}
	await tick(10)
	check(actor.pursuit_gait == Raker.PursuitGait.VEHICLE_SPRINT, "Real roof target starts vehicle sprint")
	check(actor.velocity.length() < 1.0, "Sprint accelerates instead of snapping to car speed")
	for i in 90: await tick(10)
	check(absf(Vector2(actor.velocity.x, actor.velocity.z).length() - 11.2) < .05, "10 m/s vehicle chased at 11.2 m/s")
	var visual := actor.get_node("BodyMesh")
	visual.locked = 0.0
	visual._process(0.0)
	check(visual.animation_player.current_animation == "game/sprint", "Vehicle sprint selects its imported dedicated animation")
	var saved_position := actor.position
	actor.position = rv.to_global(Vector3(0, -1.2, 6.5))
	actor._update_posture()
	check(not actor.crouched, "Approaching moving RV does not slow to crouch before contact")
	actor.position = saved_position
	var gap := actor.position.z - rv.position.z
	for i in 60: await tick(10)
	check(actor.position.z - rv.position.z < gap - 1.0, "Actual ground motion closes the vehicle gap")
	for i in 60: await tick(17)
	check(absf(Vector2(actor.velocity.x, actor.velocity.z).length() - 18.0) < .05, "Sprint reaches its 18 m/s cap")
	gap = actor.position.z - rv.position.z
	for i in 30: await tick(25)
	check(actor.position.z - rv.position.z > gap + 3.0, "Faster vehicle opens the gap beyond the cap")
	check(Vector2(actor.velocity.x, actor.velocity.z).length() <= 18.001, "Vehicle acceleration never raises the cap")
	await tick(5)
	check(Vector2(actor.velocity.x, actor.velocity.z).length() <= 6.201, "Braking immediately lowers the pursuit speed ceiling")
	await tick(0)
	check(actor.pursuit_gait != Raker.PursuitGait.VEHICLE_SPRINT, "Stopped vehicle exits sprint")
	await tick(10)
	player.position = rv.position + Vector3(10, 0, 0)
	check(actor._vehicle_sprint_target_speed() == 0.0, "Leaving the vehicle cancels even a cached boarding target")
	player.position = rv.to_global(Vector3(0, 2.5, 0))
	await physics_frame
	actor.set_crouched(true)
	check(actor._vehicle_sprint_target_speed() == 0.0, "Low cabin posture cannot sprint")
	actor.set_crouched(false)
	actor.rv_support.rv = rv
	check(actor._vehicle_sprint_target_speed() == 0.0, "Carried actor cannot sprint on a roof")
	actor.rv_support.rv = null
	actor.take_damage(10)
	check(actor.pursuit_gait != Raker.PursuitGait.VEHICLE_SPRINT and actor._vehicle_sprint_target_speed() == 0.0, "Heavy hit interrupts sprint")
	actor.reaction_remaining = 0
	actor.strike_elapsed = 0
	check(actor._vehicle_sprint_target_speed() == 0.0, "Committed attack cannot sprint")
	actor.strike_elapsed = -1
	actor.locomotion_state = Monster.LocomotionState.CLIMBING
	check(actor._vehicle_sprint_target_speed() == 0.0, "Climbing cannot sprint")
	actor.locomotion_state = Monster.LocomotionState.NORMAL
	actor.die()
	check(actor._vehicle_sprint_target_speed() == 0.0, "Death cancels sprint")
	world.free()
	if failures.is_empty(): print("PASS: Raker sprint actual pursuit, acceleration, closing gap, cap, braking and state exits")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

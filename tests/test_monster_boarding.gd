extends SceneTree

var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var monster: Monster

func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		monster._physics_process(1.0 / 60.0)

func spawn(point: Vector3, facing: float) -> void:
	if is_instance_valid(monster): monster.free()
	monster = load("res://enemies/zombie.tscn").instantiate()
	world.add_child(monster)
	monster.set_physics_process(false)
	monster.global_position = point
	monster.rotation.y = facing
	monster.target_player = player
	monster.ai_state = Monster.State.CHASE
	monster.boarding.rng.seed = 1234

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.1
	world.add_child(ground)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.position.y = 1.2
	rv.freeze = true
	rv.set_physics_process(false)
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	player.enter_seat_mode(rv.get_node("DriverSeat"))
	var door: Node3D = rv.get_node("RightMiddle")
	var roof: Node3D = rv.get_node("Ceiling")
	check(MonsterBoarding.grab_probability(Vector3(0, 0, -1), Vector3.RIGHT) > MonsterBoarding.grab_probability(Vector3(0, 0, -9), Vector3.RIGHT), "Relative tangential speed lowers grab probability")
	check(MonsterBoarding.grab_probability(Vector3.ZERO, Vector3.RIGHT) == 1.0, "Matched fast runners can grab a fast vehicle")
	check(MonsterBoarding.grab_probability(Vector3(-20, 0, 0), Vector3.RIGHT) == 0.0, "High closing speed is not a guaranteed latch")
	spawn(Vector3(2.65, 0.6, 0), PI / 2.0)
	await ticks(150)
	check(monster.boarding.mode == MonsterBoarding.Mode.DOOR, "Actual closed side leaf selects door hanging: " + monster.boarding.describe(monster))
	check(door.current_health < door.max_health and roof.current_health == roof.max_health, "Door hanger damages only the door, not roof")
	check(rv.to_local(monster.global_position).y < 1.5, "Door hanger stays at leaf instead of ascending to roof")
	var health: float = door.current_health
	monster.boarding.grip = monster.grip_capacity * 0.15
	await ticks(40)
	check(door.current_health == health, "Low grip suspends door attacks")
	door.restore_angles([-deg_to_rad(100)])
	await ticks(2)
	check(monster.locomotion_state == Monster.LocomotionState.NORMAL and monster.boarding.door == null, "Opening the leaf releases its hanging monster")
	door.restore_angles([0.0])
	spawn(Vector3(2.65, 0.6, 0), PI / 2.0)
	await ticks(80)
	check(monster.boarding.mode == MonsterBoarding.Mode.DOOR, "Replacement monster reattaches to closed door")
	var other: Monster = load("res://enemies/zombie.tscn").instantiate()
	world.add_child(other)
	other.set_physics_process(false)
	other.global_position = monster.global_position
	check(other.boarding.occupied(other, rv, door, door.boarding_entry_point(0)), "One hanging monster reserves this leaf")
	other.free()
	door.take_damage(door.max_health)
	await ticks(3)
	check(monster.locomotion_state == Monster.LocomotionState.NORMAL and monster.boarding.door == null, "Destroyed door cannot retain a hanging actor")

	# Actual solid left wall is the roof route, regardless of nearby door-frame modules.
	spawn(Vector3(-2.65, 0.6, -2.0), -PI / 2.0)
	var climbed := false
	var topped := false
	for i in range(330):
		await ticks(1)
		climbed = climbed or monster.locomotion_state == Monster.LocomotionState.CLIMBING
		if climbed and monster.locomotion_state == Monster.LocomotionState.NORMAL and monster.boarding.on_roof(monster):
			topped = true
			break
	check(climbed and topped, "Wall route climbs actual RV and acquires roof support: " + str(monster.global_position))
	var roof_health: float = roof.current_health
	await ticks(140)
	check(roof.current_health < roof_health, "Settled roof monster breaches roof above driver")

	# Constant high world speed is not strain; actual braking interrupts attacks.
	rv.freeze = false
	rv.gravity_scale = 0.0
	rv.linear_velocity = Vector3(0, 0, -12)
	monster.boarding._sample_vehicle = null
	monster.boarding.tick(monster, 1.0 / 60.0)
	monster.boarding.tick(monster, 1.0 / 60.0)
	check(monster.boarding.strain < 0.01, "Constant high speed does not automatically unseat roof monster")
	rv.linear_velocity = Vector3.ZERO
	monster.boarding.tick(monster, 1.0 / 60.0)
	check(monster.boarding.settle > 0.0 and monster.boarding.slip.length() > 0.0, "Actual sudden braking braces and slides roof monster")
	health = roof.current_health
	monster.attack_timer = 0.0
	monster._execute_attack_on_target(CombatTargeting.build_target(roof, "equipment", "underfoot"))
	check(roof.current_health == health, "Bracing blocks damage through every attack path")
	rv.freeze = true
	rv.linear_velocity = Vector3.ZERO

	spawn(Vector3(0, 0.5, -7), 0.0)
	rv.linear_velocity = Vector3(0, 0, -10)
	monster.velocity = Vector3(0, 0, -9)
	health = monster.current_health
	check(not monster._apply_vehicle_contact(rv, Vector3.FORWARD, rv.to_global(Vector3(0, 0, -6))), "Similar world velocities do not cause impact damage")
	monster.velocity = Vector3(0, 0, 3)
	check(monster._apply_vehicle_contact(rv, Vector3.FORWARD, rv.to_global(Vector3(0, 0, -6))), "Head-on relative closing speed causes collision")
	check(monster.current_health < health and monster.climb_reenter_cooldown_remaining > 0.0, "Impact damages and prevents immediate grabbing")
	rv.linear_velocity = Vector3.ZERO

	# Actual wall probe accepts a fast runner, rejects fast side swipe once per attempt.
	spawn(Vector3(-2.65, 1.0, -3.0), -PI / 2.0)
	await physics_frame
	monster.climb_wall_probe.force_raycast_update()
	check(monster.climb_wall_probe.is_colliding(), "Relative-speed scenario contacts a solid wall face")
	rv.linear_velocity = Vector3(0, 0, -10)
	monster.velocity = Vector3(0, 0, -9)
	check(monster._try_start_climb(player.global_position), "Fast monster with small relative speed grabs real RV wall")
	monster.boarding.grip = 0.01
	monster.boarding.tick(monster, 1.0 / 60.0)
	check(monster.locomotion_state == Monster.LocomotionState.NORMAL and monster.boarding.recovery > 0.0, "Exhausted grip releases and enforces recovery")
	spawn(Vector3(-2.65, 1.0, -3.0), -PI / 2.0)
	await physics_frame
	monster.climb_wall_probe.force_raycast_update()
	check(monster.climb_wall_probe.is_colliding(), "Relative-speed scenario contacts a solid wall face")
	rv.linear_velocity = Vector3(0, 0, -20)
	monster.velocity = Vector3.ZERO
	check(not monster._try_start_climb(player.global_position), "High tangential relative speed fails actual grab")
	var random_state: int = monster.boarding.rng.state
	check(not monster._try_start_climb(player.global_position) and monster.boarding.rng.state == random_state, "Failed grab does not reroll every frame during cooldown")
	rv.linear_velocity = Vector3.ZERO

	# Open rear leaves and the real ramp allow ordinary pursuit into the cabin.
	spawn(Vector3(0, 0.0, 10.5), 0.0)
	rv.position.y = 0.95
	player._physics_process(1.0 / 60.0)
	rv.get_node("RearDoor").restore_angles([-deg_to_rad(100), deg_to_rad(100)])
	await physics_frame
	rv.rear_ramp.interact(player)
	for i in range(200): await physics_frame
	check(rv.rear_ramp.deployed, "Open-entry scenario deploys production rear ramp")
	var hung_on_open_door := false
	for i in range(300):
		await ticks(1)
		hung_on_open_door = hung_on_open_door or monster.boarding.mode == MonsterBoarding.Mode.DOOR
	check(not hung_on_open_door, "Open door is traversed instead of attacked while hanging")
	check(rv.to_local(monster.global_position).z < 5.5 and rv.to_local(monster.global_position).y > 0.0, "Monster walks real rear ramp into cabin: " + str(rv.to_local(monster.global_position)))

	world.queue_free()
	await physics_frame
	if failures.is_empty():
		print("PASS: monster relative-speed boarding / door and roof breach")
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)

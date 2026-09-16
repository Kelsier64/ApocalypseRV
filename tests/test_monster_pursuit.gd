extends SceneTree

var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var monster: Monster

func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		player._physics_process(1.0 / 60.0)
		monster._physics_process(1.0 / 60.0)
func spawn(point: Vector3) -> void:
	if is_instance_valid(monster): monster.free()
	monster = load("res://enemies/zombie.tscn").instantiate()
	world.add_child(monster)
	monster.set_physics_process(false)
	monster.position = point
	monster.boarding.rng.seed = 7
	player.current_player_health = 1000.0
	player.damage_cooldown = 0.0
func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = point
	return body

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	box(Vector3(0, -0.1, 0), Vector3(100, 0.2, 100))
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(8, -0.25, 0)
	spawn(Vector3(0, -0.25, 0))
	monster.is_idle = true
	monster.idle_timer = 30.0
	await ticks(120)
	check(monster.position.x > 3.0 and monster.target_player == player, "Idle monster detects nearby player and pursues without waiting for idle timer")
	await ticks(150)
	check(player.current_player_health < 1000.0, "Ground pursuit reaches and attacks actual player")

	player.position = Vector3(1.5, -0.25, 0)
	spawn(Vector3(0, -0.25, 0))
	var device := Equipment.new()
	device.freeze = true
	var device_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	device_shape.shape = sphere
	device.add_child(device_shape)
	world.add_child(device)
	device.position = Vector3(0, 0.7, 0.7)
	device.current_health = 10000.0
	await ticks(240)
	check(player.current_player_health <= 970.0, "Reachable player receives repeated attacks even beside damageable equipment")
	check(device.current_health == 10000.0, "Nearby equipment does not steal player attack cooldown")
	device.free()
	var before_ui: float = player.current_player_health
	player.in_ui_mode = true
	await ticks(200)
	check(player.current_player_health <= before_ui - 30.0, "UI movement lock does not freeze damage invulnerability")
	player.in_ui_mode = false

	spawn(Vector3(0, -0.25, 0))
	monster.move_speed = 0.0
	var obstacle := box(Vector3(0.75, 1, 0), Vector3(0.2, 3, 4))
	await ticks(120)
	check(player.current_player_health == 1000.0, "A solid wall still prevents melee damage through it")
	obstacle.free()
	await ticks(120)
	check(player.current_player_health < 1000.0, "Removing the obstruction resumes attacks without respawning actor")

	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.position = Vector3(10, 0.95, 0)
	player.position = Vector3(12.45, -0.25, 4.0)
	spawn(Vector3(13.85, -0.25, 4.0))
	await ticks(180)
	check(player.current_player_health <= 970.0, "Beside RV wheel, chase intent does not reset an in-range player's attack every tick")
	print("RV proximity: vehicle=", monster.boarding.target_vehicle, " state=", monster.ai_state, " player_hp=", player.current_player_health)
	# A raised loading area puts an outside pursuer within melee reach of a
	# player in the open cabin, while only the player is supported by the RV.
	rv.get_node("RightMiddle").free()
	var loading_area := box(Vector3(13.2, 1.3, 0), Vector3(2.2, 0.2, 2.0))
	player.position = rv.to_global(Vector3(1.4, 0.5, 0))
	spawn(Vector3(12.8, 1.3, 0))
	await ticks(180)
	check(monster.boarding.target_vehicle == rv, "Open-cabin scenario exercises RV boarding intent")
	check(player.current_player_health <= 970.0, "RV approach can transition from pursuit to repeated player melee")
	loading_area.free()

	player.position = rv.to_global(Vector3(1.2, 2.45, 0))
	spawn(rv.to_global(Vector3(0, 2.55, 0)))
	var roof: Equipment = rv.get_node("Ceiling")
	await ticks(180)
	check(player.current_player_health < 1000.0, "Nearby visible roof player is attacked despite a slight height difference")
	check(roof.current_health == roof.max_health, "Accessible roof player takes priority over attacking the supporting roof")
	monster.free()
	player.enter_seat_mode(rv.get_node("DriverSeat"))
	player.damage_cooldown = 0.0
	player.take_damage(10.0)
	var after_hit: float = player.current_player_health
	for i in range(40):
		await physics_frame
		player._physics_process(1.0 / 60.0)
	player.take_damage(10.0)
	check(player.current_player_health == after_hit - 10.0, "Seated player's hit cooldown expires while seat movement is locked")

	world.queue_free()
	await physics_frame
	if failures.is_empty():
		print("PASS: monster perception, pursuit and player attack arbitration")
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)

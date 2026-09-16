extends SceneTree

var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var monster: Monster

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		player._physics_process(1.0 / 60.0)
		monster._physics_process(1.0 / 60.0)
func spawn(point: Vector3, facing: float = 0.0) -> void:
	if is_instance_valid(monster): monster.free()
	monster = load("res://enemies/zombie.tscn").instantiate()
	world.add_child(monster)
	monster.set_physics_process(false)
	monster.position = rv.to_global(point)
	monster.rotation.y = facing
	monster.boarding.rng.seed = 7
	player.current_player_health = 10000
	player.damage_cooldown = 0
func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60, 0.2, 60)
	collider.shape = shape
	ground.add_child(collider)
	world.add_child(ground)
	ground.position.y = -0.1
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.position.y = 0.95
	rv.freeze = true
	rv.set_physics_process(false)
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.enter_seat_mode(rv.get_node("DriverSeat"))
	await physics_frame
	var door: Equipment = rv.get_node("RightMiddle")
	door.current_health = 15
	spawn(Vector3(2.65, -0.35, 0), PI / 2)
	await ticks(660)
	print("Door breach pursuit: ", rv.to_local(monster.global_position), " hp=", player.current_player_health, " mode=", monster.boarding.describe(monster))
	check(not is_instance_valid(door), "Monster destroys actual side door")
	check(player.current_player_health < 10000 and monster.boarding.cabin.inside(monster, rv), "Door breaker enters and attacks seated player")

	var roof: Equipment = rv.get_node("Ceiling")
	roof.current_health = 15
	spawn(Vector3(0, 2.55, 2.8))
	await ticks(540)
	print("Roof breach pursuit: ", rv.to_local(monster.global_position), " hp=", player.current_player_health)
	check(not is_instance_valid(roof), "Monster destroys actual roof")
	check(player.current_player_health < 10000 and monster.boarding.mode == MonsterBoarding.Mode.NONE, "Roof breaker lands, leaves roof mode and pursues through cabin")
	check(rv.get_node("CraftingStation").current_health == rv.get_node("CraftingStation").max_health, "Interior pursuit does not attack crafting furniture")
	spawn(Vector3(-1.15, 1.0, 1.0))
	await ticks(420)
	check(player.current_player_health < 10000, "Landing on workbench finds its edge and descends into aisle")

	# A tall freestanding obstacle forces a detour, not a jump or phasing.
	var obstruction := StaticBody3D.new()
	var obstruction_shape := CollisionShape3D.new()
	var block := BoxShape3D.new()
	block.size = Vector3(0.65, 1.8, 0.7)
	obstruction_shape.shape = block
	obstruction.add_child(obstruction_shape)
	world.add_child(obstruction)
	obstruction.position = rv.to_global(Vector3(0, 1.4, -0.7))
	spawn(Vector3(0, 0.28, 2.4))
	await ticks(540)
	print("Furniture detour: ", rv.to_local(monster.global_position), " hp=", player.current_player_health)
	check(player.current_player_health < 10000, "Cabin route detours around real obstacle to reach driver")
	block.size.x = 4.0
	spawn(Vector3(0, 0.28, 2.4))
	await ticks(150)
	check(player.current_player_health == 10000 and rv.to_local(monster.global_position).z > 0, "Fully blocked aisle waits without phasing or attacking through furniture")
	obstruction.free()
	await ticks(420)
	check(player.current_player_health < 10000, "Removing aisle obstacle replans and resumes pursuit")

	spawn(Vector3(0, 0.28, 2.4))
	for i in range(420):
		rv.position.x += 0.002
		rv.rotate_y(0.001)
		await ticks(1)
	check(player.current_player_health < 10000, "Cabin waypoints follow a translating, turning vehicle")

	# Player leaves through the existing breach; pursuer must choose that exit.
	player.seated_in = null
	player.in_ui_mode = true
	player.position = rv.to_global(Vector3(6, -1.2, 1.5))
	player.current_player_health = 10000
	await ticks(600)
	print("Exit pursuit: ", rv.to_local(monster.global_position), " hp=", player.current_player_health)
	check(rv.to_local(monster.global_position).x > 3.5 and player.current_player_health < 10000, "Interior monster exits through breach and resumes ground melee")

	world.queue_free()
	await physics_frame
	if failures.is_empty():
		print("PASS: production RV breach, cabin detour and exit pursuit")
		quit(0)
	else:
		for note in failures: push_error("FAIL: " + note)
		quit(1)

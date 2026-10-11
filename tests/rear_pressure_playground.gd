extends Node3D
## Production scene with repeatable physical traversal and outdoor pressure.
const WAIT := preload("res://tests/support/test_wait.gd")
var world: Node3D
var player: CharacterBody3D
var generator: Node
var observer: Camera3D
var status: Label
var ready_for_test := false
var busy := false
var walking := false
var walk_target := Vector3.ZERO
var traversal_ok := false

func _ready() -> void:
	world = load("res://world/main_world.tscn").instantiate()
	generator = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	add_child(world)
	player = world.get_node("Player")
	observer = Camera3D.new()
	observer.position = Vector3(45, 45, 130)
	add_child(observer)
	observer.look_at(Vector3(0, 0, 55))
	var ui := CanvasLayer.new()
	ui.layer = 60
	add_child(ui)
	status = Label.new()
	status.position = Vector2(24, 330)
	status.add_theme_font_size_override("font_size", 19)
	ui.add_child(status)
	status.text = "Preparing rear pressure fixture"
	if not await world.wait_for_play() or not await WAIT.generator_idle(get_tree(), generator): return
	generator.set_process(false)
	world.get_node("DeviationPressure").set_physics_process(false)
	world.get_node("StartRun").restore({"version": 1, "phase": "sealed"})
	world.get_node("StartRun")._update_status()
	var clock: WorldClock = world.get_node("WorldClock")
	clock.running = false
	clock.weather_running = false
	clock.set_time(1, 12.0)
	clock.weather.set_weather(Vector3(1, 0, 0), true)
	clock.apply_time()
	observer.current = true
	ready_for_test = true
	status.text = "F2: walk through wrecks   F3: rear fog/encounter   F4: camera"
	print("REAR_FIXTURE_READY cars=", generator.rear_wreck_layout.placements.size())
	if "--replay" in OS.get_cmdline_user_args(): await traverse()

func _unhandled_key_input(event: InputEvent) -> void:
	if not ready_for_test or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F2 and not busy: traverse()
	elif event.keycode == KEY_F3 and not busy: pressure()
	elif event.keycode == KEY_F4:
		if observer.current: player.camera.current = true
		else: observer.current = true

func _physics_process(_delta: float) -> void:
	if walking:
		player.look_at(Vector3(walk_target.x, player.global_position.y, walk_target.z))
		Input.action_press("move_forward")
	if ready_for_test and world.get_node("DeviationPressure").state.active:
		var state: RoutePressureState = world.get_node("DeviationPressure").state
		status.text = "Rear pressure   %.1fs   fog %.2f   Rakers %d   F4: camera" % [state.exposure, state.fog, PressureSpawns.raker_count(world)]

func traverse() -> bool:
	busy = true
	traversal_ok = true
	world.get_node("DeviationPressure").set_physics_process(false)
	player.global_position = Vector3(0, .05, 0)
	player.velocity = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.camera.current = true
	var path: PackedVector3Array = generator.rear_wreck_layout.walkway
	var map := world.get_world_3d().navigation_map
	var nav_path := NavigationServer3D.map_get_path(map, path[0], path[-1], true)
	traversal_ok = nav_path.size() >= 2 and PressureSpawns.planar_distance(nav_path[-1], path[-1]) < 1.0
	for i in range(1, path.size()):
		walk_target = path[i]
		walking = true
		for step in range(420):
			if PressureSpawns.planar_distance(player.global_position, walk_target) < .3: break
			await get_tree().physics_frame
		walking = false
		Input.action_release("move_forward")
		if PressureSpawns.planar_distance(player.global_position, walk_target) >= .6: traversal_ok = false; break
		status.text = "Walking through rear wrecks: %d/6" % i
	Input.action_release("move_forward")
	status.text = "Walk %s: z=%.2f   F3: rear pressure   F4: camera" % ["PASS" if traversal_ok else "FAIL", player.global_position.z]
	print("REAR_TRAVERSAL ok=", traversal_ok, " player=", player.global_position, " nav_points=", nav_path.size())
	busy = false
	return traversal_ok

func pressure() -> void:
	busy = true
	status.text = "Preparing rear encounter navigation"
	await generator._spawn_band(-2, true)
	await WAIT.generator_idle(get_tree(), generator)
	player.global_position = Vector3(35, generator.field.height_at(35, 120) + .05, 120)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.camera.current = true
	observer.global_position = Vector3(70, 14, 145)
	observer.look_at(player.global_position + Vector3.UP)
	var director: DeviationPressure = world.get_node("DeviationPressure")
	director.restore({})
	director.set_physics_process(true)
	status.text = "Waiting for 3s rear deviation confirmation"
	print("REAR_PRESSURE_REPLAY player=", player.global_position)
	busy = false

extends SceneTree
## Use the production playground, input routing, seat and wheel physics.
const Wait := preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok and note not in failures: failures.append(note)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code, true)
	await process_frame
	key(code, false)
	await process_frame

func step(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func run() -> void:
	var stage: Node3D = load("res://tests/slender_speaker_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	if stage.get_script() == null:
		check(false, "Production playground script loads successfully")
		await finish(stage)
		return
	var ready := await Wait.until(self, func() -> bool: return stage.running, 60000, true)
	check(ready, "Default playground finishes navigation and vehicle setup")
	if not ready:
		await finish(stage)
		return
	check(stage.mode == 0, "Default launch selects manual free play")
	if stage.mode != 0:
		await finish(stage)
		return
	var rv: Chassis = stage.rv
	var player: CharacterBody3D = stage.player
	var seat: Node3D = rv.get_node("DriverSeat")
	check(player.seated_in == seat and seat.current_driver == player and rv.is_player_driving, "Manual start uses production seat ownership")
	check(not stage.observer_enabled and seat.seat_camera.current, "Manual start uses the normal driver camera")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Manual start captures mouse look")
	check(not rv.allow_test_controls and rv.control_override.is_empty(), "Manual RV has no replay input override")
	check(rv.handbrake and rv.energy.engine_running and rv.gear == 1, "Manual start is parked with a running engine and first gear")
	# The live threat starts disabled; its public toggle must work before we
	# sample the driver's full input lifecycle without damage changing it.
	check(is_instance_valid(stage.giant) and not stage.giant.can_process(), "Manual free play starts with the giant paused")
	await tap(KEY_F2)
	check(stage.giant.can_process(), "F2 enables live giant AI in manual free play")
	await tap(KEY_F2)
	await step(3)
	check(not stage.giant.can_process(), "F2 disables the giant for independent free play")
	var parked_at := rv.global_position
	await step(Engine.physics_ticks_per_second * 37)
	check(stage.elapsed > 35.0 and stage.running and not stage.completed and not paused, "Manual clock remains playable beyond replay time limits")
	check(rv.global_position.distance_to(parked_at) < .25 and rv.handbrake and rv.energy.engine_running and rv.gear == 1, "Idle manual clock preserves the parked player's controls")
	await tap(KEY_C)
	await tap(KEY_SPACE)
	check(rv.energy.engine_running and rv.gear == 1 and not rv.handbrake, "Normal C Space controls release the parked RV")
	var drive_start := rv.global_position
	key(KEY_W, true)
	await step(Engine.physics_ticks_per_second * 3)
	key(KEY_W, false)
	check(rv.throttle_input > .5 and rv.engine_force < 0.0 and rv.global_position.distance_to(drive_start) > 1.0, "Real W input moves the RV under wheel power")
	check(rv.control_override.is_empty() and not rv.allow_test_controls, "Driving leaves manual controls free of replay overrides")
	var generation_before: int = stage.generation
	await tap(KEY_R)
	check(rv.gear == 2 and stage.generation == generation_before and stage.rv == rv, "R upshifts without resetting the playground")
	key(KEY_S, true)
	await step(Engine.physics_ticks_per_second * 4)
	check(rv.brake_input > .9 and rv.linear_velocity.slide(Vector3.UP).length() < .3, "Real S input brakes the manually driven RV to a stop")
	key(KEY_S, false)
	await tap(KEY_SPACE)
	await tap(KEY_B)
	await step(Engine.physics_ticks_per_second)
	check(rv.handbrake and not rv.energy.engine_running and rv.engine_force == 0.0, "Driver can park and stop the engine without fixture interference")
	await tap(KEY_B)
	await tap(KEY_C)
	await tap(KEY_SPACE)
	drive_start = rv.global_position
	key(KEY_W, true)
	await step(Engine.physics_ticks_per_second * 2)
	key(KEY_W, false)
	check(rv.energy.engine_running and rv.global_position.distance_to(drive_start) > .5, "Driver can restart and accelerate after parking")
	key(KEY_S, true)
	await step(Engine.physics_ticks_per_second * 4)
	key(KEY_S, false)
	await tap(KEY_SPACE)
	await tap(KEY_B)
	await step(Engine.physics_ticks_per_second)
	await tap(KEY_E)
	await step(3)
	check(player.seated_in == null and seat.current_driver == null and not rv.is_player_driving, "Normal E input exits the parked seat")
	check(player.camera.current and player.is_processing_unhandled_input() and not player.body_collision_shape.disabled, "Seat exit restores walking camera, input and collider")
	var walk_start := player.global_position
	key(KEY_S, true)
	await step(30)
	key(KEY_S, false)
	check((player.global_position - walk_start).slide(Vector3.UP).length() > .15, "Real movement input walks after leaving the seat")
	seat.interact_hold(player)
	await step(3)
	check(player.seated_in == seat and seat.current_driver == player and rv.is_player_driving and seat.seat_camera.current, "Production seat interaction permits reentry after walking")
	# Pause must stop world physics, while the root still accepts resume/reset.
	await tap(KEY_F7)
	check(paused and stage.paused, "F7 pauses the entire simulation")
	check(not rv.can_process() and not player.can_process(), "Tree pause also stops production vehicle and player processing")
	var paused_elapsed: float = stage.elapsed
	parked_at = rv.global_position
	await step(30)
	check(is_equal_approx(stage.elapsed, paused_elapsed) and rv.global_position.is_equal_approx(parked_at), "Paused clock and vehicle physics remain stopped")
	await tap(KEY_F7)
	await step(3)
	check(not paused and not stage.paused and stage.elapsed > paused_elapsed, "F7 resumes the free play clock")
	await tap(KEY_F7)
	generation_before = stage.generation
	await tap(KEY_F11)
	ready = await Wait.until(self, func() -> bool: return stage.running and stage.generation > generation_before, 60000, true)
	check(ready and not paused and not stage.paused and stage.mode == 0, "F11 resets manual free play even while paused")
	if ready:
		check(stage.rv != rv and stage.player != player and is_instance_valid(stage.giant), "Reset rebuilds actors and restores the live giant")
		check(stage.rv.control_override.is_empty() and not stage.rv.allow_test_controls, "Reset preserves normal manual RV input")
	# Returning from the parked replay must discard its permanent brake
	# override and give the player the normal seat camera again.
	stage.call_deferred("select_mode", 8)
	ready = await Wait.until(self, func() -> bool: return stage.running and stage.mode == 8, 60000, true)
	check(ready and stage.rv.allow_test_controls and not stage.rv.control_override.is_empty(), "Explicit parked replay still selects scripted controls")
	if ready:
		await tap(KEY_F12)
		ready = await Wait.until(self, func() -> bool: return stage.running and stage.mode == 0, 60000, true)
		check(ready and stage.rv.control_override.is_empty() and not stage.rv.allow_test_controls and not stage.observer_enabled, "F12 leaves parked replay and restores manual driving")
		if ready: check(stage.player.seated_in.seat_camera.current, "Leaving replay restores the production driver camera")
	await finish(stage)

func finish(stage: Node3D) -> void:
	paused = false
	for code in [KEY_W, KEY_S]: key(code, false)
	stage.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: Slender free play uses real driving, parking, restart, seat exit, walking, pause and reset controls")
	for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

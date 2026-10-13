extends SceneTree
## Production v11 lesson, real terminal/pickup transactions and wheel-powered driving.
## Once driving starts, this test never assigns actor transforms or velocities.
const WAIT = preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []
var world: Node3D
var run_owner: StartRun
var tutorial: TutorialController
var vehicle: Chassis
var forward_peak := 0.0
var reverse_peak := 0.0

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if ok: return
	failures.append(detail)
	push_error("FAIL: " + detail)
	if is_instance_valid(vehicle) and is_instance_valid(run_owner.shelter):
		var wheel_contacts := 0
		for wheel: VehicleWheel3D in vehicle.installed_wheels:
			if wheel != null and wheel.is_in_contact(): wheel_contacts += 1
		print("TRAINING_DRIVING_STATE: local=", run_owner.shelter.to_local(vehicle.global_position),
			" velocity=", vehicle.linear_velocity, " planar_speed=", planar_speed(),
			" road_speed=", vehicle.road_speed(), " wheel_contacts=", wheel_contacts,
			" park_seconds=", tutorial._park_seconds, " park_range=", (tutorial._park_max - tutorial._park_min).length(),
			" angular=", vehicle.angular_velocity, " flags=", tutorial.flags,
			" gear=", vehicle.gear, " stage=", tutorial.stage)

func planar_speed() -> float:
	return vehicle.linear_velocity.slide(run_owner.shelter.global_basis.y.normalized()).length()

func physics_seconds(seconds: float) -> void:
	for tick in ceili(seconds * Engine.physics_ticks_per_second): await physics_frame

func frames(count := 3) -> void:
	for frame in count: await process_frame

func stop_and_park(expect_advancement := false) -> bool:
	vehicle.control_override = {"brake": 1.0}
	var stopped := await WAIT.until(self, func() -> bool:
		return planar_speed() <= 0.1 and vehicle.angular_velocity.length() <= 0.04,
		15000, true)
	vehicle.set_handbrake(true)
	vehicle.set_engine_running(false)
	await physics_seconds(1.2)
	# Continuous parking is sampled by the real controller. Give suspension and
	# residual braking motion a bounded settling interval after the first window.
	if expect_advancement:
		return stopped and await WAIT.until(self, func() -> bool: return tutorial.stage == 2, 5000, true)
	return stopped

func drive_to_local_z(target: float, gear: int, speed_limit: float) -> bool:
	if not vehicle.set_gear(gear) or not vehicle.set_engine_running(true): return false
	vehicle.set_handbrake(false)
	var direction := 1.0 if gear > 0 else -1.0
	var deadline := Time.get_ticks_msec() + 120000
	var ticks := 0
	while ticks < ceili(120.0 * Engine.physics_ticks_per_second) and Time.get_ticks_msec() < deadline:
		var local := run_owner.shelter.to_local(vehicle.global_position)
		var remaining := (target - local.z) * direction
		var speed := vehicle.linear_velocity.length()
		if gear > 0: forward_peak = maxf(forward_peak, speed)
		else: reverse_peak = maxf(reverse_peak, speed)
		if remaining <= 0.35:
			vehicle.control_override = {"brake": 1.0}
			if speed <= 0.1 and vehicle.angular_velocity.length() <= 0.04:
				print("TRAINING_DRIVING_STOP: target=", target, " local=", local, " flags=", tutorial.flags)
				return absf(local.z - target) < 1.0 and absf(local.x) < 2.5
		else:
			var desired := minf(speed_limit, maxf(0.4, sqrt(maxf(0.0, remaining - 0.2) * 1.2)))
			# Pedals go through Chassis' normal response and VehicleWheel3D force.
			# Spawn orientation already points along the straight central lane.
			if speed > desired + 0.08:
				vehicle.control_override = {"brake": clampf((speed - desired) * 0.7, 0.04, 1.0)}
			else:
				vehicle.control_override = {"throttle": clampf((desired - speed) * 0.8, 0.0, 0.65)}
		if local.y < -1.0 or absf(local.x) > 3.0 or vehicle.global_basis.y.y < 0.8: return false
		await physics_frame
		ticks += 1
	vehicle.control_override = {"brake": 1.0}
	return false

func run() -> void:
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = 11
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play():
		check(false, "Real v11 production world becomes playable")
		finish(); return
	run_owner = world.get_node("StartRun")
	tutorial = run_owner.get_node("Tutorial")
	vehicle = world.get_node("NewRv/Chassis")
	if not await WAIT.until(self, func() -> bool: return tutorial.initialized() and not tutorial.entry_snapshot.is_empty(), 60000, true):
		check(false, "Lesson initializes with a usable stage-entry snapshot")
		finish(); return
	var player: Node3D = world.get_node("Player")
	var clock: WorldClock = world.get_node("WorldClock")
	var building: Node3D = run_owner.shelter
	var first_gate: ShelterGarageGate = building.get_node("Gates/Gate01")
	var second_gate: ShelterGarageGate = building.get_node("Gates/Gate02")
	check(tutorial.stage == 1 and tutorial.flags.marker_index == 0 and not tutorial.flags.viewed and not tutorial.flags.flashlight, "Fresh lesson starts with no recorded actions")
	check(not run_owner._status.visible and run_owner._status.text.is_empty(), "Tutorial keeps the legacy preparation instruction HUD hidden")
	check(run_owner.phase == "preparing" and not clock.running and not clock.weather_running, "Preparation stops clock and weather")
	for index in 2:
		var marker: Node3D = building.get_node("FirstBriefing/Lane%02d" % (index + 1))
		check(is_equal_approx(building.to_local(marker.global_position).z, tutorial.MARKER_Z[index]), "Authored lane marker matches driving condition %d" % (index + 1))
	check((-vehicle.global_basis.z).dot(building.global_basis.z) > 0.99, "Production RV starts facing along the lane")
	building.get_node("Switches/Gate01Inside").interact(player)
	check(first_gate.target == 0.0 and first_gate.stable(), "First gate switch cannot bypass stage-one lock")
	building.get_node("GarageButton").interact(player)
	check(run_owner.phase == "preparing" and run_owner.gate.target == 0.0, "Departure button cannot bypass active training")
	# These fixture resource writes happen before driving; reserve floors are not
	# represented as successful refuelling or equipment transactions.
	vehicle.current_fuel = 1.0
	var socket: BatterySocket = vehicle.get_battery_socket()
	check(socket != null and socket.installed_battery != null, "Production RV owns an installed battery")
	if socket == null or socket.installed_battery == null: finish(); return
	socket.installed_battery.charge = 1.0
	await physics_seconds(0.1)
	check(vehicle.current_fuel >= 10.0 and socket.installed_battery.charge >= 19.9, "Preparation maintains fuel and usable installed battery reserves")
	var original_battery_id: String = socket.installed_battery.item_state().id
	socket.interact_hold(player)
	await physics_seconds(0.1)
	check(socket.installed_battery == null and vehicle.current_power == 0.0, "Preparation does not fabricate a battery in an empty socket")
	for index in player.inventory.items.size():
		if player.inventory.items[index].get("state", {}).get("id", "") == original_battery_id: player._set_active_slot(index)
	socket.interact(player)
	check(socket.installed_battery != null and socket.installed_battery.item_state().id == original_battery_id, "Normal socket interaction reinstalls the same removed battery")
	if socket.installed_battery == null: finish(); return
	var terminal: TrainingTerminal = tutorial.designated_terminal()
	check(terminal != null and terminal.can_operate(), "Lesson uses its real mounted designated terminal")
	if terminal == null: finish(); return
	tutorial.conditions_viewed(terminal.persistent_id, player)
	tutorial.conditions_viewed("wrong-terminal", player)
	check(not tutorial.flags.viewed, "Direct notifications without visible player-owned UI cannot count")
	terminal.interact_hold(player)
	terminal.ui_instance.select_page("steps")
	await frames()
	tutorial.conditions_viewed(terminal.persistent_id, player)
	check(terminal.ui_instance.visible and player.in_ui_mode and not tutorial.flags.viewed, "Visible Steps page cannot count as inspecting Conditions")
	terminal.ui_instance.select_page("conditions")
	tutorial.conditions_viewed("wrong-terminal", player)
	check(not tutorial.flags.viewed, "Wrong terminal identity cannot count even with the correct visible page")
	check(await WAIT.until(self, func() -> bool: return tutorial.flags.viewed, 5000), "Actual Conditions presentation records the designated terminal")
	terminal._close_ui()
	await frames()
	check(not terminal.ui_instance.visible and terminal.current_user == null and not player.in_ui_mode and not player.is_gameplay_input_blocked(), "Closing terminal releases UI ownership and gameplay input")
	var flashlight: Item
	for actor in world.get_node("WorldEntities").get_children():
		if actor is Item and actor.persistent_id == tutorial.flashlight_id: flashlight = actor
	check(flashlight != null and flashlight.scene_file_path == tutorial.FLASHLIGHT_SCENE, "Lesson owns its real shelter flashlight")
	if flashlight == null: finish(); return
	var flashlight_id: String = flashlight.persistent_id
	flashlight.interact(player)
	await frames()
	check(tutorial.flags.flashlight and player.inventory.items.any(func(item: Dictionary) -> bool: return item.get("state", {}).get("id", "") == flashlight_id), "Actual designated flashlight pickup commits inventory identity and condition")
	var seat: Item = vehicle.get_node("DriverSeat")
	seat.interact_hold(player)
	check(player.seated_in == seat and vehicle.is_player_driving, "Normal driver-seat interaction grants driving ownership")
	if player.seated_in != seat: finish(); return
	vehicle.allow_test_controls = true
	# A stop fully within the bay before marker 02 must not finish the lesson.
	if not await drive_to_local_z(-362.0, 1, 2.0):
		check(false, "Wheels drive from authored spawn into the first parking bay")
		finish(); return
	check(await stop_and_park(), "Service brake stops the early parking attempt")
	check(tutorial._fully_parked(vehicle) and tutorial.flags.marker_index == 1 and not tutorial.flags.reversed and not tutorial.flags.parked and tutorial.stage == 1 and first_gate.target == 0.0, "Parking before both ordered markers leaves driving incomplete and gate locked")
	if not await drive_to_local_z(-337.0, 1, 2.0):
		check(false, "Wheels drive beyond the second lane marker and brake")
		finish(); return
	check(tutorial.flags.marker_index == 2 and not tutorial.flags.reversed and tutorial.stage == 1, "Both markers record in order while reversal remains required")
	if not await drive_to_local_z(-362.0, -1, 1.6):
		check(false, "Powered reverse returns to parking centre through real wheel physics")
		finish(); return
	check(tutorial.flags.reversed and tutorial._fully_parked(vehicle) and tutorial.stage == 1, "Real reverse travel records the maneuver before final engine-off parking")
	check(await stop_and_park(true), "Final service brake, handbrake and engine shutdown complete a stable parking interval")
	check(tutorial.flags.viewed and tutorial.flags.flashlight and tutorial.flags.marker_index == 2 and tutorial.flags.reversed and tutorial.flags.parked and tutorial.stage == 2, "All actual driving conditions advance lesson to stage two")
	check(forward_peak <= 3.0 and reverse_peak <= 2.0, "Forward and reverse replay remain within 3 and 2 m/s")
	check(await WAIT.until(self, func() -> bool: return first_gate.is_open() and first_gate.stable(), 10000, true), "Stage completion opens and settles the first physical gate")
	building.get_node("Switches/Gate01Inside").interact(player)
	building.get_node("Switches/Gate01Outside").interact(player)
	building.get_node("Switches/Gate02Inside").interact(player)
	await physics_seconds(1.2)
	check(first_gate.is_open() and first_gate.target == 1.0 and second_gate.target == 0.0 and second_gate.stable(), "Unlocked first gate stays open while the second gate remains training-locked")
	check(run_owner.phase == "preparing" and not clock.running and not clock.weather_running and not run_owner._status.visible, "Stage advancement retains stopped preparation simulation and no instruction HUD")
	check(not terminal.ui_instance.visible and not player.in_ui_mode, "Driving completion never reopens terminal UI")
	seat.call("exit_seat")
	check(player.seated_in == null and not vehicle.is_player_driving, "Normal seat exit releases driving ownership before capture")
	check(await WAIT.until(self, func() -> bool:
		return not tutorial.entry_snapshot.is_empty() and tutorial.entry_snapshot.get("start_state", {}).get("tutorial", {}).get("stage", 0) == 2,
		10000, true), "Stage-two placeholder creates a coherent retry entry after normal seat exit")
	var checkpoint: Node = root.get_node("Checkpoint")
	var saved: Dictionary = checkpoint.capture_world(world)
	check(not saved.is_empty(), "Completed driving stage can capture a production checkpoint: " + str(checkpoint.last_error))
	if not saved.is_empty():
		check(checkpoint.validation_error(saved).is_empty(), "Real completed-stage checkpoint and its retry entry pass schema validation")
		var saved_tutorial: Dictionary = saved.start_state.tutorial
		var saved_entry: Dictionary = saved_tutorial.get("entry_snapshot", {})
		check(saved_tutorial.stage == 2 and saved_tutorial.status == "active" and saved_tutorial.flags == {"viewed": true, "flashlight": true, "marker_index": 2, "reversed": true, "parked": true}, "Checkpoint preserves actual completed driving conditions at the active stage-two placeholder")
		check(not saved_entry.is_empty() and saved_entry.start_state.tutorial.stage == 2 and saved_entry.start_state.tutorial.flags == saved_tutorial.flags and not saved_entry.start_state.tutorial.has("entry_snapshot"), "Automatic stage-two retry entry preserves completed conditions without recursive snapshots")
		check(saved.start_state.phase == "preparing" and saved.start_state.bay_gates == [true, false, false, false, false, false, false, false], "Completed-stage checkpoint preserves preparation phase and only the first unlocked gate")
	print("TRAINING_DRIVING_SPEEDS: forward=", forward_peak, " reverse=", reverse_peak)
	finish()

func finish() -> void:
	if is_instance_valid(vehicle):
		vehicle.control_override = {"brake": 1.0}
		vehicle.set_handbrake(true)
		vehicle.set_engine_running(false)
	if failures.is_empty(): print("PASS: production tutorial Conditions, flashlight, ordered markers, reverse parking and locked gates")
	if is_instance_valid(world): world.queue_free()
	quit(0 if failures.is_empty() else 1)

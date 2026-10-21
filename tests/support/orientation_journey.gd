extends SceneTree
## Current stage two uses the original production world, stock and Item transactions.
## Actor positions, camera aim and service work time are controlled test inputs.
## No inventory records, successful course flags or material deposits are injected.
const SHUTDOWN_GUARD = preload("res://tests/support/godot_472_shutdown.gd")
const WAIT = preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []
var world: Node3D
var run_owner: Node
var tutorial: Node
var workshop: Node
var vehicle: Chassis
var player: CharacterBody3D
var journey_completed := false

func _init() -> void:
	SHUTDOWN_GUARD.retain_item_base()
	run.call_deferred()

func check(ok: bool, note: String) -> bool:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
		if workshop != null: print("ORIENTATION_WORKSHOP_STATE: ", workshop.capture(), " materials=", vehicle.get_all_items())
	return ok

func frames(count := 3) -> void:
	for index in count: await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = 15
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not check(await world.wait_for_play() and await WAIT.generator_idle(self, generator), "Production two-room world becomes playable"):
		await finish(); return
	run_owner = world.get_node("StartRun")
	tutorial = run_owner.get_node("Tutorial")
	vehicle = tutorial.designated_rv()
	player = world.get_node("Player")
	# Stable ray/transaction fixture. Physical driving is checked separately.
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.set_handbrake(true)
	vehicle.set_engine_running(false)
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	if not await reception(): await finish(); return
	workshop = tutorial.workshop
	if not check(workshop != null and workshop.step == 1, "Entering the workshop starts its equipment lesson"):
		await finish(); return
	if not await initial_state(): await finish(); return
	if not await equipment_lesson(): await finish(); return
	if not await recycling_lesson(): await finish(); return
	if not await manufacturing_lesson(): await finish(); return
	if not await repair_lesson(): await finish(); return
	if not await fuel_lesson(): await finish(); return
	if not await driving_check(): await finish(); return
	if not await completion_check(): await finish(); return
	print("ORIENTATION_WORKSHOP_INPUTS: actor positions/camera aim and elapsed service work; native boot, pickup, placement, recycling, printing, rvctl, wheel and fuel transactions")
	journey_completed = true
	await finish()

func completion_check() -> bool:
	check(run_owner.phase == "preparing" and not world.get_node("WorldClock").running, "Stage-two completion retains the preparation world")
	check(tutorial.status == "active" and tutorial.stage == 2, "Stage two does not fabricate departure completion")
	return failures.is_empty()

func reception() -> bool:
	var terminal: TrainingTerminal = tutorial.designated_terminal()
	if not check(terminal != null and terminal.can_operate(), "Original reception terminal operates on internal power"): return false
	player.global_position = terminal.global_position + Vector3.RIGHT
	terminal.interact_hold(player)
	terminal.start_boot()
	terminal.advance_boot(6.0)
	if not check(tutorial.flags.boot_complete, "Actual boot completion initializes the terminal"): return false
	terminal._close_ui()
	var identity := terminal.persistent_id
	terminal.pickup(player)
	await frames()
	if not check(tutorial.flags.terminal_taken and select_item(identity), "Original dock transaction transfers the terminal into inventory"): return false
	if not check(await WAIT.until(self, func(): return run_owner.shelter.get_node("Gates/Gate01").is_open(), 8000, true), "Original pickup opens the physical inner door"): return false
	# Walk with the real standing capsule after gravity settles it onto the slab.
	# The Player origin is below its feet; a floating y=1 fixture misses this case.
	player.global_transform = run_owner.shelter.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1, -29))
	player.set_physics_process(true)
	for tick in 45: await physics_frame
	check(player.is_on_floor() and run_owner.shelter.to_local(player.global_position).y < 0.0, "Native standing capsule settles with its origin below the floor")
	Input.action_press("move_forward")
	for tick in 180:
		await physics_frame
		if run_owner.shelter.to_local(player.global_position).z > -24.0: break
	Input.action_release("move_forward")
	for tick in 4: await physics_frame
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	if not check(run_owner.shelter.to_local(player.global_position).z > -24.0 and tutorial.flags.workshop_entered, "Native walking through the door activates workshop instructions"): return false
	var reader: Node = player.read_held_terminal()
	if not check(reader != null, "Carried original terminal opens after entering the workshop"): return false
	await frames()
	var page: Dictionary = reader.ui_instance.page_data
	check(reader.ui_instance.visible and page.get("stage") == 2 and "Optional references" in page.get("title", ""), "Visible carried-terminal TUI presents the optional second-room field guide")
	reader._close_ui()
	await frames()
	return failures.is_empty()

func initial_state() -> bool:
	if not check(vehicle.current_fuel == 0.0, "Fresh workshop RV has zero fuel"): return false
	check(vehicle.get_item_count(ItemNames.METAL_PARTS) == 0 and vehicle.get_item_count(ItemNames.UNREFINED_FUEL) == 0, "Course starts without hidden repair or recipe materials")
	for slot in ["left_0", "right_0"]:
		var panel: RVStructurePanel = vehicle.get_node("StructureSlots").panel(slot)
		check(is_equal_approx(panel.max_health - panel.current_health, 60.0), "Original " + slot + " has exactly sixty damage")
	check(vehicle.get_engine() != null and vehicle.get_engine().health == 0.0 and not vehicle.has_working_engine(), "New workshop engine is completely broken")
	check(vehicle.get_node("StructureSlots").panel("roof_1").is_destroyed, "The middle ceiling is completely destroyed")
	var socket: BatterySocket = workshop.item("socket")
	if not check(socket != null and socket.installed_battery != null, "Original installed battery powers the workshop"): return false
	tutorial._physics_process(0.1)
	check(socket.installed_battery.charge == 0.0 and vehicle.current_fuel == 0.0 and not workshop.flags.refueled, "The installed empty battery and fuel stay empty without automatic reserves")
	check(not workshop.item("scrapper").is_fixed and not workshop.item("workbench").is_fixed, "Both designated machines await carrying on the workshop floor")
	if not await pickup("battery"): return false
	socket.interact(player)
	check(workshop.flags.battery_exchanged and socket.installed_battery.id == workshop.targets.battery and vehicle.has_usable_power(), "A native charged-battery exchange restores power before any equipment task")
	var hatch: Node = vehicle.get_node("EngineBay/Hatch")
	await stand_clear()
	hatch.interact(player)
	if not check(await WAIT.until(self, func(): return hatch.stable() and hatch.opened, 5000, true), "Real engine hatch fully opens for kit service"): return false
	for kit in ["engine_kit_a", "engine_kit_b"]:
		if not await pickup(kit): return false
		var identity: String = workshop.targets[kit]
		var health: float = vehicle.get_engine().health
		var operation := RepairOperation.new()
		operation.step(player, vehicle.engine_bay, true, 1.0)
		operation.cancel()
		check(select_item(identity) and vehicle.get_engine().health == health, "Cancelling engine service preserves the kit and broken engine state")
		operation.step(player, vehicle.engine_bay, true, 3.0)
		check(not select_item(identity) and vehicle.get_engine().health == health + 150.0, "Native kit transaction consumes its original Item and restores 150 durability")
	check(workshop.flags.engine_repaired and vehicle.has_working_engine() and workshop.step == 1, "Engine repair is recorded before any equipment, recycling or manufacture task")
	await stand_clear()
	hatch.interact(player)
	if not check(await WAIT.until(self, func(): return hatch.stable() and not hatch.opened, 5000, true), "Engine cover closes after native repair"): return false
	return failures.is_empty()

func select_item(identity: String) -> bool:
	for index in player.inventory.items.size():
		if player.inventory.items[index].state.id == identity:
			player._set_active_slot(index)
			return player.inventory.active_item().get("state", {}).get("id", "") == identity
	return false

func stand_clear() -> void:
	player.rv_support.clear()
	player.global_position = vehicle.to_global(Vector3(4.5, 0, -2.5))
	await physics_frame

func pickup(key: String) -> bool:
	var item: Item = workshop.item(key)
	if not check(item != null, "Designated " + key + " exists before pickup"): return false
	var identity := item.persistent_id
	player.rv_support.clear()
	var approach := run_owner.shelter.get_node_or_null(NodePath("WarehouseApproaches/" + key)) as Marker3D
	if approach != null and approach.global_position.distance_to(item.global_position) <= 2.5:
		# Authored floor approaches keep the standing capsule out of rack/wall
		# collision; its origin rests 0.25 m below the soles after reception.
		player.global_position = approach.global_position - run_owner.shelter.global_basis.y * 0.25
	else:
		player.global_position = item.global_position + vehicle.global_basis.x * 1.2
	var message: String = item.pickup(player)
	await frames()
	return check(select_item(identity), "Native " + key + " pickup retains its original identity: " + message)

func mount(key: String, point: Vector3) -> bool:
	await stand_clear()
	if not check(player.enter_equipment_placement(), "Inventory " + key + " opens its real placement preview"): return false
	for adjustment in [Vector3.ZERO, Vector3(-0.15, 0, 0), Vector3(0, 0, 0.3), Vector3(-0.15, 0, 0.3)]:
		var target: Vector3 = point + adjustment
		await physics_frame
		player.camera.global_position = vehicle.to_global(target + Vector3(0, 1.4, -0.8))
		player.camera.look_at(vehicle.to_global(target), vehicle.global_basis.y)
		player.placement.update_ghost(player)
		if player.placement.can_place_equipment and RVConnection.resolve(player.placement.target_support) == vehicle: break
	if not check(player.placement.can_place_equipment and RVConnection.resolve(player.placement.target_support) == vehicle, "RV floor and overlap rules validate " + key + ": " + player.placement.message):
		player.cancel_equipment_placement()
		return false
	if not check(player.placement.commit(player), "Native " + key + " placement commits its inventory ownership"): return false
	await frames()
	var installed: Item = workshop.item(key)
	print("ORIENTATION_MACHINE_POSE: ", key, " local=", vehicle.to_local(installed.global_position), " bounds=", installed.get_placement_bounds())
	return check(installed.can_operate() and installed.get_connected_rv() == vehicle, "Installed " + key + " operates on the designated RV")

func step_ready(expected: int) -> bool:
	return check(await WAIT.until(self, func(): return workshop.step == expected, 5000, true), "Successful native transactions advance workshop step %d" % expected)

func equipment_lesson() -> bool:
	if not await pickup("scrapper"): return false
	if not check(player.enter_equipment_placement(), "Designated machine starts a cancellable preview"): return false
	player.cancel_equipment_placement()
	check(select_item(workshop.targets.scrapper) and not workshop.flags.scrapper_placed and workshop.step == 1, "Cancelling placement retains inventory and records no installation")
	if not await mount("scrapper", Vector3(1.25, 0.5, -2.2)): return false
	check(workshop.step == 1 and not workshop.flags.workbench_placed, "One machine cannot complete the equipment lesson")
	if not await pickup("workbench") or not await mount("workbench", Vector3(-1.0, 0.5, 1)): return false
	return await step_ready(2)

func recycling_lesson() -> bool:
	var recycler: Item = workshop.item("scrapper")
	# Adversarial signal inputs complement the actual transaction journey below.
	# An event for another RV or an unmarked input cannot alter this ledger.
	var prior: Dictionary = workshop.capture()
	recycler.recycle_committed.emit("other-rv", workshop.targets.scrap_a, {ItemNames.METAL_PARTS: 3})
	recycler.recycle_committed.emit(vehicle.persistent_id, "other-scrap", {ItemNames.METAL_PARTS: 3})
	check(workshop.capture() == prior, "Other RV and other input identities cannot create marked recycling evidence")
	for key in ["scrap_a", "scrap_b", "barrel", "scrap_c", "scrap_d"]:
		if not await pickup(key): return false
		var identity: String = workshop.targets[key]
		await stand_clear()
		if key == "barrel":
			recycler.accept_held_item(player)
		else:
			player.drop_item()
			await frames()
			var input: Item = workshop.by_id(identity)
			if not check(input != null, "Native drop creates the original " + key + " input"): return false
			input.global_position = recycler.to_global(Vector3(0, 1.5, 0))
			recycler.recycle_prop(input)
		if not check(identity not in workshop.recycled_ids, "Queued " + key + " cannot count before its material deposit"): return false
		if key == "scrap_a":
			recycler._on_service_stopped()
			check(identity not in workshop.recycled_ids and is_instance_valid(workshop.by_id(identity)), "Cancelled recycling releases the stock without completion")
			var input: Item = workshop.by_id(identity)
			input.global_position = recycler.to_global(Vector3(0, 1.5, 0))
			if input.has_method("set_processing"): input.set_processing(false)
			recycler.recycle_prop(input)
		recycler.step_work(recycler.crush_time)
		if not check(identity in workshop.recycled_ids, "Actual recycler work commits " + key): return false
	if not check(vehicle.get_item_count(ItemNames.METAL_PARTS) == 14 and vehicle.get_item_count(ItemNames.UNREFINED_FUEL) == 10, "Original stock plus two extra scraps supplies fourteen metal and ten raw fuel"): return false
	return await step_ready(3)

func manufacturing_lesson() -> bool:
	var bench: CraftingStation = workshop.item("workbench")
	await stand_clear()
	if not check(bench.request_craft("gasoline"), "Actual recipe accepts the recycled materials: " + bench.last_error): return false
	check(workshop.output_ids.is_empty() and workshop.gasoline_id.is_empty() and workshop.step == 3, "Adding a recipe to the queue does not count as output or pickup")
	bench.cancel_jobs()
	check(workshop.output_ids.is_empty() and vehicle.get_item_count(ItemNames.METAL_PARTS) == 14 and vehicle.get_item_count(ItemNames.UNREFINED_FUEL) == 10, "Cancelling queued printing restores actual materials and creates no completion")
	if not check(bench.request_craft("gasoline"), "The refunded materials can queue the real fuel recipe"): return false
	bench.step_work(RecipeCatalog.find("gasoline").duration)
	if not check(workshop.output_ids.size() == 1, "Manufacturing creates one physical gasoline can: " + bench.last_error): return false
	check(workshop.gasoline_id.is_empty() and workshop.step == 3, "An uncollected printed can cannot advance the guide")
	var identity: String = workshop.output_ids[0]
	var output: Item = workshop.by_id(identity)
	if not check(output != null, "Printed output exists on the real print bed"): return false
	output.interact(player)
	await frames()
	if not check(workshop.gasoline_id == identity and select_item(identity), "Native printed-can pickup retains the manufactured identity"): return false
	check(vehicle.get_item_count(ItemNames.METAL_PARTS) == 12 and vehicle.get_item_count(ItemNames.UNREFINED_FUEL) == 5, "Gasoline recipe consumes exactly two metal and five raw fuel")
	return await step_ready(4)

func repair_lesson() -> bool:
	await stand_clear()
	var tablet: Item = workshop.item("tablet")
	var construction: RVStructureConstruction = vehicle.get_node("StructureSlots").construction
	tablet.interact_hold(player)
	if not check(construction.begin(tablet, "right_0", "repair").is_empty(), "Existing rvctl begins the first specified wall repair"): return false
	tablet._close_ui()
	check(construction.job.is_empty() and workshop.repaired_ids.is_empty() and vehicle.get_item_count(ItemNames.METAL_PARTS) == 12, "Closing rvctl cancels repair without material consumption or completion")
	for slot in ["right_0", "left_0"]:
		tablet.interact_hold(player)
		if not check(construction.begin(tablet, slot, "repair").is_empty(), "Native rvctl starts repair of " + slot): return false
		construction._physics_process(2.0)
		tablet._close_ui()
		var panel: RVStructurePanel = vehicle.get_node("StructureSlots").panel(slot)
		if not check(slot in workshop.repaired_ids and panel.current_health == panel.max_health, "Real repair transaction restores " + slot): return false
	check(workshop.step == 4 and vehicle.get_item_count(ItemNames.METAL_PARTS) == 8, "Both walls use four metal, leaving enough for ceiling reconstruction")
	tablet.interact_hold(player)
	var roof_reason: String = construction.begin(tablet, "roof_1", "rebuild")
	if not check(roof_reason.is_empty(), "Native rvctl accepts reconstruction of the destroyed roof: " + roof_reason): return false
	construction._physics_process(6.0)
	tablet._close_ui()
	check(workshop.flags.roof_rebuilt and workshop.wall_ready("roof_1") and vehicle.get_item_count(ItemNames.METAL_PARTS) == 2, "Actual roof rebuild restores geometry and consumes six metal, retaining two spare metal")
	var socket: Node3D = vehicle.get_node("WheelSocket0")
	player.global_position = socket.global_position + vehicle.global_basis.x * 2
	socket.interact_hold(player)
	if not check(workshop.flags.wheel_removed and vehicle.installed_wheels[0] == null, "Native wheel removal releases the designated original flat tire"): return false
	var decoy: Item = load("res://props/wheel.tscn").instantiate()
	decoy.persistent_id = "journey-unmarked-healthy-wheel"
	WorldEntities.get_container(world).add_child(decoy)
	decoy.global_position = player.global_position + vehicle.global_basis.x
	decoy.pickup(player)
	await frames()
	if not check(select_item("journey-unmarked-healthy-wheel"), "Negative control picks up an actual unmarked healthy wheel"): return false
	socket.interact_hold(player)
	check(vehicle.wheel_ids[0] == "journey-unmarked-healthy-wheel" and not workshop.flags.wheel_installed and workshop.step == 4, "A real healthy unmarked wheel installation cannot satisfy the marked-spare lesson")
	select_item(workshop.gasoline_id)
	socket.interact_hold(player)
	if not check(vehicle.installed_wheels[0] == null, "Native removal frees the socket after the unmarked-wheel negative control"): return false
	# This extra wheel exists only for the negative control. Leaving it beside
	# the front axle can roll it underneath the RV during the departure test.
	# Keep the original discarded flat tire as part of the production journey.
	var removed_decoy: Item = workshop.by_id("journey-unmarked-healthy-wheel")
	if not check(removed_decoy != null, "Native removal returns the unmarked fixture wheel to the world"): return false
	removed_decoy.queue_free()
	await frames()
	if not await pickup("spare"): return false
	player.global_position = socket.global_position + vehicle.global_basis.x * 2
	socket.interact_hold(player)
	if not check(workshop.flags.wheel_installed and vehicle.installed_wheels[0] != null, "Native wheel insertion installs the marked healthy spare"): return false
	return await step_ready(5)

func fuel_lesson() -> bool:
	var port: Item = workshop.item("fuel_port")
	var decoy: Item = load("res://props/gas_can.tscn").instantiate()
	decoy.persistent_id = "journey-unmarked-fuel-can"
	WorldEntities.get_container(world).add_child(decoy)
	decoy.global_position = player.global_position + vehicle.global_basis.x
	decoy.pickup(player)
	await frames()
	if not check(select_item("journey-unmarked-fuel-can"), "Negative control picks up a real unmarked gasoline can"): return false
	port.interact(player)
	if not check(vehicle.current_fuel > 0.0 and not workshop.flags.refueled and workshop.step == 5, "A real unmarked-can fuel transfer cannot satisfy manufactured-can evidence"): return false
	# Explicit fixture reset after the real rejection-evidence control. Ordinary
	# preparation must never perform this reset or supply a gasoline reserve.
	vehicle.current_fuel = 0.0
	if not check(select_item(workshop.gasoline_id), "Fuel lesson retains the actual manufactured can"): return false
	vehicle.current_fuel = vehicle.max_fuel
	var inventory: Array[Dictionary] = player.inventory.items.duplicate(true)
	port.interact(player)
	check(not workshop.flags.refueled and workshop.step == 5 and player.inventory.items == inventory, "A full tank rejects the fuel transaction without consumption or completion")
	vehicle.current_fuel = 0.0
	tutorial._physics_process(0.1)
	if not check(vehicle.current_fuel == 0.0 and not workshop.flags.refueled, "Workshop fuel stays zero across preparation ticks"): return false
	var filled_id: String = workshop.gasoline_id
	var before: int = player.inventory.items.size()
	port.interact(player)
	if not check(workshop.flags.refueled and workshop.refuel_amount == vehicle.fuel_per_gas_can and vehicle.current_fuel == vehicle.fuel_per_gas_can, "Real designated fuel-port transfer fills the original RV"): return false
	if not check(not select_item(filled_id) and select_item(workshop.empty_can_id) and player.inventory.active_item().scene_path == "res://props/gas_can_empty.tscn" and player.inventory.items.size() == before, "Native fuel conversion returns a real identified empty can"): return false
	if not await step_ready(6): return false
	check(workshop.ready_for_departure(), "Completed ledger also has working machines, healthy walls/spare and actual fuel")
	var scrapper: Item = workshop.item("scrapper")
	scrapper.enabled = false
	check(workshop.ready_for_departure() and tutorial.departure_block_reason().is_empty(), "Disabled workshop equipment cannot turn optional tasks into an exit lock")
	scrapper.enabled = true
	var wall: RVStructurePanel = vehicle.get_node("StructureSlots").panel("left_0")
	wall.set_health(wall.max_health - 1.0)
	check(workshop.ready_for_departure() and tutorial.departure_block_reason().is_empty(), "An unfinished side wall cannot turn optional repair into an exit lock")
	wall.set_health(wall.max_health)
	var wheel_health: float = vehicle.wheel_health[0]
	vehicle.wheel_health[0] = 0.0
	check(workshop.ready_for_departure() and tutorial.departure_block_reason().is_empty(), "A flat tire affects ordinary physics without creating a tutorial exit lock")
	vehicle.wheel_health[0] = wheel_health
	return check(workshop.ready_for_departure(), "Restored current working states recover readiness without replaying evidence")

func driving_check() -> bool:
	var poses := {}
	for key in ["scrapper", "workbench"]: poses[key] = vehicle.to_local(workshop.item(key).global_position)
	var seat: Item = vehicle.get_node("DriverSeat")
	player.global_position = seat.global_position + vehicle.global_basis.z
	seat.interact_hold(player)
	if not check(player.seated_in == seat and vehicle.is_player_driving, "Native seat owns the restored RV for its short driving check"): return false
	vehicle.allow_test_controls = true
	vehicle.freeze = false
	vehicle.set_physics_process(true)
	for tick in 5: await physics_frame
	if not check(vehicle.set_gear(1) and vehicle.set_engine_running(true), "Repaired RV accepts its real forward gear and engine start"): return false
	vehicle.set_handbrake(false)
	var origin := vehicle.global_position
	vehicle.control_override = {"throttle": 0.35}
	for tick in 120: await physics_frame
	vehicle.control_override = {"brake": 1.0}
	var distance := vehicle.global_position.distance_to(origin)
	if not check(distance > 0.5 and vehicle.global_basis.y.y > 0.8, "Native wheel forces drive the repaired original RV with both machines aboard"): return false
	for key in ["scrapper", "workbench"]:
		var machine: Item = workshop.item(key)
		check(machine.can_operate() and machine.get_connected_rv() == vehicle and vehicle.to_local(machine.global_position).distance_to(poses[key]) < 0.02, "Driving preserves the fastened " + key + " pose and service")
	print("ORIENTATION_WORKSHOP_DRIVE: wheel_distance=", distance, " position=", run_owner.shelter.to_local(vehicle.global_position))
	return failures.is_empty()

func finish() -> void:
	if not journey_completed and failures.is_empty(): check(false, "The complete workshop journey must reach its final checkpoint")
	if is_instance_valid(world):
		world.queue_free()
		await frames()
	if failures.is_empty(): print("PASS: orientation workshop native production journey")
	quit(0 if failures.is_empty() else 1)

extends "res://tests/test_training_workshop.gd"
## Stage seven uses real service transactions and independent checkpoint retry state.
var maintenance_entry: Dictionary = {}

func stage_ready(expected: int) -> bool:
	if expected == 7:
		if not check(await WAIT.until(self, func(): return tutorial.stage == 7, 5000, true), "Controller enters maintenance before readiness checks"): return false
		tutorial.set_physics_process(false)
		if not check(await WAIT.until(self, func(): return run_owner.save_block_reason().is_empty(), 5000, true), "Prior bay gates finish their physical opening before readiness checks"): return false
		var service: TutorialService = tutorial.service
		var original_health: float = vehicle.get_engine().health
		var original_wheel: float = vehicle.wheel_health[0]
		var original_materials: Dictionary = vehicle.get_all_items()
		check(not service.configure_if_ready(vehicle) and not service.configured, "Outside bay seven cannot configure faults or supplies")
		var height: float = run_owner.shelter.to_local(vehicle.global_position).y
		vehicle.global_transform = run_owner.shelter.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0, height, -94))
		player.global_position = run_owner.shelter.to_global(Vector3(9, 0.1, -94))
		await physics_frame
		await frames()
		var seat: Item = workshop.item("seat")
		if seat == null: seat = vehicle.get_node("DriverSeat")
		seat.interact_hold(player)
		check(player.seated_in != null and not service.configure_if_ready(vehicle), "Seated player cannot configure the maintenance exercise")
		seat.exit_seat()
		player.set_physics_process(false)
		await physics_frame
		await frames()
		if not check(player.get_player_mode() == player.PlayerMode.NORMAL, "Real seat exit releases its player mode: " + str(seat.exit_message)): return false
		player.global_position = run_owner.shelter.to_global(Vector3(9, 0.1, -94))
		vehicle.set_engine_running(true)
		check(not service.configure_if_ready(vehicle), "Running engine cannot configure maintenance")
		vehicle.set_engine_running(false)
		vehicle.set_handbrake(false)
		check(not service.configure_if_ready(vehicle), "Released handbrake cannot configure maintenance")
		vehicle.set_handbrake(true)
		var tablet: Item = workshop.item("tablet")
		tablet.interact_hold(player)
		if not player.in_ui_mode:
			print("MAINTENANCE_TABLET: mode=", player.get_player_mode(), " can_operate=", tablet.can_operate(), " power=", vehicle.current_power, " visible=", tablet.ui_instance.visible, " current_user=", tablet.current_user)
		check(player.in_ui_mode and not service.configure_if_ready(vehicle), "Active tablet interaction cannot configure maintenance")
		tablet._close_ui()
		check(not service.configured and vehicle.get_engine().health == original_health and vehicle.wheel_health[0] == original_wheel and vehicle.get_all_items() == original_materials, "All rejected preparation attempts preserve durability and resources")
		check(workshop.by_id(vehicle.persistent_id + ":training:repair-kit") == null and workshop.by_id(vehicle.persistent_id + ":training:spare-wheel") == null, "Rejected preparation grants no maintenance stock")
		tutorial.set_physics_process(true)
	return await super.stage_ready(expected)

func continue_training() -> bool:
	var service: TutorialService = tutorial.service
	maintenance_entry = tutorial.entry_snapshot.duplicate(true)
	var configured: Dictionary = service.capture()
	var materials: Dictionary = vehicle.get_all_items()
	var engine: EngineState = vehicle.get_engine()
	var wall: RVStructurePanel = vehicle.get_node("StructureSlots").panel("left_0")
	check(service.configured and service.engine_id == engine.id and service.wheel_id == vehicle.wheel_ids[0], "Configuration records the original engine and mounted wheel")
	check(engine.health == engine.definition().max_health - 150.0 and wall.current_health == wall.max_health - 60.0 and vehicle.wheel_health[0] == 0.0, "Maintenance applies exactly its three designated faults")
	check(vehicle.get_item_count(ItemNames.METAL_PARTS) >= 2 and workshop.by_id(service.kit_id) != null and workshop.by_id(service.spare_id) != null, "Configuration provides actual repair materials and physical marked stock")
	service.configure_if_ready(vehicle)
	check(service.capture() == configured and vehicle.get_all_items() == materials, "Repeated preparation does not shock the vehicle or duplicate supplies")
	if not await repair_original_engine(): return false
	check(service.flags.engine and not service.flags.wall and not service.flags.wheel, "Engine may complete first without completing the lesson")
	var current: Dictionary = checkpoint.capture_world(world)
	if not check(not current.is_empty() and checkpoint.validation_error(current).is_empty(), "Partial maintenance captures a valid current checkpoint"): return false
	if not await load_and_verify(current, "Partial maintenance checkpoint"): return false
	service = tutorial.service
	check(service.capture() == current.start_state.tutorial.service and service.flags.engine and vehicle.get_engine().health == vehicle.get_engine().definition().max_health, "Partial reload preserves genuine engine success without applying faults again")
	check(tutorial.entry_snapshot == maintenance_entry, "Partial reload preserves the earlier configured retry boundary")
	check_maintenance_ownership(checkpoint.capture_world(world), service)
	if not check(await tutorial.restart_stage(), "Maintenance retry replaces the world from its actual configured entry"): return false
	world = current_scene
	if not await WAIT.generator_idle(self, world.get_node("WorldGenerator")) or not await WAIT.retired_candidates(self, checkpoint): return false
	_bind_fixture()
	service = tutorial.service
	check(service.capture() == configured and tutorial.entry_snapshot == maintenance_entry and vehicle.get_all_items() == materials, "Retry restores initial maintenance faults, supplies and evidence exactly once")
	check_maintenance_ownership(checkpoint.capture_world(world), service)
	if not await repair_original_engine(): return false
	if not await replace_original_wheel(): return false
	# Recorded successes remain insufficient while the current engine is unusable.
	vehicle.get_engine().health = 0.0
	if not await repair_wall(): return false
	check(service.flags.engine and service.flags.wall and service.flags.wheel and not service.complete() and tutorial.stage == 7, "Three recorded repairs cannot advance while the current original engine is unusable")
	vehicle.get_engine().health = vehicle.get_engine().definition().max_health
	if not await stage_ready(8): return false
	check(tutorial.terminal_page().available and run_owner.phase == "preparing", "Successful maintenance captures the stage-eight fuel entry and retains departure lock")
	var gate: ShelterGarageGate = run_owner.shelter.get_node("Gates").get_child(6)
	check(gate.is_open() and run_owner.bay_unlocked(6), "Maintenance success opens actual gate seven")
	return true

func take_service_item(identity: String) -> bool:
	var item: Item = workshop.by_id(identity)
	if not check(item != null, "Physical service stock exists: " + identity): return false
	player.global_position = item.global_position + vehicle.global_basis.x * 1.2
	item.pickup(player)
	await frames()
	return check(select_item(identity), "Physical service pickup selects original identity " + identity)

func repair_original_engine() -> bool:
	var service: TutorialService = tutorial.service
	var bay: Node = vehicle.engine_bay
	var hatch: Node = bay.get_node("Hatch")
	player.global_position = run_owner.shelter.to_global(Vector3(9, 0.1, -94))
	if not hatch.opened: hatch.interact(player)
	if not check(await WAIT.until(self, func(): return hatch.stable() and hatch.opened, 5000, true), "Real maintenance hatch physically opens before repair"): return false
	var repair := RepairOperation.new()
	var initial_health: float = vehicle.get_engine().health
	if select_item(workshop.gasoline_id): repair.step(player, bay, true, 3.0)
	check(not service.flags.engine and vehicle.get_engine().health == initial_health, "Non-kit inventory cannot repair the engine or record success")
	var original: EngineState = vehicle.get_engine()
	bay.installed_engine = EngineState.new()
	check(not service.engine_ready() and not service.complete(), "Substituting a healthy different engine cannot satisfy original-engine maintenance")
	bay.installed_engine = original
	if not await take_service_item(service.kit_id): return false
	repair.step(player, bay, true, 1.5)
	repair.cancel()
	check(not service.flags.engine and select_item(service.kit_id) and original.health == initial_health, "Cancelled engine repair retains its physical kit and damaged original engine")
	repair.step(player, bay, true, 3.0)
	check(service.flags.engine and service.engine_ready() and not select_item(service.kit_id), "Holding H commits one real kit and repairs the original engine")
	return true

func replace_original_wheel() -> bool:
	var service: TutorialService = tutorial.service
	var socket: Node = vehicle.get_node("WheelSocket0")
	select_item(workshop.gasoline_id)
	vehicle.add_item(ItemNames.METAL_PARTS, 2)
	RepairOperation.new().step(player, socket, true, 2.0)
	check(vehicle.wheel_health[0] > 0.0 and not service.flags.wheel, "H patching the original mounted tire does not count as replacement")
	socket.interact_hold(player)
	check(service.flags.removed and vehicle.installed_wheels[0] == null and not service.flags.wheel, "Real socket removal creates the original wheel output without completing replacement")
	if not await take_service_item(service.wheel_id): return false
	socket.interact_hold(player)
	check(vehicle.wheel_ids[0] == service.wheel_id and not service.flags.wheel, "Actual reinstallation of the original patched tire cannot count")
	select_item(workshop.gasoline_id)
	socket.interact_hold(player)
	if not await take_service_item(service.spare_id): return false
	socket.interact_hold(player)
	check(service.flags.wheel and service.wheel_ready() and not select_item(service.spare_id), "Actual designated spare insertion transfers its identity from inventory to wheel ownership")
	check_maintenance_ownership(checkpoint.capture_world(world), service)
	return true

func repair_wall() -> bool:
	var service: TutorialService = tutorial.service
	var wall: RVStructurePanel = vehicle.get_node("StructureSlots").panel("left_0")
	var initial: float = wall.current_health
	wall.set_health(wall.max_health)
	check(not service.flags.wall, "Direct wall health restoration records no construction transaction")
	wall.set_health(initial)
	var construction: RVStructureConstruction = vehicle.get_node("StructureSlots").construction
	var tablet: Item = workshop.item("tablet")
	tablet.interact_hold(player)
	var before: int = vehicle.get_item_count(ItemNames.METAL_PARTS)
	check(construction.begin(tablet, "left_0", "repair").is_empty(), "Real tablet starts designated wall repair")
	construction._physics_process(1.0)
	tablet._close_ui()
	check(not service.flags.wall and wall.current_health == initial and vehicle.get_item_count(ItemNames.METAL_PARTS) == before, "Closing tablet cancels wall work without charging or counting success")
	tablet.interact_hold(player)
	if not check(construction.begin(tablet, "left_0", "repair").is_empty(), "Real tablet restarts designated wall repair"): return false
	construction._physics_process(2.0)
	check(service.flags.wall and service.wall_ready() and vehicle.get_item_count(ItemNames.METAL_PARTS) == before - 2, "Committed wall repair consumes real materials and records full durability")
	tablet._close_ui()
	return true

func check_maintenance_ownership(snapshot: Dictionary, service: TutorialService) -> void:
	for identity in [service.kit_id, service.spare_id, service.wheel_id]:
		var counts: Dictionary = ownership(snapshot, identity)
		var mounted_wheel := 0
		for record: Dictionary in snapshot.vehicles:
			for wheel: Dictionary in record.wheels:
				if wheel.get("id", "") == identity and wheel.get("installed", false): mounted_wheel += 1
		var total := mounted_wheel
		for value: int in counts.values(): total += value
		check(total <= 1, "Maintenance item has at most one inventory, world or installed-wheel owner: " + identity)

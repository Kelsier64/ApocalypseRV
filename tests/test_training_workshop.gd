extends SceneTree
## Production lessons 2-6: real stock, UI, inventory placement and material work.
## Only lesson one and actor positions are fixture setup; no workshop flags are set.
const WAIT = preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []
var world: Node3D
var run_owner: StartRun
var tutorial: TutorialController
var workshop: TutorialWorkshop
var vehicle: Chassis
var player: CharacterBody3D
var checkpoint: Node
var stage_entries: Dictionary = {}

func _init() -> void: _run.call_deferred()

func check(okay: bool, detail: String) -> bool:
	if not okay:
		failures.append(detail)
		push_error("FAIL: " + detail)
		if is_instance_valid(tutorial) and is_instance_valid(workshop) and is_instance_valid(vehicle):
			print("WORKSHOP_STATE: stage=", tutorial.stage, " flags=", workshop.flags,
				" recycled=", workshop.recycled_ids, " outputs=", workshop.output_ids,
				" materials=", vehicle.get_all_items(), " checkpoint_error=", checkpoint.last_error)
	return okay

func frames(count := 3) -> void:
	for frame in count: await process_frame

func tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await frames()

func _bind_fixture() -> void:
	run_owner = world.get_node("StartRun")
	tutorial = run_owner.get_node("Tutorial")
	workshop = tutorial.workshop
	vehicle = tutorial.designated_rv()
	player = world.get_node("Player")
	# Stable deck rays and deterministic work calls isolate the transactions from
	# the driving lesson, which has its own wheel-driven production test.
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.set_handbrake(true)
	vehicle.set_engine_running(false)
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO

func _run() -> void:
	root.size = Vector2i(1280, 720)
	checkpoint = root.get_node("Checkpoint")
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = 11
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play() or not await WAIT.generator_idle(self, generator):
		check(false, "Production v11 workshop world becomes ready")
		await finish(); return
	tutorial = world.get_node("StartRun/Tutorial")
	if not await WAIT.until(self, func(): return tutorial.initialized() and not tutorial.entry_snapshot.is_empty(), 30000, true):
		check(false, "Production lesson one initializes its stock and retry state")
		await finish(); return
	_bind_fixture()
	# Prior driving is explicitly outside this fixture. Subsequent lessons must
	# advance through the actual controller and successful gameplay transactions.
	tutorial.flags = {"viewed": true, "flashlight": true, "marker_index": 2, "reversed": true, "parked": true}
	tutorial.stage = 2
	tutorial.entry_snapshot.clear()
	run_owner.apply_tutorial_gates()
	if not await stage_ready(2): await finish(); return
	if not await battery_lesson(): await finish(); return
	if not await console_lesson(): await finish(); return
	if not await placement_lesson(): await finish(); return
	if not await restart_recycling_lesson(): await finish(); return
	if not await recycling_lesson(): await finish(); return
	if not await manufacturing_lesson(): await finish(); return
	check(tutorial.stage == 7 and tutorial.status == "active" and tutorial.terminal_page().available and tutorial.service.configured, "Stage seven offers its configured maintenance exercise")
	check(run_owner.phase == "preparing" and not world.get_node("WorldClock").running, "Workshop completion retains preparation and stopped world time")
	for index in range(8):
		var gate: ShelterGarageGate = run_owner.shelter.get_node("Gates").get_child(index)
		check(gate.is_open() == (index < 6) and run_owner.bay_unlocked(index) == (index < 6), "Completed gates 1-6 open; later gate %d retains its lock" % (index + 1))
	run_owner.shelter.get_node("GarageButton").interact(player)
	check(run_owner.phase == "preparing", "Pending maintenance cannot bypass the tutorial departure lock")
	if not await continue_training(): await finish(); return
	if not await reload_stage_entries(): await finish(); return
	await finish()

func stage_ready(expected: int) -> bool:
	if expected == 7:
		if is_instance_valid(player.seated_in): player.seated_in.exit_seat()
		var height: float = run_owner.shelter.to_local(vehicle.global_position).y
		vehicle.global_transform = run_owner.shelter.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0, height, -94))
		player.global_position = run_owner.shelter.to_global(Vector3(9, 0.1, -94))
		player.velocity = Vector3.ZERO
	var ready: bool = await WAIT.until(self, func(): return tutorial.stage == expected and not tutorial.entry_snapshot.is_empty() and run_owner.save_block_reason().is_empty(), 30000, true)
	if not ready and expected == 7:
		print("MAINTENANCE_READY: configured=", tutorial.service.configured,
			" fully_inside=", tutorial._fully_inside(vehicle, TutorialService.PARKING),
			" local_rv=", run_owner.shelter.to_local(vehicle.global_position),
			" player_mode=", player.get_player_mode(), " seated=", player.seated_in,
			" engine_running=", vehicle.energy.engine_running, " brake=", vehicle.handbrake,
			" velocity=", vehicle.linear_velocity, " angular=", vehicle.angular_velocity,
			" save_block=", run_owner.save_block_reason(), " checkpoint_error=", checkpoint.last_error)
	if not check(ready, "Stage %d advances and captures its genuine stable entry" % expected): return false
	var saved: Dictionary = checkpoint.capture_world(world)
	if not check(not saved.is_empty(), "Stage %d captures a real current checkpoint" % expected): return false
	check(checkpoint.validation_error(saved).is_empty(), "Stage %d current and retry checkpoint schemas validate" % expected)
	check(saved.start_state.tutorial.stage == expected and saved.start_state.tutorial.entry_snapshot.start_state.tutorial.stage == expected, "Stage %d snapshot and independent entry retain the same explicit lesson" % expected)
	check(not saved.start_state.tutorial.entry_snapshot.start_state.tutorial.has("entry_snapshot"), "Stage %d entry contains no recursively nested retry snapshot" % expected)
	if expected in range(2, 7) and not stage_entries.has(expected):
		stage_entries[expected] = tutorial.entry_snapshot.duplicate(true)
	return true

func continue_training() -> bool:
	return true

func select_item(identity: String) -> bool:
	for index in player.inventory.items.size():
		if player.inventory.items[index].state.id == identity:
			player._set_active_slot(index)
			return player.inventory.active_item().get("state", {}).get("id", "") == identity
	return false

func pickup(key: String) -> bool:
	var item := workshop.item(key)
	if not check(item != null, "Designated " + key + " exists before pickup"): return false
	var identity := item.persistent_id
	# Repositioning gives the transaction fixture physical reach; it never
	# supplies inventory records or successful tutorial events.
	player.global_position = item.global_position + vehicle.global_basis.x * 1.2
	var message: String = item.pickup(player)
	await frames()
	return check(select_item(identity), "Actual " + key + " pickup transfers its original identity: " + message)

func battery_lesson() -> bool:
	var socket := workshop.item("socket") as BatterySocket
	if not check(socket != null and socket.installed_battery != null, "Battery lesson uses the designated original socket"): return false
	var original_id: String = socket.installed_battery.id
	player.global_position = socket.global_position + vehicle.global_basis.x
	socket.interact_hold(player)
	check(socket.installed_battery == null and not workshop.flags.battery, "Removing the original battery does not complete replacement")
	if not check(select_item(original_id), "Removed original battery remains selectable in the real inventory"): return false
	socket.interact(player)
	await physics_frame
	check(socket.installed_battery != null and socket.installed_battery.id == original_id and tutorial.stage == 2 and not workshop.flags.battery, "Reinstalling the original battery cannot complete stage two")
	if not await pickup("battery"): return false
	player.global_position = socket.global_position + vehicle.global_basis.x
	socket.interact(player)
	check(socket.installed_battery != null and socket.installed_battery.id == workshop.targets.battery and workshop.flags.battery, "Actual reserve-battery exchange records the designated charged battery")
	return await stage_ready(3)

func console_lesson() -> bool:
	var tablet := workshop.item("tablet")
	var ui: Node = tablet.ui_instance
	ui.select_page("energy")
	await frames()
	check(not workshop.flags.energy, "Hidden tablet navigation cannot complete a workshop page")
	tablet.interact_hold(player)
	await frames()
	check(workshop.flags.overview and player.in_ui_mode, "The real mounted tablet presents its Overview page")
	ui.select_page("energy")
	ui.select_page("equipment")
	await frames()
	check(workshop.flags.equipment and not workshop.flags.energy, "Only the rendered page counts when an earlier selection is replaced")
	ui.select_page("energy")
	await frames()
	check(workshop.flags.energy, "Presenting the Energy page records the actual console session")
	ui.select_page("equipment")
	await frames()
	ui._set_light("cabin", true)
	check(not workshop.flags.lights_on, "Turning cabin lights on before an off action cannot finish the cycle")
	ui._set_light("cabin", false)
	check(workshop.flags.lights_off and not vehicle.interior_requested.cabin and tutorial.stage == 3, "Actual console Off transaction records the first half of the lighting cycle")
	ui._set_light("cabin", true)
	check(workshop.flags.lights_on and vehicle.interior_requested.cabin, "Actual console On transaction restores cabin lights")
	tablet._close_ui()
	return await stage_ready(4)

func mount(key: String, local: Vector3) -> bool:
	if not check(player.enter_equipment_placement(), "Inventory " + key + " opens an actual placement preview"): return false
	player.global_position = vehicle.to_global(Vector3(0, 0.55, 0))
	# Every candidate is validated by the real camera ray and overlap rules.
	# Small aim adjustments accommodate the raised deck and extending mast.
	for adjustment in [Vector3.ZERO, Vector3(-0.15, 0, 0), Vector3(0, 0, 0.3), Vector3(-0.15, 0, 0.3)]:
		var target: Vector3 = local + adjustment
		player.camera.global_position = vehicle.to_global(target + Vector3(0, 1.4, -0.8))
		player.camera.look_at(vehicle.to_global(target), vehicle.global_basis.y)
		await physics_frame
		player.placement.update_ghost(player)
		if player.placement.can_place_equipment and RVConnection.resolve(player.placement.target_support) == vehicle: break
	if not check(player.placement.can_place_equipment and RVConnection.resolve(player.placement.target_support) == vehicle, "Real RV deck ray validates " + key + " placement: " + player.placement.message):
		player.cancel_equipment_placement()
		return false
	if not check(player.placement.commit(player), "Validated " + key + " preview commits through inventory ownership"): return false
	await physics_frame
	await frames()
	var installed := workshop.item(key)
	return check(installed != null and installed.can_operate() and installed.get_connected_rv() == vehicle, "Committed " + key + " retains its designated identity and RV service")

func placement_lesson() -> bool:
	if not await pickup("scrapper"): return false
	if not check(player.enter_equipment_placement(), "Training scrapper starts the preview intended for Escape cancellation"): return false
	await tap(KEY_ESCAPE)
	check(workshop.flags.cancelled and not player.is_placing_equipment() and not player.settings_open and select_item(workshop.targets.scrapper), "Actual Escape input cancels the designated preview without opening settings or consuming inventory")
	if not await mount("scrapper", Vector3(1.1, 0.5, 3)): return false
	if not await pickup("workbench") or not await mount("workbench", Vector3(-1, 0.5, 4)): return false
	check(tutorial.stage == 4 and workshop.flags.scrapper_placed and workshop.flags.workbench_placed and not workshop.flags.remounted, "Installing both machines alone cannot bypass the required remount")
	if not await pickup("scrapper"): return false
	check(workshop.targets.scrapper in workshop.unmounted_ids and not workshop.flags.remounted, "Actual installed-machine pickup records its former RV ownership")
	if not await mount("scrapper", Vector3(1.1, 0.5, 3)): return false
	return await stage_ready(5)

func recycle_scrap(key: String) -> bool:
	if not await pickup(key): return false
	var identity: String = workshop.targets[key]
	var recycler := workshop.item("scrapper")
	player.global_position = recycler.global_position + vehicle.global_basis.x * 1.2
	player.drop_item()
	await frames()
	var input := workshop.by_id(identity)
	if not check(input != null and not select_item(identity), "Dropping " + key + " creates one physical input and releases inventory ownership"): return false
	input.global_position = recycler.to_global(Vector3(0, 1.5, 0))
	recycler.recycle_prop(input)
	check(identity not in workshop.recycled_ids and input.processing_owner == recycler, "Queued " + key + " is not yet a committed tutorial deposit")
	recycler.step_work(recycler.crush_time)
	return check(identity in workshop.recycled_ids, "Production scrapper deposits the actual " + key + " yield")

func restart_recycling_lesson() -> bool:
	var entry := tutorial.entry_snapshot.duplicate(true)
	var targets := workshop.targets.duplicate(true)
	var materials := vehicle.get_all_items()
	if not await recycle_scrap("scrap_a"): return false
	check(workshop.recycled_ids.size() == 1 and vehicle.get_item_count(ItemNames.METAL_PARTS) == int(materials.get(ItemNames.METAL_PARTS, 0)) + 3, "Stage five records partial recycling and its actual materials")
	workshop.item("scrap_b").queue_free()
	workshop.item("scrapper").queue_free()
	await frames()
	check(workshop.item("scrap_b") == null and workshop.item("scrapper") == null and tutorial.can_restart(), "Losing both stock and installed recycler retains the genuine stage retry")
	var current: Dictionary = checkpoint.capture_world(world)
	check(not current.is_empty() and checkpoint.validation_error(current).is_empty(), "Partial progress with lost designated actors remains a valid current checkpoint")
	if not check(await tutorial.restart_stage(), "Stage-five restart performs an actual in-memory world replacement"): return false
	world = current_scene
	if not check(await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, checkpoint), "Restarted stage-five world and retired candidate settle"): return false
	_bind_fixture()
	check(tutorial.stage == 5 and workshop.recycled_ids.is_empty() and workshop.targets == targets, "Restart resets partial recycling to its entry and retains all designated IDs")
	check(vehicle.get_all_items() == materials and tutorial.entry_snapshot == entry, "Restart restores actual material storage and preserves the original retry boundary")
	for key in ["scrap_a", "scrap_b", "barrel", "scrapper", "workbench"]:
		check(workshop.item(key) != null and workshop.item(key).persistent_id == targets[key], "Restart restores lost/consumed " + key + " with its original identity")
	check(workshop.item("scrapper").can_operate() and workshop.item("workbench").can_operate(), "Restart restores both prior installed workshop services")
	return await stage_ready(5)

func recycling_lesson() -> bool:
	var recycler := workshop.item("scrapper")
	var metal_before := vehicle.get_item_count(ItemNames.METAL_PARTS)
	var fuel_before := vehicle.get_item_count(ItemNames.UNREFINED_FUEL)
	var unrelated: Item = load("res://props/scrap.tscn").instantiate()
	WorldEntities.get_container(world).add_child(unrelated)
	unrelated.scrap_yields = {ItemNames.METAL_PARTS: Vector2(1, 1)}
	unrelated.global_position = recycler.to_global(Vector3(0, 1.5, 0))
	recycler.recycle_prop(unrelated)
	recycler.step_work(recycler.crush_time)
	check(workshop.recycled_ids.is_empty() and vehicle.get_item_count(ItemNames.METAL_PARTS) == metal_before + 1, "A real unrelated scrap deposit cannot impersonate marked tutorial stock")
	if not await recycle_scrap("scrap_a") or not await recycle_scrap("scrap_b"): return false
	if not await pickup("barrel"): return false
	player.global_position = recycler.global_position + vehicle.global_basis.x * 1.2
	var accepted: String = recycler.accept_held_item(player)
	check(workshop.recycled_ids.size() == 2 and not select_item(workshop.targets.barrel), "Actual large-item intake consumes the barrel without prematurely committing it: " + accepted)
	recycler.step_work(recycler.crush_time)
	check(workshop.recycled_ids.size() == 3 and vehicle.get_item_count(ItemNames.METAL_PARTS) == metal_before + 9 and vehicle.get_item_count(ItemNames.UNREFINED_FUEL) == fuel_before + 10, "Two marked scraps and oil barrel commit deterministic usable recipe materials")
	return await stage_ready(6)

func manufacturing_lesson() -> bool:
	var bench := workshop.item("workbench") as CraftingStation
	var recipe := RecipeCatalog.find("gasoline")
	player.global_position = vehicle.to_global(Vector3(0, 0.55, 0))
	if not check(bench.request_craft("gasoline"), "Recycled materials fund the actual designated workbench recipe: " + bench.last_error): return false
	check(tutorial.stage == 6 and workshop.output_ids.is_empty() and workshop.gasoline_id.is_empty(), "Queueing gasoline cannot complete the manufacture or pickup conditions")
	bench.step_work(recipe.duration * 0.5)
	check(workshop.output_ids.is_empty(), "A partial gasoline print does not complete manufacture")
	bench.step_work(recipe.duration)
	if not check(workshop.output_ids.size() == 1 and bench.jobs.is_empty() and workshop.gasoline_id.is_empty(), "Actual completed recipe creates one recorded physical output without granting it"): return false
	await physics_frame
	check(tutorial.stage == 6, "Stage six waits for actual pickup after successful manufacture")
	var identity: String = workshop.output_ids[0]
	# Preserve the current progress after manufacture, while the independent
	# stage entry still has no completed output. Loading must retain that split.
	var current: Dictionary = checkpoint.capture_world(world)
	if not check(not current.is_empty() and checkpoint.validation_error(current).is_empty(), "Finished gasoline output captures a valid current workshop checkpoint"): return false
	if not await load_and_verify(current, "Current stage-six checkpoint"): return false
	check(workshop.output_ids == [identity] and workshop.gasoline_id.is_empty() and tutorial.entry_snapshot.start_state.tutorial.workshop.output_ids.is_empty(), "Current checkpoint restores manufactured output separately from its earlier retry boundary")
	var gasoline := workshop.by_id(identity)
	if not check(gasoline != null and gasoline.scene_file_path == recipe.scene_path, "Recorded output is a real gasoline Item in the production world"): return false
	player.global_position = gasoline.global_position + vehicle.global_basis.x
	gasoline.interact(player)
	check(workshop.gasoline_id == identity and select_item(identity), "Actual gasoline pickup records the manufactured identity and inventory ownership")
	return await stage_ready(7)

func reload_stage_entries() -> bool:
	for stage in range(2, 7):
		if not check(stage_entries.has(stage), "Stage %d retains its first genuine entry for reload coverage" % stage): return false
		var entry: Dictionary = stage_entries[stage]
		if not await load_and_verify(entry, "Stage %d entry retry" % stage): return false
		check(tutorial.can_restart() and tutorial.entry_snapshot == entry, "Stage %d entry reload immediately preserves its exact reusable retry boundary" % stage)
	return true

func load_and_verify(saved: Dictionary, label: String) -> bool:
	var expected: Dictionary = saved.start_state.tutorial
	var old_world_id := world.get_instance_id()
	if not check(await checkpoint.load_snapshot(world, saved), label + " completes an actual in-memory world replacement"): return false
	world = current_scene
	if not check(world.get_instance_id() != old_world_id, label + " replaces the production world rather than mutating progress flags"): return false
	if not check(await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, checkpoint), label + " settles generation and retires its staging candidate"): return false
	_bind_fixture()
	await physics_frame
	check(tutorial.stage == expected.stage and tutorial.status == expected.status and workshop.capture() == expected.workshop, label + " restores exact lesson flags, designated targets and output ledgers")
	check(player.inventory.items == saved.player.items, label + " restores actual player inventory records without granting items")
	var expected_vehicle: Dictionary = {}
	for record: Dictionary in saved.vehicles:
		if record.id == expected.rv_id: expected_vehicle = record
	if not check(not expected_vehicle.is_empty(), label + " identifies its saved designated vehicle"): return false
	check(vehicle.persistent_id == expected_vehicle.id and vehicle.get_all_items() == expected_vehicle.materials and vehicle.stored_items == expected_vehicle.items, label + " restores the same RV, material storage and stored inventory")
	var actual: Dictionary = checkpoint.capture_world(world)
	if not check(not actual.is_empty() and checkpoint.validation_error(actual).is_empty(), label + " recaptures a valid current and retry world"): return false
	# Item identity can be owned by a socket or inventory rather than a world
	# actor. Compare all designated ownership locations, including consumed stock.
	var identities: Array = expected.workshop.targets.values()
	identities.append_array(expected.workshop.output_ids)
	for identity: String in identities:
		var before := ownership(saved, identity)
		var after := ownership(actual, identity)
		check(after == before, label + " retains canonical ownership without respawning or duplicating " + identity)
		var owners := 0
		for count: int in after.values(): owners += count
		check(owners <= 1, label + " gives " + identity + " at most one gameplay owner")
	for actor: Dictionary in expected_vehicle.mounted_items:
		if actor.state.id not in [expected.workshop.targets.scrapper, expected.workshop.targets.workbench]: continue
		var installed := workshop.by_id(actor.state.id)
		check(installed != null and installed.can_operate() and installed.get_connected_rv() == vehicle and installed.capture_service_state() == actor.state.service, label + " restores the prior installed workshop service " + actor.scene)
	for index in range(8):
		var gate: ShelterGarageGate = run_owner.shelter.get_node("Gates").get_child(index)
		check(gate.is_open() == saved.start_state.bay_gates[index] and run_owner.bay_unlocked(index) == (index < expected.stage - 1), label + " restores physical gate %d and its later-stage lock" % (index + 1))
	var expected_entry: Dictionary = expected.get("entry_snapshot", saved)
	check(tutorial.entry_snapshot == expected_entry and tutorial.can_restart(), label + " keeps the independent original entry available for another retry")
	check(run_owner.phase == saved.start_state.phase and run_owner.phase == "preparing", label + " preserves preparation without automatic departure")
	return true

func ownership(snapshot: Dictionary, identity: String) -> Dictionary:
	var counts := {"world": 0, "mounted": 0, "inventory": 0, "stored": 0, "socket": 0}
	for item: Dictionary in snapshot.player.items:
		if item.state.id == identity: counts.inventory += 1
	for actor: Dictionary in snapshot.actors:
		if actor.kind == "item" and actor.state.id == identity: counts.world += 1
	for record: Dictionary in snapshot.vehicles:
		for item: Dictionary in record.items:
			if item.state.id == identity: counts.stored += 1
		for actor: Dictionary in record.mounted_items:
			if actor.state.id == identity: counts.mounted += 1
			if actor.scene == "res://rv/battery_socket.tscn" and actor.state.service.get("battery", {}).get("id", "") == identity: counts.socket += 1
	return counts

func finish() -> void:
	if is_instance_valid(world):
		world.get_node("WorldGenerator").set_process(false)
		await WAIT.generator_idle(self, world.get_node("WorldGenerator"))
		await WAIT.navigation_bakes_finished(self, world)
		world.free()
		for frame in 2:
			await physics_frame
			await process_frame
	if failures.is_empty(): print("PASS: production workshop lessons 2-6, current-output checkpoint and every stage entry reload")
	quit(0 if failures.is_empty() else 1)

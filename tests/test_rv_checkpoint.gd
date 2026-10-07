extends SceneTree
var failures: Array[String] = []
const PATH := "res://.godot/test-rv-checkpoint.save"
const WAIT = preload("res://tests/support/test_wait.gd")

func _init() -> void:
	_run.call_deferred()

func expect(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	var world: Node3D = load("res://world/test_world.tscn").instantiate()
	world.get_node("WorldGenerator").world_seed = 1790440711
	root.add_child(world)
	current_scene = world
	await process_frame
	var rv: Chassis = world.get_node("NewRv/Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = world.get_node("Player")
	player.set_physics_process(false)
	var station: CraftingStation = rv.get_node("CraftingStation")
	station.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1, 2)), rv)
	var scrapper: Item = rv.get_node("Scrapper")
	scrapper.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1, -2)), rv)
	rv.add_item(ItemNames.METAL_PARTS, 10)
	rv.add_item(ItemNames.UNREFINED_FUEL, 10)
	rv.current_power = 42.0
	rv.set_engine_running(true)
	station.request_craft("gasoline")
	station.step_work(0.5)
	var prop: Item = world.get_node("Scrap")
	prop.global_position = scrapper.global_position + Vector3.UP
	scrapper.recycle_prop(prop)
	scrapper.step_work(0.4)
	if not await _finish_navigation(world):
		quit(1)
		return
	# Real terminal construction must give F6 a useful reason while its operator
	# is in UI mode, rather than failing through the generic interaction gate.
	var construction_slots: Node = rv.get_node("StructureSlots")
	var construction: Node = construction_slots.construction
	var terminal: Node = rv.get_node("TabletScreen")
	var checkpoint_gate: Node = root.get_node("Checkpoint")
	rv.set_engine_running(false)
	construction_slots.panel("front").set_health(60.0)
	terminal.interact_hold(player)
	expect(player.get_player_mode() == player.PlayerMode.UI and terminal.ui_instance.visible, "Real tablet puts the save operator in UI mode")
	var blocked_path := PATH + ".construction-" + InstanceIds.create()
	expect(not checkpoint_gate.save_world(world, blocked_path) and checkpoint_gate.last_error.code == "state", "Ordinary tablet UI still prevents saving when no construction job exists")
	expect(construction.begin(terminal, "front", "repair").is_empty(), "Real tablet starts construction for save gate fixture")
	expect(not checkpoint_gate.save_world(world, blocked_path) and checkpoint_gate.last_error.code == "motion" and checkpoint_gate.error_message().contains("車體施工中"), "Saving during actual tablet construction reports the specific construction reason before UI mode")
	expect(not FileAccess.file_exists(blocked_path), "Blocked construction save creates no file")
	terminal._close_ui()
	expect(not construction.is_building() and player.get_player_mode() == player.PlayerMode.NORMAL, "Closing tablet cancels construction and restores normal player mode")
	construction_slots.panel("front").set_health(120.0)
	rv.set_engine_running(true)
	var charge := rv.current_power
	var installed_ref: WeakRef = weakref(rv.energy.battery)
	var battery_id := rv.energy.battery.id
	var rv_id := rv.persistent_id
	var scrap_id := prop.persistent_id
	var fuel := rv.current_fuel
	var saved_materials := rv.get_all_items()
	var visited := {"actors": [], "layout": InteriorLayout.generate(42), "explored": ["r000"]}
	world.get_node("PoiInstances").saved_instances["visited"] = visited
	var spare: Item = world.get_node("SpareBattery")
	var spare_ref: WeakRef = weakref(spare.battery)
	spare.battery.charge = 17.0
	player.add_prop_item(spare, spare.scene_file_path)
	spare.queue_free()
	await process_frame
	# One engine in each ownership domain must survive disk restore exactly once.
	var installed_engine_id := rv.get_engine().id
	rv.get_engine().health = 311.0
	var carried := EngineState.new({"model": "upgraded", "health": 273.0})
	var carried_item := carried.item()
	player.add_item(carried_item.name, true, carried_item.scene_path, carried_item.state)
	var stored := EngineState.new({"health": 0.0})
	rv.stored_items.append(stored.item())
	var loose: Item = load("res://props/engine_upgraded.tscn").instantiate()
	loose.restore_item_state(EngineState.new({"model": "upgraded", "health": 91.0}).item().state)
	WorldEntities.get_container(world).add_child(loose)
	loose.global_position = rv.global_position + Vector3(9, 1, 0)
	loose.freeze = true
	var loose_id: String = loose.engine.id
	rv.headlights_requested = true
	rv.engine_bay.get_node("Hatch").set_open(true)
	var checkpoint := root.get_node("Checkpoint")
	var clock: WorldClock = world.get_node("WorldClock")
	clock.running = false
	clock.set_time(3, 17.75)
	clock.weather.set_weather(Vector3(0, 2, 2))
	clock.weather.advance(360)
	player.current_stamina = 12.0
	player.stamina_exhausted = true
	var structure_slots: Node = rv.get_node("StructureSlots")
	structure_slots.panel("front").set_health(37.0)
	structure_slots.panel("left_2").take_damage(999.0)
	structure_slots.panel("rear").restore_angles([-0.2, 0.4])
	structure_slots.panel("roof_0").set_health(37.0)
	structure_slots.panel("roof_1").set_health(40.0)
	expect(structure_slots.panel("roof_1").definition.type_id == "rv_ceiling_hatch", "Default middle roof retains the left hatch variant")
	structure_slots.panel("roof_2").take_damage(999.0)
	await process_frame # Commit supported Item drops before capturing the graph.
	var preview_path := PATH + ".preview-" + InstanceIds.create()
	expect(player.enter_equipment_placement(), "Held engine enters the real Item placement preview")
	expect(not checkpoint.save_world(world, preview_path) and checkpoint.last_error.code == "preview", "Placement preview blocks saving with a concrete reason")
	expect(not FileAccess.file_exists(preview_path), "Rejected placement preview creates no checkpoint")
	player.cancel_equipment_placement()
	expect(player.get_player_mode() == player.PlayerMode.NORMAL and player.inventory.active_item().state.id == carried.id, "Cancelling save-blocking preview retains the same carried Item")
	expect(checkpoint.save_world(world, PATH), "Checkpoint writes main-world snapshot")
	print("CHECKPOINT written")
	var saved: Dictionary = checkpoint.read_checkpoint(PATH)
	expect(not saved.is_empty(), "Checkpoint validates from disk without objects")
	if saved.is_empty():
		world.queue_free()
		await process_frame
		quit(1)
		return
	expect(saved.version == 5 and saved.vehicles[0].structures.size() == 11, "Disk checkpoint keeps eleven damageable structures separate from the fixed chassis deck")
	for item in saved.vehicles[0].mounted_items:
		expect(item.support.get("slot", "") != "floor", "Installed Item never references a removed floor structure")
	expect(saved.clock == clock.capture(), "Checkpoint captures day, fractional time and day duration")
	expect(saved.weather == clock.weather.capture(), "Checkpoint captures weather transition and RNG")
	expect(saved.get("generation_version") == 6, "Generation version independent of checkpoint version")
	expect(saved.player.stamina == 12.0 and saved.player.stamina_exhausted, "Checkpoint stores current stamina and exhaustion.")
	var old_player_data := saved.duplicate(true)
	old_player_data.player.erase("stamina")
	old_player_data.player.erase("stamina_exhausted")
	expect(checkpoint.validation_error(old_player_data).is_empty(), "Older checkpoints without stamina remain valid.")
	var legacy_data := saved.duplicate(true)
	legacy_data.erase("generation_version")
	legacy_data.erase("clock")
	legacy_data.erase("weather")
	legacy_data.profile.erase("generation_version")
	checkpoint.pending = legacy_data
	var legacy_world: Node3D = load("res://world/test_world.tscn").instantiate()
	checkpoint.prepare_world(legacy_world)
	expect(legacy_world.get_node("WorldClock").hour_of_day() == 8.0, "Legacy checkpoint without time starts at 08:00")
	expect(legacy_world.get_node("WorldClock").weather.sample() == Vector3.ZERO, "Legacy checkpoint defaults to dry overcast")
	expect(legacy_world.get_node("WorldGenerator").profile.generation_version == 2, "Unversioned worlds keep v2 geometry")
	legacy_world.free()
	legacy_data = saved.duplicate(true)
	legacy_data.generation_version = 3
	checkpoint.pending = legacy_data
	legacy_world = load("res://world/test_world.tscn").instantiate()
	checkpoint.prepare_world(legacy_world)
	var legacy_profile: WorldProfile = legacy_world.get_node("WorldGenerator").profile
	expect(legacy_profile.generation_version == 3 and legacy_profile.terrain_half_width == 225, "Explicit v3 worlds retain original width despite newer saved profile fields")
	legacy_world.free()
	checkpoint.pending = {}
	var bad := saved.duplicate(true)
	bad.clock.elapsed_seconds = NAN
	checkpoint.write_checkpoint(PATH + ".badclock", bad)
	expect(checkpoint.read_checkpoint(PATH + ".badclock").is_empty(), "Invalid saved clock rejected before world restore")
	var bad_weather := saved.duplicate(true)
	bad_weather.weather.remaining = NAN
	expect(checkpoint.validation_error(bad_weather) == "weather", "Invalid weather rejected before mutation")
	bad = saved.duplicate(true)
	bad.player.items.append(rv.get_engine().item())
	checkpoint.write_checkpoint(PATH + ".duplicate", bad)
	expect(checkpoint.read_checkpoint(PATH + ".duplicate").is_empty(), "Duplicate engine across installed and inventory ownership rejected")
	bad = saved.duplicate(true)
	bad.player.stamina = -1.0
	expect(checkpoint.validation_error(bad) == "player.stamina", "Invalid stamina is rejected before restore.")
	bad = saved.duplicate(true)
	bad.version = -1
	checkpoint.write_checkpoint(PATH + ".invalid", bad)
	expect(checkpoint.read_checkpoint(PATH + ".invalid").is_empty(), "Unsupported version rejected")
	print("CHECKPOINT validated, freeing old world")
	world.queue_free()
	await process_frame
	expect(installed_ref.get_ref() == null and spare_ref.get_ref() == null, "Old world releases installed and inventory source batteries")
	print("CHECKPOINT old world released")
	checkpoint.pending = saved
	world = load("res://world/test_world.tscn").instantiate()
	world.get_node("WorldClock").running = false
	root.add_child(world)
	expect(world.get_node("WorldClock").capture() == saved.clock, "Disk restore preserves clock before first rendered frame")
	expect(world.get_node("WorldClock").weather.capture() == saved.weather, "Disk restore preserves weather before first rendered frame")
	expect(world.get_node("WorldClock").label.text == "DAY 3   17:45", "Restored clock HUD is populated immediately")
	current_scene = world
	var restored: Chassis = get_first_node_in_group(Groups.CHASSIS)
	restored.freeze = true
	restored.set_physics_process(false)
	player = world.get_node("Player")
	player.set_physics_process(false)
	expect(player.current_stamina == 12.0 and player.stamina_exhausted, "Checkpoint restores stamina and exhaustion.")
	var restored_ref: WeakRef = weakref(restored.energy.battery)
	if not await _finish_navigation(world):
		quit(1)
		return
	expect(restored.persistent_id == rv_id and restored.energy.battery.id == battery_id, "Vehicle and battery identity restored")
	expect(is_equal_approx(restored.current_power, charge) and is_equal_approx(restored.current_fuel, fuel), "Charge and fuel not reset by scene loading")
	expect(restored.get_all_items() == saved_materials and restored.energy.engine_running, "Materials and running engine restored")
	expect(player.inventory.items[0].state.battery.charge == 17.0, "Inventory battery charge survives disk save")
	expect(restored.get_engine().id == installed_engine_id and restored.get_engine().health == 311.0, "Installed engine survives disk restore")
	expect(player.inventory.items[1].state.engine.id == carried.id and player.inventory.items[1].state.engine.health == 273.0, "Carried upgraded engine keeps ID and durability")
	expect(restored.stored_items.size() == 3 and restored.stored_items[2].state.engine.id == stored.id and restored.stored_items[2].state.engine.health == 0.0, "Stored broken engine persists without starter kit duplication")
	expect(restored.headlights_requested and restored.engine_bay.hatch_open, "Headlight request and service hatch persist")
	expect(restored.get_node("StructureSlots").snapshot() == saved.vehicles[0].structures, "Disk restore preserves structure damage, destroyed gap and door angles")
	expect(restored.get_node("StructureSlots").occupant("left_2") == null, "Disk load never automatically fills a destroyed wall slot")
	expect(restored.get_node("StructureSlots").occupant("roof_2") == null and restored.get_node("StructureSlots").occupant("roof_0") != null, "Disk load preserves the rear roof gap without removing the surviving front roof")
	expect(restored.get_node("StructureSlots").panel("roof_1").definition.type_id == "rv_ceiling_hatch", "Disk load retains the hatch roof type independently of neighbouring segments")
	var loose_matches := 0
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Item and actor.persistent_id == loose_id:
			loose_matches += 1
			expect(actor.engine.health == 91.0 and actor.engine.model_id == "upgraded", "Ground engine keeps model and durability")
	expect(loose_matches == 1, "Ground engine restores exactly once")
	expect(world.get_node("PoiInstances").saved_instances.get("visited") == visited, "Exact bunker manifest and exploration survive checkpoint")
	var restored_station: CraftingStation
	var restored_scrapper: Item
	for device in restored.get_equipment():
		if device is CraftingStation: restored_station = device
		if "props_being_crushed" in device: restored_scrapper = device
	expect(restored_station.jobs.size() == 1 and is_equal_approx(restored_station.jobs[0].remaining, 1.5), "Craft progress restored without charging materials again")
	expect(restored_scrapper.props_being_crushed.size() == 1, "Scrapper input restored once")
	expect(restored_scrapper.props_being_crushed[0].prop.persistent_id == scrap_id, "Input identity retained")
	expect(is_equal_approx(restored_scrapper.props_being_crushed[0].timer, 1.1), "Scrapper progress retained")
	var matches := 0
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Item and actor.persistent_id == scrap_id: matches += 1
	expect(matches == 1, "Processing input is not duplicated into world actors")
	world.queue_free()
	await process_frame
	await process_frame
	expect(restored_ref.get_ref() == null, "Restored world releases its battery")
	if failures.is_empty():
		print("PASS: disk checkpoint, world restore, battery and production ownership")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

# This short test rebuilds then destroys a whole procedural world. Await its
# background work instead of shutting down NavigationServer during a bake.
func _finish_navigation(world: Node3D) -> bool:
	var generator: Node = world.get_node("WorldGenerator")
	generator.set_process(false)
	if not await WAIT.until(self, func() -> bool: return not generator.building):
		push_error("FAIL: checkpoint terrain build did not finish within 60 seconds")
		return false
	if not await WAIT.navigation_bakes_finished(self, world):
		push_error("FAIL: checkpoint navigation bake did not finish within 60 seconds")
		return false
	await physics_frame
	await process_frame
	return true

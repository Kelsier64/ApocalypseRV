extends SceneTree
var failures: Array[String] = []
const PATH := "res://.godot/test-rv-checkpoint.save"

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
	var station: CraftingStation = world.get_node("CraftingStation")
	station.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1, 2)), rv)
	var scrapper: Equipment = world.get_node("Scrapper")
	scrapper.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1, -2)), rv)
	rv.add_item(ItemNames.METAL_PARTS, 10)
	rv.add_item(ItemNames.UNREFINED_FUEL, 10)
	rv.current_power = 42.0
	rv.set_engine_running(true)
	station.request_craft("gasoline")
	station.step_work(0.5)
	var prop: Prop = world.get_node("Scrap")
	prop.global_position = scrapper.global_position + Vector3.UP
	scrapper.recycle_prop(prop)
	scrapper.step_work(0.4)
	await _finish_navigation(world)
	var charge := rv.current_power
	var installed_ref: WeakRef = weakref(rv.energy.battery)
	var battery_id := rv.energy.battery.id
	var rv_id := rv.persistent_id
	var scrap_id := prop.persistent_id
	var fuel := rv.current_fuel
	var saved_materials := rv.get_all_items()
	world.get_node("PoiInstances").saved_instances["visited"] = {"actors": []}
	var spare: Prop = world.get_node("SpareBattery")
	var spare_ref: WeakRef = weakref(spare.battery)
	spare.battery.charge = 17.0
	player.add_prop_item(spare, spare.scene_file_path)
	spare.queue_free()
	await process_frame
	var checkpoint := root.get_node("Checkpoint")
	expect(checkpoint.save_world(world, PATH), "Checkpoint writes main-world snapshot")
	print("CHECKPOINT written")
	var saved: Dictionary = checkpoint.read_checkpoint(PATH)
	expect(not saved.is_empty(), "Checkpoint validates from disk without objects")
	var bad := saved.duplicate(true)
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
	root.add_child(world)
	current_scene = world
	var restored: Chassis = get_first_node_in_group(Groups.CHASSIS)
	restored.freeze = true
	restored.set_physics_process(false)
	player = world.get_node("Player")
	player.set_physics_process(false)
	var restored_ref: WeakRef = weakref(restored.energy.battery)
	await _finish_navigation(world)
	expect(restored.persistent_id == rv_id and restored.energy.battery.id == battery_id, "Vehicle and battery identity restored")
	expect(is_equal_approx(restored.current_power, charge) and is_equal_approx(restored.current_fuel, fuel), "Charge and fuel not reset by scene loading")
	expect(restored.get_all_items() == saved_materials and restored.energy.engine_running, "Materials and running engine restored")
	expect(player.inventory.items[0].state.battery.charge == 17.0, "Inventory battery charge survives disk save")
	expect(world.get_node("PoiInstances").saved_instances.has("visited"), "POI memory survives checkpoint")
	var restored_station: CraftingStation
	var restored_scrapper: Equipment
	for device in restored.get_equipment():
		if device is CraftingStation: restored_station = device
		if "props_being_crushed" in device: restored_scrapper = device
	expect(restored_station.jobs.size() == 1 and is_equal_approx(restored_station.jobs[0].remaining, 1.5), "Craft progress restored without charging materials again")
	expect(restored_scrapper.props_being_crushed.size() == 1, "Scrapper input restored once")
	expect(restored_scrapper.props_being_crushed[0].prop.persistent_id == scrap_id, "Input identity retained")
	expect(is_equal_approx(restored_scrapper.props_being_crushed[0].timer, 1.1), "Scrapper progress retained")
	var matches := 0
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Prop and actor.persistent_id == scrap_id: matches += 1
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
func _finish_navigation(world: Node3D) -> void:
	var generator: Node = world.get_node("WorldGenerator")
	generator.set_process(false)
	while generator.building:
		await process_frame
	for chunk in generator.active_chunks:
		var navigation: NavigationRegion3D = chunk.node.navigation
		if navigation:
			while NavigationServer3D.is_baking_navigation_mesh(navigation.navigation_mesh):
				await process_frame
	await physics_frame
	await process_frame

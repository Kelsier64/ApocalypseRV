extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)
func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(15, 2, 0)
	world.add_child(player)
	player.set_physics_process(false)
	# Use the installed production devices. The old extra workstation floated
	# above the floor, leaving too little roof clearance for a correctly raised can.
	var recycler: Equipment = rv.get_node("Scrapper")
	var station: CraftingStation = rv.get_node("CraftingStation")
	await physics_frame
	# Fix the loot roll, not the production result: exercise pickup/drop and the real recycler.
	var loot: Prop = load("res://props/oil_barrel.tscn").instantiate()
	world.add_child(loot)
	loot.scrap_yields = {ItemNames.METAL_PARTS: Vector2(4, 4), ItemNames.UNREFINED_FUEL: Vector2(10, 10)}
	loot.interact(player)
	await process_frame
	check(player.inventory.items.size() == 1, "Loot enters inventory")
	player.drop_item()
	var dropped: Prop
	for child in WorldEntities.get_container(world).get_children():
		if child is Prop and child.item_name == "Oil Barrel": dropped = child
	check(dropped != null and player.inventory.items.is_empty(), "Dropped loot retains one world owner")
	dropped.global_position = recycler.global_position + Vector3.UP
	recycler.recycle_prop(dropped)
	rv.current_fuel = 0.0
	rv.current_power = 10.0
	rv.step_energy_system(0.0, 0.0, 0.0, 1.5)
	check(rv.get_item_count(ItemNames.UNREFINED_FUEL) == 10 and rv.get_item_count(ItemNames.METAL_PARTS) == 4, "Loot becomes usable materials")
	check(station.request_craft("gasoline"), "Recycled materials fund fuel recipe")
	rv.step_energy_system(0.0, 0.0, 0.0, 2.0)
	var gasoline: Prop
	for child in WorldEntities.get_container(world).get_children():
		if child is Prop and child.item_name == ItemNames.GAS_CAN: gasoline = child
	check(gasoline != null and station.jobs.is_empty(), "Production creates physical fuel once")
	if gasoline == null:
		push_error("FAIL: Production creates physical fuel once: " + station.last_error)
		quit(1)
		return
	gasoline.interact(player)
	rv.get_node("FuelPort").interact(player)
	check(rv.current_fuel == 30.0 and player.get_active_item_name() == ItemNames.GAS_CAN_EMPTY, "Refueling transfers fuel and returns empty can")
	rv.get_node("FuelPort").take_damage(60.0)
	RepairOperation.new().step(player, rv.get_node("FuelPort"), true, 2.0)
	check(rv.get_node("FuelPort").current_health == rv.get_node("FuelPort").max_health and rv.get_item_count(ItemNames.METAL_PARTS) == 0, "Remaining scrap repairs installed equipment")
	rv.current_power = 0.0
	check(rv.set_engine_running(true), "Empty battery can recover through manual ignition")
	rv.step_energy_system(0.0, 0.0, 0.0, 5.0)
	check(rv.current_power > 0.0 and rv.current_fuel < 30.0, "Recycled fuel charges depleted battery")
	rv.get_node("DriverSeat").interact_hold(player)
	rv.handbrake = false
	rv.allow_test_controls = true
	rv.control_override = {"throttle": 0.3}
	rv._physics_process(1.0 / 60.0)
	check(rv.engine_force < 0.0 and player.seated_in != null, "Repaired and refueled vehicle permits departure")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: loot, recycle, craft, refuel, repair, recharge and departure cycle")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

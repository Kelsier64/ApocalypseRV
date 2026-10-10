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
	var recycler: Item = rv.get_node("Scrapper")
	var station: CraftingStation = rv.get_node("CraftingStation")
	await physics_frame
	# Fix the loot roll, not the production result: exercise pickup/drop and the real recycler.
	var loot: Item = load("res://props/oil_barrel.tscn").instantiate()
	world.add_child(loot)
	loot.scrap_yields = {ItemNames.METAL_PARTS: Vector2(4, 4), ItemNames.UNREFINED_FUEL: Vector2(10, 10)}
	loot.interact(player)
	await process_frame
	check(player.inventory.items.size() == 1, "Loot enters inventory")
	player.drop_item()
	var dropped: Item
	for child in WorldEntities.get_container(world).get_children():
		if child is Item and child.item_name == "Oil Barrel": dropped = child
	check(dropped != null and player.inventory.items.is_empty(), "Dropped loot retains one world owner")
	dropped.global_position = recycler.global_position + Vector3.UP
	recycler.recycle_prop(dropped)
	rv.current_fuel = 0.0
	# Observe actual upper surface displacement through the production pivots.
	# A paired shredder must feed both sides inward, and stop when unpowered.
	rv.current_power = 0.0
	var stopped1: Basis = recycler.roller1.basis
	var stopped2: Basis = recycler.roller2.basis
	var remaining: float = recycler.props_being_crushed[0].timer
	recycler.step_work(.02)
	check(recycler.roller1.basis.is_equal_approx(stopped1) and recycler.roller2.basis.is_equal_approx(stopped2) and is_equal_approx(recycler.props_being_crushed[0].timer, remaining), "Unpowered cutter stacks retain pose and input progress")
	rv.current_power = 10.0
	var surface1: Vector3 = recycler.roller1.to_local(recycler.to_global(recycler.roller1.position + Vector3.UP * .19))
	var upper1: Vector3 = recycler.to_local(recycler.roller1.to_global(surface1))
	var surface2: Vector3 = recycler.roller2.to_local(recycler.to_global(recycler.roller2.position + Vector3.UP * .19))
	var upper2: Vector3 = recycler.to_local(recycler.roller2.to_global(surface2))
	rv.step_energy_system(0.0, 0.0, 0.0, .02)
	var moved1: Vector3 = recycler.to_local(recycler.roller1.to_global(surface1))
	var moved2: Vector3 = recycler.to_local(recycler.roller2.to_global(surface2))
	check(moved1.x < upper1.x and moved2.x > upper2.x and moved1.y < upper1.y and moved2.y < upper2.y, "Both powered roller surfaces move inward and down toward the cutting nip")
	rv.step_energy_system(0.0, 0.0, 0.0, 1.48)
	check(rv.get_item_count(ItemNames.UNREFINED_FUEL) == 10 and rv.get_item_count(ItemNames.METAL_PARTS) == 4, "Loot becomes usable materials")
	check(station.request_craft("gasoline"), "Recycled materials fund fuel recipe")
	rv.step_energy_system(0.0, 0.0, 0.0, 2.0)
	var gasoline: Item
	for child in WorldEntities.get_container(world).get_children():
		if child is Item and child.item_name == ItemNames.GAS_CAN: gasoline = child
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

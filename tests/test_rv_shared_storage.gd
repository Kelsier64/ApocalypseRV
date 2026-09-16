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
	world.add_child(player)
	player.position = Vector3(10, 2, 0)
	player.set_physics_process(false)
	await physics_frame
	var socket: BatterySocket = rv.get_node("BatterySocket")
	var battery_id := socket.installed_battery.id
	rv.current_power = 37.0
	socket.start_placement(player)
	var container := WorldEntities.get_container(world)
	var drops: Array[Prop] = []
	for child in container.get_children():
		if child is Prop and child.item_name == ItemNames.BATTERY: drops.append(child)
	check(drops.size() == 1 and rv.current_power == 0.0, "Moving socket drops exactly one battery and disconnects power")
	check(drops[0].battery.id == battery_id and drops[0].battery.charge == 37.0, "Dropped battery preserves identity and charge")
	check(absf(rv.to_local(drops[0].global_position).x) > 2.5, "Dropped battery clears chassis collision")
	socket.cancel_placement()
	player.placement.placing_equipment = null
	check(socket.installed_battery == null, "Cancelling move does not recreate dropped battery")
	drops[0].interact(player)
	await process_frame
	socket.interact(player)
	check(rv.current_power == 37.0, "Dropped battery can be picked up and reinstalled")
	socket.take_damage(999.0)
	check(socket.installed_battery == null and rv.current_power == 0.0, "Damaged socket ejects its battery")
	var count := 0
	var recovered: Prop
	for child in container.get_children():
		if child is Prop and child.item_name == ItemNames.BATTERY and not child.is_queued_for_deletion():
			count += 1
			recovered = child
	check(count == 1, "Repeated service cleanup does not duplicate battery")
	socket.drop_battery()
	socket.repair_health(999.0)
	recovered.interact(player)
	await process_frame
	socket.interact(player)
	var second: BatterySocket = load("res://rv/battery_socket.tscn").instantiate()
	rv.add_child(second)
	second.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(2.2, 0.2, -1)), rv)
	player.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"battery": {"id": "spare", "charge": 19.0, "capacity": 100.0, "weight": 15.0}})
	check(second.interact(player).contains("另一個") and second.installed_battery == null, "Second socket cannot connect a second battery")
	check(rv.remove_battery_to_player(player), "Remove first battery before choosing another socket")
	second.interact(player)
	check(socket.installed_battery == null and second.installed_battery != null and rv.current_power == 19.0, "Any empty installed socket can accept the only vehicle battery")
	second.interact(player)
	check(rv.current_power == 37.0 and player.inventory.active_item().state.battery.charge == 19.0, "Explicit target socket swaps its own battery")
	var box: Equipment = rv.get_node("ItemBox")
	rv.stored_items.clear() # Isolate the one-slot storage transaction from starter supplies.
	rv.item_capacity = 1
	check(rv.store_player_item(player, 0), "Battery enters chassis warehouse")
	player.add_item(ItemNames.WHEEL, false, "res://props/wheel.tscn", {"condition": 27.0})
	check(not rv.store_player_item(player, 0) and player.inventory.items.size() == 1, "Full warehouse leaves source item unchanged")
	for index in range(5): player.add_item(ItemNames.WHEEL, false, "res://props/wheel.tscn")
	check(not rv.take_stored_item(player, 0) and rv.stored_items.size() == 1, "Full backpack leaves warehouse item unchanged")
	player.inventory.items.clear()
	var power := rv.current_power
	rv.step_energy_system(0.0, 0.0, 0.0, 2.0)
	check(rv.stored_items[0].state.battery.charge == 19.0 and rv.current_power < power, "Warehouse battery does not drain or supply power")
	var second_box: Equipment = load("res://equipment/item_box.tscn").instantiate()
	rv.add_child(second_box)
	second_box.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 4, 0)), rv)
	rv.current_power = 0.0
	second_box.interact(player)
	check(player.in_ui_mode and second_box.storage_ui.rv == rv, "Another box opens same storage without power")
	second_box.take_damage(999.0)
	check(not player.in_ui_mode and rv.stored_items.size() == 1, "Box destruction closes UI and retains warehouse")
	box.detach_from_support()
	check(rv.item_capacity == 1 and rv.stored_items.size() == 1, "Removing box does not remove capacity or items")
	check(rv.take_stored_item(player, 0) and player.inventory.items[0].state.battery.charge == 19.0, "Recovered warehouse battery retains its state")
	rv.store_player_item(player, 0)
	rv.current_fuel = 43.0
	var port: Equipment = rv.get_node("FuelPort")
	port.detach_from_support()
	check(rv.current_fuel == 43.0 and rv.max_fuel == 100.0, "Removing filler leaves chassis fuel")
	player.add_item(ItemNames.GAS_CAN, false, "res://props/gas_can.tscn")
	check(port.interact(player).contains("尚未接入") and player.get_active_item_name() == ItemNames.GAS_CAN, "Detached port refuses refueling without consuming can")
	rv.current_power = 0.0
	var seat: Equipment = rv.get_node("DriverSeat")
	seat.interact_hold(player)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_B
	event.pressed = true
	seat._unhandled_input(event)
	check(rv.energy.engine_running, "Driver B starts without battery charge")
	seat._unhandled_input(event)
	check(not rv.energy.engine_running, "Driver B stops same engine")
	seat.exit_seat()
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved), "New storage snapshot validates")
	var before := container.get_child_count()
	check(VehicleSnapshot.apply(rv, saved), "Storage snapshot applies")
	check(rv.current_fuel == 43.0 and rv.stored_items[0].state.battery.charge == 19.0 and rv.item_capacity == 1, "Fuel, warehouse states and capacities restored")
	check(container.get_child_count() == before, "Restoring vehicle does not eject or duplicate old installed battery")
	# Convert representative v1 data through the disk checkpoint entry point.
	var legacy := saved.duplicate(true)
	legacy.version = 1
	legacy.health = 450.0
	legacy.battery = {"id": "old-installed", "charge": 28.0, "capacity": 100.0, "weight": 15.0}
	for index in range(legacy.equipment.size() - 1, -1, -1):
		if legacy.equipment[index].scene == "res://rv/battery_socket.tscn": legacy.equipment.remove_at(index)
	legacy.equipment.append({"scene": "res://equipment/fuel_tank.tscn", "id": "old-tank", "transform": Transform3D.IDENTITY, "health": 120.0, "enabled": true, "support": "chassis", "service": {"fuel": 33.0, "capacity": 100.0}})
	legacy.equipment.append({"scene": "res://equipment/material_rack.tscn", "id": "old-rack", "transform": Transform3D.IDENTITY, "health": 120.0, "enabled": true, "support": "chassis", "service": {"capacity": 300}})
	for field in ["items", "fuel", "fuel_capacity", "material_capacity", "item_capacity"]: legacy.erase(field)
	var bundle := {"name": "Material Bundle", "is_large": false, "scene_path": "res://props/material_bundle.tscn", "state": {"materials": {"Metal Parts": 7}}}
	var old := {"version": 1, "vehicles": [legacy], "actors": [],
		"seed": 12, "bands": [0], "poi": {"visited": {"actors": [{"scene": bundle.scene_path, "state": {"materials": {"Metal Parts": 2}}}]}},
		"player": {"items": [bundle], "slot": 0, "health": 100.0, "transform": Transform3D.IDENTITY}}
	var checkpoint := root.get_node("Checkpoint")
	var path := "res://.godot/rv-storage-legacy.save"
	checkpoint.write_checkpoint(path, old)
	var upgraded: Dictionary = checkpoint.read_checkpoint(path)
	check(not upgraded.is_empty(), "Legacy disk checkpoint upgrades")
	if not upgraded.is_empty():
		check(upgraded.vehicles[0].fuel == 33.0 and upgraded.vehicles[0].materials["Metal Parts"] == 9, "Legacy fuel and inventory/POI bundles credited once")
		check(upgraded.player.items.is_empty() and upgraded.poi.visited.actors.is_empty(), "Converted material models removed")
		check(VehicleSnapshot.apply(rv, upgraded.vehicles[0]) and rv.energy.battery.id == "old-installed" and rv.current_power == 28.0, "Old installed battery becomes a socket battery")
		check(checkpoint.read_checkpoint(path).vehicles[0].materials["Metal Parts"] == 9, "Repeated loading never double-credits migration")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: shared warehouse, battery ejection, fuel ownership, powerless driver and save migration")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Real service owners publish only completed construction, repair, wheel and fuel transfers.
var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var construction_events: Array = []
var engine_events: Array = []
var wheel_remove_events: Array = []
var wheel_install_events: Array = []
var fuel_events: Array = []

class RejectingInventory extends PlayerInventory:
	var reject_consumption := false
	var fail_empty_grant := false
	var append_before_failure := false
	func consume_active() -> bool:
		return false if reject_consumption else super.consume_active()
	func add_item(item_name: String, is_large: bool, scene_path: String, state: Dictionary = {}) -> bool:
		if fail_empty_grant and scene_path == "res://props/gas_can_empty.tscn":
			if append_before_failure: super.add_item(item_name, is_large, scene_path, state)
			return false
		return super.add_item(item_name, is_large, scene_path, state)

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func clear_inventory() -> void:
	player.inventory = PlayerInventory.new()
	player.refresh_inventory()
func grant(path: String, name: String, id: String) -> void:
	check(player.add_item(name, false, path, {"id": id, "condition": 100.0}), "Real player grants " + id)

func run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(20, 2, 0)
	world.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	rv.engine_repair_committed.connect(func(engine_id: String, kit_id: String):
		engine_events.append([engine_id, kit_id, rv.get_engine().health, player.inventory.items.size()]))
	rv.wheel_removed.connect(func(slot: int, id: String):
		wheel_remove_events.append([slot, id, rv.installed_wheels[slot] == null]))
	rv.wheel_installed.connect(func(slot: int, id: String):
		wheel_install_events.append([slot, id, rv.installed_wheels[slot] != null, player.inventory.items.size()]))
	rv.refuel_committed.connect(func(port_id: String, can_id: String, empty_id: String, amount: float):
		var delivered := false
		for item in player.inventory.items:
			if item.scene_path == "res://props/gas_can_empty.tscn" and item.state.id == empty_id: delivered = true
		fuel_events.append([port_id, can_id, empty_id, amount, rv.current_fuel, delivered]))
	await check_construction()
	check_engine()
	check_wheels()
	check_fuel()
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: successful service transaction identities, commit ordering, cancellation and refuel rollback")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check_construction() -> void:
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var construction: RVStructureConstruction = slots.construction
	construction.set_physics_process(false)
	construction.operation_committed.connect(func(slot: String, operation: String):
		construction_events.append([slot, operation, slots.panel(slot).current_health, rv.get_item_count("Metal Parts")]))
	var tablet: Item = rv.get_node("TabletScreen")
	rv.get_battery_socket().set_physics_process(false)
	rv.current_power = 100.0
	rv.inventory = {"Metal Parts": 100}
	tablet.interact_hold(player)
	check(tablet.is_management_active(), "Actual tablet authorizes service construction")
	var panel: RVStructurePanel = slots.panel("left_1")
	panel.set_health(30.0)
	check(construction.begin(tablet, "left_1", "repair").is_empty(), "Repair starts")
	construction._physics_process(1.0)
	check(construction_events.is_empty() and panel.current_health == 30.0, "Incomplete repair emits nothing")
	tablet._close_ui()
	construction._physics_process(2.0)
	check(construction_events.is_empty() and rv.get_item_count("Metal Parts") == 100, "Closing tablet cancels without event or material spend")
	tablet.interact_hold(player)
	check(construction.begin(tablet, "left_1", "repair").is_empty(), "Repair restarts")
	construction._physics_process(2.0)
	check(construction_events == [["left_1", "repair", 90.0, 98]], "Repair event follows material and health commits")
	check(not construction.begin(tablet, "floor", "repair").is_empty() and construction_events.size() == 1, "Fixed floor cannot produce construction event")
	check(construction.begin(tablet, "left_1", "repair").is_empty(), "Last-tick material rejection fixture starts")
	rv.inventory = {"Metal Parts": 1}
	construction._physics_process(2.0)
	check(construction_events.size() == 1 and panel.current_health == 90.0, "Insufficient materials at completion emit nothing")
	rv.inventory = {"Metal Parts": 100}
	check(construction.begin(tablet, "left_1", "repair").is_empty(), "Damage cancellation fixture starts")
	panel.take_damage(1.0)
	construction._physics_process(2.0)
	check(construction_events.size() == 1, "Target damage cancellation emits nothing")
	# Clear the production wall attachments and mast as in the construction suite.
	for device in rv.get_equipment():
		if device.mount_support == panel:
			device.set_mount_support(rv)
			device.position.x = 20.0
	rv.get_node("CraftingStation").position.x = 0.0
	tablet.position.x = 0.0
	await physics_frame
	check(construction.begin(tablet, "left_1", "convert", "rv_side_door").is_empty(), "Real wall conversion starts")
	construction._physics_process(4.0)
	panel = slots.panel("left_1")
	check(construction_events.size() == 2 and construction_events[1][1] == "convert" and panel.definition.type_id == "rv_side_door" and rv.get_item_count("Metal Parts") == 98, "Conversion event follows replacement and payment")
	panel.take_damage(panel.max_health)
	await physics_frame
	await physics_frame
	check(construction.begin(tablet, "left_1", "rebuild").is_empty(), "Destroyed wall rebuild starts")
	construction._physics_process(6.0)
	panel = slots.panel("left_1")
	check(construction_events.size() == 3 and construction_events[2][1] == "rebuild" and panel.current_health == panel.max_health and rv.get_item_count("Metal Parts") == 92, "Rebuild event follows restored part and payment")
	tablet._close_ui()

func check_engine() -> void:
	clear_inventory()
	var bay: Node = rv.engine_bay
	bay.hatch_open = true
	rv.get_engine().health = 0.0
	var engine_id: String = rv.get_engine().id
	grant("res://props/engine_repair_kit.tscn", "Engine repair kit", "service-kit")
	var repair := RepairOperation.new()
	repair.step(player, bay, true, 1.5)
	repair.step(player, null, false, 0.1)
	check(engine_events.is_empty() and player.inventory.items.size() == 1 and rv.get_engine().health == 0.0, "Released repair consumes no kit and emits nothing")
	repair.step(player, bay, true, 1.5)
	bay.installed_engine = EngineState.new({"id": engine_id, "health": 0.0})
	repair.step(player, bay, true, 1.5)
	check(engine_events.is_empty() and rv.get_engine().health == 0.0, "Replacing the engine object resets progress even with the same identity")
	player.inventory.items[0].state.id = "replacement-kit"
	repair.step(player, bay, true, 1.5)
	check(engine_events.is_empty(), "Changing the active kit resets progress")
	repair.step(player, bay, true, 1.5)
	check(engine_events == [[engine_id, "replacement-kit", 150.0, 0]], "Repair event follows original engine health gain and exactly one kit consumption")
	rv.get_engine().health = rv.get_engine().definition().max_health
	grant("res://props/engine_repair_kit.tscn", "Engine repair kit", "unused-kit")
	repair.step(player, bay, true, 3.0)
	check(engine_events.size() == 1 and player.inventory.items.size() == 1, "Full engine consumes no kit and emits nothing")
	rv.get_engine().health = 0.0
	bay.hatch_open = false
	repair.step(player, bay, true, 3.0)
	check(engine_events.size() == 1 and rv.get_engine().health == 0.0, "Closed hatch emits nothing")
	bay.hatch_open = true
	var rejecting := RejectingInventory.new()
	rejecting.items = player.inventory.items.duplicate(true)
	rejecting.reject_consumption = true
	player.inventory = rejecting
	repair.step(player, bay, true, 3.0)
	check(engine_events.size() == 1 and rv.get_engine().health == 0.0, "Failed kit consumption cannot repair or report a commit")
	bay.hatch_open = false

func check_wheels() -> void:
	clear_inventory()
	var old_id: String = rv.wheel_ids[0]
	rv.wheel_health[0] = 0.0
	rv.linear_velocity = Vector3.RIGHT
	check(not rv.remove_wheel_to_world(0) and wheel_remove_events.is_empty(), "Moving wheel removal emits nothing")
	rv.linear_velocity = Vector3.ZERO
	check(rv.remove_wheel_to_world(0) and wheel_remove_events == [[0, old_id, true]], "Wheel removal event follows physical output and empty slot")
	var output: Item
	for child in WorldEntities.get_container(rv).get_children():
		if child is Item and child.persistent_id == old_id: output = child
	check(output != null and output.condition == 0.0, "Removed broken wheel exists physically with its genuine identity")
	check(not rv.remove_wheel_to_world(0) and wheel_remove_events.size() == 1, "Empty slot removal emits nothing")
	grant("res://props/wheel.tscn", ItemNames.WHEEL, "replacement-wheel")
	var rejecting := RejectingInventory.new()
	rejecting.items = player.inventory.items.duplicate(true)
	rejecting.reject_consumption = true
	player.inventory = rejecting
	check(not rv.install_wheel_from_player(player, 0) and rv.installed_wheels[0] == null and wheel_install_events.is_empty(), "Failed inventory consumption cannot install or report a wheel")
	rejecting.reject_consumption = false
	check(not rv.install_wheel_from_player(player, 1) and wheel_install_events.is_empty(), "Occupied slot emits no wheel install event")
	check(rv.install_wheel_from_player(player, 0) and wheel_install_events == [[0, "replacement-wheel", true, 0]], "Wheel install event follows consumption and physical installation")
	check(rv.wheel_ids[0] == "replacement-wheel" and rv.wheel_health[0] == 100.0, "Replacement keeps its inventory identity and condition")
	if output != null: output.free()

func check_fuel() -> void:
	clear_inventory()
	var port: Item = rv.get_node("FuelPort")
	rv.current_fuel = rv.max_fuel
	grant("res://props/gas_can.tscn", ItemNames.GAS_CAN, "fuel-can")
	var initial: Array[Dictionary] = player.inventory.items.duplicate(true)
	port.interact(player)
	check(fuel_events.is_empty() and player.inventory.items == initial, "Full tank emits nothing and retains fuel can")
	rv.current_fuel = 70.0
	for partial_failure in [false, true]:
		var rejecting := RejectingInventory.new()
		rejecting.items = initial.duplicate(true)
		rejecting.fail_empty_grant = true
		rejecting.append_before_failure = partial_failure
		player.inventory = rejecting
		port.interact(player)
		check(fuel_events.is_empty() and rv.current_fuel == 70.0 and player.inventory.items == initial and player.inventory.active_slot == 0, "Failed empty-can creation rolls back inventory and fuel, partial=" + str(partial_failure))
	clear_inventory()
	for index in PlayerInventory.MAX_SLOTS:
		grant("res://props/gas_can.tscn", ItemNames.GAS_CAN, "full-bag-can-" + str(index))
	rv.current_fuel = 90.0
	port.interact(player)
	check(fuel_events.size() == 1 and player.inventory.items.size() == PlayerInventory.MAX_SLOTS, "Full inventory can exchange one gasoline can for one empty can")
	if not fuel_events.is_empty():
		var event: Array = fuel_events[0]
		check(event[0] == port.persistent_id and event[1] == "full-bag-can-0" and event[2] != event[1] and event[3] == 10.0 and event[4] == 100.0 and event[5], "Refuel event reports actual accepted amount and delivered empty-can identity")
	rv.current_fuel = 0.0
	rv.add_fuel(5.0)
	check(fuel_events.size() == 1, "Direct fuel grants never report player refueling")
	clear_inventory()
	port.interact(player)
	check(fuel_events.size() == 1 and rv.current_fuel == 5.0, "No active fuel can emits nothing")

extends Node
class_name TutorialService
## One-time service exercise and evidence from committed vehicle transactions.
const PARKING := AABB(Vector3(-3.5, -1, -108), Vector3(7, 8, 28))
const WALL_SLOT := "left_0"
const WHEEL_SLOT := 0
var controller: Node
var configured := false
var engine_id := ""
var wheel_id := ""
var spare_id := ""
var kit_id := ""
var fuel_port_id := ""
var flags := {"wall": false, "engine": false, "removed": false, "wheel": false,
	"refueled": false, "departure": false}
var fuel_can_id := ""
var empty_can_id := ""
var fuel_amount := 0.0

func capture() -> Dictionary:
	return {"version": 1, "configured": configured, "wall_slot": WALL_SLOT,
		"wheel_slot": WHEEL_SLOT, "engine_id": engine_id, "wheel_id": wheel_id,
		"spare_id": spare_id, "kit_id": kit_id, "fuel_port_id": fuel_port_id,
		"flags": flags.duplicate(true), "fuel_can_id": fuel_can_id,
		"empty_can_id": empty_can_id, "fuel_amount": fuel_amount}

func restore(data: Dictionary) -> void:
	if data.is_empty(): return
	configured = data.configured
	engine_id = data.engine_id
	wheel_id = data.wheel_id
	spare_id = data.spare_id
	kit_id = data.kit_id
	fuel_port_id = data.fuel_port_id
	flags = data.flags.duplicate(true)
	fuel_can_id = data.fuel_can_id
	empty_can_id = data.empty_can_id
	fuel_amount = data.fuel_amount

func configure_if_ready(vehicle: Chassis) -> bool:
	if controller.stage != 7 or controller.status != "active": return false
	if configured: return true
	var player: Node = controller._world().get_node("Player")
	if player.get_player_mode() != player.PlayerMode.NORMAL or player.settings_open: return false
	if vehicle.energy.engine_running or not vehicle.handbrake or vehicle.linear_velocity.length() > 0.2 or vehicle.angular_velocity.length() > 0.05: return false
	if not controller._fully_inside(vehicle, PARKING): return false
	if not vehicle.save_block_reason().is_empty(): return false
	if not controller._run().save_block_reason().is_empty() or vehicle.get_node("StructureSlots").is_building(): return false
	var bay: Node = vehicle.get_node("EngineBay")
	var wall: RVStructurePanel = vehicle.get_node("StructureSlots").panel(WALL_SLOT)
	if wall == null or wall.is_destroyed or bay.installed_engine == null or vehicle.installed_wheels[WHEEL_SLOT] == null: return false
	engine_id = bay.installed_engine.id
	wheel_id = vehicle.wheel_ids[WHEEL_SLOT]
	spare_id = vehicle.persistent_id + ":training:spare-wheel"
	kit_id = vehicle.persistent_id + ":training:repair-kit"
	fuel_port_id = vehicle.persistent_id + ":training:missing-fuel-port"
	for equipment in vehicle.get_equipment():
		if equipment.scene_file_path == "res://equipment/fuel_port.tscn": fuel_port_id = equipment.persistent_id
	# All guards precede the single fault/supply transaction. Restores never enter it.
	configured = true
	wall.set_health(maxf(0.0, wall.max_health - 60.0))
	bay.installed_engine.health = maxf(0.0, bay.installed_engine.definition().max_health - 150.0)
	vehicle.puncture_wheel(WHEEL_SLOT)
	var metal: int = vehicle.get_item_count(ItemNames.METAL_PARTS)
	# Reserve the exercise's two repair materials even if ordinary storage is full.
	if metal < 2: vehicle.deposit_materials({ItemNames.METAL_PARTS: 2 - metal}, true)
	_spawn("res://props/engine_repair_kit.tscn", kit_id, Vector3(-7, 0.12, -94))
	_spawn("res://props/wheel.tscn", spare_id, Vector3(-8.5, 0.03, -94))
	controller.entry_snapshot.clear()
	controller.progress_changed.emit()
	return true

func _spawn(path: String, identity: String, position: Vector3) -> Item:
	var item: Item = load(path).instantiate()
	item.persistent_id = identity
	WorldEntities.get_container(controller._world()).add_child(item)
	item.global_position = controller._run().shelter.to_global(position)
	return item

func bind_events(vehicle: Chassis) -> void:
	var construction: Node = vehicle.get_node("StructureSlots").construction
	if not construction.operation_committed.is_connected(_wall): construction.operation_committed.connect(_wall)
	if not vehicle.engine_repair_committed.is_connected(_engine): vehicle.engine_repair_committed.connect(_engine)
	if not vehicle.wheel_removed.is_connected(_removed): vehicle.wheel_removed.connect(_removed)
	if not vehicle.wheel_installed.is_connected(_wheel): vehicle.wheel_installed.connect(_wheel)
	if not vehicle.refuel_committed.is_connected(_refuel): vehicle.refuel_committed.connect(_refuel)

func _active(stage: int) -> bool:
	return configured and controller.stage == stage and controller.status == "active" and not controller.entry_snapshot.is_empty()

func _wall(slot: String, operation: String) -> void:
	if _active(7) and slot == WALL_SLOT and operation == "repair" and wall_ready():
		flags.wall = true
		controller.progress_changed.emit()

func _engine(identity: String, consumed_kit: String) -> void:
	if _active(7) and identity == engine_id and not consumed_kit.is_empty() and engine_ready():
		flags.engine = true
		controller.progress_changed.emit()

func _removed(slot: int, identity: String) -> void:
	if _active(7) and slot == WHEEL_SLOT and identity == wheel_id:
		flags.removed = true
		controller.progress_changed.emit()

func _wheel(slot: int, identity: String) -> void:
	if _active(7) and flags.removed and slot == WHEEL_SLOT and identity == spare_id and wheel_ready():
		flags.wheel = true
		controller.progress_changed.emit()

func _refuel(port_id: String, can_id: String, empty_id: String, amount: float) -> void:
	if not _active(8) or amount <= 0 or can_id != controller.workshop.gasoline_id or empty_id.is_empty(): return
	var port: Item = controller.workshop.by_id(port_id)
	if port == null or not port.can_operate() or port.get_connected_rv() != controller.designated_rv(): return
	var player: Node = controller._world().get_node("Player")
	if not player.inventory.items.any(func(item): return item.state.id == empty_id and item.scene_path == "res://props/gas_can_empty.tscn"): return
	flags.refueled = true
	fuel_can_id = can_id
	empty_can_id = empty_id
	fuel_amount = amount
	controller.progress_changed.emit()

func wall_ready() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	if vehicle == null: return false
	var wall: RVStructurePanel = vehicle.get_node("StructureSlots").panel(WALL_SLOT)
	return wall != null and not wall.is_destroyed and is_equal_approx(wall.current_health, wall.max_health)

func engine_ready() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	if vehicle == null: return false
	var engine: EngineState = vehicle.get_node("EngineBay").installed_engine
	return engine != null and engine.id == engine_id and is_equal_approx(engine.health, engine.definition().max_health)

func wheel_ready() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	return vehicle != null and vehicle.installed_wheels[WHEEL_SLOT] != null and vehicle.wheel_ids[WHEEL_SLOT] == spare_id and vehicle.wheel_health[WHEEL_SLOT] > 0.0

func hatch_closed() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	if vehicle == null: return false
	var hatch: Node = vehicle.get_node("EngineBay/Hatch")
	return hatch.stable() and not hatch.requested_open and not hatch.opened

func complete() -> bool:
	if not configured: return false
	if controller.stage == 7:
		return flags.wall and flags.engine and flags.wheel and wall_ready() and engine_ready() and wheel_ready()
	return controller.stage == 8 and flags.refueled and fuel_amount > 0.0

func page() -> Dictionary:
	var title := "Combined vehicle maintenance"
	var conditions := []
	var steps := []
	var controls := []
	if controller.stage == 7:
		conditions = [
			_condition("ready", "Park fully in bay 7, stop, apply handbrake, switch off and leave the seat", configured),
			_condition("wall", "Repair side slot left_0 through rvctl Structure to full durability", flags.wall and wall_ready()),
			_condition("engine", "Repair the original engine with one engine repair kit", flags.engine and engine_ready()),
			_condition("wheel", "Remove the damaged left-front tire and install the marked spare", flags.wheel and wheel_ready())]
		steps = ["Park inside the marked seventh bay and finish all interactions. The exercise then applies its faults once and supplies a repair kit and spare tire in the side work area.",
			"Open rvctl Structure, select left_0, and complete Repair. Keep the tablet open until construction finishes. Field H repair does not repair a body wall.",
			"Open the front maintenance cover and wait until it is fully open. Select an engine repair kit and hold H on the engine socket for three seconds. Replacing the engine does not count.",
			"With no tire selected, hold E on the left-front wheel socket to remove the damaged tire. Pick up the marked spare, then hold E on that empty socket to install it.",
			"Complete the three repairs in any order. Patching or reinstalling the original tire does not count. Close the maintenance cover before departure."]
		controls = ["Hold E rvctl. F5 Structure. Tab / Enter Select slot and Repair.", "E Open / close engine cover. H Engine repair: hold 3 seconds with a kit selected.", "Hold E Remove / install a tire at its socket. E Pick up the marked spare."]
	elif controller.stage == 8:
		title = "Refuel the RV"
		conditions = [_condition("refuel", "Transfer fuel from your manufactured can into this RV", flags.refueled and fuel_amount > 0.0), _condition("empty", "Receive the returned empty can", flags.refueled and not empty_can_id.is_empty())]
		steps = ["Park in the eighth bay. Select the gasoline can you manufactured at the training workbench.", "Use the RV fuel port to transfer fuel and receive an empty can. A full tank rejects the can without consuming it.", "The preparation fuel reserve is not a fuel transfer. Keep the empty can for future supplies."]
		controls = ["1-6 / Mouse wheel Select the manufactured gasoline can. E Use the RV fuel port."]
	elif controller.stage == 9:
		title = "Begin the journey"
		conditions = [_condition("vehicle", "Keep the repaired original RV ready for departure", flags.wall and flags.engine and flags.wheel and wall_ready() and engine_ready() and wheel_ready()), _condition("hatch", "Close the maintenance cover completely", hatch_closed()), _condition("button", "Use the shelter departure button", flags.departure), _condition("outside", "Exit with the entire RV and let the shelter seal", controller.status == "completed")]
		steps = ["Drive into the final bay and park. Switch off the engine and apply the handbrake. Close the front maintenance cover and wait for it to stop.", "Take your supplies with you. Leave the seat and use the departure button beside the final exit. World time, weather and enemies resume when it accepts.", "Return to the driver's seat, start the engine and drive the entire RV onto the road. You and all mounted equipment must clear the exit.", "The gate reopens if its closing path is blocked. Once it seals after departure, this terminal becomes your searchable field manual."]
		controls = ["E Departure button / engine cover. Hold E Driver's seat. B Engine. Space Handbrake.", "W/S Throttle / brake. A/D Steer. Esc Restart Stage before departure / close terminal."]
	return {"available": controller.status == "active", "stage": controller.stage, "title": title,
		"conditions": conditions, "steps": steps, "reference": controls}

func _condition(identity: String, text: String, done: bool) -> Dictionary:
	return {"id": identity, "label": text, "complete": done}

extends Node
class_name OrientationWorkshop
## Optional field-guide receipts. Vehicle services, not this checklist, gate driving.
const ROLE_KEYS := ["scrapper", "workbench", "scrap_a", "scrap_b", "barrel", "spare", "battery", "engine_kit_a", "engine_kit_b", "scrap_c", "scrap_d", "scrap_e", "scrap_f", "scrap_g", "scrap_h", "barrel_b"]
const TARGET_KEYS := ["scrapper", "workbench", "scrap_a", "scrap_b", "barrel", "spare", "socket", "tablet", "fuel_port", "wall_a", "wall_b", "wheel_slot", "original_wheel"]
const EXTRA_TARGET_KEYS := ["battery", "engine_kit_a", "engine_kit_b", "scrap_c", "scrap_d", "scrap_e", "scrap_f", "scrap_g", "scrap_h", "barrel_b", "original_battery", "engine", "roof_slot"]
const LEGACY_FLAG_KEYS := ["scrapper_placed", "workbench_placed", "wheel_removed", "wheel_installed", "refueled"]
const FLAG_KEYS := ["scrapper_placed", "workbench_placed", "wheel_removed", "wheel_installed", "refueled", "battery_exchanged", "engine_repaired", "roof_rebuilt"]
var controller: Node
var configured := false
var migration_pending := false
var step := 1
var targets: Dictionary = {}
var flags := {"scrapper_placed": false, "workbench_placed": false, "wheel_removed": false, "wheel_installed": false, "refueled": false, "battery_exchanged": false, "engine_repaired": false, "roof_rebuilt": false}
var placed_ids: Array[String] = []
var recycled_ids: Array[String] = []
var output_ids: Array[String] = []
var gasoline_id := ""
var empty_can_id := ""
var repaired_ids: Array[String] = []
var removed_wheel_ids: Array[String] = []
var refuel_amount := 0.0

func capture() -> Dictionary:
	return {"version": 2, "configured": configured, "migration_pending": migration_pending, "step": step,
		"targets": targets.duplicate(true), "flags": flags.duplicate(true), "placed_ids": placed_ids.duplicate(),
		"recycled_ids": recycled_ids.duplicate(), "output_ids": output_ids.duplicate(), "gasoline_id": gasoline_id,
		"empty_can_id": empty_can_id, "repaired_ids": repaired_ids.duplicate(), "removed_wheel_ids": removed_wheel_ids.duplicate(), "refuel_amount": refuel_amount}

static func upgrade_state(data: Dictionary) -> Dictionary:
	var upgraded := data.duplicate(true)
	if upgraded.get("version") == 1:
		upgraded.version = 2
		for key in ["battery_exchanged", "engine_repaired", "roof_rebuilt"]: upgraded.flags[key] = false
	return upgraded

func restore(saved: Dictionary) -> void:
	var data := upgrade_state(saved)
	configured = data.configured
	migration_pending = data.migration_pending
	step = data.step
	targets = data.targets.duplicate(true)
	flags = data.flags.duplicate(true)
	placed_ids.assign(data.placed_ids)
	recycled_ids.assign(data.recycled_ids)
	output_ids.assign(data.output_ids)
	gasoline_id = data.gasoline_id
	empty_can_id = data.empty_can_id
	repaired_ids.assign(data.repaired_ids)
	removed_wheel_ids.assign(data.removed_wheel_ids)
	refuel_amount = data.refuel_amount

func by_id(identity: String) -> Item:
	if identity.is_empty() or not is_inside_tree(): return null
	for actor in get_tree().get_nodes_in_group(Groups.ITEMS):
		if actor is Item and actor.persistent_id == identity and not actor.presentation_only and not actor.is_queued_for_deletion() and controller._world().is_ancestor_of(actor) and WorldEntities.same_world(controller._world(), actor): return actor
	return null

func item(key: String) -> Item:
	return by_id(str(targets.get(key, "")))

func prepare(vehicle: Chassis, migrating := false) -> bool:
	if configured: return true
	if vehicle == null or vehicle.installed_wheels[0] == null: return false
	var building: Node3D = controller.get_parent().get("shelter")
	if not is_instance_valid(building): return false
	if migrating:
		WalkInSites.ensure_orientation_workshop(building, WorldEntities.get_container(controller._world()))
	var found := {}
	var expected_ids := WalkInSites.orientation_workshop_ids(building)
	for actor in get_tree().get_nodes_in_group(Groups.ITEMS):
		if not actor is Item or actor.presentation_only or actor.is_queued_for_deletion() or not controller._world().is_ancestor_of(actor) or not WorldEntities.same_world(controller._world(), actor): continue
		for role in ROLE_KEYS:
			if actor.persistent_id == expected_ids[role]: found[role] = actor.persistent_id
	if found.size() != ROLE_KEYS.size(): return false
	var socket := vehicle.get_battery_socket()
	var tablet: Item = vehicle.get_node_or_null("TabletScreen")
	var port: Item
	for equipment in vehicle.get_equipment():
		if equipment.scene_file_path == "res://equipment/fuel_port.tscn": port = equipment
	var slots: RVStructureSlots = vehicle.get_node("StructureSlots")
	var wall_a: RVStructurePanel = slots.panel("left_0")
	var wall_b: RVStructurePanel = slots.panel("right_0")
	var roof: RVStructurePanel = slots.panel("roof_1")
	var engine := vehicle.get_engine()
	if socket == null or socket.installed_battery == null or engine == null or tablet == null or port == null or wall_a == null or wall_b == null or roof == null or wall_a.is_destroyed or wall_b.is_destroyed: return false
	found.merge({"socket": socket.persistent_id, "tablet": tablet.persistent_id, "fuel_port": port.persistent_id,
		"wall_a": "left_0", "wall_b": "right_0", "wheel_slot": 0, "original_wheel": vehicle.wheel_ids[0],
		"original_battery": socket.installed_battery.id, "engine": engine.id, "roof_slot": "roof_1"})
	# All guards precede the sole fault configuration. Loading v2 never enters it.
	targets = found
	controller.rv_id = vehicle.persistent_id
	configured = true
	migration_pending = false
	wall_a.set_health(minf(wall_a.current_health, maxf(0.0, wall_a.max_health - 60.0)))
	wall_b.set_health(minf(wall_b.current_health, maxf(0.0, wall_b.max_health - 60.0)))
	vehicle.puncture_wheel(0)
	engine.health = 0.0
	vehicle.set_engine_running(false)
	socket.installed_battery.charge = 0.0
	roof.set_health(0.0)
	bind_events(vehicle)
	controller.progress_changed.emit()
	return true

func bind_events(vehicle: Chassis) -> void:
	if not configured or vehicle == null: return
	var player: Node = controller._world().get_node_or_null("Player")
	if player == null: return
	if not player.item_acquired.is_connected(acquired): player.item_acquired.connect(acquired)
	if not player.placement.placement_committed.is_connected(_placed): player.placement.placement_committed.connect(_placed)
	var recycler := item("scrapper")
	if recycler != null and not recycler.recycle_committed.is_connected(_recycled): recycler.recycle_committed.connect(_recycled)
	var bench := item("workbench")
	if bench != null and not bench.output_committed.is_connected(_output): bench.output_committed.connect(_output)
	var construction: Node = vehicle.get_node("StructureSlots").construction
	if not construction.operation_committed.is_connected(_wall): construction.operation_committed.connect(_wall)
	if not vehicle.wheel_removed.is_connected(_removed): vehicle.wheel_removed.connect(_removed)
	if not vehicle.wheel_installed.is_connected(_wheel): vehicle.wheel_installed.connect(_wheel)
	if not vehicle.refuel_committed.is_connected(_refuel): vehicle.refuel_committed.connect(_refuel)
	if not vehicle.battery_exchanged.is_connected(_battery): vehicle.battery_exchanged.connect(_battery)
	if not vehicle.engine_repair_committed.is_connected(_engine): vehicle.engine_repair_committed.connect(_engine)

func _active() -> bool:
	return configured and controller.initialized() and controller._active_world() and controller.status == "active" and controller.flags.workshop_entered and controller.designated_rv() != null

func mounted(key: String) -> bool:
	var device := item(key)
	var vehicle: Chassis = controller.designated_rv()
	return vehicle != null and device != null and device.can_operate() and device.get_connected_rv() == vehicle

func installed(key: String) -> bool:
	var vehicle: Chassis = controller.designated_rv()
	return mounted(key) and vehicle.has_usable_power()

func _placed(identity: String, vehicle_id: String) -> void:
	if not _active() or vehicle_id != controller.rv_id or identity not in [targets.scrapper, targets.workbench]: return
	var key := "scrapper" if identity == targets.scrapper else "workbench"
	if not mounted(key): return
	if identity not in placed_ids: placed_ids.append(identity)
	flags[key + "_placed"] = true
	_changed()

func _recycled(vehicle_id: String, identity: String, amounts: Dictionary) -> void:
	if not _active() or vehicle_id != controller.rv_id or not installed("scrapper") or identity in recycled_ids: return
	var role := ""
	for key in targets:
		if (str(key).begins_with("scrap_") or key in ["barrel", "barrel_b"]) and targets[key] == identity: role = key
	if role.is_empty(): return
	var expected := {"Metal Parts": 2, "Unrefined Fuel": 10} if role.begins_with("barrel") else {"Metal Parts": 3}
	if amounts != expected: return
	recycled_ids.append(identity)
	_changed()

func _output(vehicle_id: String, identity: String, recipe: String) -> void:
	if not _active() or vehicle_id != controller.rv_id or recipe != "gasoline" or identity.is_empty() or not installed("workbench"): return
	var output := by_id(identity)
	if output == null or output.scene_file_path != "res://props/gas_can.tscn": return
	if identity not in output_ids and output_ids.size() < 64: output_ids.append(identity)
	_changed()

func _inventory_has(identity: String, scene: String) -> bool:
	var player: Node = controller._world().get_node_or_null("Player")
	if player == null: return false
	for entry: Dictionary in player.inventory.items:
		if entry.get("scene_path", "") == scene and entry.get("state", {}).get("id", "") == identity: return true
	return false

func acquired(identity: String, scene: String) -> void:
	if not _active() or scene != "res://props/gas_can.tscn" or identity not in output_ids or not _inventory_has(identity, scene): return
	if gasoline_id.is_empty() or not flags.refueled: gasoline_id = identity
	_changed()

func wall_ready(slot: String) -> bool:
	var vehicle: Chassis = controller.designated_rv()
	if vehicle == null: return false
	var panel: RVStructurePanel = vehicle.get_node("StructureSlots").panel(slot)
	return panel != null and not panel.is_destroyed and is_equal_approx(panel.current_health, panel.max_health)

func wheel_ready() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	return vehicle != null and vehicle.installed_wheels[targets.wheel_slot] != null and vehicle.wheel_ids[targets.wheel_slot] == targets.spare and vehicle.wheel_health[targets.wheel_slot] > 0.0

func _wall(slot: String, operation: String) -> void:
	if not _active() or not wall_ready(slot): return
	if slot == targets.get("roof_slot", "roof_1") and operation == "rebuild":
		flags.roof_rebuilt = true
		_changed()
		return
	if slot not in [targets.wall_a, targets.wall_b] or operation != "repair": return
	if slot not in repaired_ids: repaired_ids.append(slot)
	_changed()

func _removed(slot: int, identity: String) -> void:
	if not _active() or slot != targets.wheel_slot or identity != targets.original_wheel: return
	var vehicle: Chassis = controller.designated_rv()
	if vehicle.installed_wheels[slot] != null: return
	flags.wheel_removed = true
	if identity not in removed_wheel_ids: removed_wheel_ids.append(identity)
	_changed()

func _wheel(slot: int, identity: String) -> void:
	if not _active() or not flags.wheel_removed or slot != targets.wheel_slot or identity != targets.spare or not wheel_ready(): return
	flags.wheel_installed = true
	_changed()

func _refuel(port_id: String, can_id: String, empty_id: String, amount: float) -> void:
	if not _active() or port_id != targets.fuel_port or can_id not in output_ids or empty_id.is_empty() or not is_finite(amount) or amount <= 0.0: return
	if not mounted("fuel_port") or not _inventory_has(empty_id, "res://props/gas_can_empty.tscn"): return
	flags.refueled = true
	gasoline_id = can_id
	empty_can_id = empty_id
	refuel_amount = amount
	_changed()

func battery_ready() -> bool:
	var socket := item("socket") as BatterySocket
	return socket != null and mounted("socket") and socket.installed_battery != null and socket.installed_battery.condition > 0.0 and socket.installed_battery.charge > 0.0

func engine_ready() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	if vehicle == null: return false
	var engine := vehicle.get_engine()
	return engine != null and engine.health > 0.0

func _battery(socket_id: String, previous_id: String, installed_id: String) -> void:
	if not _active() or socket_id != targets.socket or installed_id.is_empty() or previous_id == installed_id or not battery_ready(): return
	var socket := item("socket") as BatterySocket
	if socket.installed_battery.id != installed_id: return
	flags.battery_exchanged = true
	_changed()

func _engine(identity: String, kit_id: String) -> void:
	if not _active() or kit_id.is_empty() or not engine_ready(): return
	var engine := controller.designated_rv().get_engine() as EngineState
	if engine.id != identity: return
	flags.engine_repaired = true
	_changed()

func complete() -> bool:
	if not configured: return false
	match step:
		1: return flags.scrapper_placed and flags.workbench_placed and installed("scrapper") and installed("workbench")
		2: return [targets.scrap_a, targets.scrap_b, targets.barrel].all(func(identity): return identity in recycled_ids)
		3: return not gasoline_id.is_empty()
		4: return repaired_ids.size() == 2 and flags.wheel_removed and flags.wheel_installed and flags.battery_exchanged and flags.engine_repaired and flags.roof_rebuilt and battery_ready() and engine_ready() and wall_ready(str(targets.get("roof_slot", "roof_1"))) and wall_ready(targets.wall_a) and wall_ready(targets.wall_b) and wheel_ready()
		5: return flags.refueled and refuel_amount > 0.0 and not empty_can_id.is_empty()
	return false

func ready_for_departure() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	# A reference for ordinary road readiness; optional workshop receipts do not
	# grant or deny departure authorization.
	return configured and vehicle != null and battery_ready() and engine_ready() and vehicle.current_fuel > 0.0

func _changed() -> void:
	while step < 6 and complete(): step += 1
	controller.progress_changed.emit()

func tick() -> void:
	var vehicle: Chassis = controller.designated_rv()
	if vehicle == null: return
	bind_events(vehicle)
	if _active() and step < 6 and complete(): _changed()

func page() -> Dictionary:
	var conditions := []
	var steps := ["This workshop is optional. Use these references in any order; you can leave when the RV's normal driving systems work.",
		"Supplies: search the warehouse racks, pallet bays and side aisles. Loose supplies sit on the lower shelves; sealed shipping crates are scenery. Keep the central vehicle lane clear.",
		"Power: collect the charged reserve battery. Select it and use the RV battery socket to exchange the empty installed battery. The socket needs a healthy installed battery; no reserve charge is added automatically.",
		"Engine: open the front maintenance cover and wait until it stops. Select an engine repair kit, aim at the engine socket and hold H for 3 seconds. Each consumed kit restores 150 engine durability; a second kit improves the repair.",
		"Equipment: find the scrapper and workbench among the warehouse storage bays, one large item at a time. Board via the side access and fasten them to the rear cabin floor. Keep the walkway, intake and output bed clear. Equipment can be mounted before restoring power.",
		"Materials: drop small scraps into the installed scrapper intake. Carry an oil barrel to the intake and deposit it as a held large item. Wait until materials enter RV storage. All eight scraps and both barrels yield 28 Metal Parts and 20 Unrefined Fuel.",
		"Gasoline: open the RV's rvctl tablet, choose Crafting, the marked workbench and Gasoline Can. Confirm production (2 Metal Parts + 5 Unrefined Fuel), wait for the physical output and pick it up.",
		"Walls: with the engine off and handbrake applied, open rvctl Structure. Select left_0 or right_0 and Repair (2 Metal Parts each). Keep rvctl open until the job finishes.",
		"Roof: in rvctl Structure, select destroyed slot roof_1 and Rebuild (6 Metal Parts). Clear the construction area and keep rvctl open until completion. Repairs and reconstruction are optional for departure.",
		"Tire: with no tire selected, hold E at the left-front wheel socket to remove the original flat tire. Find the healthy spare among the pallet bays and hold E at that same empty socket to install it.",
		"Fuel: select a completed gasoline can and use the RV fuel port. A successful transfer returns an empty can. You can refuel before completing any repair or equipment reference.",
		"Departure: close the maintenance cover and stow the rear ramp. Board the driver's seat, start the engine, select first gear and release the handbrake. Drive towards the exit; its vehicle sensor opens the gate. Clear the exit with the entire RV to begin the journey."]
	var controls := ["E: pick up / open cover / exchange selected battery / use fuel port. Hold E: fixed rvctl, driver's seat or wheel socket.",
		"H: hold 3 seconds at the exposed engine socket with a repair kit selected. 1-6 / Mouse wheel: select inventory item.",
		"F: placement preview. Left click: fasten. Right click / Esc: cancel preview. Q/E: rotate. R: surface/upright mode. Arrow keys: shift. Hold F: remove fixed equipment.",
		"G: drop selected small scrap into intake. Hold E at scrapper: deposit a held large item.",
		"rvctl F4: Crafting. F5: Structure. Tab / Enter: choose workstation, recipe, slot or operation. Esc: close.",
		"B: engine. C: first gear. Space: handbrake. W/S: throttle/brake. A/D: steer. T: read selected field terminal while on foot."]
	if configured:
		conditions = [_condition("battery", "Optional: exchange the battery and restore usable charge", flags.battery_exchanged and battery_ready()),
			_condition("engine", "Optional: repair the engine with a kit until it can start", flags.engine_repaired and engine_ready()),
			_condition("scrapper", "Optional: fasten and power the marked scrapper", flags.scrapper_placed and installed("scrapper")),
			_condition("workbench", "Optional: fasten and power the marked workbench", flags.workbench_placed and installed("workbench")),
			_condition("recycle", "Optional: recycle marked Scrap A, Scrap B and the first oil barrel", [targets.scrap_a, targets.scrap_b, targets.barrel].all(func(identity): return identity in recycled_ids)),
			_condition("manufacture", "Optional: manufacture and pick up a gasoline can", not gasoline_id.is_empty() and gasoline_id in output_ids),
			_condition("walls", "Optional: repair both designated walls to full durability", repaired_ids.size() == 2 and wall_ready(targets.wall_a) and wall_ready(targets.wall_b)),
			_condition("roof", "Optional: rebuild roof_1 to full durability", flags.roof_rebuilt and wall_ready(str(targets.get("roof_slot", "roof_1")))),
			_condition("wheel", "Optional: remove the original flat and install the marked healthy spare", flags.wheel_removed and flags.wheel_installed and wheel_ready()),
			_condition("refuel", "Optional: refuel from manufactured gasoline and receive the empty can", flags.refueled and refuel_amount > 0.0 and not empty_can_id.is_empty())]
	return {"available": true, "stage": 2, "title": "Workshop field guide / Optional references", "conditions": conditions, "steps": steps, "reference": controls}
func _condition(identity: String, text: String, done: bool) -> Dictionary:
	return {"id": identity, "label": text, "complete": done}

static func validation_error(value: Variant) -> String:
	if not value is Dictionary: return "state"
	var fields := ["version", "configured", "migration_pending", "step", "targets", "flags", "placed_ids", "recycled_ids", "output_ids", "gasoline_id", "empty_can_id", "repaired_ids", "removed_wheel_ids", "refuel_amount"]
	if value.size() != fields.size() or not value.has_all(fields): return "fields"
	if not value.version is int or value.version not in [1, 2]: return "version"
	if not value.configured is bool or not value.migration_pending is bool: return "configured"
	if not value.step is int or value.step < 1 or value.step > 6: return "step"
	var required_flags: Array = LEGACY_FLAG_KEYS if value.version == 1 else FLAG_KEYS
	if not value.targets is Dictionary or not value.flags is Dictionary or value.flags.size() != required_flags.size() or not value.flags.has_all(required_flags): return "targets/flags"
	for key in required_flags:
		if not value.flags[key] is bool: return "flags." + key
	for key in ["placed_ids", "recycled_ids", "output_ids", "repaired_ids", "removed_wheel_ids"]:
		if not value[key] is Array or value[key].size() > 64: return key
		var seen := {}
		for identity in value[key]:
			if not identity is String or identity.is_empty() or seen.has(identity): return key
			seen[identity] = true
	if not value.gasoline_id is String or not value.empty_can_id is String: return "can_id"
	if not (value.refuel_amount is int or value.refuel_amount is float) or not is_finite(float(value.refuel_amount)) or value.refuel_amount < 0.0: return "refuel_amount"
	if not value.configured:
		if not value.targets.is_empty() or value.step != 1 or not value.placed_ids.is_empty() or not value.recycled_ids.is_empty() or not value.output_ids.is_empty() or not value.repaired_ids.is_empty() or not value.removed_wheel_ids.is_empty() or not value.gasoline_id.is_empty() or not value.empty_can_id.is_empty() or value.refuel_amount != 0.0: return "unconfigured"
		for key in required_flags:
			if value.flags[key]: return "unconfigured"
		return ""
	if value.migration_pending or not value.targets.has_all(TARGET_KEYS): return "targets"
	if value.version == 1 and value.targets.size() != TARGET_KEYS.size(): return "targets"
	var target_ids := {}
	for key in value.targets:
		if key not in TARGET_KEYS and (value.version == 1 or key not in EXTRA_TARGET_KEYS): return "targets." + str(key)
		if key == "wheel_slot":
			if not value.targets[key] is int or value.targets[key] != 0: return "targets.wheel_slot"
		elif not value.targets[key] is String or value.targets[key].is_empty(): return "targets." + key
		elif key not in ["wall_a", "wall_b", "roof_slot"]:
			if target_ids.has(value.targets[key]): return "targets.duplicate"
			target_ids[value.targets[key]] = true
	if value.targets.wall_a != "left_0" or value.targets.wall_b != "right_0": return "targets.wall"
	if value.targets.get("roof_slot", "roof_1") != "roof_1": return "targets.roof_slot"
	for identity in value.output_ids:
		if target_ids.has(identity): return "output_ids.alias"
	if not value.empty_can_id.is_empty() and (target_ids.has(value.empty_can_id) or value.empty_can_id in value.output_ids): return "empty_can_id.alias"
	for identity in value.placed_ids:
		if identity not in [value.targets.scrapper, value.targets.workbench]: return "placed_ids"
	for identity in value.recycled_ids:
		var found := false
		for role in value.targets:
			if (str(role).begins_with("scrap_") or role in ["barrel", "barrel_b"]) and value.targets[role] == identity: found = true
		if not found: return "recycled_ids"
	for identity in value.repaired_ids:
		if identity not in [value.targets.wall_a, value.targets.wall_b]: return "repaired_ids"
	for identity in value.removed_wheel_ids:
		if identity != value.targets.original_wheel: return "removed_wheel_ids"
	if value.flags.scrapper_placed != (value.targets.scrapper in value.placed_ids) or value.flags.workbench_placed != (value.targets.workbench in value.placed_ids): return "placed_flags"
	if value.flags.wheel_removed != (value.targets.original_wheel in value.removed_wheel_ids) or value.flags.wheel_installed and not value.flags.wheel_removed: return "wheel_flags"
	if not value.gasoline_id.is_empty() and value.gasoline_id not in value.output_ids: return "gasoline_id"
	if value.flags.refueled != (not value.empty_can_id.is_empty() and value.refuel_amount > 0.0) or value.flags.refueled and value.gasoline_id.is_empty(): return "refuel"
	if not value.flags.refueled and (not value.empty_can_id.is_empty() or value.refuel_amount != 0.0): return "refuel"
	if value.version == 1:
		if value.step >= 2 and value.placed_ids.size() != 2: return "step.mount"
		if value.step >= 3 and value.recycled_ids.size() != 3: return "step.recycle"
		if value.step >= 4 and value.gasoline_id.is_empty(): return "step.gasoline"
		if value.step >= 5 and (value.repaired_ids.size() != 2 or not value.flags.wheel_installed): return "step.repair"
		if value.step == 6 and not value.flags.refueled: return "step.refuel"
		if value.step < 2 and not value.recycled_ids.is_empty() or value.step < 3 and not value.output_ids.is_empty() or value.step < 4 and (not value.repaired_ids.is_empty() or not value.removed_wheel_ids.is_empty()) or value.step < 5 and value.flags.refueled: return "step.evidence"
	return ""

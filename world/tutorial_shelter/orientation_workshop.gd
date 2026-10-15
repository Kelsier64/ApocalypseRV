extends Node
class_name OrientationWorkshop
## The two-room workshop consumes native, committed gameplay transactions.
const ROLE_KEYS := ["scrapper", "workbench", "scrap_a", "scrap_b", "barrel", "spare"]
const TARGET_KEYS := ["scrapper", "workbench", "scrap_a", "scrap_b", "barrel", "spare", "socket", "tablet", "fuel_port", "wall_a", "wall_b", "wheel_slot", "original_wheel"]
const FLAG_KEYS := ["scrapper_placed", "workbench_placed", "wheel_removed", "wheel_installed", "refueled"]
var controller: Node
var configured := false
var migration_pending := false
var step := 1
var targets: Dictionary = {}
var flags := {"scrapper_placed": false, "workbench_placed": false, "wheel_removed": false, "wheel_installed": false, "refueled": false}
var placed_ids: Array[String] = []
var recycled_ids: Array[String] = []
var output_ids: Array[String] = []
var gasoline_id := ""
var empty_can_id := ""
var repaired_ids: Array[String] = []
var removed_wheel_ids: Array[String] = []
var refuel_amount := 0.0

func capture() -> Dictionary:
	return {"version": 1, "configured": configured, "migration_pending": migration_pending, "step": step,
		"targets": targets.duplicate(true), "flags": flags.duplicate(true), "placed_ids": placed_ids.duplicate(),
		"recycled_ids": recycled_ids.duplicate(), "output_ids": output_ids.duplicate(), "gasoline_id": gasoline_id,
		"empty_can_id": empty_can_id, "repaired_ids": repaired_ids.duplicate(), "removed_wheel_ids": removed_wheel_ids.duplicate(), "refuel_amount": refuel_amount}

func restore(data: Dictionary) -> void:
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
	if socket == null or tablet == null or port == null or wall_a == null or wall_b == null or wall_a.is_destroyed or wall_b.is_destroyed: return false
	found.merge({"socket": socket.persistent_id, "tablet": tablet.persistent_id, "fuel_port": port.persistent_id,
		"wall_a": "left_0", "wall_b": "right_0", "wheel_slot": 0, "original_wheel": vehicle.wheel_ids[0]})
	# All guards precede the sole fault configuration. Loading v2 never enters it.
	targets = found
	controller.rv_id = vehicle.persistent_id
	configured = true
	migration_pending = false
	wall_a.set_health(minf(wall_a.current_health, maxf(0.0, wall_a.max_health - 60.0)))
	wall_b.set_health(minf(wall_b.current_health, maxf(0.0, wall_b.max_health - 60.0)))
	vehicle.puncture_wheel(0)
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

func _active(expected: int) -> bool:
	return configured and step == expected and controller.initialized() and controller._active_world() and controller.status == "active" and controller.flags.workshop_entered and controller.designated_rv() != null

func installed(key: String) -> bool:
	var device := item(key)
	var vehicle: Chassis = controller.designated_rv()
	return vehicle != null and device != null and device.can_operate() and device.get_connected_rv() == vehicle and vehicle.has_usable_power()

func _placed(identity: String, vehicle_id: String) -> void:
	if not _active(1) or vehicle_id != controller.rv_id or identity not in [targets.scrapper, targets.workbench]: return
	var key := "scrapper" if identity == targets.scrapper else "workbench"
	if not installed(key): return
	if identity not in placed_ids: placed_ids.append(identity)
	flags[key + "_placed"] = true
	_changed()

func _recycled(vehicle_id: String, identity: String, amounts: Dictionary) -> void:
	if not _active(2) or vehicle_id != controller.rv_id or not installed("scrapper") or identity in recycled_ids: return
	if identity not in [targets.scrap_a, targets.scrap_b, targets.barrel]: return
	var expected := {"Metal Parts": 2, "Unrefined Fuel": 10} if identity == targets.barrel else {"Metal Parts": 3}
	if amounts != expected: return
	recycled_ids.append(identity)
	_changed()

func _output(vehicle_id: String, identity: String, recipe: String) -> void:
	if not _active(3) or vehicle_id != controller.rv_id or recipe != "gasoline" or identity.is_empty() or not installed("workbench"): return
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
	if not _active(3) or scene != "res://props/gas_can.tscn" or identity not in output_ids or not _inventory_has(identity, scene): return
	gasoline_id = identity
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
	if not _active(4) or slot not in [targets.wall_a, targets.wall_b] or operation != "repair" or not wall_ready(slot): return
	if slot not in repaired_ids: repaired_ids.append(slot)
	_changed()

func _removed(slot: int, identity: String) -> void:
	if not _active(4) or slot != targets.wheel_slot or identity != targets.original_wheel: return
	var vehicle: Chassis = controller.designated_rv()
	if vehicle.installed_wheels[slot] != null: return
	flags.wheel_removed = true
	if identity not in removed_wheel_ids: removed_wheel_ids.append(identity)
	_changed()

func _wheel(slot: int, identity: String) -> void:
	if not _active(4) or not flags.wheel_removed or slot != targets.wheel_slot or identity != targets.spare or not wheel_ready(): return
	flags.wheel_installed = true
	_changed()

func _refuel(port_id: String, can_id: String, empty_id: String, amount: float) -> void:
	if not _active(5) or port_id != targets.fuel_port or can_id != gasoline_id or empty_id.is_empty() or not is_finite(amount) or amount <= 0.0: return
	if not installed("fuel_port") or not _inventory_has(empty_id, "res://props/gas_can_empty.tscn"): return
	flags.refueled = true
	empty_can_id = empty_id
	refuel_amount = amount
	_changed()

func complete() -> bool:
	if not configured: return false
	match step:
		1: return flags.scrapper_placed and flags.workbench_placed and installed("scrapper") and installed("workbench")
		2: return recycled_ids.size() == 3
		3: return not gasoline_id.is_empty()
		4: return repaired_ids.size() == 2 and flags.wheel_removed and flags.wheel_installed and wall_ready(targets.wall_a) and wall_ready(targets.wall_b) and wheel_ready()
		5: return flags.refueled and refuel_amount > 0.0 and not empty_can_id.is_empty()
	return false

func ready_for_departure() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	return configured and step == 6 and vehicle != null and flags.scrapper_placed and flags.workbench_placed and recycled_ids.size() == 3 and not gasoline_id.is_empty() and repaired_ids.size() == 2 and flags.wheel_removed and flags.wheel_installed and flags.refueled and not empty_can_id.is_empty() and refuel_amount > 0.0 and installed("scrapper") and installed("workbench") and wall_ready(targets.wall_a) and wall_ready(targets.wall_b) and wheel_ready() and vehicle.current_fuel > 0.0

func _changed() -> void:
	if step < 6 and complete(): step += 1
	controller.progress_changed.emit()

func tick() -> void:
	var vehicle: Chassis = controller.designated_rv()
	if vehicle == null: return
	bind_events(vehicle)
	# This is a safety reserve on an installed, usable battery, never a score event.
	var socket := vehicle.get_battery_socket()
	if socket != null and socket.can_operate() and socket.get_connected_rv() == vehicle and socket.installed_battery != null and socket.installed_battery.condition > 0:
		socket.installed_battery.charge = maxf(socket.installed_battery.charge, minf(20.0, socket.installed_battery.capacity))
	if _active(step) and step < 6 and complete(): _changed()

func page() -> Dictionary:
	var conditions := []
	var steps := []
	var controls := []
	var title := "Workshop preparation"
	if not configured:
		return {"available": true, "stage": 2, "title": title, "conditions": [_condition("setup", "Workshop supplies must be available", false)], "steps": ["Inspect the workshop equipment and original RV."], "reference": ["T: read the selected field terminal. Esc: close."]}
	match step:
		1:
			title = "1 / Install workshop equipment"
			for key in ["scrapper", "workbench"]: conditions.append(_condition(key, "Fasten the marked " + key + " to the original RV with usable power", flags[key + "_placed"] and installed(key)))
			steps = ["Pick up the marked scrapper and workbench from the side work areas, one large item at a time.", "Board the RV via its side access. Fasten both units to the rear cabin floor, keeping the walkway, scrapper intake and workbench output clear.", "Use the RV's existing rvctl tablet for crafting and vehicle repairs. This field terminal is your guide."]
			controls = ["E: pick up. F: placement preview. Left click: fasten. Right click / Esc: cancel preview.", "Q/E: rotate. R: surface/upright mode. Arrow keys: shift preview. Hold F: remove installed equipment."]
		2:
			title = "2 / Recover materials"
			for key in ["scrap_a", "scrap_b", "barrel"]: conditions.append(_condition(key, "Recycle marked " + key.replace("_", " ") + " into RV storage", targets[key] in recycled_ids))
			steps = ["Collect marked Scrap A and Scrap B from the east supply rack, and the marked oil barrel beside it.", "Drop each small scrap into the installed scrapper intake. Carry the oil barrel to the intake and deposit the held large item.", "Wait until all three inputs finish. Their committed yield is 8 Metal Parts and 10 Unrefined Fuel; queued or interrupted inputs do not count."]
			controls = ["E: pick up. G: drop selected small scrap into the intake.", "Hold E: deposit a held large item at the scrapper."]
		3:
			title = "3 / Manufacture gasoline"
			conditions = [_condition("output", "Finish a Gasoline Can at the marked workbench", not output_ids.is_empty()), _condition("pickup", "Pick up its completed gasoline can", not gasoline_id.is_empty())]
			steps = ["Open the RV's rvctl tablet and select Crafting, the marked workbench, then Gasoline Can.", "Confirm production. The recipe uses 2 Metal Parts and 5 Unrefined Fuel.", "Keep the output bed clear. Wait for the physical can to appear, then pick it up. A queued job does not count."]
			controls = ["Hold E: open rvctl. F4: Crafting. Tab / Enter: select workstation, recipe and Craft.", "E: pick up the completed can. Esc: close rvctl."]
		4:
			title = "4 / Repair the RV"
			for key in ["wall_a", "wall_b"]: conditions.append(_condition(key, "Repair " + targets[key] + " through rvctl Structure to full durability", targets[key] in repaired_ids and wall_ready(targets[key])))
			conditions.append(_condition("wheel", "Remove the original flat left-front tire and install the marked healthy spare", flags.wheel_removed and flags.wheel_installed and wheel_ready()))
			steps = ["Stop the engine and apply the handbrake. Open rvctl Structure, choose left_0, then Repair. Keep rvctl open until it finishes; repeat for right_0.", "Each wall needs 2 Metal Parts. Rebuilding or converting a wall does not count.", "At the left-front wheel socket, select an item other than a tire and hold E to remove the original flat tire.", "Pick up the marked spare from the west floor stand and hold E at that same empty wheel socket to install it.", "Repair walls and change the tire in any order. Patching or reinstalling the original flat tire does not count."]
			controls = ["Hold E: open rvctl. F5: Structure. Tab / Enter: choose slot and Repair.", "Hold E at wheel socket: remove or install selected tire. E: pick up spare."]
		5:
			title = "5 / Refuel the RV"
			conditions = [_condition("fuel", "Transfer fuel from your manufactured gasoline can into this RV", flags.refueled and refuel_amount > 0.0), _condition("empty", "Receive the returned empty can", not empty_can_id.is_empty())]
			steps = ["Select the gasoline can you produced and picked up at the marked workbench.", "Use the original RV fuel port. The transfer must succeed and return an empty can to your inventory.", "The RV started with no fuel. The battery safety reserve does not add any fuel."]
			controls = ["1-6 / Mouse wheel: select the manufactured gasoline can. E at fuel port: refuel."]
		6:
			title = "Vehicle restored"
			conditions = [_condition("equipment", "Both marked workshop units remain fastened and powered on the original RV", flags.scrapper_placed and flags.workbench_placed and installed("scrapper") and installed("workbench")),
				_condition("recycling", "All three designated inputs were committed to RV storage", recycled_ids.size() == 3),
				_condition("manufacture", "A gasoline can was produced and picked up", not gasoline_id.is_empty() and gasoline_id in output_ids),
				_condition("walls", "Both designated walls were repaired and remain at full durability", repaired_ids.size() == 2 and wall_ready(targets.wall_a) and wall_ready(targets.wall_b)),
				_condition("wheel", "The original flat was removed and the marked healthy spare remains installed", flags.wheel_removed and flags.wheel_installed and wheel_ready()),
				_condition("fuel", "Manufactured fuel was transferred, an empty can returned, and fuel remains in the RV", flags.refueled and refuel_amount > 0.0 and not empty_can_id.is_empty() and controller.designated_rv() != null and controller.designated_rv().current_fuel > 0.0)]
			steps = ["Keep your field terminal and supplies aboard. The depot exit remains secured.", "Keep the workshop units powered, both repaired walls intact, the marked spare installed and fuel in the tank."]
			controls = ["T: read the selected field terminal. Esc: close."]
	return {"available": true, "stage": 2, "title": title, "conditions": conditions, "steps": steps, "reference": controls}

func _condition(identity: String, text: String, done: bool) -> Dictionary:
	return {"id": identity, "label": text, "complete": done}

static func validation_error(value: Variant) -> String:
	if not value is Dictionary: return "state"
	var fields := ["version", "configured", "migration_pending", "step", "targets", "flags", "placed_ids", "recycled_ids", "output_ids", "gasoline_id", "empty_can_id", "repaired_ids", "removed_wheel_ids", "refuel_amount"]
	if value.size() != fields.size() or not value.has_all(fields): return "fields"
	if not value.version is int or value.version != 1: return "version"
	if not value.configured is bool or not value.migration_pending is bool: return "configured"
	if not value.step is int or value.step < 1 or value.step > 6: return "step"
	if not value.targets is Dictionary or not value.flags is Dictionary or value.flags.size() != FLAG_KEYS.size() or not value.flags.has_all(FLAG_KEYS): return "targets/flags"
	for key in FLAG_KEYS:
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
		for key in FLAG_KEYS:
			if value.flags[key]: return "unconfigured"
		return ""
	if value.migration_pending or value.targets.size() != TARGET_KEYS.size() or not value.targets.has_all(TARGET_KEYS): return "targets"
	var target_ids := {}
	for key in TARGET_KEYS:
		if key == "wheel_slot":
			if not value.targets[key] is int or value.targets[key] != 0: return "targets.wheel_slot"
		elif not value.targets[key] is String or value.targets[key].is_empty(): return "targets." + key
		elif key not in ["wall_a", "wall_b"]:
			if target_ids.has(value.targets[key]): return "targets.duplicate"
			target_ids[value.targets[key]] = true
	if value.targets.wall_a != "left_0" or value.targets.wall_b != "right_0": return "targets.wall"
	for identity in value.output_ids:
		if target_ids.has(identity): return "output_ids.alias"
	if not value.empty_can_id.is_empty() and (target_ids.has(value.empty_can_id) or value.empty_can_id in value.output_ids): return "empty_can_id.alias"
	for identity in value.placed_ids:
		if identity not in [value.targets.scrapper, value.targets.workbench]: return "placed_ids"
	for identity in value.recycled_ids:
		if identity not in [value.targets.scrap_a, value.targets.scrap_b, value.targets.barrel]: return "recycled_ids"
	for identity in value.repaired_ids:
		if identity not in [value.targets.wall_a, value.targets.wall_b]: return "repaired_ids"
	for identity in value.removed_wheel_ids:
		if identity != value.targets.original_wheel: return "removed_wheel_ids"
	if value.flags.scrapper_placed != (value.targets.scrapper in value.placed_ids) or value.flags.workbench_placed != (value.targets.workbench in value.placed_ids): return "placed_flags"
	if value.flags.wheel_removed != (value.targets.original_wheel in value.removed_wheel_ids) or value.flags.wheel_installed and not value.flags.wheel_removed: return "wheel_flags"
	if not value.gasoline_id.is_empty() and value.gasoline_id not in value.output_ids: return "gasoline_id"
	if value.flags.refueled != (not value.empty_can_id.is_empty() and value.refuel_amount > 0.0) or value.flags.refueled and value.gasoline_id.is_empty(): return "refuel"
	if not value.flags.refueled and (not value.empty_can_id.is_empty() or value.refuel_amount != 0.0): return "refuel"
	if value.step >= 2 and value.placed_ids.size() != 2: return "step.mount"
	if value.step >= 3 and value.recycled_ids.size() != 3: return "step.recycle"
	if value.step >= 4 and value.gasoline_id.is_empty(): return "step.gasoline"
	if value.step >= 5 and (value.repaired_ids.size() != 2 or not value.flags.wheel_installed): return "step.repair"
	if value.step == 6 and not value.flags.refueled: return "step.refuel"
	if value.step < 2 and not value.recycled_ids.is_empty() or value.step < 3 and not value.output_ids.is_empty() or value.step < 4 and (not value.repaired_ids.is_empty() or not value.removed_wheel_ids.is_empty()) or value.step < 5 and value.flags.refueled: return "step.evidence"
	return ""

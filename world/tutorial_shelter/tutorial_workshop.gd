extends Node
class_name TutorialWorkshop
## Lessons 2-6 consume ordinary Items and committed gameplay transactions.
var controller: Node
var targets: Dictionary = {}
var flags := {"battery": false, "overview": false, "energy": false, "equipment": false,
	"lights_off": false, "lights_on": false, "cancelled": false,
	"scrapper_placed": false, "workbench_placed": false, "remounted": false}
var placed_ids: Array[String] = []
var unmounted_ids: Array[String] = []
var recycled_ids: Array[String] = []
var output_ids: Array[String] = []
var gasoline_id := ""
var _objects: Dictionary = {}

func prepared() -> bool:
	return not targets.is_empty()

func capture() -> Dictionary:
	return {"version": 1, "targets": targets.duplicate(true), "flags": flags.duplicate(true),
		"placed_ids": placed_ids.duplicate(), "unmounted_ids": unmounted_ids.duplicate(),
		"recycled_ids": recycled_ids.duplicate(), "output_ids": output_ids.duplicate(), "gasoline_id": gasoline_id}

func restore(data: Dictionary) -> void:
	if data.is_empty(): return
	targets = data.targets.duplicate(true)
	flags = data.flags.duplicate(true)
	placed_ids.assign(data.placed_ids)
	unmounted_ids.assign(data.unmounted_ids)
	recycled_ids.assign(data.recycled_ids)
	output_ids.assign(data.output_ids)
	gasoline_id = data.gasoline_id

func prepare(vehicle: Chassis) -> void:
	if prepared() or not is_instance_valid(controller._run().shelter): return
	var prefix: String = vehicle.persistent_id + ":training:"
	var socket := vehicle.get_battery_socket()
	var tablet: Item = vehicle.get_node_or_null("TabletScreen")
	# Historical retry records retain the original devices even if they were
	# subsequently lost. References never fabricate replacement RV equipment.
	var socket_id := socket.persistent_id if socket != null else prefix + "missing-socket"
	var tablet_id := tablet.persistent_id if tablet != null else prefix + "missing-tablet"
	var original := socket.installed_battery.id if socket != null and socket.installed_battery != null else prefix + "original-battery"
	for saved_vehicle: Dictionary in controller.entry_snapshot.get("vehicles", []):
		if saved_vehicle.id != vehicle.persistent_id: continue
		for actor: Dictionary in saved_vehicle.get("mounted_items", []):
			if actor.scene == "res://rv/battery_socket.tscn": socket_id = actor.state.id
			if actor.scene == "res://equipment/tablet_screen.tscn": tablet_id = actor.state.id
	targets = {"battery": prefix + "battery", "original_battery": original, "socket": socket_id,
		"tablet": tablet_id, "scrapper": prefix + "scrapper", "workbench": prefix + "workbench",
		"scrap_a": prefix + "scrap-a", "scrap_b": prefix + "scrap-b", "barrel": prefix + "barrel"}
	var supplies: Array[Item] = []
	supplies.append(_spawn("battery", "res://props/battery.tscn", Vector3(-8, 0.35, -306)))
	supplies.append(_spawn("scrapper", "res://equipment/scrapper.tscn", Vector3(8, 0.03, -224)))
	supplies.append(_spawn("workbench", "res://equipment/crafting_station.tscn", Vector3(-8, 0.03, -224)))
	supplies.append(_spawn("scrap_a", "res://props/scrap.tscn", Vector3(8, 0.18, -178)))
	supplies.append(_spawn("scrap_b", "res://props/scrap.tscn", Vector3(9, 0.18, -178)))
	supplies.append(_spawn("barrel", "res://props/oil_barrel.tscn", Vector3(8.5, 0.55, -174)))
	item("battery").battery.charge = 60.0
	item("battery")._update_label()
	item("scrap_a").scrap_yields = {"Metal Parts": Vector2(3, 3)}
	item("scrap_b").scrap_yields = {"Metal Parts": Vector2(3, 3)}
	item("barrel").scrap_yields = {"Metal Parts": Vector2(2, 2), "Unrefined Fuel": Vector2(10, 10)}
	item("scrap_a").item_name = "Training Scrap A"
	item("scrap_b").item_name = "Training Scrap B"
	item("workbench").item_name = "Training Workbench"
	item("scrapper").item_name = "Training Scrapper"
	# One-time migration adds the same deterministic supplies to the old entry,
	# rather than recapturing the player's current progress as a retry boundary.
	if not controller.entry_snapshot.is_empty():
		var entry: Dictionary = controller.entry_snapshot
		for supply in supplies: entry.actors.append(WorldActorSnapshot.capture(supply))
		entry.start_state.tutorial.version = 2
		entry.start_state.tutorial["workshop"] = capture()
	controller.progress_changed.emit()

func _spawn(key: String, path: String, position: Vector3) -> Item:
	var prop: Item = load(path).instantiate()
	prop.persistent_id = targets[key]
	if "battery" in prop: prop.battery.id = prop.persistent_id
	var container := WorldEntities.get_container(controller._world())
	container.add_child(prop)
	prop.global_position = controller._run().shelter.to_global(position)
	_objects[prop.persistent_id] = weakref(prop)
	return prop

func by_id(identity: String) -> Item:
	if _objects.has(identity):
		var cached: Item = _objects[identity].get_ref()
		if is_instance_valid(cached) and not cached.is_queued_for_deletion() and not cached.presentation_only and controller._world().is_ancestor_of(cached) and WorldEntities.same_world(controller._world(), cached): return cached
	for actor in get_tree().get_nodes_in_group(Groups.ITEMS):
		if actor is Item and actor.persistent_id == identity and not actor.presentation_only and not actor.is_queued_for_deletion() and controller._world().is_ancestor_of(actor) and WorldEntities.same_world(controller._world(), actor):
			_objects[identity] = weakref(actor)
			return actor
	return null

func item(key: String) -> Item:
	return by_id(str(targets.get(key, "")))

func _active(stage: int) -> bool:
	return prepared() and controller.stage == stage and controller.status == "active" and not controller.entry_snapshot.is_empty()

func bind_events(vehicle: Chassis) -> void:
	if not vehicle.battery_exchanged.is_connected(_battery): vehicle.battery_exchanged.connect(_battery)
	if not vehicle.cabin_lights_changed.is_connected(_lights): vehicle.cabin_lights_changed.connect(_lights)
	var player: Node = controller._world().get_node("Player")
	if not player.item_unmounted.is_connected(_unmounted): player.item_unmounted.connect(_unmounted)
	if not player.placement.placement_cancelled.is_connected(_cancelled): player.placement.placement_cancelled.connect(_cancelled)
	if not player.placement.placement_committed.is_connected(_placed): player.placement.placement_committed.connect(_placed)
	var tablet := item("tablet")
	if tablet != null:
		var callback := _viewed.bind(tablet)
		if not tablet.section_viewed.is_connected(callback): tablet.section_viewed.connect(callback)
	var recycler := item("scrapper")
	if recycler != null and not recycler.recycle_committed.is_connected(_recycled): recycler.recycle_committed.connect(_recycled)
	var bench := item("workbench")
	if bench != null and not bench.output_committed.is_connected(_output): bench.output_committed.connect(_output)

func _battery(socket_id: String, previous_id: String, installed_id: String) -> void:
	if not _active(2) or socket_id != targets.socket or installed_id != targets.battery or installed_id == targets.original_battery or previous_id == installed_id: return
	var socket := item("socket")
	if socket == null or socket.get_connected_rv() != controller.designated_rv() or socket.installed_battery == null or socket.installed_battery.id != installed_id or socket.installed_battery.condition <= 0 or socket.installed_battery.charge <= 0: return
	flags.battery = true
	controller.progress_changed.emit()

func _viewed(player: Node3D, section: String, tablet: Item) -> void:
	if not _active(3) or player != controller._world().get_node("Player") or tablet.persistent_id != targets.tablet or tablet.get_connected_rv() != controller.designated_rv(): return
	if section in ["overview", "energy", "equipment"]:
		flags[section] = true
		controller.progress_changed.emit()

func _lights(enabled: bool, source: Node) -> void:
	if not _active(3) or source != item("tablet") or source.current_user != controller._world().get_node("Player"): return
	if not _cabin_ready(controller.designated_rv()): return
	if not enabled: flags.lights_off = true
	elif flags.lights_off: flags.lights_on = true
	controller.progress_changed.emit()

func _cancelled(identity: String) -> void:
	if not _active(4) or identity not in [targets.scrapper, targets.workbench]: return
	flags.cancelled = true
	controller.progress_changed.emit()

func _placed(identity: String, rv_id: String) -> void:
	if not _active(4) or rv_id != controller.rv_id or identity not in [targets.scrapper, targets.workbench]: return
	var device := by_id(identity)
	if device == null or not device.can_operate() or device.get_connected_rv() != controller.designated_rv(): return
	if identity in unmounted_ids: flags.remounted = true
	if identity not in placed_ids: placed_ids.append(identity)
	flags["scrapper_placed" if identity == targets.scrapper else "workbench_placed"] = true
	controller.progress_changed.emit()

func _unmounted(identity: String, rv_id: String) -> void:
	if _active(4) and rv_id == controller.rv_id and identity in placed_ids and identity not in unmounted_ids:
		unmounted_ids.append(identity)

func _recycled(rv_id: String, identity: String, amounts: Dictionary) -> void:
	if not _active(5) or rv_id != controller.rv_id or identity not in [targets.scrap_a, targets.scrap_b, targets.barrel] or amounts.is_empty(): return
	if identity not in recycled_ids: recycled_ids.append(identity)
	controller.progress_changed.emit()

func _output(rv_id: String, identity: String, recipe: String) -> void:
	if not _active(6) or rv_id != controller.rv_id or recipe != "gasoline" or identity.is_empty(): return
	if identity not in output_ids and output_ids.size() < 64: output_ids.append(identity)
	controller.progress_changed.emit()

func acquired(identity: String, scene: String) -> void:
	if _active(6) and scene == "res://props/gas_can.tscn" and identity in output_ids:
		gasoline_id = identity
		controller.progress_changed.emit()

func complete() -> bool:
	var vehicle: Chassis = controller.designated_rv()
	match controller.stage:
		2:
			var socket := item("socket")
			return flags.battery and socket != null and socket.can_operate() and socket.get_connected_rv() == vehicle and socket.installed_battery != null and socket.installed_battery.id == targets.battery and socket.installed_battery.condition > 0 and socket.installed_battery.charge > 0
		3: return flags.overview and flags.energy and flags.equipment and flags.lights_off and flags.lights_on and bool(vehicle.interior_requested.cabin) and _cabin_ready(vehicle)
		4:
			var recycler := item("scrapper")
			var bench := item("workbench")
			return flags.scrapper_placed and flags.workbench_placed and flags.cancelled and flags.remounted and recycler != null and bench != null and recycler.can_operate() and bench.can_operate() and recycler.get_connected_rv() == vehicle and bench.get_connected_rv() == vehicle and vehicle.has_usable_power()
		5: return recycled_ids.size() == 3
		6: return not gasoline_id.is_empty()
	return false

func _cabin_ready(vehicle: Chassis) -> bool:
	if vehicle == null or not vehicle.has_usable_power(): return false
	for device in vehicle.get_equipment():
		if device is CabinLightStrip and device.can_operate(): return true
	return false

func _installed(key: String) -> bool:
	var device := item(key)
	return device != null and device.can_operate() and device.get_connected_rv() == controller.designated_rv() and controller.designated_rv().has_usable_power()

func page() -> Dictionary:
	var conditions := []
	var steps := []
	var controls := []
	var title := "Maintenance briefing pending"
	match controller.stage:
		2:
			title = "Replace the battery"
			conditions = [_condition("battery", "Install the marked reserve battery in this RV and restore usable power", complete())]
			steps = ["Drive into the second bay and park with the engine stopped.", "Pick up the reserve battery in the side work area.", "Select it in your inventory, then exchange it at the RV battery socket. Reinstalling the original battery does not count."]
			controls = ["E Pick up / install selected battery. Hold E Remove the installed battery.", "1-6 / Mouse wheel Select inventory item. Stop before exchanging batteries."]
		3:
			title = "RV control console"
			for section in ["overview", "energy", "equipment"]: conditions.append(_condition(section, "Read rvctl " + section.capitalize(), flags[section]))
			conditions.append(_condition("lights_off", "Switch cabin lighting off through rvctl", flags.lights_off))
			conditions.append(_condition("lights_on", "Switch it back on and leave it enabled", flags.lights_on and bool(controller.designated_rv().interior_requested.cabin) and _cabin_ready(controller.designated_rv())))
			steps = ["Park in the third bay. Open the vehicle's rvctl tablet.", "Read Overview, Energy and Equipment. Use the cabin-light controls to turn the lights off, then back on."]
			controls = ["Hold E Open the fixed rvctl tablet. F1 Overview, F2 Energy, F3 Equipment.", "Tab / Enter Navigate and select controls. Esc Close."]
		4:
			title = "Install workshop equipment"
			conditions = [_condition("scrapper", "Fasten the training scrapper to this RV and restore its service", flags.scrapper_placed and _installed("scrapper")), _condition("workbench", "Fasten the training workbench to this RV and restore its service", flags.workbench_placed and _installed("workbench")), _condition("cancel", "Cancel one equipment placement preview", flags.cancelled), _condition("remount", "Remove an installed training unit and fasten it again", flags.remounted)]
			steps = ["Collect the workbench and scrapper from opposite sides of the fourth bay, one large item at a time.", "The rear cabin has room for these units. Keep the central walkway, scrapper feed and workbench print bed clear.", "Begin placement, cancel one preview, then fasten both units securely to the RV floor.", "Unfasten either installed training unit and fasten it again. Both must be connected and usable before the gate opens."]
			controls = ["E Pick up. F Placement preview. Left click Confirm. Right click / Esc Cancel preview.", "Q/E Rotate. R Surface/upright mode. Arrow keys Shift preview. Hold F Remove an installed item."]
		5:
			title = "Recover supplies"
			for key in ["scrap_a", "scrap_b", "barrel"]: conditions.append(_condition(key, "Recycle " + ("marked oil barrel" if key == "barrel" else "marked scrap " + ("A" if key == "scrap_a" else "B")) + " into RV storage", targets[key] in recycled_ids))
			steps = ["Collect the two marked scraps and oil barrel from the fifth bay's side work area.", "Drop small scraps into your training scrapper's feed. Carry the oil barrel to the scrapper and deposit it through the large-item intake.", "Wait for all three inputs to finish and their materials to enter RV storage. A queued or interrupted input is not complete."]
			controls = ["E Pick up. G Drop selected item. Hold E Deposit a held large item at the scrapper."]
		6:
			title = "Manufacture fuel"
			conditions = [_condition("output", "Finish manufacturing a gasoline can at the training workbench", not output_ids.is_empty()), _condition("pickup", "Pick up one of its completed gasoline cans", not gasoline_id.is_empty())]
			steps = ["Park in the sixth bay. The recovered supplies are enough for gasoline.", "Open rvctl Crafting, select the training workbench and the Gasoline Can recipe, then confirm production.", "Keep the print bed clear. Wait for the physical can to appear, then pick it up. Adding a job to the queue does not count."]
			controls = ["Hold E Open rvctl. F4 Crafting. Tab / Enter Select workstation, recipe and Craft.", "E Pick up the completed can."]
		7:
			steps = ["Workshop training complete. The maintenance briefing is not available yet."]
	return {"available": controller.stage < 7, "stage": controller.stage, "title": title,
		"conditions": conditions, "steps": steps, "reference": controls}

func _condition(identity: String, text: String, done: bool) -> Dictionary:
	return {"id": identity, "label": text, "complete": done}

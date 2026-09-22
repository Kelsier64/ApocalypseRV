extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await physics_frame
	await process_frame
	var front: CabinLightStrip = rv.get_node("CabinLightFront")
	var rear: CabinLightStrip = rv.get_node("CabinLightRear")
	check(front.can_operate() and rear.can_operate() and front.mount_support == rv.get_node("Ceiling"), "Preset strips are equipment mounted to the roof")
	check(front.mass == 1.5 and front.bottom_face == Equipment.BottomFace.UP, "Light equipment has weight and mounts by its upper face")
	rv.current_power = 80
	rv.interior_requested = {"cabin": false, "work": false, "service": false}
	rv.energy.step(rv, 0, 1)
	var baseline := rv.energy.load_rate
	var console: Node = rv.get_node("TabletScreen").ui_instance
	console.on_open()
	var cabin_buttons := console.find_children("*", "Button", true, false).filter(func(button): return button.text == "車內照明開關")
	check(cabin_buttons.size() == 1, "Console exposes the cabin lighting control")
	if cabin_buttons.is_empty(): quit(1); return
	cabin_buttons[0].pressed.emit()
	rv.energy.step(rv, 0, 1)
	check(is_equal_approx(rv.energy.load_rate - baseline, 0.06), "Console request powers exactly two strips")
	var strip_controls: Array = console.device_labels[front.persistent_id].get_parent().find_children("*", "Button", true, false)
	check(strip_controls.size() == 1, "Console also controls each light equipment item")
	if strip_controls.is_empty(): quit(1); return
	strip_controls[0].pressed.emit()
	rv.energy.step(rv, 0, 1)
	await process_frame
	check(is_equal_approx(rv.energy.load_rate - baseline, 0.03) and not front.get_node("CabinLighting").lamps[0].visible and rear.get_node("CabinLighting").lamps[0].visible, "Disabled strip goes dark and stops its own load")
	front.detach_from_support()
	check(not front.can_operate() and not rv.get_equipment().has(front), "Detached strip stops service and leaves equipment registry")
	rear.current_health = 0
	rv.energy.step(rv, 0, 1)
	await process_frame
	check(not rv.interior_powered.cabin and is_equal_approx(rv.energy.load_rate, baseline), "No operational strips means no hidden cabin light or draw")
	front.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.5, 2.44, 0)), rv, rv.get_node("Ceiling"))
	front.set_enabled(true)
	var saved := VehicleSnapshot.capture(rv)
	var id := front.persistent_id
	check(VehicleSnapshot.validate(saved) and VehicleSnapshot.apply(rv, saved), "Equipment save restores strips through trusted scene catalog")
	var strips := rv.get_equipment().filter(func(device): return device is CabinLightStrip)
	check(strips.size() == 2 and strips.any(func(device): return device.persistent_id == id and device.position.is_equal_approx(Vector3(0.5, 2.44, 0)) and device.mount_support is Equipment), "Moved strip identity, position and support survive reload")
	var removed := saved.duplicate(true)
	removed.equipment = removed.equipment.filter(func(entry): return entry.scene != "res://equipment/cabin_light_strip.tscn")
	check(VehicleSnapshot.apply(rv, removed) and not rv.get_equipment().any(func(device): return device is CabinLightStrip), "Saving removed strips never respawns them")
	var legacy := removed.duplicate(true)
	legacy.erase("cabin_light_devices")
	var migrated := VehicleSnapshot.upgrade(legacy)
	check(VehicleSnapshot.validate(migrated) and migrated.equipment.size() == legacy.equipment.size() + 2, "Legacy roof lights convert once to two supported devices")
	check(VehicleSnapshot.upgrade(migrated) == migrated and legacy.equipment.size() == removed.equipment.size(), "Migration is idempotent and does not mutate source")
	check(VehicleSnapshot.apply(rv, migrated), "Legacy converted lights load")
	rv.get_equipment().filter(func(device): return device.get("structure_kind") == "roof")[0].detach_from_support()
	await process_frame
	await process_frame
	check(not rv.get_equipment().any(func(device): return device is CabinLightStrip), "Removing supporting roof detaches the actual light equipment")
	world.queue_free()
	await process_frame
	for failure in failures: push_error("FAIL: " + failure)
	if failures.is_empty(): print("PASS: console-controlled light equipment, power, detach, persistence and legacy conversion")
	quit(0 if failures.is_empty() else 1)

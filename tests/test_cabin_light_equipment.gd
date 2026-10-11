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
	check(front.can_operate() and rear.can_operate() and front.mount_support == rv.get_node("RoofFront") and rear.mount_support == rv.get_node("RoofRear"), "Preset strips are Item mounted to the roof")
	check(front.mass == 1.5 and front.bottom_face == Item.BottomFace.UP, "Light equipment has weight and mounts by its upper face")
	rv.current_power = 80
	rv.interior_requested = {"cabin": false, "work": false, "service": false}
	rv.energy.step(rv, 0, 1)
	var baseline := rv.energy.load_rate
	var player: Node3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(20, 1, 0)
	player.set_physics_process(false)
	var tablet: Item = rv.get_node("TabletScreen")
	tablet.interact_hold(player)
	var console: Node = tablet.ui_instance
	check(player.in_ui_mode and tablet.current_user == player, "Light controls have a real tablet operator")
	console.select_page("equipment")
	check(console.controls["cabin"] is CheckButton and console.controls["service"] is CheckButton, "Console exposes native cabin and engine service light controls")
	console.controls["cabin"].button_pressed = true
	rv.energy.step(rv, 0, 1)
	check(is_equal_approx(rv.energy.load_rate - baseline, 0.06), "Console request powers exactly two strips")
	console.select_page("equipment")
	var strip_control: CheckButton = console.controls["device:" + front.persistent_id]
	check(strip_control.button_pressed, "Console also controls each installed light by persistent identity")
	strip_control.button_pressed = false
	rv.energy.step(rv, 0, 1)
	await process_frame
	check(is_equal_approx(rv.energy.load_rate - baseline, 0.03) and not front.get_node("CabinLighting").lamps[0].visible and rear.get_node("CabinLighting").lamps[0].visible, "Disabled strip goes dark and stops its own load")
	front.detach_from_support()
	check(not front.can_operate() and not rv.get_equipment().has(front), "Detached strip stops service and leaves equipment registry")
	rear.current_health = 0
	rv.energy.step(rv, 0, 1)
	await process_frame
	check(not rv.interior_powered.cabin and is_equal_approx(rv.energy.load_rate, baseline), "No operational strips means no hidden cabin light or draw")
	tablet._close_ui()
	front.confirm_placement(rv.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.5, 2.44, 0)), rv, rv.get_node("RoofMiddle"))
	front.set_enabled(true)
	rear.current_health = rear.max_health
	var saved := VehicleSnapshot.capture(rv)
	var id := front.persistent_id
	check(VehicleSnapshot.validate(saved) and VehicleSnapshot.apply(rv, saved), "Item save restores strips through trusted scene catalog")
	var strips := rv.get_equipment().filter(func(device): return device is CabinLightStrip)
	check(strips.size() == 2 and strips.any(func(device): return device.persistent_id == id and device.position.is_equal_approx(Vector3(0.5, 2.44, 0)) and device.mount_support == rv.get_node("RoofMiddle")), "Moved strip identity, position and support survive reload")
	var removed := saved.duplicate(true)
	removed.mounted_items = removed.mounted_items.filter(func(entry): return entry.scene != "res://equipment/cabin_light_strip.tscn")
	check(VehicleSnapshot.apply(rv, removed) and not rv.get_equipment().any(func(device): return device is CabinLightStrip), "Saving removed strips never respawns them")
	var legacy := removed.duplicate(true)
	legacy.version = 3
	check(VehicleSnapshot.upgrade(legacy).is_empty(), "Legacy roof lights are not migrated into the new structure system")
	check(VehicleSnapshot.apply(rv, saved), "Restore supported light Item before destructive check")
	rv.get_node("StructureSlots").panel("roof_1").take_damage(999.0)
	await process_frame
	await process_frame
	var remaining := rv.get_equipment().filter(func(device): return device is CabinLightStrip)
	check(remaining.size() == 1 and remaining[0].mount_support == rv.get_node("RoofRear") and remaining[0].can_operate(), "Middle roof breach drops only its relocated strip and preserves the rear light")
	check(not rv.get_node("RoofFront").is_destroyed, "Other roof panels remain intact after one lamp support breaks")
	rv.get_node("StructureSlots").panel("roof_2").take_damage(999.0)
	await process_frame
	await process_frame
	check(not rv.get_equipment().any(func(device): return device is CabinLightStrip), "Destroying the rear roof drops the remaining strip without hidden lights")
	world.queue_free()
	await process_frame
	for failure in failures: push_error("FAIL: " + failure)
	if failures.is_empty(): print("PASS: console-controlled light Item, power, detach, persistence and legacy rejection")
	quit(0 if failures.is_empty() else 1)

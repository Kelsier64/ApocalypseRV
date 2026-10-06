extends SceneTree
var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var controller: RVStructureConstruction

class TerminalStub extends Node:
	var rv: Node3D
	var current_user: Node
	var ui_instance: CanvasLayer
	var online := true
	func can_operate() -> bool: return online
	func get_connected_rv() -> Node3D: return rv

func _init() -> void: _run.call_deferred()
func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

func _run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await physics_frame
	await physics_frame
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	controller = slots.construction
	controller.set_physics_process(false)
	var terminal := TerminalStub.new()
	terminal.rv = rv
	terminal.current_user = Node.new()
	terminal.add_child(terminal.current_user)
	terminal.ui_instance = CanvasLayer.new()
	terminal.add_child(terminal.ui_instance)
	world.add_child(terminal)
	# Keep energy authority real while the test advances only construction time.
	var socket: BatterySocket = rv.get_battery_socket()
	socket.set_physics_process(false)
	rv.energy.battery = socket.installed_battery
	rv.current_power = rv.max_power
	rv.energy.engine_running = false
	rv.storage.items["Metal Parts"] = 100
	var panel: Node = slots.panel("left_1")
	panel.set_health(30.0)
	check(controller.begin(terminal, "left_1", "repair").is_empty(), "Repair starts from open powered terminal")
	check(not controller.begin(terminal, "left_1", "repair").is_empty(), "Second click cannot create a second job")
	controller._physics_process(1.99)
	check(panel.current_health == 30 and rv.get_item_count("Metal Parts") == 100, "No health or material change before completion")
	controller._physics_process(0.01)
	check(panel.current_health == 90 and rv.get_item_count("Metal Parts") == 98, "One repair gives 60 HP and costs two parts")
	check(controller.begin(terminal, "left_1", "repair").is_empty(), "Second repair starts")
	controller._physics_process(2.0)
	check(panel.current_health == panel.max_health and not controller.is_building(), "Repair clamps to maximum and stops after one round")
	check(not controller.begin(terminal, "left_1", "repair").is_empty(), "Full health repair is rejected")
	panel.set_health(60.0)
	var materials := rv.get_item_count("Metal Parts")
	check(controller.begin(terminal, "left_1", "repair").is_empty(), "Damage cancellation job starts")
	panel.take_damage(1.0)
	check(not controller.is_building() and rv.get_item_count("Metal Parts") == materials, "Hit cancels immediately without spending")
	for interruption in ["close", "service", "power", "engine", "speed"]:
		check(controller.begin(terminal, "left_1", "repair").is_empty(), "Job starts before " + interruption)
		match interruption:
			"close": terminal.ui_instance.visible = false
			"service": terminal.online = false
			"power": rv.current_power = 0.0
			"engine": rv.energy.engine_running = true
			"speed": rv.linear_velocity = Vector3(0.51, 0, 0)
		controller._physics_process(0.02)
		check(not controller.is_building() and rv.get_item_count("Metal Parts") == materials, interruption + " cancels without spending")
		terminal.ui_instance.visible = true
		terminal.online = true
		rv.current_power = rv.max_power
		rv.energy.engine_running = false
		rv.linear_velocity = Vector3.ZERO
	# Materials can disappear during the countdown; completion must reject it.
	check(controller.begin(terminal, "left_1", "repair").is_empty(), "Material revalidation job starts")
	rv.storage.items["Metal Parts"] = 1
	var health: float = panel.current_health
	controller._physics_process(2.0)
	check(not controller.is_building() and panel.current_health == health and rv.get_item_count("Metal Parts") == 1, "Missing materials at completion cannot grant health")
	rv.storage.items["Metal Parts"] = 100
	# Production now mounts the interior roof ladder on LeftMiddle. Move that
	# default device clear before testing controlled wall conversion cases.
	for device in rv.get_equipment():
		if device.mount_support == panel:
			device.set_mount_support(rv)
			device.position.x = 20.0
	var door_type := ""
	for type in RVStructureSlots.types_for_slot("left_1"):
		if type != panel.definition.type_id: door_type = type
	check(controller.begin(terminal, "left_1", "convert", panel.definition.type_id) != "", "Same type conversion is rejected")
	var ratio: float = panel.current_health / panel.max_health
	var attached := Item.new()
	attached.equipment_name = "AttachedDevice"
	rv.add_child(attached)
	attached.confirm_placement(attached.global_transform, rv, panel)
	var indirect := Item.new()
	indirect.equipment_name = "IndirectDevice"
	rv.add_child(indirect)
	indirect.confirm_placement(indirect.global_transform, rv, attached)
	await physics_frame
	# Fixed Items retain both direct and transitive mount dependencies.
	check(attached.is_fixed and indirect.is_fixed and indirect.mount_support == attached, "Controlled wall fixtures are fixed to their intended supports")
	check(controller.rejection_reason(terminal, "left_1", "convert", door_type).contains("IndirectDevice"), "Conversion lists direct and indirect attached devices")
	check(controller.begin(terminal, "left_1", "repair").is_empty(), "Repair permits attached devices")
	controller.cancel()
	indirect.free()
	attached.free()
	var obstacle := StaticBody3D.new()
	obstacle.name = "ConstructionBlocker"
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.5, 0.3)
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = panel.global_position
	await physics_frame
	check(controller.begin(terminal, "left_1", "convert", door_type).contains("ConstructionBlocker"), "Candidate door collision prevents trapping an obstacle")
	obstacle.free()
	await physics_frame
	check(controller.begin(terminal, "left_1", "convert", door_type).is_empty(), "Wall to door conversion starts")
	controller._physics_process(4.0)
	panel = slots.panel("left_1")
	check(panel.definition.type_id == door_type and is_equal_approx(panel.current_health / panel.max_health, ratio), "Conversion preserves health percentage")
	check(panel.angles[0] == 0 and rv.get_item_count("Metal Parts") == 98, "New door is closed and costs two parts")
	panel.take_damage(panel.max_health)
	check(slots.occupant("left_1") == null, "Destroyed panel leaves an empty slot")
	# A late blocker must be checked again before the material commit.
	check(controller.begin(terminal, "left_1", "rebuild", door_type).is_empty(), "Rebuild starts before a late blocker")
	obstacle = StaticBody3D.new()
	obstacle.name = "LateConstructionBlocker"
	collider = CollisionShape3D.new()
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = panel.global_position
	await physics_frame
	controller._physics_process(6.0)
	check(panel.is_destroyed and rv.get_item_count("Metal Parts") == 98, "Late collision obstruction cancels rebuild without spending")
	obstacle.free()
	await physics_frame
	check(controller.begin(terminal, "left_1", "rebuild", door_type).is_empty(), "Destroyed slot can rebuild selected type")
	controller._physics_process(6.0)
	panel = slots.panel("left_1")
	check(not panel.is_destroyed and panel.current_health == panel.max_health and rv.get_item_count("Metal Parts") == 92, "Rebuild restores full health and costs six parts")
	# Roof variants use the same transaction, including real opening geometry.
	var roof: Node = slots.panel("roof_0")
	check(roof.definition.type_id == "rv_ceiling" and slots.panel("roof_1").definition.type_id == "rv_ceiling_hatch" and slots.panel("roof_2").definition.type_id == "rv_ceiling", "Production roof starts solid / left hatch / solid")
	for slot_id in ["roof_0", "roof_1", "roof_2"]:
		check(slots.panel(slot_id).mass == 50.0 and slots.panel(slot_id).max_health == 120.0, "Roof segment keeps 50 kg and 120 HP: " + slot_id)
		check(RVStructureSlots.types_for_slot(slot_id).has("rv_ceiling_hatch"), "Every roof slot permits a hatch variant: " + slot_id)
	# Move existing mounted lights clear before adding controlled support cases.
	for device in rv.get_equipment():
		if device.mount_support == roof:
			device.set_mount_support(rv)
			device.position.x = 20.0
	attached = Item.new()
	attached.equipment_name = "RoofAttachedDevice"
	rv.add_child(attached)
	attached.confirm_placement(attached.global_transform, rv, roof)
	indirect = Item.new()
	indirect.equipment_name = "RoofIndirectDevice"
	rv.add_child(indirect)
	indirect.confirm_placement(indirect.global_transform, rv, attached)
	await physics_frame
	check(attached.is_fixed and indirect.is_fixed and indirect.mount_support == attached, "Controlled roof fixtures are fixed to their intended supports")
	check(controller.rejection_reason(terminal, "roof_0", "convert", "rv_ceiling_hatch").contains("RoofIndirectDevice"), "Roof variant change rejects indirect attached Item")
	indirect.free()
	attached.free()
	roof.set_health(60.0)
	var roof_materials := rv.get_item_count("Metal Parts")
	obstacle = StaticBody3D.new()
	obstacle.name = "HatchOpeningOccupant"
	collider = CollisionShape3D.new()
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	# The hatch is on the left: x=-1.8..-.35, z=-.8..+.8 in each segment.
	var opening_point: Vector3 = roof.to_global(Vector3(-1.075, 0, 0))
	obstacle.global_position = opening_point
	await physics_frame
	check(controller.begin(terminal, "roof_0", "convert", "rv_ceiling_hatch").is_empty(), "A body wholly inside the left opening does not block hatch installation")
	controller._physics_process(4.0)
	roof = slots.panel("roof_0")
	check(roof.definition.type_id == "rv_ceiling_hatch" and roof.current_health == 60.0 and rv.get_item_count("Metal Parts") == roof_materials - 2, "Solid-to-hatch preserves health and costs two parts")
	check(controller.begin(terminal, "roof_0", "convert", "rv_ceiling").contains("HatchOpeningOccupant"), "Closing the opening rejects an occupant in its real collision volume")
	check(rv.get_item_count("Metal Parts") == roof_materials - 2, "Blocked roof conversion does not spend materials")
	obstacle.free()
	await physics_frame
	var opening_query := PhysicsRayQueryParameters3D.create(opening_point + Vector3.UP * 0.4, opening_point - Vector3.UP * 0.4, 1)
	check(rv.get_world_3d().direct_space_state.intersect_ray(opening_query).is_empty(), "Hatch opening has no hidden roof collision")
	check(controller.begin(terminal, "roof_0", "convert", "rv_ceiling").is_empty(), "Removing the opening occupant permits solid roof conversion")
	controller._physics_process(4.0)
	roof = slots.panel("roof_0")
	check(roof.definition.type_id == "rv_ceiling" and roof.current_health == 60.0 and rv.get_item_count("Metal Parts") == roof_materials - 4, "Hatch-to-solid preserves health and costs two parts")
	await physics_frame
	check(not rv.get_world_3d().direct_space_state.intersect_ray(opening_query).is_empty(), "Solid variant actually closes the former opening")
	roof.take_damage(roof.max_health)
	check(controller.begin(terminal, "roof_0", "rebuild", "rv_ceiling_hatch").is_empty(), "Destroyed roof slot can rebuild as the hatch variant")
	controller._physics_process(6.0)
	roof = slots.panel("roof_0")
	check(roof.definition.type_id == "rv_ceiling_hatch" and roof.current_health == 120.0 and rv.get_item_count("Metal Parts") == roof_materials - 10, "Roof hatch rebuild costs six parts and restores full segment health")
	# Restore the material fixture for the independent real-terminal scenarios.
	rv.storage.items["Metal Parts"] = roof_materials
	var tablet: Node = rv.get_node("TabletScreen")
	var tablet_health: float = tablet.current_health
	tablet.take_damage(9999.0)
	check(tablet.current_health == tablet_health and not tablet.is_in_group(Groups.MONSTER_DAMAGEABLE), "Tablet is immune and excluded from monster attack targets")
	var player: Node3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(10, 0, 0)
	player.set_physics_process(false)
	panel.set_health(40.0)
	tablet.interact_hold(player)
	var ui: Node = tablet.ui_instance
	check(ui.visible and ui.service_tabs.get_tab_count() == 2 and ui.structure_rows.size() == 12, "Real tablet opens with a dedicated structure page and all twelve slots")
	check(ui.structure_buttons.filter(func(entry): return entry.slot == "roof_1" and entry.operation == "convert").size() == 1, "Roof row exposes the same variant conversion action as side rows")
	ui.service_tabs.current_tab = 1
	ui._refresh_structures()
	for entry in ui.structure_buttons:
		if entry.slot == "left_1" and entry.operation == "repair":
			check(not entry.button.disabled and entry.button.text.contains("2 Metal Parts"), "Repair button shows fee and is enabled for damaged structure")
			entry.button.pressed.emit()
	check(controller.is_building(), "Real UI repair button starts the vehicle construction job")
	tablet._close_ui()
	check(not controller.is_building() and rv.get_item_count("Metal Parts") == 92 and panel.current_health == 40, "Closing actual terminal cancels its job without charge or repair")
	# Construction updates before the terminal in the vehicle tree. Losing the
	# operator must block the final commit even before terminal cleanup runs.
	tablet.interact_hold(player)
	check(controller.begin(tablet, "left_1", "repair").is_empty(), "Real operator starts final-tick death scenario")
	controller._physics_process(1.99)
	player.is_player_dead = true
	controller._physics_process(0.01)
	check(not controller.is_building() and rv.get_item_count("Metal Parts") == 92 and panel.current_health == 40, "Operator death before terminal update prevents last-tick material commit")
	player.is_player_dead = false
	tablet._close_ui()
	tablet.interact_hold(player)
	check(controller.begin(tablet, "left_1", "repair").is_empty(), "Real operator starts UI mode loss scenario")
	player.exit_ui_mode()
	controller._physics_process(2.0)
	check(not controller.is_building() and rv.get_item_count("Metal Parts") == 92 and panel.current_health == 40, "Leaving player UI mode invalidates construction before tablet hides")
	tablet._close_ui()
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: transactional structure construction and tablet immunity")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

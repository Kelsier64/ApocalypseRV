extends SceneTree
## Item ownership transitions through production player inventory and gestures.
var failures: Array[String] = []
var world: Node3D
var actor: CharacterBody3D
var ray: RayCast3D
var entities: Node3D

func _init() -> void: run.call_deferred()

func check(value: bool, note: String) -> void:
	if not value: failures.append(note)

func steps(count: int = 2) -> void:
	for index in count:
		await physics_frame
		await process_frame

func find_item(id: String) -> Item:
	for child in entities.get_children():
		if child is Item and child.persistent_id == id and not child.presentation_only and not child.is_queued_for_deletion(): return child
	return null

func make_item(path: String, at: Vector3) -> Item:
	var item := load(path).instantiate() as Item
	item.position = at
	entities.add_child(item)
	return item

func clear_bag() -> void:
	actor.cancel_equipment_placement()
	actor.inventory.items.clear()
	actor.inventory.active_slot = 0
	actor.refresh_inventory()

func check_new_grants() -> void:
	check(actor.add_item(ItemNames.GAS_CAN_EMPTY, false, "res://props/gas_can_empty.tscn"), "Sparse new grant receives canonical Item state")
	var granted: Dictionary = actor.inventory.active_item().state.duplicate(true)
	check(ItemState.valid("res://props/gas_can_empty.tscn", granted), "New grant is immediately valid for v5 persistence")
	check(actor.add_item("Scrap", false, "res://props/scrap.tscn"), "Second new grant can fill another slot")
	actor._set_active_slot(1)
	actor._set_active_slot(0)
	check(actor.held_item_node.persistent_id == granted.id and actor.inventory.active_item().state == granted, "Re-equipping preserves inventory-owned new grant identity")
	var save_path := "res://.godot/test-item-grant.save"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_var(actor.inventory.items, false)
	file.close()
	file = FileAccess.open(save_path, FileAccess.READ)
	var restored: Array = file.get_var(false)
	file.close()
	DirAccess.remove_absolute(save_path)
	check(restored[0].state == granted and ItemState.unique_ids(restored), "Disk serialization retains canonical granted identity and condition")
	actor.drop_item()
	var dropped := find_item(granted.id)
	check(dropped != null and dropped.capture_item_state() == granted, "Dropping a new grant preserves its complete Item state")
	if dropped: dropped.queue_free()
	clear_bag()
	check(not actor.add_item("Scrap", false, "res://props/scrap.tscn", {"id": "", "condition": 100}), "Grant boundary refuses malformed complete state")
	check(actor.inventory.items.is_empty(), "Malformed state refusal does not insert inventory record")
	var battery := BatteryState.new({"id": "grant-battery", "capacity": 160.0, "charge": 21.0, "weight": 18.0, "condition": 37.0})
	check(actor.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"battery": battery.snapshot()}), "Sparse battery grant accepts existing subtype data")
	check(actor.inventory.active_item().state.id == battery.id and actor.inventory.active_item().state.battery == battery.snapshot() and actor.inventory.active_item().state.condition == 37.0, "Battery grant retains embedded ID, charge and durability")
	clear_bag()
	var authored_battery := {"id": "authored-battery", "capacity": 100.0, "charge": 19.0, "weight": 15.0}
	check(actor.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"battery": authored_battery}), "Authored sparse battery payload defaults missing condition")
	check(actor.inventory.active_item().state.id == authored_battery.id and actor.inventory.active_item().state.battery.charge == 19.0 and actor.inventory.active_item().state.condition == 100.0, "Authored battery grant preserves charge and ID with full default durability")
	check(not authored_battery.has("condition"), "Grant initialization leaves caller-authored sparse data unchanged")
	clear_bag()
	check(not actor.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"id": authored_battery.id, "condition": 100.0, "battery": authored_battery}), "Complete saved-style state with missing subtype durability is refused, not repaired")
	var engine := EngineState.new({"id": "grant-engine", "model": "standard", "health": 217.0})
	check(actor.add_item(engine.definition().display_name, true, "res://props/engine_standard.tscn", {"engine": engine.snapshot()}), "Sparse engine grant accepts existing subtype data")
	check(actor.inventory.active_item().state.id == engine.id and actor.inventory.active_item().state.engine == engine.snapshot(), "Engine grant retains embedded ID and health")
	clear_bag()
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(100, 1, 100)
	world.add_child(shell)
	var rv := shell.get_node("Chassis") as Chassis
	rv.freeze = true
	rv.set_physics_process(false)
	await steps()
	rv.current_fuel = 0.0
	check(actor.add_item(ItemNames.GAS_CAN, false, "res://props/gas_can.tscn"), "Gas-can grant receives canonical state")
	var full_id: String = actor.inventory.active_item().state.id
	var fuel_port := rv.get_node("FuelPort") as Item
	check(fuel_port.interact(actor).contains("空罐"), "Fuel-port conversion produces empty can through grant boundary")
	var empty: Dictionary = actor.inventory.active_item().state.duplicate(true)
	check(actor.inventory.active_item().scene_path == "res://props/gas_can_empty.tscn" and ItemState.valid("res://props/gas_can_empty.tscn", empty) and empty.id != full_id, "Converted empty can owns one valid new identity")
	file = FileAccess.open(save_path, FileAccess.WRITE)
	file.store_var(actor.inventory.items, false)
	file.close()
	file = FileAccess.open(save_path, FileAccess.READ)
	restored = file.get_var(false)
	file.close()
	DirAccess.remove_absolute(save_path)
	check(restored[0].scene_path == "res://props/gas_can_empty.tscn" and restored[0].state == empty, "Refueled empty-can disk save retains its scene path, ID and complete state")
	actor.inventory.items.assign(restored)
	actor.refresh_inventory()
	check(actor.held_item_node.scene_file_path == "res://props/gas_can_empty.tscn" and actor.held_item_node.get_node("gas_can").scene_file_path == "res://assets/models/gas_can/gas_can.glb", "Reloaded converted empty can instantiates its gameplay scene and shared visual")
	check(actor.held_item_node.persistent_id == empty.id, "Converted empty-can identity survives held-model refresh")
	actor.drop_item()
	dropped = find_item(empty.id)
	check(dropped != null and dropped.capture_item_state() == empty, "Converted empty-can throw retains canonical state")
	if dropped: dropped.queue_free()
	shell.queue_free()
	clear_bag()
	await steps()

func run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	actor = load("res://player/player.tscn").instantiate()
	actor.position = Vector3(20, 1, 20)
	world.add_child(actor)
	actor.set_physics_process(false)
	ray = actor.camera.get_node("InteractRay")
	ray.set_physics_process(false)
	entities = WorldEntities.get_container(actor)
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.2, 4, 4)
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	wall.position = Vector3(0, 2, 0)
	await steps()
	await check_new_grants()

	# Capacity rejection leaves real fixed ownership and service state intact.
	var generator := make_item("res://equipment/generator.tscn", Vector3(2, 2, 0))
	await steps()
	generator.confirm_placement(generator.global_transform, entities, wall)
	check(generator.is_fixed and generator.mount_support == wall, "Generator fixes to wall")
	generator.condition = 41.0
	var generator_id := generator.persistent_id
	for index in PlayerInventory.MAX_SLOTS:
		actor.inventory.add_item("Scrap", false, "res://props/scrap.tscn")
	check(not actor.add_prop_item(generator, generator.scene_file_path), "Full inventory refuses fixed equipment")
	check(generator.is_fixed and generator.mount_support == wall and is_equal_approx(generator.condition, 41), "Rejected pickup preserves support and durability")
	clear_bag()
	actor.body_state.sever(&"left_arm")
	check(not actor.add_prop_item(generator, generator.scene_file_path), "One arm cannot carry equipment")
	check(generator.is_fixed, "Missing-arm refusal does not detach equipment")
	actor.body_state.reset()
	actor.refresh_inventory()
	generator.charging = true
	var service_before := generator.capture_service_state()
	check(not actor.add_prop_item(generator, "res://equipment/not_registered.tscn"), "Unregistered Item scene fails pickup before service cleanup")
	check(generator.is_fixed and generator.mount_support == wall and not generator._service_stopped and generator.capture_service_state() == service_before, "Invalid-scene pickup retains support and service state")

	# F hold picks up; releasing that same gesture must not start a ghost.
	ray._step_buttons(generator, false, true, 2.1)
	check(actor.inventory.items.size() == 1 and actor.inventory.active_item().is_large, "F hold transfers equipment to large-item inventory")
	check(actor.inventory.active_item().state.id == generator_id and is_equal_approx(float(actor.inventory.active_item().state.condition), 41), "F hold retains identity and condition")
	ray._step_buttons(null, false, false, 0.0)
	check(not actor.is_placing_equipment(), "Successful F hold suppresses placement tap")
	check(actor.held_item_node is Item and actor.held_item_node.presentation_only, "Held equipment is presentation only")
	check(not actor.can_drive() and not actor._can_use_ladder(), "Two-handed equipment blocks driving and climbing")
	await steps()
	var held: Node3D = actor.held_item_node
	ray._step_buttons(null, false, true, .1)
	ray._step_buttons(null, false, false, 0.0)
	check(actor.is_placing_equipment(), "F tap with inventory starts independent preview")
	check(actor.placement.placing_equipment != held and not held.visible, "Preview hides the separate held equipment model immediately")
	check(actor.placement.placing_equipment.presentation_only, "Preview cannot activate services")
	check(actor.inventory.items.size() == 1, "Preview retains inventory ownership")
	await steps()
	check(not held.is_visible_in_tree(), "Carry updates cannot reveal the held model during preview")
	var slot_label: Label = actor.inventory_ui.slots_container.get_child(0).get_child(0)
	check(slot_label.is_visible_in_tree() and slot_label.text.contains(actor.inventory.active_item().name), "Preview keeps the Item visible in the inventory bar")
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	actor.placement.handle_input(actor, cancel)
	check(actor.inventory.items.size() == 1 and actor.held_item_node == held and held.visible, "Right-click cancellation restores the same held model and inventory ownership")
	check(actor.enter_equipment_placement(), "Preview can reopen after right-click cancellation")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	actor.placement.handle_input(actor, escape)
	check(not actor.is_placing_equipment() and held.visible and actor.inventory.active_item().state.id == generator_id, "Esc restores the held model without removing the inventory Item")
	check(actor.enter_equipment_placement(), "Preview can reopen")
	actor.drop_item()
	var dropped := find_item(generator_id)
	check(not actor.is_placing_equipment() and actor.inventory.items.is_empty(), "G cancels preview and consumes inventory once")
	check(dropped != null and not dropped.is_fixed and not dropped.freeze, "G creates a loose pickup with physical motion")
	if dropped:
		check(is_equal_approx(dropped.condition, 41), "Equipment throw retains condition")
		dropped.queue_free()
	await steps()

	# Small props also fix, and support loss restores physical pickup behavior.
	actor.position = Vector3(3, 1, 0)
	await steps()
	var scrap := make_item("res://props/scrap.tscn", Vector3(5, 3, 5))
	var scrap_id := scrap.persistent_id
	check(actor.add_prop_item(scrap, scrap.scene_file_path), "Small prop enters unified inventory")
	scrap.queue_free()
	check(actor.enter_equipment_placement(), "Small item supports placement mode")
	actor.placement.target_support = wall
	actor.placement.can_place_equipment = true
	actor.placement.placing_equipment.global_transform = Transform3D(Basis.IDENTITY, actor.global_position + Vector3.UP)
	check(not actor.placement.commit(actor) and actor.inventory.items.size() == 1, "Fresh actor-overlap rejection retains inventory and preview")
	actor.placement.placing_equipment.global_transform = Transform3D(Basis.IDENTITY, Vector3(1, 2, 0))
	check(actor.placement.commit(actor), "Placement commits inventory into fixed world Item")
	var fixed := find_item(scrap_id)
	check(actor.inventory.items.is_empty() and not actor.is_placing_equipment(), "Placement consumes once and exits preview")
	check(fixed != null and fixed.is_fixed and fixed.mount_support == wall, "Ordinary prop is fixed to named support")
	check(not actor.placement.commit(actor), "Repeated commit cannot duplicate item")
	var loose := make_item("res://props/scrap.tscn", Vector3(8, 3, 8))
	check(not PlacementRules.valid_target(loose, loose), "Item cannot support itself")
	if fixed:
		check(PlacementRules.valid_target(loose, fixed), "Fixed Item supports another Item")
		check(not PlacementRules.valid_target(fixed, loose), "Loose Item cannot support a fixed placement")
		var upper := make_item("res://props/scrap.tscn", Vector3(10, 3, 10))
		upper.confirm_placement(upper.global_transform, entities, fixed)
		check(PlacementRules.valid_target(loose, upper), "Intact fixed Item support chain accepts placement")
		for field in ["processing_owner", "_support_release_pending", "support_lost"]:
			fixed.set(field, world if field == "processing_owner" else true)
			check(not PlacementRules.valid_target(loose, fixed), "Placement rejects direct support with " + field)
			check(not PlacementRules.valid_target(loose, upper), "Placement rejects support chain with " + field)
			fixed.set(field, null if field == "processing_owner" else false)
		check(PlacementRules.valid_target(loose, upper), "Restored usable support chain accepts placement again")
		upper.queue_free()
		check(not PlacementRules.valid_target(loose, upper), "Queued support deletion immediately rejects placement")
	wall.queue_free()
	await steps()
	if fixed:
		check(not fixed.is_fixed and not fixed.freeze, "Wall removal drops attached Item")
		check(fixed.persistent_id == scrap_id, "Support drop preserves identity")
		clear_bag()
		check(actor.add_prop_item(fixed, fixed.scene_file_path), "Dropped attached Item can be picked up again")
		fixed.queue_free()
	loose.queue_free()
	world.queue_free()
	await steps()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: unified Item player preflight, F gestures, preview ownership, commit/drop and support pickup")
	quit(0 if failures.is_empty() else 1)

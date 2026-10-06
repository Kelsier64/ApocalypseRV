extends SceneTree

var failures: Array[String] = []
const SCENE := "res://props/flashlight.tscn"

func _init() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	_expect(InputMap.action_get_events("toggle_flashlight").any(func(event: InputEvent) -> bool: return event is InputEventKey and event.physical_keycode == KEY_L), "On-foot flashlight action uses L")
	_expect(InputMap.action_get_events("toggle_flashlight").any(func(event: InputEvent) -> bool: return event is InputEventKey and event.keycode == KEY_L), "Flashlight also accepts logical L")
	var native_key := InputEventKey.new()
	native_key.pressed = true
	native_key.keycode = KEY_L
	native_key.physical_keycode = 4194313
	_expect(InputMap.event_is_action(native_key, "toggle_flashlight"), "Native logical L event matches flashlight action")
	var fresh_world: Node3D = load("res://world/test_world.tscn").instantiate()
	_expect(fresh_world.get_node_or_null("Flashlight") is Flashlight, "Fresh world places one ground flashlight")
	_expect(fresh_world.get_node("Player").inventory.items.is_empty(), "Fresh player receives no flashlight grant")
	var removable: Array[Node] = []
	root.get_node("Checkpoint")._collect_removable(fresh_world, removable)
	for actor in removable:
		if is_instance_valid(actor): actor.free()
	_expect(fresh_world.get_node_or_null("Flashlight") == null, "Checkpoint actor replacement removes default flashlight for old saves")
	fresh_world.free()
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	var entities := Node3D.new()
	entities.name = "WorldEntities"
	world.add_child(entities)
	root.add_child(world)
	current_scene = world
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	var floor := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(2.0, 0.2, 2.0)
	floor_collision.shape = floor_shape
	floor.add_child(floor_collision)
	world.add_child(floor)
	floor.position = Vector3(3.0, -0.1, 0.0)
	var loose: Flashlight = load(SCENE).instantiate()
	world.add_child(loose)
	loose.position = Vector3(3.0, 1.0, 0.0)
	for step in 120: await physics_frame
	_expect(loose.global_position.y > 0.10 and loose.global_position.y < 0.35 and loose.linear_velocity.length() < 0.2, "Loose flashlight settles on a simple collision floor")
	loose.free()
	floor.free()
	var flashlight: Flashlight = load(SCENE).instantiate()
	world.add_child(flashlight)
	flashlight.freeze = true
	_expect(flashlight.charge == 100.0 and not flashlight.switched_on and not flashlight.get_node("Beam").visible, "Ground flashlight starts full and off")
	_expect(not flashlight.is_large and SaveSceneCatalog.resolve(SCENE, "item") != null, "Flashlight is a whitelisted small Item")
	for i in PlayerInventory.MAX_SLOTS:
		_expect(player.add_item("Scrap", false, "res://props/scrap.tscn"), "Fill inventory slot")
	_expect(flashlight.interact(player).begins_with("無法拾取"), "Full inventory refuses pickup")
	_expect(not flashlight.is_queued_for_deletion(), "Rejected pickup remains in world")
	player.inventory.items.clear()
	player.inventory.active_slot = 0
	player.refresh_inventory()
	var id := flashlight.persistent_id
	_expect(flashlight.interact(player).begins_with("已拾取"), "Flashlight pickup succeeds")
	await process_frame
	_expect(player.inventory.items.size() == 1 and player.inventory.active_item().state.id == id, "Pickup preserves Item identity in inventory")
	_expect(not is_instance_valid(flashlight), "Picked-up world Item is removed")
	player._toggle_flashlight()
	_expect(player.inventory.active_item().state.flashlight.on and player.held_item_node.get_node("Beam").visible, "L toggle lights selected held flashlight")
	player._advance_flashlight(150.0)
	_expect(is_equal_approx(player.inventory.active_item().state.flashlight.charge, 50.0), "150 illuminated seconds use half the charge")
	player.in_ui_mode = true
	player._advance_flashlight(100.0)
	_expect(is_equal_approx(player.inventory.active_item().state.flashlight.charge, 50.0) and not player.held_item_node.get_node("Beam").visible, "UI hides light and pauses drain")
	player.in_ui_mode = false
	var placing := Node3D.new()
	world.add_child(placing)
	player.placement.placing_equipment = placing
	player._advance_flashlight(100.0)
	_expect(is_equal_approx(player.inventory.active_item().state.flashlight.charge, 50.0), "Placement pauses drain")
	player.placement.placing_equipment = null
	var seat := Node3D.new()
	world.add_child(seat)
	player.seated_in = seat
	player._advance_flashlight(100.0)
	_expect(is_equal_approx(player.inventory.active_item().state.flashlight.charge, 50.0), "Seat pauses drain")
	player.seated_in = null
	player.grab_control.captor = placing
	player._advance_flashlight(100.0)
	_expect(is_equal_approx(player.inventory.active_item().state.flashlight.charge, 50.0), "Grab without previously visible light pauses drain")
	player.grab_control.captor = null
	player.is_player_dead = true
	player._advance_flashlight(100.0)
	_expect(is_equal_approx(player.inventory.active_item().state.flashlight.charge, 50.0), "Death pauses drain")
	player.is_player_dead = false
	player._advance_flashlight(150.0)
	_expect(player.inventory.active_item().state.flashlight.charge == 0.0 and not player.inventory.active_item().state.flashlight.on and not player.held_item_node.get_node("Beam").visible, "300 illuminated seconds empty battery and shut beam off")
	player._toggle_flashlight()
	_expect(not player.inventory.active_item().state.flashlight.on, "Empty battery cannot be switched on")
	var empty: Dictionary = player.inventory.active_item().duplicate(true)
	_expect(VehicleSnapshot.valid_item(empty), "Drained flashlight is valid inventory data")
	empty.state.flashlight.charge = NAN
	_expect(not VehicleSnapshot.valid_item(empty), "Nonfinite charge is rejected")
	empty.state.flashlight.charge = 101.0
	_expect(not VehicleSnapshot.valid_item(empty), "Overfilled charge is rejected")
	empty.state.flashlight.charge = 50.0
	empty.state.flashlight.on = "yes"
	_expect(not VehicleSnapshot.valid_item(empty), "Nonboolean on state is rejected")
	player.inventory.items[0].state.flashlight = {"charge": 36.0, "on": false}
	player.refresh_inventory()
	player._toggle_flashlight()
	player.add_item("Scrap", false, "res://props/scrap.tscn")
	player._set_active_slot(1)
	_expect(not player.inventory.items[0].state.flashlight.on and is_equal_approx(player.inventory.items[0].state.flashlight.charge, 36.0), "Switching away turns light off without resetting charge")
	player._set_active_slot(0)
	_expect(not player.inventory.active_item().state.flashlight.on, "Switching back leaves light off")
	player._toggle_flashlight()
	player.drop_item()
	await process_frame
	var dropped: Flashlight = null
	for child in entities.get_children():
		if child is Flashlight: dropped = child
	_expect(dropped != null, "Drop creates a world flashlight")
	if dropped:
		_expect(dropped.persistent_id == id and is_equal_approx(dropped.charge, 36.0) and not dropped.switched_on, "Drop preserves id and charge and turns light off")
		var snapshot := WorldActorSnapshot.capture(dropped)
		_expect(WorldActorSnapshot.validation_error(snapshot, "actor").is_empty(), "World snapshot accepts flashlight state")
		dropped.free()
		var restored: Flashlight = WorldActorSnapshot.restore(snapshot, entities)
		_expect(restored.persistent_id == id and is_equal_approx(restored.charge, 36.0) and not restored.switched_on, "World snapshot restores exact charge and off state")
		_expect(restored.interact(player).begins_with("已拾取"), "Restored flashlight can be picked up")
		await process_frame
		player._set_active_slot(1)
		_expect(player.inventory.active_item().state.id == id and is_equal_approx(player.inventory.active_item().state.flashlight.charge, 36.0), "Re-pick preserves charge")
		player._toggle_flashlight()
		var rv: Chassis = load("res://rv/chassis.tscn").instantiate()
		_expect(rv.store_player_item(player, 1), "Flashlight can be put in RV item storage")
		_expect(not rv.stored_items[0].state.flashlight.on and is_equal_approx(rv.stored_items[0].state.flashlight.charge, 36.0), "Putaway turns light off without charging it")
		_expect(rv.take_stored_item(player, 0), "Flashlight can be retrieved from storage")
		player._set_active_slot(1)
		player._toggle_flashlight()
		player.add_item("Wheel", true, "res://props/wheel.tscn")
		_expect(player.inventory.active_slot == 2 and not player.inventory.items[1].state.flashlight.on, "Implicit large-item selection turns flashlight off")
		player._set_active_slot(1)
		_expect(player.inventory.active_slot == 2, "Large-item selection lock remains enforced")
		player.consume_active_item()
		player._toggle_flashlight()
		player.held_item_node.hide()
		player._advance_flashlight(30.0)
		_expect(is_equal_approx(player.inventory.items[1].state.flashlight.charge, 36.0), "Hidden held preview does not drain")
		player.held_item_node.show()
		_expect(rv.store_player_item(player, 0), "Earlier slot can be stored while flashlight is selected")
		_expect(not player.inventory.active_item().state.flashlight.on and is_equal_approx(player.inventory.active_item().state.flashlight.charge, 36.0), "Removing earlier slot turns implicitly deselected flashlight off")
		rv.free()
	world.free()
	if failures.is_empty():
		print("PASS: flashlight pickup, drain, modes, and snapshots")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

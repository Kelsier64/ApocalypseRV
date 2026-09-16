extends SceneTree
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var ray: RayCast3D
var camera: Camera3D
var rv: Chassis

func _init() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func aim(target: Node3D, offset: Vector3 = Vector3(2, 0, 0)) -> void:
	camera.global_position = target.global_position + offset
	camera.look_at(target.global_position, Vector3.UP)
	ray.target_position = Vector3(0, 0, -3)
	ray.force_raycast_update()
	check(ray.get_collider() == target, "Visible target is ray-reachable: " + target.name)
	ray._physics_process(0.016)
func key(down: bool, delta: float = 0.016) -> void:
	if down: Input.action_press("interact")
	else: Input.action_release("interact")
	ray.force_raycast_update()
	ray._physics_process(delta)
func tap() -> void:
	key(true)
	key(false)
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
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(20, 1, 0)
	world.add_child(player)
	player.set_physics_process(false)
	camera = player.get_node("Camera3D")
	ray = camera.get_node("InteractRay")
	ray.set_physics_process(false)
	await physics_frame
	aim(rv.get_node("FuelPort"), Vector3(1.8, 0.45, 0))
	check(ray.prompt_label.text.contains("加油孔"), "Default mounted fuel tank has reachable interaction prompt")
	aim(rv.get_node("ItemBox"), Vector3(0.5, 0.9, -1.2))
	check(ray.prompt_label.text.contains("道具箱"), "Default mounted rack has reachable interaction prompt")
	var socket := rv.get_node("BatterySocket")
	check(not rv.has_node("Ignition"), "No separate ignition object")
	var target_box := rv.get_node("ItemBox")
	aim(socket)
	check(ray.prompt_label.text.contains("電池插槽"), "Aimed socket explains its purpose")
	tap()
	check(ray.feedback_label.text.contains("選取電池"), "Empty-hand battery tap explains prerequisite")
	var battery: Prop = load("res://props/battery.tscn").instantiate()
	battery.position = Vector3(8, 1, 0)
	world.add_child(battery)
	battery.freeze = true
	battery.battery.charge = 23.0
	await physics_frame
	aim(battery)
	tap()
	check(player.inventory.items.size() == 1 and ray.feedback_label.text.contains("已拾取"), "Real ray and E pick up battery with feedback")
	await process_frame
	aim(socket)
	var original_id := rv.energy.battery.id
	tap()
	check(rv.current_power == 23.0 and player.inventory.active_item().state.battery.id == original_id, "Short E exchanges once through real input")
	# Press and release can both arrive between physics ticks; neither edge may be lost.
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.pressed = true
	var release := InputEventKey.new()
	release.physical_keycode = KEY_E
	release.pressed = false
	ray._unhandled_input(press)
	ray._unhandled_input(release)
	ray._physics_process(0.016)
	check(rv.energy.battery.id == original_id, "A tap shorter than a physics frame still swaps once")
	key(true, 1.1)
	check(rv.energy.battery == null, "Long E removes installed battery")
	key(true, 1.1)
	key(false)
	check(rv.energy.battery == null and player.inventory.items.size() == 2, "Held E and its release do not remove twice or reinsert")
	check(not socket.get_node("Cell").visible, "Empty socket model shows no installed battery")
	tap()
	check(rv.energy.battery != null and socket.get_node("Cell").visible, "Tap inserts battery and updates visible model")
	key(true, 0.6)
	aim(target_box, Vector3(0.5, 0.9, -1.2))
	key(true, 0.7)
	key(false)
	check(rv.energy.battery != null and not player.in_ui_mode, "Looking away cancels hold without opening another device")
	var tank: Equipment = rv.get_node("FuelPort")
	rv.current_fuel = 0.0
	await physics_frame
	aim(tank, Vector3(1.8, 0.45, 0))
	tap()
	check(ray.feedback_label.text.contains("汽油罐"), "Fuel port explains required held item")
	player.inventory.items.clear()
	player.add_item(ItemNames.GAS_CAN, false, "res://props/gas_can.tscn")
	player.inventory.active_slot = 0
	tap()
	check(rv.current_fuel == 30.0 and player.get_active_item_name() == ItemNames.GAS_CAN_EMPTY, "Fuel port fills chassis and returns empty can")
	var rack: Equipment = rv.get_node("ItemBox")
	rv.stored_items.clear()
	rack.position = Vector3(0, 4, 0)
	player.inventory.items.clear()
	player.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"battery": {"id": "stored-test", "charge": 19.0, "capacity": 100.0, "weight": 15.0}})
	player.refresh_inventory()
	rv.add_item(ItemNames.METAL_PARTS, 8)
	rv.current_power = 0.0
	await physics_frame
	aim(rack)
	tap()
	check(player.in_ui_mode and rack.storage_ui.visible and rv.current_power == 0.0, "E opens unpowered item storage")
	var button: Button = rack.storage_ui.rows.get_child(1)
	button.pressed.emit()
	check(rv.stored_items.size() == 1 and player.inventory.items.is_empty(), "Storage button deposits the actual battery")
	check(rv.stored_items[0].state.battery.charge == 19.0, "Stored battery retains charge")
	button = rack.storage_ui.rows.get_child(2)
	button.pressed.emit()
	check(rv.stored_items.is_empty() and player.inventory.items.size() == 1, "Storage button retrieves item")
	rack.storage_ui.close()
	key(false)
	aim(rack)
	tap()
	check(player.in_ui_mode, "E opens storage again")
	rack._on_service_stopped()
	check(not player.in_ui_mode, "Box removal releases UI and player")
	Input.action_release("interact")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: actual rays and E gestures for battery, fuel port and shared item box")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

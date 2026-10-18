extends SceneTree
## Transaction events report successful device use, never setup or interrupted UI.
var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var tablet: Item
var ui: Node
var battery_events: Array = []
var sections: Array = []
var light_events: Array = []
var cancelled: Array = []
var committed: Array = []

func _init() -> void: run.call_deferred()

func check(value: bool, note: String) -> void:
	if not value: failures.append(note)

func frames(count := 4) -> void:
	for frame in count: await process_frame

func run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	world.add_child(floor_body)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(20, 0.05, 0)
	player.set_physics_process(false)
	await physics_frame
	await frames()
	var socket := rv.get_battery_socket()
	check(socket != null, "Real RV has a mounted battery socket")
	if socket == null:
		finish()
		return
	socket.set_physics_process(false)
	rv.battery_exchanged.connect(func(socket_id: String, previous_id: String, installed_id: String): battery_events.append([socket_id, previous_id, installed_id]))
	rv.cabin_lights_changed.connect(func(enabled: bool, source: Node): light_events.append([enabled, source]))
	check_batteries(socket)
	tablet = rv.get_node("TabletScreen")
	ui = tablet.ui_instance
	tablet.section_viewed.connect(func(user: Node3D, section: String): sections.append([user, section]))
	await check_console()
	await check_placement(floor_body)
	world.queue_free()
	await frames()
	finish()

func check_batteries(socket: BatterySocket) -> void:
	var battery: Item = load("res://props/battery.tscn").instantiate()
	world.add_child(battery)
	var installed_id: String = battery.persistent_id
	var previous_id: String = socket.installed_battery.id
	check(player.add_prop_item(battery, battery.scene_file_path), "Replacement battery enters the actual inventory")
	battery.queue_free()
	rv.linear_velocity = Vector3(1, 0, 0)
	check(not rv.exchange_battery(player, socket) and battery_events.is_empty(), "Moving vehicle rejects exchange without an event")
	rv.linear_velocity = Vector3.ZERO
	check(rv.exchange_battery(player, socket), "Stationary exchange succeeds")
	check(battery_events == [[socket.persistent_id, previous_id, installed_id]], "Exchange reports both genuine battery identities and the socket")
	check(player.inventory.active_item().state.id == previous_id and socket.installed_battery.id == installed_id, "Event follows the completed inventory/socket transfer")
	check(rv.remove_battery_to_player(player, socket) and battery_events.size() == 1, "Removing a battery does not report an exchange")
	player.inventory.active_slot = player.inventory.items.size() - 1
	check(rv.exchange_battery(player, socket), "Installation into an empty socket succeeds")
	check(battery_events.size() == 2 and battery_events[1] == [socket.persistent_id, "", installed_id], "Empty socket installation reports an empty previous identity")
	player.inventory.items.clear()
	player.refresh_inventory()
	rv.current_power = 80.0

func check_console() -> void:
	ui.select_page("energy")
	await frames()
	check(sections.is_empty(), "Hidden UI selection cannot record a viewed page")
	tablet.interact_hold(player)
	check(sections.is_empty(), "Opening does not count before the presentation frame")
	await frames()
	check(sections == [[player, "overview"]], "Actual open Overview presentation reports its current player once")
	ui.select_page("energy")
	ui.select_page("equipment")
	await frames()
	check(sections.size() == 2 and sections[1] == [player, "equipment"], "A page replaced before layout cannot count as viewed")
	ui.select_page("energy")
	ui.enter_shell()
	await frames()
	check(sections.size() == 2, "Switching to shell invalidates a pending section presentation")
	ui.submit_command("status")
	await frames()
	check(sections.size() == 2, "Text status output cannot count as a graphical section")
	ui.submit_command("rvctl")
	await frames()
	check(sections.size() == 3 and sections[2] == [player, "energy"], "rvctl counts only after actually presenting the management page")
	rv.toggle_interior_light("cabin")
	check(light_events.is_empty(), "Non-console light setup emits no tutorial transaction")
	rv.interior_requested.cabin = true
	ui.select_page("equipment")
	ui._set_light("cabin", false)
	ui._set_light("cabin", false)
	ui._set_light("cabin", true)
	check(light_events == [[false, tablet], [true, tablet]], "Successful off/on console actions report once with their actual source")
	ui.enter_shell()
	ui._set_light("cabin", false)
	check(rv.interior_requested.cabin and light_events.size() == 2, "A hidden management action cannot change lights or report success")
	ui.enter_tui()
	await frames()
	var before: int = sections.size()
	ui.select_page("energy")
	tablet._close_ui()
	await frames()
	check(sections.size() == before, "Closing the session prevents a pending view event")

func check_placement(floor_body: StaticBody3D) -> void:
	player.placement.placement_cancelled.connect(func(identity: String): cancelled.append(identity))
	player.placement.placement_committed.connect(func(identity: String, vehicle_id: String): committed.append([identity, vehicle_id]))
	var item: Item = load("res://props/flashlight.tscn").instantiate()
	world.add_child(item)
	var identity := item.persistent_id
	check(player.add_prop_item(item, item.scene_file_path), "Placement item enters the real inventory")
	item.queue_free()
	check(player.enter_equipment_placement(), "Real inventory item creates a placement preview")
	player.cancel_equipment_placement()
	check(cancelled.is_empty(), "Lifecycle cancellation cannot count as an explicit user action")
	check(player.enter_equipment_placement(), "Player can restart the preview after interruption")
	var cancel_event := InputEventMouseButton.new()
	cancel_event.button_index = MOUSE_BUTTON_RIGHT
	cancel_event.pressed = true
	player.placement.handle_input(player, cancel_event)
	check(cancelled == [identity] and committed.is_empty(), "Right click reports the actual cancelled preview identity without committing")
	check(player.enter_equipment_placement(), "Player starts a placement intended for confirmation")
	check(not player.placement.commit(player) and committed.is_empty(), "An unvalidated preview cannot report a commit")
	player.camera.global_position = Vector3(20, 2, 0.8)
	player.camera.look_at(Vector3(20, 0, 0))
	await physics_frame
	await frames()
	player.placement.update_ghost(player)
	check(player.placement.can_place_equipment and player.placement.target_support == floor_body, "Actual floor ray validates the placement")
	check(player.placement.commit(player), "Validated real placement commits")
	check(committed == [[identity, ""]] and cancelled == [identity], "Commit emits after consuming inventory and does not emit user cancellation")
	check(player.inventory.items.is_empty(), "Successful placement consumes the transferred inventory item")
	var fixed: Item
	for actor in WorldEntities.get_container(player).get_children():
		if actor is Item and actor.persistent_id == identity and not actor.presentation_only: fixed = actor
	check(fixed != null and fixed.is_fixed and fixed.mount_support == floor_body, "Commit leaves the same identity fixed to its actual world support")

func finish() -> void:
	for failure in failures: push_error("FAIL: " + failure)
	if failures.is_empty(): print("PASS: successful tutorial transactions and interrupted device presentation")
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Real input routing, actor physics and mounted-seat ownership in a small arena.
var failures: Array[String] = []
var arena: Node3D
var player: CharacterBody3D
var menu: Node
var clock: WorldClock
var rv_shell: Node3D

class SmallInterior extends PoiInterior:
	# Exercise production transition and viewport routing without bunker generation.
	func build(_seed: int, _saved: Dictionary = {}) -> bool:
		var floor_body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = WorldBoundaryShape3D.new()
		floor_body.add_child(collision)
		add_child(floor_body)
		exit_door = PoiEntrance.new()
		add_child(exit_door)
		layout = {"rooms": [], "links": [], "floor_spacing": 4.0}
		var map_layer := CanvasLayer.new()
		map_layer.layer = 3
		add_child(map_layer)
		_map = load("res://world/instances/interior_map.gd").new()
		_map.interior = self
		_map.size = Vector2(600, 400)
		_map.hide()
		map_layer.add_child(_map)
		return true
	func spawn_transform() -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0))

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func frames(count: int) -> void:
	for frame in count: await physics_frame
func key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
func tap(code: Key) -> void:
	key(code, true)
	key(code, false)
	await process_frame
	await process_frame
func click_button(button: Button) -> void:
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			break
		ancestor = ancestor.get_parent()
	await process_frame
	await process_frame
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	button.get_viewport().push_input(motion, true)
	await process_frame
	check(button.get_viewport().get_visible_rect().has_point(point), "Pointer target lies inside the GUI fixture viewport")
	check(button.get_viewport().gui_get_hovered_control() == button, "Pointer motion reaches the intended setting button through normal GUI hit testing")
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		button.get_viewport().push_input(event, true)
		await process_frame
func check_toggle_selection(name: StringName, value: bool, note: String) -> void:
	var buttons: Array = menu.controls[name].buttons
	check(buttons[1].button_pressed == value and buttons[0].button_pressed != value, note)
func check_resolution_summary(note: String) -> void:
	var viewport := player.get_viewport()
	var dimensions := Vector2i(viewport.get_visible_rect().size)
	var ratio := viewport.scaling_3d_scale
	var rendered := Vector2i(Vector2(dimensions) * ratio)
	check(menu.controls[&"render_mode"].current.text == "3D：%d × %d（%.0f%%）" % [rendered.x, rendered.y, ratio * 100.0], note + " reports the actor viewport's actual 3D dimensions and scale")
	check(menu.controls[&"render_mode"].description.text.contains("視窗：%d × %d" % [dimensions.x, dimensions.y]), note + " explains the current window dimensions")
func run() -> void:
	# The dummy display defaults to a 64 × 64 viewport. Give the GUI fixture
	# a supported client area so real pointer events can reach visible rows.
	root.size = Vector2i(1280, 720)
	var settings := root.get_node("GameSettings")
	var previous_path: String = settings.storage_path
	var original := {}
	for name: String in ["walk_fov", "drive_fov", "sensitivity", "invert_y", "retro", "render_mode", "render_scale", "aa"]: original[name] = settings.get_setting(name)
	var isolated_path := "res://.godot/test-logs/settings-menu/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated_path.get_base_dir()))
	settings.storage_path = isolated_path
	arena = Node3D.new()
	arena.set_meta("entity_domain", true)
	root.add_child(arena)
	current_scene = arena
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	clock = WorldClock.new()
	arena.add_child(clock)
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(20, 0.05, 0)
	arena.add_child(player)
	menu = player.get_node("SettingsMenu")
	await frames(30)
	check(player.is_on_floor(), "Settings fixture lands on real collision floor")
	var checkpoint := root.get_node("Checkpoint")
	var previous_loading: bool = checkpoint.loading
	checkpoint.loading = true
	check(not menu.open_menu(), "Settings entry is refused while production checkpoint service is loading")
	checkpoint.loading = previous_loading
	key(KEY_ESCAPE, true, true)
	await process_frame
	check(not player.settings_open, "Echo Escape cannot open settings")
	key(KEY_ESCAPE, false)
	await tap(KEY_ESCAPE)
	check(player.settings_open and player.is_gameplay_input_blocked() and not paused, "Escape routes to settings without pausing the tree")
	check(menu.get_viewport().gui_get_focus_owner() != null, "Opened settings provides keyboard focus")
	var scale_control: HSlider = menu.controls[&"render_scale"].control
	check(scale_control.editable == (int(settings.get_setting("render_mode")) == 1), "Manual scale control reflects the selected rendering mode")
	check(menu.controls[&"render_scale"].panel.visible == scale_control.editable, "Automatic rendering hides the unused manual percentage row")
	check_resolution_summary("Outdoor settings")
	if not settings.supports_vsync_toggle():
		var vsync_buttons: Array = menu.controls[&"vsync"].buttons
		check(vsync_buttons[0].disabled and vsync_buttons[1].disabled and menu.controls[&"vsync"].reason.visible, "Unsupported vertical sync disables both choices and explains why")
	settings.set_setting("retro", true)
	await process_frame
	await click_button(menu.controls[&"retro"].buttons[0])
	check(not settings.get_setting("retro"), "Clicking the Off choice applies the actual retro preference")
	check_toggle_selection(&"retro", false, "Off choice is exclusive")
	await click_button(menu.controls[&"retro"].buttons[0])
	check_toggle_selection(&"retro", false, "Clicking the selected Off choice keeps a selection")
	var on_button: Button = menu.controls[&"retro"].buttons[1]
	on_button.grab_focus()
	await tap(KEY_ENTER)
	check(settings.get_setting("retro"), "Keyboard activation of On applies the actual retro preference")
	check_toggle_selection(&"retro", true, "On choice is exclusive after keyboard activation")
	await tap(KEY_ENTER)
	check_toggle_selection(&"retro", true, "Repeated keyboard activation keeps the selected On choice")
	settings.set_setting("render_mode", 0)
	check(not menu.controls[&"render_scale"].panel.visible, "Automatic mode hides manual percentage controls")
	settings.set_setting("render_mode", 1)
	check(menu.controls[&"render_scale"].panel.visible, "Manual mode exposes the editable percentage row")
	if not settings.supports_volumetric_fog():
		var fog_control: OptionButton = menu.controls[&"fog_quality"].control
		check(fog_control.is_item_disabled(1) and fog_control.is_item_disabled(2) and fog_control.is_item_disabled(3) and menu.controls[&"fog_quality"].reason.visible, "Unsupported volumetric choices are disabled with an explanation")
	# Space can intentionally activate a focused GUI button. Clear GUI focus to
	# test whether unclaimed gameplay keys leak through the input boundary.
	menu.get_viewport().gui_release_focus()
	key(KEY_ESCAPE, true, true)
	await process_frame
	check(player.settings_open, "Echo Escape cannot close settings")
	key(KEY_ESCAPE, false)
	player.add_item("Scrap", false, "res://props/scrap.tscn")
	player.add_item("Wheel", false, "res://props/wheel.tscn")
	var before_slot: int = player.inventory.active_slot
	var before_items: int = player.inventory.items.size()
	await tap(KEY_1)
	await tap(KEY_G)
	check(player.inventory.active_slot == before_slot and player.inventory.items.size() == before_items, "Menu consumes hotbar and drop events")
	var scrap: Item = load("res://props/scrap.tscn").instantiate()
	scrap.position = player.position + Vector3(0, 1.6, -1.5)
	scrap.freeze = true
	arena.add_child(scrap)
	await frames(3)
	var ray: RayCast3D = player.camera.get_node("InteractRay")
	player.camera.look_at(scrap.global_position, Vector3.UP)
	ray.force_raycast_update()
	check(ray.get_collider() == scrap, "Menu interaction fixture has a reachable real prop")
	await tap(KEY_E)
	check(player.inventory.items.size() == before_items and is_instance_valid(scrap), "Menu consumes real interaction input")
	var walk_position := player.global_position
	key(KEY_W, true)
	key(KEY_SPACE, true)
	await frames(12)
	check(player.global_position.distance_to(walk_position) < 0.05, "Menu blocks held movement and jumping")
	await tap(KEY_ESCAPE)
	check(not player.settings_open and player.is_gameplay_input_blocked(), "Closing menu latches keys still held")
	await frames(8)
	check(player.global_position.distance_to(walk_position) < 0.05, "Held W and Space cannot move immediately after close")
	key(KEY_W, false)
	key(KEY_SPACE, false)
	await frames(3)
	check(not player.is_gameplay_input_blocked(), "Releasing held keys restores gameplay")
	key(KEY_W, true)
	await frames(12)
	key(KEY_W, false)
	check(player.global_position.distance_to(walk_position) > 0.5, "A fresh real movement press works after releasing the latch")
	await frames(3)
	check(menu.open_menu(), "Public settings entry opens in normal mode")
	player.position.y = 4.0
	player.velocity = Vector3.ZERO
	player.damage_cooldown = 0.5
	var initial_time := clock.elapsed_seconds
	await frames(45)
	check(player.global_position.y < 1.5 and clock.elapsed_seconds > initial_time, "Gravity and world time continue while menu is open")
	check(player.damage_cooldown == 0.0, "Menu does not freeze damage cooldown")
	player.take_damage(10)
	check(player.current_player_health == 90.0 and player.settings_open, "Incoming nonfatal damage still applies while setting controls remain open")
	var walking_fov := 89.0 if float(original.walk_fov) == 91.0 else 91.0
	var fov_slider: Range = menu.controls[&"walk_fov"].control
	fov_slider.value = walking_fov
	check(is_equal_approx(player.camera.fov, walking_fov), "Settings slider updates the production walking camera through its signal binding")
	menu.close_menu()
	var persisted := ConfigFile.new()
	check(persisted.load(isolated_path) == OK and persisted.get_value("input", "walk_fov") == walking_fov, "Closing settings flushes the actual UI edit to isolated preferences")
	await frames(35)
	var retro_before: bool = settings.get_setting("retro")
	await tap(KEY_F8)
	check(settings.get_setting("retro") == retro_before, "F8 has no display-preference shortcut")
	await test_seat_and_carrier(settings)
	await test_interior_routing(settings)
	await test_limb_settings()
	await test_lifecycle()
	for name: String in original: settings.set_setting(name, original[name])
	settings.flush()
	settings.storage_path = previous_path
	for code: Key in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SPACE, KEY_ESCAPE, KEY_E]: key(code, false)
	arena.queue_free()
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": print("NOTE: Dummy display cannot verify native mouse capture or rendered settings layout.")
	if failures.is_empty(): print("PASS: settings event routing, release latch, live physics, damage, seat coasting and lifecycle")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func test_seat_and_carrier(settings: Node) -> void:
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	rv_shell = shell
	arena.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.position.y = 1.2
	rv.set_physics_process(false)
	await frames(3)
	var seat: Item = rv.get_node("DriverSeat")
	seat.interact_hold(player)
	check(player.seated_in == seat, "Production mounted seat accepts the test driver")
	settings.set_setting("drive_fov", 96.0)
	check(is_equal_approx(seat.seat_camera.fov, 96.0), "Driving FOV updates an existing seat camera")
	rv.set_engine_running(true)
	rv.set_gear(2)
	rv.handbrake = false
	rv.throttle_input = 0.7
	rv.brake_input = 0.5
	rv.steering = 0.2
	await tap(KEY_ESCAPE)
	check(player.settings_open and player.seated_in == seat, "Escape opens settings while seated without exiting")
	menu.get_viewport().gui_release_focus()
	for code: Key in [KEY_B, KEY_SPACE, KEY_Z, KEY_E]: await tap(code)
	check(rv.energy.engine_running and rv.gear == 2 and not rv.handbrake and player.seated_in == seat, "Menu blocks ignition, handbrake, gear and seat-exit events")
	key(KEY_W, true)
	key(KEY_S, true)
	key(KEY_A, true)
	var start_fuel: float = rv.current_fuel
	for frame in range(45):
		await physics_frame
		rv._physics_process(1.0 / Engine.physics_ticks_per_second)
	check(rv.throttle_input == 0.0 and rv.brake_input == 0.0 and absf(rv.steering) < 0.02, "Menu releases gradual throttle, foot brake and steering")
	check(rv.energy.engine_running and rv.gear == 2 and not rv.handbrake and rv.current_fuel < start_fuel, "Menu preserves drivetrain state and ongoing fuel consumption")
	key(KEY_W, false)
	key(KEY_S, false)
	key(KEY_A, false)
	# Actual VehicleBody integration proves the menu does not freeze or anchor the RV.
	rv.gravity_scale = 0.0
	rv.freeze = false
	rv.linear_velocity = Vector3(0, 0, -4)
	var start_position := rv.global_position
	await frames(30)
	var coast_distance := rv.global_position.distance_to(start_position)
	var seat_distance := player.global_position.distance_to(seat.global_position)
	# SceneTree.physics_frame resumes this coroutine before player callbacks.
	# Native VehicleBody transforms can consequently lead a seat follower by
	# one physics step; test the measured carrier-point displacement budget.
	var step_motion := ClimbMath.point_velocity(rv, seat.global_position).length() / Engine.physics_ticks_per_second
	print("SETTINGS_COAST distance=", coast_distance, " seat_error=", seat_distance, " step_motion=", step_motion, " velocity=", rv.linear_velocity)
	check(coast_distance > 1.0, "Vehicle coasts physically while settings are open")
	check(seat_distance <= step_motion + 0.01, "Seated actor follows the moving vehicle within one physics step while settings are open")
	rv.freeze = true
	rv.linear_velocity = Vector3.ZERO
	menu.close_menu()
	seat.exit_seat(true)
	await frames(3)
	# Real roof collision/support is retained through translation and turning.
	rv.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
	player.global_position = rv.to_global(Vector3(0, 2.5, 0))
	player.velocity = Vector3.ZERO
	await frames(20)
	check(menu.open_menu(), "Roof actor can open settings")
	var roof_anchor := rv.to_local(player.global_position)
	for frame in range(60):
		rv.position.z -= 4.0 / Engine.physics_ticks_per_second
		rv.rotate_y(0.15 / Engine.physics_ticks_per_second)
		await physics_frame
	check(rv.to_local(player.global_position).distance_to(roof_anchor) < 0.2, "Settings-open actor stays on a colliding RV roof through driving and turning")
	menu.close_menu()
	player.global_position = Vector3(20, 0.05, 0)
	player.velocity = Vector3.ZERO
	await frames(3)

func test_limb_settings() -> void:
	var intact := {"items": player.inventory.items.duplicate(true), "slot": player.inventory.active_slot, "health": player.current_player_health, "transform": player.global_transform, "body": player.body_state.capture()}
	var seat: Item = rv_shell.get_node("Chassis/DriverSeat")
	seat.interact_hold(player)
	check(player.seated_in == seat and menu.open_menu(), "Intact driver opens settings before injury")
	player.sever_part(&"left_arm", {})
	await frames(3)
	check(player.seated_in == seat and player.settings_open, "Losing one arm preserves the capable driver's seat and open settings")
	player.sever_part(&"right_arm", {})
	await frames(3)
	check(player.seated_in == null and seat.current_driver == null and not player.settings_open, "Losing the final arm forces seat release and closes settings")
	seat.interact_hold(player)
	check(player.seated_in == null, "Closing settings does not restore an armless actor's driving capability")
	player.restore_checkpoint_state(intact)
	player.sever_part(&"left_leg", {})
	await frames(35)
	check(player.is_crawling() and player.is_on_floor() and menu.open_menu(), "Crawling actor retains settings access")
	var crawl_origin := player.global_position
	var crawl_stamina: float = player.current_stamina
	for action: StringName in [&"move_forward", &"jump", &"sprint"]: Input.action_press(action)
	await frames(12)
	check(player.global_position.distance_to(crawl_origin) < 0.05 and player.velocity.y <= 0.01, "Settings block crawling movement and jumping")
	menu.close_menu()
	await frames(12)
	check(player.is_gameplay_input_blocked() and player.global_position.distance_to(crawl_origin) < 0.05, "Crawling remains blocked until held menu controls are released")
	for action: StringName in [&"move_forward", &"jump", &"sprint"]: Input.action_release(action)
	await frames(3)
	check(not player.is_gameplay_input_blocked(), "Releasing controls restores crawling input")
	for action: StringName in [&"move_forward", &"jump", &"sprint"]: Input.action_press(action)
	await frames(20)
	var crawl_speed := Vector2(player.velocity.x, player.velocity.z).length()
	check(player.global_position.distance_to(crawl_origin) > 0.1 and crawl_speed < player.SPEED and player.velocity.y <= 0.01, "Fresh input resumes crawling without restoring sprint or jump")
	check(player.current_stamina >= crawl_stamina, "Crawling with sprint held does not consume sprint stamina after closing settings")
	for action: StringName in [&"move_forward", &"jump", &"sprint"]: Input.action_release(action)
	player.restore_checkpoint_state(intact)
	await frames(3)

func test_lifecycle() -> void:
	var tablet: Item = rv_shell.get_node("Chassis/TabletScreen")
	tablet.interact_hold(player)
	check(player.in_ui_mode and tablet.current_user == player, "Production mounted tablet owns player input")
	check(not menu.open_menu(), "Tablet ownership refuses settings entry")
	await tap(KEY_ESCAPE)
	check(not player.in_ui_mode and not player.settings_open, "Tablet Escape closes tablet without opening settings")
	var equipment: Item = rv_shell.get_node("Chassis/Generator")
	var equipment_id := equipment.persistent_id
	check(equipment.pickup(player).begins_with("已拾取"), "Production equipment enters inventory before placement")
	check(player.enter_equipment_placement(), "Production Item begins inventory-backed placement preview")
	await tap(KEY_ESCAPE)
	check(not player.is_placing_equipment() and not player.settings_open, "Placement Escape cancels preview without opening settings")
	check(player.inventory.active_item().state.id == equipment_id, "Escape cancellation keeps held Item ownership")
	await tap(KEY_ESCAPE)
	check(player.settings_open, "Next Escape opens settings after tablet is closed")
	var monster: Raker = load("res://enemies/raker.tscn").instantiate()
	arena.add_child(monster)
	monster.set_physics_process(false)
	monster.position = player.position + Vector3(0, 0, 1)
	player.grab_control.immunity = 0.0
	check(player.begin_grab(monster, 6), "Production grab acquires a settings-open player")
	check(not player.settings_open and not menu.open_menu(), "Grab closes settings and prevents reopening")
	player.grab_control.end("test")
	monster.queue_free()
	await frames(3)
	check(menu.open_menu(), "Settings can open after grab release")
	player.damage_cooldown = 0.0
	player.take_damage(1000)
	check(player.is_player_dead and not player.settings_open and not menu.open_menu(), "Death closes settings and refuses reopening during ragdoll")

func test_interior_routing(settings: Node) -> void:
	var manager := PoiInstanceManager.new()
	manager.name = "PoiInstances"
	manager.interior_factory = func(): return SmallInterior.new()
	arena.add_child(manager)
	var building := Node3D.new()
	var return_point := Marker3D.new()
	return_point.name = "ReturnPoint"
	return_point.position = Vector3(20, 0.05, 3)
	building.add_child(return_point)
	arena.add_child(building)
	settings.set_setting("render_mode", 1)
	settings.set_setting("render_scale", 0.75)
	settings.set_setting("aa", 1)
	check(menu.open_menu(), "Settings open before entering a POI")
	await manager.enter(player, building, "settings-small-interior", 42)
	check(not player.settings_open and player.get_parent() == manager.interior, "Production POI transition closes settings and reparents the actor")
	check(manager.viewport.own_world_3d and is_equal_approx(manager.viewport.scaling_3d_scale, 0.75) and manager.viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "New production interior viewport receives manual scale and FXAA")
	await frames(15)
	await tap(KEY_ESCAPE)
	check(player.settings_open and menu.visible, "Root Escape is forwarded to the interior player's settings")
	check_resolution_summary("Interior settings")
	check(manager._layer.layer == 60 and not manager._status.visible, "Interior settings composite moves above root overlays and hides the exterior status title")
	await tap(KEY_M)
	check(not manager.interior._map.visible, "Production interior M input cannot open the explored map while settings owns input")
	key(KEY_W, true)
	var origin := player.global_position
	await frames(10)
	check(player.global_position.distance_to(origin) < 0.05, "Forwarded held input remains blocked in the interior World3D")
	key(KEY_W, false)
	await tap(KEY_ESCAPE)
	check(not player.settings_open and not menu.visible, "Interior Escape closes settings through production viewport forwarding")
	check(manager._layer.layer == 20 and manager._status.visible, "Closing interior settings restores the gameplay composite layer and exterior status title")
	await tap(KEY_M)
	check(manager.interior._map.visible, "Production interior M input opens the actual map after settings closes")
	await tap(KEY_M)
	check(not manager.interior._map.visible, "Production interior M input closes the actual map again")
	await manager.leave()
	check(player.get_parent() == arena and manager.active_id.is_empty() and not player.settings_open, "Returning outdoors preserves closed settings ownership")
	manager.queue_free()
	building.queue_free()
	await frames(3)

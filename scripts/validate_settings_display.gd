extends SceneTree
## Bounded native GPU evidence; deliberately outside the headless test catalog.
## Run: godot --path . --log-file .godot/test-logs/settings-display/native.log --script res://scripts/validate_settings_display.gd
## Interactive interior: append -- --manual-interior (Esc opens settings; use its Quit button to exit).
const DIRECTORY := "res://.godot/test-logs/settings-display"
const PREFERENCES := DIRECTORY + "/preferences.cfg"
const SWATCH_POINT := Vector2i(60, 130)
var failures: Array[String] = []
var evidence := {}
var settings: Node
var world: Node3D
var player: CharacterBody3D
var menu: CanvasLayer
var original_values := {}
var original_path := ""
var original_mode := DisplayServer.WINDOW_MODE_WINDOWED
var original_size := Vector2i.ZERO
var original_position := Vector2i.ZERO
var original_mouse := Input.MOUSE_MODE_VISIBLE
var finishing := false
var manual_interior := false

class ManualInterior extends PoiInterior:
	var scene_builder: Callable
	func build(_seed: int, _saved: Dictionary = {}) -> bool:
		var floor_body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = WorldBoundaryShape3D.new()
		floor_body.add_child(collision)
		add_child(floor_body)
		scene_builder.call(self)
		exit_door = PoiEntrance.new()
		exit_door.position = Vector3(3, 1, -3)
		var door_shape := CollisionShape3D.new()
		var door_box := BoxShape3D.new()
		door_box.size = Vector3(1.2, 2.0, 0.2)
		door_shape.shape = door_box
		exit_door.add_child(door_shape)
		var marker := Label3D.new()
		marker.text = "EXIT — E"
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		exit_door.add_child(marker)
		add_child(exit_door)
		return true
	func spawn_transform() -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0))

func _init() -> void:
	run.call_deferred()

func check(value: bool, note: String) -> void:
	if not value: failures.append(note)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native settings display validation rejects headless; a real display/GPU is required.")
		quit(1)
		return
	manual_interior = "--manual-interior" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.wait_time = 180.0 if manual_interior else 60.0
	watchdog.ignore_time_scale = true
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(watchdog)
	watchdog.timeout.connect(func():
		if manual_interior:
			evidence.manual_end = "180-second fixture lifetime reached"
		else:
			check(false, "Native validation exceeded its 60-second deadline")
		finish())
	watchdog.start()
	settings = root.get_node("GameSettings")
	original_path = settings.storage_path
	original_values = settings.values.duplicate(true)
	original_mode = DisplayServer.window_get_mode()
	original_size = DisplayServer.window_get_size()
	original_position = DisplayServer.window_get_position()
	original_mouse = Input.mouse_mode
	settings.storage_path = PREFERENCES
	var initial := {"window_mode": 0, "render_mode": 1, "render_scale": 1.0, "retro": false, "brightness": 1.0, "contrast": 1.0, "saturation": 1.0, "aa": 0, "fog_quality": 0, "walk_fov": 75.0, "max_fps": 60}
	for key: String in initial:
		settings.set_setting(key, initial[key], false)
	evidence.renderer = RenderingServer.get_current_rendering_method()
	evidence.display = DisplayServer.get_name()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	build_fixture()
	if manual_interior:
		await stage_manual_interior()
		return
	await check_layout(Vector2i(1280, 720), "menu-1280x720.png")
	await check_layout(Vector2i(1024, 600), "menu-1024x600.png")
	await check_actor_viewport_summary()
	menu.close_menu()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await rendered_frames(3)
	await check_pixels()
	await check_window_preview()
	var master := AudioServer.get_bus_index("Master")
	settings.set_setting("master_volume", 0.0)
	check(AudioServer.is_bus_mute(master), "Native Master bus mute is applied")
	settings.set_setting("master_volume", 0.5)
	check(not AudioServer.is_bus_mute(master) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(master)), 0.5), "Native Master bus gain is applied")
	evidence.audio_note = "Bus state checked; no claim of audible playback."
	await finish()

func stage_manual_interior() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	world.add_child(floor_body)
	var manager := PoiInstanceManager.new()
	manager.name = "PoiInstances"
	manager.interior_factory = func():
		var room := ManualInterior.new()
		room.scene_builder = add_scene
		return room
	world.add_child(manager)
	# The production facade tracks indoor/outdoor state; the manager itself
	# registers its new viewport and forwards native input into that viewport.
	world.add_child(OutdoorPresentation.new())
	var building := Node3D.new()
	building.set_meta("poi_title", "SETTINGS INPUT VALIDATION")
	var return_point := Marker3D.new()
	return_point.name = "ReturnPoint"
	return_point.position = Vector3(0, 0.05, 2)
	building.add_child(return_point)
	world.add_child(building)
	await manager.enter(player, building, "manual-settings-interior", 42)
	check(manager.state == PoiInstanceManager.State.INDOOR and player.get_viewport() == manager.viewport and manager.viewport.own_world_3d, "Interactive fixture stages the production player in a production-managed interior viewport")
	if not failures.is_empty():
		await finish()
		return
	player.set_physics_process(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await capture(root, "manual-interior-ready.png")
	evidence.manual_note = "Production POI input forwarding; isolated preferences; awaiting human Esc, popup and mapping checks."
	var file := FileAccess.open(DIRECTORY + "/manual-interior-evidence.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t"))
	print("MANUAL_INTERIOR_READY: own World3D/SubViewport, 1280x720, captured mouse, Esc settings, E exit, settings Quit; 180-second bounded lifetime")

func build_fixture() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	add_scene(world)
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.camera.current = true
	menu = player.get_node("SettingsMenu")
	var hud := CanvasLayer.new()
	hud.layer = 80
	hud.visible = not manual_interior
	world.add_child(hud)
	var swatch := ColorRect.new()
	swatch.position = Vector2(20, 100)
	swatch.size = Vector2(120, 70)
	swatch.color = Color("36cc9a")
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(swatch)
	var label := Label.new()
	label.position = Vector2(20, 180)
	label.text = "Native UI swatch: unchanged by 3D color settings"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(label)

func add_scene(parent: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("385062")
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	parent.add_child(environment)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(3, 3, 0.5)
	mesh.mesh = cube
	mesh.position = Vector3(0, 1.78, -4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("b2492b")
	mesh.material_override = material
	parent.add_child(mesh)

func rendered_frames(count: int) -> void:
	for frame in count:
		await process_frame
		await RenderingServer.frame_post_draw

func capture(viewport: Viewport, name: String) -> Image:
	await rendered_frames(2)
	var result := viewport.get_texture().get_image()
	check(result != null and not result.is_empty(), "GPU viewport returns image: " + name)
	if result == null or result.is_empty(): return null
	check(result.save_png(DIRECTORY + "/" + name) == OK, "Screenshot evidence saves: " + name)
	return result

func check_layout(dimensions: Vector2i, filename: String) -> void:
	DisplayServer.window_set_size(dimensions)
	await rendered_frames(3)
	check(Vector2i(root.get_visible_rect().size) == dimensions, "Native client viewport reaches requested size %s" % dimensions)
	check(menu.open_menu(), "Settings opens for native layout at %s" % dimensions)
	await rendered_frames(3)
	check_resolution_summary("Native layout at %s" % dimensions)
	var panel: Control = menu.get("_panel")
	var bounds := panel.get_global_rect()
	var viewport_bounds := root.get_visible_rect()
	check(viewport_bounds.grow(1.0).encloses(bounds), "Settings panel fits native viewport at %s" % dimensions)
	var focus := root.gui_get_focus_owner()
	check(focus != null and focus.is_visible_in_tree(), "Native settings receives visible keyboard focus")
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.physical_keycode = KEY_TAB
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.keycode = KEY_TAB
	release.physical_keycode = KEY_TAB
	release.pressed = false
	Input.parse_input_event(release)
	await rendered_frames(2)
	check(root.gui_get_focus_owner() != null and root.gui_get_focus_owner() != focus, "Native GUI Tab advances keyboard focus")
	for entry: Dictionary in menu.controls.values():
		var control: Control = entry.control
		if not control.is_visible_in_tree(): continue
		var control_bounds := control.get_global_rect()
		var clip_bounds := inherited_clip_rect(control)
		var visible_bounds := control_bounds.intersection(clip_bounds)
		# Scroll pages intentionally contain rows beyond their vertical view.
		# Check their actually drawn intersection and the full horizontal row
		# width, since this menu disables horizontal scrolling.
		if visible_bounds.has_area(): check(viewport_bounds.grow(1.0).encloses(visible_bounds), "Clipped setting control fits native viewport: " + str(control.name))
		check(control_bounds.position.x >= clip_bounds.position.x - 1.0 and control_bounds.end.x <= clip_bounds.end.x + 1.0, "Setting control fits the horizontal scroll/tab layout: " + str(control.name))
	evidence[filename] = {"client_size": str(viewport_bounds.size), "panel_bounds": str(bounds)}
	await capture(root, filename)
	menu.close_menu()

func check_resolution_summary(note: String) -> void:
	var viewport := player.get_viewport()
	var dimensions := Vector2i(viewport.get_visible_rect().size)
	var ratio := viewport.scaling_3d_scale
	var rendered := Vector2i(Vector2(dimensions) * ratio)
	check(menu.get("_resolution_label").text == "3D：%d × %d（%.0f%%）" % [rendered.x, rendered.y, ratio * 100.0], note + " displays applied 3D size and percentage")
	check(menu.controls[&"render_mode"].description.text.contains("視窗：%d × %d" % [dimensions.x, dimensions.y]), note + " explains native window size")

func check_actor_viewport_summary() -> void:
	var original_player_transform := player.global_transform
	var original_camera_transform: Transform3D = player.camera.global_transform
	DisplayServer.window_set_size(Vector2i(1280, 720))
	settings.set_setting("render_mode", 1)
	settings.set_setting("render_scale", 0.75)
	check(menu.open_menu(), "Native manual resolution summary opens")
	await rendered_frames(3)
	check_resolution_summary("Native manual 75% rendering")
	check(menu.controls[&"render_scale"].panel.visible, "Manual rendering exposes percentage controls")
	# Resize while visible: the row must follow the viewport, without another
	# preference edit or reopening the menu to trigger a refresh.
	DisplayServer.window_set_size(Vector2i(1024, 600))
	await rendered_frames(3)
	check_resolution_summary("Visible menu after native resize")
	menu.close_menu()
	var manager := PoiInstanceManager.new()
	manager.name = "PoiInstances"
	manager.interior_factory = func():
		var room := ManualInterior.new()
		room.scene_builder = add_scene
		return room
	world.add_child(manager)
	world.add_child(OutdoorPresentation.new())
	var building := Node3D.new()
	var return_point := Marker3D.new()
	return_point.name = "ReturnPoint"
	building.add_child(return_point)
	world.add_child(building)
	await manager.enter(player, building, "resolution-summary-interior", 42)
	check(player.get_viewport() == manager.viewport, "Native summary fixture moves the actor into the production-managed viewport")
	settings.set_setting("render_mode", 0)
	check(menu.open_menu(), "Native interior automatic resolution summary opens")
	await rendered_frames(3)
	check_resolution_summary("Native indoor automatic rendering")
	check(is_equal_approx(manager.viewport.scaling_3d_scale, 1.0) and not menu.controls[&"render_scale"].panel.visible, "Indoor automatic mode renders at full resolution and hides manual percentage controls")
	settings.set_setting("render_mode", 1)
	settings.set_setting("render_scale", 0.5)
	await rendered_frames(3)
	check_resolution_summary("Native indoor manual 50% rendering")
	check(is_equal_approx(manager.viewport.scaling_3d_scale, 0.5) and menu.controls[&"render_scale"].panel.visible, "Manual indoor rendering updates the applied ratio and exposes its controls")
	menu.close_menu()
	await manager.leave()
	player.set_physics_process(false)
	player.global_transform = original_player_transform
	player.camera.global_transform = original_camera_transform
	player.camera.current = true
	manager.queue_free()
	building.queue_free()
	settings.set_setting("render_mode", 1)
	settings.set_setting("render_scale", 1.0)
	await rendered_frames(3)

func inherited_clip_rect(control: Control) -> Rect2:
	var clipping := root.get_visible_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor.clip_contents or ancestor is ScrollContainer or ancestor is TabContainer):
			clipping = clipping.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return clipping

func color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

func effect_count(viewport: Viewport) -> int:
	var count := 0
	for child in viewport.get_children():
		if child is CanvasLayer and child.name == "VideoEffects":
			for effect in child.get_children():
				if effect is ColorRect and effect.material is ShaderMaterial: count += 1
	return count

func check_pixels() -> void:
	var baseline := await capture(root, "outdoor-baseline.png")
	if baseline == null: return
	# The production interaction crosshair is Canvas UI at the exact center.
	# Sample the flat cube nearby so this measures the 3D pass, not that HUD.
	var center := baseline.get_size() / 2 + Vector2i(40, 40)
	var base_scene := baseline.get_pixelv(center)
	var base_ui := baseline.get_pixelv(SWATCH_POINT)
	check(base_scene.r > base_scene.g + 0.12 and base_scene.r > base_scene.b + 0.12, "Center GPU sample reaches the red fixture cube rather than the player model or background")
	check(settings.set_setting("brightness", 0.75), "GPU validation brightness is an accepted preference value")
	settings.set_setting("contrast", 1.0)
	settings.set_setting("saturation", 0.0)
	var graded := await capture(root, "outdoor-graded.png")
	if graded == null: return
	var graded_scene := graded.get_pixelv(center)
	check(color_distance(base_scene, graded_scene) > 0.08, "Actual GPU color shader changes the 3D scene pixel")
	check(color_distance(base_ui, graded.get_pixelv(SWATCH_POINT)) < 0.01, "Native Canvas HUD/UI swatch keeps its original color")
	settings.register_viewport(root)
	settings.register_viewport(root)
	check(effect_count(root) == 1, "Root viewport has exactly one color postprocess after repeated registration")
	var indoor := SubViewport.new()
	indoor.size = Vector2i(root.get_visible_rect().size)
	indoor.own_world_3d = true
	indoor.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.add_child(indoor)
	settings.register_viewport(indoor, true)
	settings.register_viewport(indoor, true)
	check(effect_count(indoor) == 1, "Indoor viewport has exactly one color postprocess after repeated registration")
	var interior_world := Node3D.new()
	indoor.add_child(interior_world)
	add_scene(interior_world)
	var camera := Camera3D.new()
	interior_world.add_child(camera)
	camera.global_transform = player.camera.global_transform
	camera.fov = player.camera.fov
	camera.current = true
	var indoor_image := await capture(indoor, "indoor-graded.png")
	if indoor_image == null:
		indoor.queue_free()
		return
	var display := CanvasLayer.new()
	display.layer = 20
	world.add_child(display)
	var texture := TextureRect.new()
	texture.texture = indoor.get_texture()
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_SCALE
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.add_child(texture)
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var composite := await capture(root, "indoor-composited-on-root.png")
	if composite != null:
		var indoor_scene := indoor_image.get_pixelv(center)
		var composite_scene := composite.get_pixelv(center)
		check(color_distance(indoor_scene, composite_scene) < 0.02, "Already graded indoor scene is composited onto the root without a second color pass")
		check(color_distance(base_ui, composite.get_pixelv(SWATCH_POINT)) < 0.01, "Root HUD/UI swatch remains unchanged above the indoor composite")
		evidence.pixel_samples = {"outdoor_baseline": str(base_scene), "outdoor_graded": str(graded_scene), "indoor_graded": str(indoor_scene), "composited": str(composite_scene), "ui": str(base_ui)}
	display.queue_free()
	indoor.queue_free()
	await rendered_frames(2)

func check_window_preview() -> void:
	check(is_equal_approx(settings.window_preview_seconds, 15.0), "Production native confirmation deadline defaults to 15 seconds")
	settings.set_setting("window_mode", 0, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var available := DisplayServer.screen_get_usable_rect()
	var size := DisplayServer.window_get_size()
	var safe_position := available.position + Vector2i(16, 24)
	safe_position = Vector2i(Vector2(safe_position).clamp(Vector2(available.position), Vector2(available.end - size)))
	DisplayServer.window_set_position(safe_position)
	await rendered_frames(3)
	var saved_size := DisplayServer.window_get_size()
	var saved_position := DisplayServer.window_get_position()
	check(settings.begin_window_preview(1), "Native fullscreen preview begins")
	var first_countdown: float = settings.preview_remaining()
	check(first_countdown > 14.5 and first_countdown <= 15.0, "Native production countdown starts at 15 seconds")
	await rendered_frames(3)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN and settings.preview_remaining() > 0.0 and settings.preview_remaining() < first_countdown, "Native fullscreen preview applies and its actual countdown advances")
	settings.cancel_window_preview()
	await rendered_frames(3)
	check_window_restored(saved_size, saved_position, "explicit cancel")
	settings.window_preview_seconds = 0.4
	check(settings.begin_window_preview(1), "Short native preview begins for bounded expiry validation")
	var deadline := Time.get_ticks_msec() + 2000
	while settings.preview_remaining() > 0.0 and Time.get_ticks_msec() < deadline: await process_frame
	await rendered_frames(3)
	check_window_restored(saved_size, saved_position, "automatic deadline")
	settings.window_preview_seconds = 15.0
	check(settings.begin_window_preview(1), "Native preview begins for isolated confirmation")
	settings.confirm_window_preview()
	await rendered_frames(3)
	var persisted := ConfigFile.new()
	check(persisted.load(PREFERENCES) == OK and persisted.get_value("display", "window_mode") == 1, "Native mode confirmation persists only to isolated preferences")
	check(settings.begin_window_preview(0), "Native windowed preview begins after confirmed fullscreen")
	settings.confirm_window_preview()
	await rendered_frames(3)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Confirmed native windowed mode returns the validation window")
	evidence.window_note = "15-second production default/countdown checked; actual automatic expiry used a bounded 0.4-second deadline."

func check_window_restored(size: Vector2i, position: Vector2i, reason: String) -> void:
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and settings.get_setting("window_mode") == 0, "Native preview restores mode after " + reason)
	check(DisplayServer.window_get_size() == size and DisplayServer.window_get_position() == position, "Native preview restores size and position after " + reason)

func finish() -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(settings):
		settings.cancel_window_preview()
		settings.window_preview_seconds = 15.0
		if is_instance_valid(menu): menu.close_menu()
		settings.flush()
		if is_instance_valid(world): world.queue_free()
		await process_frame
		for key: String in original_values: settings.set_setting(key, original_values[key], false)
		settings.storage_path = original_path
		DisplayServer.window_set_mode(original_mode)
		if original_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(original_size)
			DisplayServer.window_set_position(original_position)
		Input.mouse_mode = original_mouse
	evidence.failures = failures
	evidence.native_manual_note = "Automated Godot rendering/API evidence; no OS desktop interaction, hearing or manual play claim."
	var evidence_name := "manual-interior-evidence.json" if manual_interior else "evidence.json"
	var file := FileAccess.open(DIRECTORY + "/" + evidence_name, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t"))
	if failures.is_empty() and manual_interior: print("MANUAL INTERIOR fixture closed; automated display checks were not run in this mode.")
	elif failures.is_empty(): print("PASS: native settings layout, GPU color/UI separation, single viewport passes, window preview and Master bus state")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

extends Node3D
## Outdoor authoring fixture: one World3D, no instance manager or teleport doors.
var player: CharacterBody3D
var observer: Camera3D
var status: Label
var replay := false
var route_index := 0
var route_frames := 0
var navigation: NavigationRegion3D
var ready_for_play := false
var graybox_pumps := false
var route := PackedVector3Array([
	Vector3(0, 0, -8), Vector3(0, 0, -18), Vector3(12, 0, -18),
	Vector3(12, 0, 0), Vector3(6.5, 0, 0), Vector3(6.5, 0, -10.5),
	Vector3(0, 0, -10.5), Vector3(0, 0, 19)])

func _ready() -> void:
	process_physics_priority = -10
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("ApocalypseRV - Northline Gas Station")
		DisplayServer.window_set_size(Vector2i(1280, 800))
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("879592")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b8c6bf")
	settings.ambient_light_energy = 0.6
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.fog_enabled = true
	settings.fog_light_color = Color("879592")
	settings.fog_density = 0.0015
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -32, 0)
	sun.light_color = Color("ffe4bc")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	navigation = NavigationRegion3D.new()
	navigation.name = "SiteNavigation"
	add_child(navigation)
	$Station.reparent(navigation)
	_box("Terrain", Vector3(100, 0.4, 100), Vector3(0, -0.23, 0), Color("495348"), true)
	# Keep yard surfaces outside the building slab; no hidden overlapping floor.
	_box("Forecourt", Vector3(37, 0.06, 29.5), Vector3(0, -0.01, 11.75), Color("4e5350"), true)
	_box("RearApron", Vector3(37, 0.06, 8), Vector3(0, -0.01, -21), Color("4e5350"), true)
	for x in [-14.75, 14.75]:
		_box("SideApron", Vector3(7.5, 0.06, 14), Vector3(x, -0.01, -10), Color("4e5350"), true)
	_box("Highway", Vector3(9, 0.05, 100), Vector3(-24, 0, 0), Color("303937"), true)
	for z in range(-45, 50, 8):
		_box("RoadMark", Vector3(0.13, 0.01, 4), Vector3(-24, 0.035, z), Color("b8af8b"))
	for x in [12.5, 16.5]:
		_box("ParkingLine", Vector3(0.09, 0.015, 7), Vector3(x, 0.035, 13), Color("b8af8b"))
	for z in [-24, -20, -16, -12, -8, -4, 0, 4, 8, 12, 16, 20]:
		_box("BoundaryPost", Vector3(0.15, 1.1, 0.15), Vector3(20, 0.55, z), Color("63645a"), true)
	_box("BoundaryRail", Vector3(0.12, 0.15, 46), Vector3(20, 0.85, -2), Color("63645a"), true)
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	navigation.navigation_mesh = mesh
	navigation.bake_navigation_mesh(true)
	while NavigationServer3D.is_baking_navigation_mesh(mesh):
		await get_tree().process_frame
	await get_tree().physics_frame
	var entities := WorldEntities.get_container(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = 190926
	for point in navigation.get_node("Station").find_children("*", "Marker3D", true, false):
		if not point is PoiLootPoint: continue
		var scene: PackedScene = point.roll_scene(rng)
		if scene == null: continue
		var item: Prop = scene.instantiate()
		entities.add_child(item)
		item.global_transform = point.global_transform
	var rv: Node3D = preload("res://rv/new_rv.tscn").instantiate()
	rv.position = Vector3(-15, 0.5, 20)
	add_child(rv)
	player = preload("res://player/player.tscn").instantiate()
	player.position = Vector3(0, 0.1, 21)
	add_child(player)
	player.get_node("Camera3D").make_current()
	observer = Camera3D.new()
	observer.far = 250
	add_child(observer)
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(18, 100)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(status)
	status.text = "NORTHLINE / Walk-in gas station\nWASD + mouse / E loot / G drop\nF1 walk / F2 exterior / F3 shop / F4 workshop / F5 walking replay\nPumps offline. Shop, service bay and rear exit are open."
	status.text += "\nF6 pump close-up / F7 graybox-model comparison"
	ready_for_play = true
	if DisplayServer.get_name() != "headless":
		get_window().set_deferred("title", "ApocalypseRV - Northline Gas Station")
		get_window().set_deferred("size", Vector2i(1280, 800))
	print("GAS_STATION_READY")
	if "--replay" in OS.get_cmdline_user_args(): start_replay()

func _box(label: String, size: Vector3, at: Vector3, color: Color, solid := false) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	visual.material_override = material
	body.add_child(visual)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
	navigation.add_child(body)

func _unhandled_key_input(event: InputEvent) -> void:
	if not ready_for_play or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F1: _walk_view()
		KEY_F2: _view(Vector3(29, 19, 35), Vector3(0, 1, -1))
		KEY_F3: _view(Vector3(0, 2.7, -5), Vector3(-5, 1.2, -12))
		KEY_F4: _view(Vector3(8, 2.5, -5), Vector3(5, 1, -13))
		KEY_F5: start_replay()
		KEY_F6: _view(Vector3(8.5, 2.1, 12.1), Vector3(6, 1.4, 9))
		KEY_F7: toggle_pump_visuals()
		KEY_F8: _capture()

func toggle_pump_visuals() -> void:
	graybox_pumps = not graybox_pumps
	for pump in navigation.get_node("Station/Furnishings").get_children():
		if not pump.scene_file_path.ends_with("/fuel_pump.tscn"): continue
		if not pump.has_node("GrayboxPreview"):
			var source: Node3D = preload("res://world/poi_kit/furniture/fuel_pump_graybox.tscn").instantiate()
			var visuals: Node3D = source.get_node("Visuals")
			for visual_node in [visuals] + visuals.find_children("*", "", true, false):
				visual_node.owner = null
			source.remove_child(visuals)
			visuals.name = "GrayboxPreview"
			pump.add_child(visuals)
			source.free()
		pump.get_node("Visuals").visible = not graybox_pumps
		pump.get_node("GrayboxPreview").visible = graybox_pumps
	status.text = "PUMP / %s\nF6 close-up / F7 compare / F1 walk / F5 replay" % ("GRAYBOX" if graybox_pumps else "IMPORTED GLB")

func _capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/gas-station-preview.png")

func _walk_view() -> void:
	player.set_physics_process(true)
	player.get_node("Camera3D").make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _view(at: Vector3, target: Vector3) -> void:
	replay = false
	Input.action_release("move_forward")
	player.set_physics_process(false)
	observer.position = at
	observer.look_at(target)
	observer.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func start_replay() -> void:
	_walk_view()
	player.position = Vector3(0, 0.1, 21)
	player.velocity = Vector3.ZERO
	player.get_node("Camera3D").rotation = Vector3.ZERO
	route_index = 0
	route_frames = 0
	replay = true

func _physics_process(_delta: float) -> void:
	if not replay: return
	route_frames += 1
	if route_frames > 3600:
		Input.action_release("move_forward")
		replay = false
		status.text = "FAIL: Walking route blocked at %s" % player.position
		push_error(status.text)
		return
	var direction: Vector3 = route[route_index] - player.position
	direction.y = 0
	if direction.length() < 0.3:
		route_index += 1
		if route_index == route.size():
			replay = false
			Input.action_release("move_forward")
			status.text = "PASS: Shop > rear exit > yard > workshop > shop > forecourt\nF1 walk / F2 exterior / F3 shop / F4 workshop / F5 replay"
			print("PASS: gas station continuous walking route")
			return
		return
	player.rotation.y = atan2(-direction.x, -direction.z)
	Input.action_press("move_forward")

func _exit_tree() -> void:
	Input.action_release("move_forward")

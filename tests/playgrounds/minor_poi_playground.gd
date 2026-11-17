extends Node3D
## Authoring gallery with real player, RV, navigation and production actor activation.
class SiteHost extends Node3D:
	var outdoor_sites: Dictionary = {}
	var field := WorldField.new(42)
var host: SiteHost
var player: CharacterBody3D
var camera: Camera3D
var navigation: NavigationRegion3D
var site_node: Node3D
var selected := 0
var seed_value := 42
var busy := true
var ready_for_play := false
var status: Label
var auto_capture := false

func _ready() -> void:
	get_window().title = "ApocalypseRV - Roadside POI Gallery"
	get_window().size = Vector2i(1280, 800)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("71837d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b8c6bf")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_color = Color("ffe4bc")
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	navigation = NavigationRegion3D.new()
	add_child(navigation)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.position.y = -0.2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.4, 100)
	shape.shape = box
	ground.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	visual.mesh = mesh
	visual.material_override = IndustrialArt.material("concrete", Color("50594a"))
	ground.add_child(visual)
	navigation.add_child(ground)
	var entities := Node3D.new()
	entities.name = "WorldEntities"
	add_child(entities)
	host = SiteHost.new()
	add_child(host)
	var rv: Node3D = preload("res://rv/new_rv.tscn").instantiate()
	rv.position = Vector3(0, 0.3, 18)
	rv.rotation.y = PI / 2
	add_child(rv)
	player = preload("res://player/player.tscn").instantiate()
	add_child(player)
	camera = Camera3D.new()
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(20, 110)
	status.add_theme_font_size_override("font_size", 20)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(status)
	await show_site()
	ready_for_play = true
	if "--capture-all" in OS.get_cmdline_user_args():
		auto_capture = true
		for index in range(18):
			selected = index
			await show_site()
			await capture()
		print("GALLERY_CAPTURED_18")
		auto_capture = false
		if "--quit-after-capture" in OS.get_cmdline_user_args(): get_tree().quit()

func show_site() -> void:
	busy = true
	player.set_physics_process(false)
	if is_instance_valid(site_node): site_node.free()
	for actor in WorldEntities.get_container(self).get_children(): actor.free()
	host.outdoor_sites.clear()
	host.field = WorldField.new(seed_value)
	var definition := POIConfig.definition(StringName(MinorSites.definition_ids()[selected]))
	var site := {"index": selected, "id": "gallery", "definition_id": str(definition.definition_id), "minor": true,
		"seed": host.field.seed_for(selected, "minor_art"), "building": Transform3D.IDENTITY}
	site_node = POISpawner.new().spawn_site(site, navigation)
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_radius = 0.5
	nav.agent_height = 2
	nav.cell_size = 0.25
	navigation.navigation_mesh = nav
	navigation.bake_navigation_mesh(true)
	while NavigationServer3D.is_baking_navigation_mesh(nav): await get_tree().process_frame
	for i in range(3): await get_tree().physics_frame
	WalkInSites.activate(host, site, navigation)
	# Gallery freezes encounters for inspection; production uses normal AI.
	for actor in WorldEntities.get_container(self).get_children():
		if actor is Monster: actor.set_physics_process(false)
	player.position = Vector3(0, 0.2, 8)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.set_physics_process(true)
	overview()
	status.text = "%02d / 18   %s   seed %d\nLeft/Right: layout   N: seed   F1: walk   F2: overview   F7: capture\nWASD / E pickup / G drop. Gallery enemies frozen; production AI active." % [selected + 1, definition.definition_id, seed_value]
	print("MINOR_GALLERY_READY ", definition.definition_id)
	busy = false

func overview() -> void:
	camera.fov = 50
	camera.position = Vector3(15, 10, 12)
	camera.look_at(Vector3(0, 0.8, -3))
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func capture() -> void:
	for i in range(10): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/minor-captures")
	get_viewport().get_texture().get_image().save_png("res://.godot/minor-captures/%02d.png" % selected)

func _unhandled_key_input(event: InputEvent) -> void:
	if busy or auto_capture or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_RIGHT:
			selected = (selected + 1) % 18
			show_site()
		KEY_LEFT:
			selected = posmod(selected - 1, 18)
			show_site()
		KEY_N:
			seed_value += 1
			show_site()
		KEY_F1:
			player.camera.make_current()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		KEY_F2: overview()
		KEY_F7: capture()

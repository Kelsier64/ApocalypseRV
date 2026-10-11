extends Node3D
## Presentation sandbox using the production model and printing controller.
var station: CraftingStation
var elapsed := 0.0
var paused := false
var recipe_index := 7
var camera: Camera3D
var angle := -0.6
var label: Label
var capturing := false

func _ready() -> void:
	DisplayServer.window_set_title("Fabricator - print preview")
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.025, 0.035, 0.05)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.65, 0.77, 0.86)
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -35, 0)
	light.light_energy = 2.2
	light.shadow_enabled = true
	add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2, 2, -1)
	fill.light_color = Color(0.3, 0.7, 1.0)
	fill.light_energy = 3.0
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.075, 0.09, 0.11)
	floor_material.roughness = 0.9
	plane.material = floor_material
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	station = preload("res://equipment/crafting_station.tscn").instantiate()
	station.presentation_only = true
	add_child(station)
	camera = Camera3D.new()
	camera.fov = 38
	add_child(camera)
	camera.current = true
	_update_camera()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(32, 24)
	label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(label)
	capturing = "--capture" in OS.get_cmdline_user_args()
	if capturing: _capture.call_deferred()

func _process(delta: float) -> void:
	if capturing: return
	if not paused: elapsed = fmod(elapsed + delta, 10.0)
	_show_progress(clampf(elapsed / 8.0, 0.0, 1.0))

func _show_progress(amount: float) -> void:
	var recipe := RecipeCatalog.all()[mini(recipe_index, RecipeCatalog.all().size() - 1)]
	station.print_visual.sync_job({"id": str(recipe_index), "recipe": recipe.recipe_id, "remaining": recipe.duration * (1.0 - amount), "crouching": recipe.recipe_id == "printed_player" and "--crouch" in OS.get_cmdline_user_args()}, station.spawn_marker.transform)
	label.text = "FABRICATOR / %s   %d%%\nSpace: pause   R: replay   1-8: recipe   Left/Right: orbit" % [recipe.display_name, roundi(amount * 100.0)]

func _update_camera() -> void:
	camera.position = Vector3(sin(angle) * 5.0, 3.25, -cos(angle) * 5.0)
	camera.look_at(Vector3(0, 1.25, 0))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE: paused = not paused
		KEY_R: elapsed = 0.0
		KEY_LEFT: angle -= 0.3
		KEY_RIGHT: angle += 0.3
	if event.keycode >= KEY_1 and event.keycode <= KEY_8:
		recipe_index = event.keycode - KEY_1
		elapsed = 0.0
	_update_camera()

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/fabricator-preview")
	for index in [7, 3, 1, 6]:
		recipe_index = index
		for amount in [0.0, 0.25, 0.5, 0.75, 1.0]:
			_show_progress(amount)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://.godot/fabricator-preview/recipe%d-%03d.png" % [index, roundi(amount * 100.0)])
	print("PASS: fabricator presentation captures")
	get_tree().quit()

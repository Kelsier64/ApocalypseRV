extends Node3D
## Authoring showroom only. Its entrance teleports within this fixture, NOT a
## production instance loader. F6 uses real player input and collision.

const SMALL = preload("res://world/poi_kit/rooms/utility_small.tscn")
const CORRIDOR = preload("res://world/poi_kit/rooms/service_corridor.tscn")
const HALL = preload("res://world/poi_kit/rooms/maintenance_hall.tscn")
const EXTERIOR = preload("res://world/poi_kit/exteriors/service_entrance.tscn")
var player: CharacterBody3D
var observer: Camera3D
var small: PoiRoom
var corridor: PoiRoom
var hall: PoiRoom
var exterior: Node3D
var status: Label
var mode_name := "EXTERIOR / building shell + independent entrance"
var replay := false
var replay_time := 0.0
var loot_count := 0
var debug_markers: Node3D
var cutaway := false

func _ready() -> void:
	process_physics_priority = -10
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("ApocalypseRV - POI Asset Workshop")
		DisplayServer.window_set_size(Vector2i(1280, 800))
	_setup_environment()
	var entities := Node3D.new()
	entities.name = "WorldEntities"
	add_child(entities)
	small = SMALL.instantiate()
	add_child(small)
	corridor = CORRIDOR.instantiate()
	add_child(corridor)
	assert(corridor.connect_to(&"south", small.get_socket(&"north")))
	hall = HALL.instantiate()
	add_child(hall)
	assert(hall.connect_to(&"south", corridor.get_socket(&"north")))
	exterior = EXTERIOR.instantiate()
	exterior.position = Vector3(0, 0, 18)
	add_child(exterior)
	exterior.get_node("Entrance").entry_requested.connect(_enter_sample)
	player = preload("res://player/player.tscn").instantiate()
	add_child(player)
	observer = Camera3D.new()
	observer.fov = 68
	add_child(observer)
	_make_hud()
	_spawn_sample_loot(entities)
	_make_markers()
	_set_view(1)
	if "--replay" in OS.get_cmdline_user_args():
		_start_replay()

func _setup_environment() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("9caaa9")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c4d2d1")
	settings.ambient_light_energy = 0.45
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("ffe6c5")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	ground.name = "Courtyard"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.2, 100)
	shape.shape = box
	shape.position = Vector3(0, -0.12, 0)
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = box.size
	mesh.mesh = ground_mesh
	mesh.position = shape.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("454f50")
	mesh.material_override = mat
	ground.add_child(mesh)
	add_child(ground)
	for x in [-9, -5, 5, 9]:
		var line := MeshInstance3D.new()
		var marking := BoxMesh.new()
		marking.size = Vector3(0.09, 0.01, 7)
		line.mesh = marking
		line.material_override = preload("res://world/poi_kit/materials/orange.tres")
		line.position = Vector3(x, 0, 28)
		add_child(line)

func _make_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(22, 20)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.065, 0.07, 0.91)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_width_left = 3
	style.border_color = Color("dc8b42")
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", Color("e1e8df"))
	panel.add_child(status)

func _spawn_sample_loot(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70915
	for room in [small, hall]:
		for point in room.find_children("*", "Marker3D", true, false):
			if point is PoiLootPoint:
				var scene: PackedScene = point.roll_scene(rng)
				if scene != null:
					var prop: Node3D = scene.instantiate()
					parent.add_child(prop)
					prop.global_transform = point.global_transform
					loot_count += 1
	print("WORKSHOP: spawned %d sample props once from authored loot markers" % loot_count)

func _make_markers() -> void:
	debug_markers = Node3D.new()
	debug_markers.name = "AuthoringOverlay"
	add_child(debug_markers)
	for room in [small, corridor, hall]:
		for point in room.find_children("*", "Marker3D", true, false):
			if point is PoiLootPoint or point is PoiDoorSocket:
				var mesh := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 0.09
				sphere.height = 0.18
				mesh.mesh = sphere
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = Color.CYAN if point is PoiDoorSocket else Color.YELLOW
				mesh.material_override = mat
				debug_markers.add_child(mesh)
				mesh.global_position = point.global_position + (Vector3.UP if point is PoiDoorSocket else Vector3.ZERO)
	debug_markers.visible = false

func _set_view(index: int) -> void:
	replay = false
	Input.action_release("move_forward")
	Input.action_release("interact")
	_set_cutaway(index == 4)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.get_node("Camera3D/InteractRay").set_physics_process(false)
	player.get_node("InventoryUI").visible = false
	player.get_node("HealthBarUI").visible = false
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	match index:
		1:
			mode_name = "EXTERIOR / shell, canopy, entrance, return marker"
			observer.position = Vector3(14, 8, 35)
			observer.look_at(Vector3(0, 2, 20))
		2:
			mode_name = "01 STORES / 9 x 9 m / clear height 4.5 m"
			observer.position = Vector3(3.1, 2.9, 3.5)
			observer.look_at(Vector3(-1.2, 1.2, -2.0))
		3:
			mode_name = "03 WORKSHOP / 18 x 18 m / clear height 6 m"
			observer.position = hall.position + Vector3(6.5, 3.4, 6.5)
			observer.look_at(hall.position + Vector3(-2, 1.5, -3))
		4:
			mode_name = "CUTAWAY / connected door sockets / collision stays enabled"
			observer.position = Vector3(29, 39, 24)
			observer.look_at(Vector3(0, 0, -6))
		5:
			_walk(Vector3(0, 0.05, 25))

func _set_cutaway(enabled: bool) -> void:
	cutaway = enabled
	for room in [small, corridor, hall]:
		room.get_node("Visuals/Ceiling").visible = not enabled
	exterior.get_node("Visuals/Roof").visible = not enabled

func _walk(pos: Vector3) -> void:
	player.position = pos
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.get_node("Camera3D").rotation = Vector3.ZERO
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	player.get_node("Camera3D/InteractRay").set_physics_process(true)
	player.get_node("InventoryUI").visible = true
	player.get_node("HealthBarUI").visible = true
	player.get_node("Camera3D").current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mode_name = "WALK / WASD + mouse / E pickup or enter / G drop / F1 overview"

func _enter_sample(actor: Node3D, _destination_id: StringName) -> void:
	if actor == player:
		_walk(Vector3(0, 0.05, 3.0))
		print("WORKSHOP: entrance interaction transferred player into sample room")

func _start_replay() -> void:
	_set_cutaway(false)
	_walk(Vector3(0, 0.05, 25))
	replay_time = 0
	replay = true
	mode_name = "WALK TEST / entrance interaction + real player traversal"

func _physics_process(delta: float) -> void:
	if replay:
		replay_time += delta
		# Let the camera ray refresh after teleporting from the inspection view.
		if replay_time > 0.25 and replay_time < 0.5:
			Input.action_press("interact")
		else:
			Input.action_release("interact")
		if replay_time > 0.75 and player.position.z < 5.0:
			Input.action_press("move_forward")
		if player.position.z < -27:
			replay = false
			Input.action_release("move_forward")
			mode_name = "PASS / player crossed stores, corridor and workshop"
			print("PASS: workshop traversal reached hall with production player")
		elif replay_time > 12.0 or player.position.y < -1:
			replay = false
			Input.action_release("move_forward")
			mode_name = "FAIL / traversal blocked; inspect collision"
			push_error("Workshop traversal failed at " + str(player.position))

func _process(_delta: float) -> void:
	status.text = "NORTHLINE  /  POI ASSET WORKSHOP\n" + mode_name + "\n\nF1 Exterior    F2 Stores    F3 Workshop    F4 Cutaway\nF5 Walk + entrance    F6 Walk test    M Markers\nSample props: %d  |  cyan: doors  /  yellow: loot" % loot_count

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_F1 and event.keycode <= KEY_F5:
			_set_view(event.keycode - KEY_F1 + 1)
		elif event.keycode == KEY_F6:
			_start_replay()
		elif event.keycode == KEY_M:
			debug_markers.visible = not debug_markers.visible

func _exit_tree() -> void:
	Input.action_release("move_forward")
	Input.action_release("interact")

extends Node3D
## Drive a real RV toward a frozen Slender Speaker along a 1.5 km straight
## road and listen to the head loudspeaker's distance mix. AI is off; the
## loudspeaker, its echo layer and the RV cabin muffling run as in game.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const RV := preload("res://rv/new_rv.tscn")
const VehicleSettle := preload("res://tests/support/vehicle_settle.gd")
## RV starts this far up the road; forward is -Z, toward the giant at the origin.
const START_DISTANCES := [900.0, 400.0, 120.0]
## Giant offsets beside the road: roadside, forest edge, deep forest.
const GIANT_OFFSETS := [20.0, 60.0, 120.0]
const ROAD_START := 1000.0
const ROAD_END := -500.0

var actors: Node3D
var giant: SlenderSpeaker
var player: CharacterBody3D
var rv: Chassis
var hud: Label
var start_index := 0
var offset_index := 0
var generation := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().title = "ApocalypseRV - Slender Speaker Audio"
	set_meta("entity_domain", true)
	actors = WorldEntities.get_container(self)
	_build_environment()
	_build_road()
	var canvas := CanvasLayer.new()
	canvas.layer = 40
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(16, 130)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud)
	await _reset()


func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("24313b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a1b3c0")
	environment.environment.ambient_light_energy = .65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)


func _build_road() -> void:
	var length := ROAD_START - ROAD_END
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300, .3, length)
	collision.shape = shape
	floor_body.add_child(collision)
	add_child(floor_body)
	floor_body.position = Vector3(0, -.15, (ROAD_START + ROAD_END) * .5)
	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, length)
	surface.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("53564a")
	material.albedo_texture = load("res://assets/materials/industrial/forest_floor.png")
	material.uv1_scale = Vector3(70, 350, 1)
	material.roughness = 1.0
	surface.material_override = material
	floor_body.add_child(surface)
	surface.position.y = .151
	# Visual-only trees give a sense of speed; the road between them stays clear.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026112
	for index in 260:
		var tree := MeshInstance3D.new()
		tree.mesh = ForestMeshes.tree(index % 6)
		tree.position = Vector3(rng.randf_range(10, 140) * (-1 if index % 2 else 1), 0, rng.randf_range(ROAD_END, ROAD_START))
		tree.scale = Vector3(3.1, rng.randf_range(13, 21), 3.1)
		tree.rotation.y = rng.randf_range(-PI, PI)
		add_child(tree)


func _reset() -> void:
	generation += 1
	var ticket := generation
	for child in actors.get_children(): child.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	if ticket != generation: return
	var vehicle: Node3D = RV.instantiate()
	actors.add_child(vehicle)
	vehicle.position = Vector3(0, 1.8, START_DISTANCES[start_index])
	rv = vehicle.get_node("Chassis")
	rv.handbrake = true
	var wait := VehicleSettle.new()
	if not await wait.wait_for_vehicle(get_tree(), rv, func() -> bool: return ticket == generation): return
	player = PLAYER.instantiate()
	actors.add_child(player)
	player.global_position = rv.to_global(Vector3(0, .6, -3))
	rv.get_node("DriverSeat").interact_hold(player)
	rv.gear = 1
	rv.set_engine_running(true)
	player.seated_in.seat_camera.make_current()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	giant = GIANT.instantiate()
	actors.add_child(giant)
	giant.global_position = Vector3(-GIANT_OFFSETS[offset_index], .02, 0)
	giant.rotation.y = -PI * .5
	# Freeze the AI only; the loudspeaker keeps its own processing.
	giant.set_physics_process(false)


func _process(_delta: float) -> void:
	if not is_instance_valid(giant) or giant.patrol_music == null:
		hud.text = "Setting up..."
		return
	var music := giant.patrol_music
	var listener: Node3D = get_viewport().get_camera_3d()
	var distance := listener.global_position.distance_to(music.global_position) if listener != null else 0.0
	var levels: Dictionary = music.mix(distance)
	var fade := maxf(0.0, 1.0 - distance / music.max_distance)
	hud.text = "SLENDER SPEAKER AUDIO\nDistance %.0f m · RV %.0f km/h\nDirect %+.1f dB · Echo %+.1f dB · Shelf %.0f Hz · Panning %.2f · Range fade %+.1f dB\nF2 Restart at %.0f / %.0f / %.0f m (now %.0f) · F3 Giant %.0f / %.0f / %.0f m from road (now %.0f)\nWASD Drive · E Exit Seat · Hold E Enter Seat · Space Handbrake · Esc Settings" % [
		distance, rv.road_speed() * 3.6 if is_instance_valid(rv) else 0.0,
		levels.direct_db, levels.echo_db, levels.cutoff_hz, levels.panning, linear_to_db(maxf(fade, .0001)),
		START_DISTANCES[0], START_DISTANCES[1], START_DISTANCES[2], START_DISTANCES[start_index],
		GIANT_OFFSETS[0], GIANT_OFFSETS[1], GIANT_OFFSETS[2], GIANT_OFFSETS[offset_index]]


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo): return
	match event.keycode:
		KEY_F2:
			start_index = (start_index + 1) % START_DISTANCES.size()
			_reset()
		KEY_F3:
			offset_index = (offset_index + 1) % GIANT_OFFSETS.size()
			if is_instance_valid(giant): giant.global_position.x = -GIANT_OFFSETS[offset_index]
		_: return
	get_viewport().set_input_as_handled()

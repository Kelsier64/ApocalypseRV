extends Node3D
## Production world. F2 views, 1-4 exterior variants, F3 real walking replay.
var main: Node3D
var player: CharacterBody3D
var site: Dictionary
var camera: Camera3D
var label: Label
var stage := 0
var variant := 0
var walking := false
var route_index := 1
var walk_time := 0.0
var samples: Array[float] = []
var interact_ticks := 0

func _ready() -> void:
	get_window().title = "ApocalypseRV - Outdoor Art Validation"
	main = load("res://world/test_world.tscn").instantiate()
	var generator = main.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = WorldProfile.new()
	generator.profile.chunks_ahead = 1
	generator.profile.chunks_behind = 1
	add_child(main)
	site = generator.field.stop(0)
	player = main.get_node("Player")
	for enemy in get_tree().get_nodes_in_group(Groups.MONSTERS): enemy.queue_free()
	var rv: Chassis = main.get_node("NewRv/Chassis")
	rv.global_position = site.frame * Vector3(-3, 1, 5)
	rv.linear_velocity = Vector3.ZERO
	player.global_position = site.route[0] + Vector3(0, 0.1, 8)
	camera = Camera3D.new()
	camera.far = 500
	add_child(camera)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	label = Label.new()
	label.position = Vector2(25, 370)
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	_view()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F2:
		walking = false
		Input.action_release("move_forward")
		stage = (stage + 1) % 5
		_view()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
		variant = event.keycode - KEY_1
		for building in get_tree().get_nodes_in_group("poi_entrances"):
			if building.global_position.distance_to(site.building.origin) < 1: building.queue_free()
		site.exterior = ExplorationSite.TYPES[variant]
		site.title = ExplorationSite.NAMES[variant]
		main.get_node("WorldGenerator").poi_spawner.spawn_site(site, main.get_node("WorldGenerator").active_chunks[1].node)
		_view()
	elif event.keycode == KEY_F3:
		player.inventory.items.clear()
		var item := EngineState.new().item()
		player.add_item(item.name, true, item.scene_path, item.state)
		player.global_position = site.route[0] + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		player.in_ui_mode = false
		player.camera.current = true
		walking = true
		route_index = 1
		walk_time = 0
		samples.clear()
	elif event.keycode == KEY_F4:
		var manager := main.get_node("PoiInstances") as PoiInstanceManager
		if manager.busy: return
		if not manager.active_id.is_empty():
			await manager.leave()
		else:
			# Replay the actual interact action for physical-key automation hosts.
			interact_ticks = 6
			Input.action_press("interact")
	elif event.keycode == KEY_F5:
		get_window().size = Vector2i(1280, 800) if get_window().size.x != 1280 else Vector2i(960, 720)
	elif event.keycode == KEY_F6:
		stage = 5 + posmod(stage - 4, 3) if stage >= 5 else 5
		_view()
	elif event.keycode == KEY_F7:
		var rv: Chassis = main.get_node("NewRv/Chassis")
		rv.current_power = 80.0 if rv.current_power < 1 else 0.0
	elif event.keycode == KEY_F9:
		var panel: Equipment = main.get_node("NewRv/Chassis/RightFront")
		panel.current_health = panel.max_health if panel.current_health < panel.max_health * 0.3 else panel.max_health * 0.2
	elif event.keycode == KEY_F10:
		player.in_ui_mode = false
		main.get_node("NewRv/Chassis/TabletScreen").interact_hold(player)
	elif event.keycode == KEY_R:
		get_tree().reload_current_scene()

func _view() -> void:
	player.in_ui_mode = true
	camera.current = true
	var positions := [site.road.origin + Vector3(0, 2.3, 18), site.frame.origin + Vector3(0, 1.8, 8), site.route[3] + Vector3.UP * 1.8, site.building * Vector3(11, 3, 21), site.route[6] + Vector3.UP * 1.8]
	var rv: Chassis = main.get_node("NewRv/Chassis")
	positions.append_array([rv.to_global(Vector3(9, 3, -11)), rv.to_global(Vector3(0.8, 1.95, -1.8)), rv.to_global(Vector3(0.8, 1.8, 5.0))])
	camera.global_position = positions[stage]
	var target: Vector3 = site.building.origin + Vector3.UP * 5
	if stage == 2: target = site.route[4] + Vector3.UP * 1.8
	if stage == 4: target = site.frame.origin + Vector3.UP * 2
	if stage == 5: target = rv.to_global(Vector3(0, 1.1, 0))
	if stage == 6: target = rv.to_global(Vector3(-0.45, 1.3, -5))
	if stage == 7: target = rv.to_global(Vector3(-0.7, 1.0, 0))
	camera.look_at(target)
	label.text = "%s | %s\nF2 view | 1-4 building | F3 walk | F4 enter/return | F5 resize | F8 retro\nF6 RV/cabin/equipment | F7 battery | F9 panel damage | R reset" % [ExplorationSite.NAMES[variant], ["HIGHWAY", "PARKING", "OCCLUDED TRAIL", "ENTRANCE", "RETURN VIEW", "RV", "CABIN", "EQUIPMENT"][stage]]

func _physics_process(delta: float) -> void:
	if interact_ticks > 0:
		interact_ticks -= 1
		if interact_ticks == 0: Input.action_release("interact")
	if not walking: return
	walk_time += delta
	var target: Vector3 = site.route[route_index]
	if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 0.35:
		route_index += 1
		if route_index >= site.route.size():
			walking = false
			Input.action_release("move_forward")
			print("HORROR WALK complete seconds=", walk_time, " frames=", samples.size())
			if not samples.is_empty():
				samples.sort()
				print("HORROR FRAME median_ms=", samples[samples.size() / 2], " p95_ms=", samples[int(samples.size() * 0.95)])
			label.text = "Walk complete: %.1f seconds | F2 views | F8 retro" % walk_time
			return
		target = site.route[route_index]
	player.look_at(Vector3(target.x, player.global_position.y, target.z))
	player.camera.rotation = Vector3.ZERO
	Input.action_press("move_forward")
	label.text = "CARRY ENGINE | %.1f s | waypoint %d/%d\nF2 stop | F8 retro" % [walk_time, route_index, site.route.size() - 1]

func _process(delta: float) -> void:
	# Keep validation instructions out of the real terminal's controls.
	var tablet: Node = main.get_node("NewRv/Chassis/TabletScreen")
	label.visible = not tablet.ui_instance.visible
	if walking: samples.append(delta * 1000.0)

func _exit_tree() -> void:
	Input.action_release("move_forward")
	Input.action_release("interact")

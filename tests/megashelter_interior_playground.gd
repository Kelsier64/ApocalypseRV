extends Node3D
## Actual exterior/manager/player pipeline; inspection views do not alter gameplay lighting.
var manager: PoiInstanceManager
var building: Node3D
var player: CharacterBody3D
var preview: Camera3D
var status: Label
var seed_value := 42
var running := false
var cutaway := false
var inspect_index := 0

func _ready() -> void:
	DisplayServer.window_set_title("ApocalypseRV - Megashelter Interior")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	collision.shape = box
	collision.position.y = -0.5
	ground.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	visual.mesh = mesh
	visual.position.y = -0.5
	ground.add_child(visual)
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 0.8
	add_child(sun)
	manager = PoiInstanceManager.new()
	manager.name = "PoiInstances"
	add_child(manager)
	player = preload("res://player/player.tscn").instantiate()
	add_child(player)
	var canvas := CanvasLayer.new()
	canvas.layer = 30
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(24, 590)
	status.add_theme_font_size_override("font_size", 16)
	canvas.add_child(status)
	await _load_seed()
	if manager.interior == null: return
	if "--capture" in OS.get_cmdline_user_args(): await _capture()
	if "--replay" in OS.get_cmdline_user_args(): await _replay()

func _load_seed() -> void:
	running = true
	if not manager.active_id.is_empty(): await manager.leave()
	if is_instance_valid(building): building.queue_free()
	await get_tree().process_frame
	var plan := MegashelterPlan.generate(seed_value)
	var site := {"id": "shelter-preview:%d" % seed_value, "seed": seed_value, "definition_id": "modular_megashelter", "placement": "off_road", "building": Transform3D.IDENTITY, "exterior_plan": plan}
	building = POISpawner.new().spawn_site(site, self)
	if building == null:
		status.text = "FAIL / exterior"
		running = false
		return
	player.complete_world_transition(Transform3D(Basis.IDENTITY, Vector3(plan.access_point.x, 0.1, float(plan.depth)*0.5 + 5.5)))
	for i in 8: await get_tree().physics_frame
	# Use the player's ray and actual entrance signal; the manager is not invoked
	# directly here so the fixture catches an interaction skin hidden in a wall.
	Input.action_press("interact")
	for i in 3: await get_tree().physics_frame
	Input.action_release("interact")
	var deadline := Time.get_ticks_msec() + 15000
	while manager.state != PoiInstanceManager.State.INDOOR and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if manager.interior == null:
		status.text = "FAIL / " + manager.last_error
		running = false
		return
	preview = Camera3D.new()
	manager.interior.add_child(preview)
	if not player.inventory.items.any(func(item: Dictionary) -> bool: return item.get("scene_path") == "res://props/flashlight.tscn"):
		var torch := preload("res://props/flashlight.tscn").instantiate() as Item
		manager.interior.entities.add_child(torch)
		torch.interact(player)
	# Test fixture only: the actual shelter never grants a flashlight.
	if not player.inventory.active_item().get("state", {}).get("flashlight", {}).get("on", false):
		player._toggle_flashlight()
	cutaway = false
	inspect_index = 0
	running = false
	_hint()
	print("MEGASHELTER_PREVIEW_READY seed=%d rooms=%d exterior_m2=%.0f" % [seed_value, manager.interior.rooms.size(), manager.interior.exterior_area])

func _hint() -> void:
	status.text = "SHELTER / seed %d\nF1 walk / F2 overview / F3 cutaway / F4 next room / F5 carry replay / F6 next seed / F8 capture\nE exit / L flashlight / M explored map" % seed_value

func _inspect(index: int) -> void:
	if manager.interior == null: return
	inspect_index = posmod(index, manager.interior.rooms.size())
	var room := manager.interior.rooms[inspect_index]
	player.set_physics_process(false)
	var at := room.to_global(Vector3(room.footprint.x*0.32, 1.65, room.footprint.y*0.14))
	preview.projection = Camera3D.PROJECTION_PERSPECTIVE
	preview.fov = 75
	preview.global_position = at
	preview.look_at(room.to_global(Vector3(-room.footprint.x*0.25, 1.4, -room.footprint.y*0.25)))
	preview.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status.text = "SHELTER / %s / %s\nF1 walk / F4 next room / F5 carry replay / F6 next seed / F8 capture" % [room.room_id, "DARK" if room.get_meta("megashelter_dark", false) else "LIT"]

func _overview() -> void:
	var inside := manager.interior
	var bounds: AABB = inside.rooms[0].occupancy()
	for room in inside.rooms: bounds = bounds.merge(room.transform * room.occupancy())
	var extent := maxf(bounds.size.x, bounds.size.z)
	preview.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview.size = extent * 1.15
	preview.position = bounds.get_center() + Vector3(0.3, 1.3, 0.6)*extent
	preview.look_at(bounds.get_center())
	preview.current = true
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _replay() -> void:
	if running or manager.interior == null: return
	running = true
	_walk()
	var replay = preload("res://tests/bunker_replay.gd").new()
	var passed: bool = await replay.run(manager.interior, player, func(message): status.text = message)
	if passed:
		# Exercise the actual exit ray and E interaction, rather than calling leave.
		var exit := manager.interior.exit_door
		player.look_at(Vector3(exit.global_position.x, player.global_position.y, exit.global_position.z))
		player.camera.look_at(exit.global_position + Vector3.UP * 1.4)
		Input.action_press("interact")
		for i in 4: await get_tree().physics_frame
		Input.action_release("interact")
		for i in 30: await get_tree().physics_frame
		passed = manager.state == PoiInstanceManager.State.OUTDOOR and player.get_parent() == self
	status.text = "PASS / all rooms, large cargo and exterior return" if passed else "FAIL / inspect log"
	print("MEGASHELTER_REPLAY: " + status.text)
	running = false
	if "--quit-after-replay" in OS.get_cmdline_user_args(): get_tree().quit(0 if passed else 1)

func _walk() -> void:
	player.camera.current = true
	player.set_physics_process(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hint()

func _capture() -> void:
	var dir := "res://.godot/art-work/megashelter-interior"
	DirAccess.make_dir_recursive_absolute(dir)
	for index in manager.interior.rooms.size():
		_inspect(index)
		for i in 12: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%d-%s.png" % [dir, seed_value, manager.interior.rooms[index].room_id])
	_walk()
	if "--quit-after-capture" in OS.get_cmdline_user_args(): get_tree().quit()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or running or manager == null: return
	if event.keycode == KEY_F6:
		seed_value += 1
		_load_seed()
		return
	if manager.interior == null: return
	match event.keycode:
		KEY_F1: _walk()
		KEY_F2: _overview()
		KEY_F3:
			cutaway = not cutaway
			for room in manager.interior.rooms:
				room.get_node("Visuals/CeilingSlab").visible = not cutaway
		KEY_F4: _inspect(inspect_index + 1)
		KEY_F5: _replay()
		KEY_F8:
			DirAccess.make_dir_recursive_absolute("res://.godot/art-work/megashelter-interior")
			get_viewport().get_texture().get_image().save_png("res://.godot/art-work/megashelter-interior/preview.png")

func _exit_tree() -> void:
	Input.action_release("move_forward")
	Input.action_release("interact")

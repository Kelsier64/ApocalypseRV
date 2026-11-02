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
var inspection_torch: SpotLight3D

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
	while manager.state == PoiInstanceManager.State.INDOOR:
		var previous_id := manager.active_id
		await manager.leave()
		if manager.active_id == previous_id:
			running = false
			return
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
	_prepare_preview()
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
	status.text = "SHELTER / seed %d\nF1 walk / F2 overview / F3 cutaway / F4 next room / F5 carry replay / F6 next seed / F7 entrance / F8 capture\nE exit / L flashlight / M explored map" % seed_value

func _prepare_preview() -> void:
	# Returning through the stairwell rebuilds reception in a new viewport.
	if is_instance_valid(preview) and preview.get_parent() == manager.interior: return
	preview = Camera3D.new()
	manager.interior.add_child(preview)
	var torch_source := preload("res://props/flashlight.tscn").instantiate()
	inspection_torch = torch_source.get_node("Beam").duplicate() as SpotLight3D
	torch_source.free()
	preview.add_child(inspection_torch)
	inspection_torch.rotation = Vector3.ZERO
	inspection_torch.position = Vector3(0.12,-0.12,-0.1)
	inspection_torch.hide()

func _inspect(index: int) -> void:
	if manager.interior == null: return
	inspect_index = posmod(index, manager.interior.rooms.size())
	var room := manager.interior.rooms[inspect_index]
	player.set_physics_process(false)
	player.hide()
	var at := room.to_global(Vector3(room.footprint.x*0.32, 1.65, room.footprint.y*0.14))
	preview.projection = Camera3D.PROJECTION_PERSPECTIVE
	preview.fov = 75
	preview.global_position = at
	preview.look_at(room.to_global(Vector3(-room.footprint.x*0.25, 1.4, -room.footprint.y*0.25)))
	preview.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status.text = "SHELTER / %s / %s\nF1 walk / F4 next room / F5 carry replay / F6 next seed / F8 capture" % [room.room_id, "DARK" if room.get_meta("megashelter_dark", false) else "LIT"]

func _inspect_entrance() -> void:
	if manager.interior == null: return
	var room := manager.interior.rooms[0]
	player.set_physics_process(false)
	player.hide()
	preview.projection = Camera3D.PROJECTION_PERSPECTIVE
	preview.fov = 68
	preview.global_position = room.to_global(Vector3(0.1, 1.65, -0.8))
	preview.look_at(room.to_global(Vector3(0, 1.65, room.footprint.y*0.5-0.3)))
	preview.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status.text = "SHELTER / RECEPTION ENTRANCE\nF1 walk / F4 next room / F7 entrance / F8 capture"

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
	player.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _replay() -> void:
	if running or manager.interior == null: return
	running = true
	_walk()
	var replay = preload("res://tests/bunker_replay.gd").new()
	var passed: bool = await replay.run(manager.interior, player, func(message): status.text = message)
	if passed:
		# Finish through the pedestrian leaf with real movement and the player ray.
		var exit: Marker3D = manager.interior.rooms[0].get_node("Walkway/PedestrianExit")
		passed = await replay.route(exit.global_position + exit.global_basis.z*1.2)
		if passed:
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
	player.show()
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
	_inspect_entrance()
	for i in 12: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%d-reception-entrance.png" % [dir, seed_value])
	if "--detail-capture" in OS.get_cmdline_user_args():
		for room in manager.interior.rooms:
			if room.function_id == "sanitary":
				await _detail_capture(dir, room, Vector3(-room.footprint.x*0.5+0.8,0.86,-room.footprint.y*0.5+2.4), Vector3(2.3,0.85,1.2), "basins")
				await _detail_capture(dir, room, Vector3(room.footprint.x*0.5-0.9,0.58,-room.footprint.y*0.5+2.1), Vector3(-1.8,1.0,0.2), "toilet")
		for room in manager.interior.rooms:
			var side := posmod(str(room.room_id).hash(),4)
			if room.function_id == "reception" and side == 2: continue
			var angle := -PI*0.5*side
			var span: float = room.footprint.x if side%2 == 0 else room.footprint.y
			if span < 7: continue
			var depth: float = room.footprint.y*0.5 if side%2 == 0 else room.footprint.x*0.5
			var pose := Transform3D(Basis(Vector3.UP,angle),Basis(Vector3.UP,angle)*Vector3(0,0,-depth))
			var target := pose*Vector3(span*0.5-1.65,0.725,0.14)
			await _detail_capture(dir,room,target,pose.basis*Vector3(0,0.45,1.8),"wall-cavity")
			break
	_walk()
	if "--quit-after-capture" in OS.get_cmdline_user_args(): get_tree().quit()

func _detail_capture(dir: String, room: PoiRoom, target: Vector3, offset: Vector3, label: String) -> void:
	player.hide()
	player.set_physics_process(false)
	preview.projection = Camera3D.PROJECTION_PERSPECTIVE
	preview.fov = 65
	preview.global_position = room.to_global(target+offset)
	preview.look_at(room.to_global(target))
	preview.current = true
	inspection_torch.show()
	status.text = "SHELTER DETAIL / %s / FLASHLIGHT" % label
	for i in 12: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%d-detail-%s.png" % [dir,seed_value,label])
	inspection_torch.hide()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or running or manager == null or manager.busy: return
	if event.keycode == KEY_F6:
		seed_value += 1
		_load_seed()
		return
	if manager.interior == null or manager.interior.profile_id != &"megashelter": return
	_prepare_preview()
	match event.keycode:
		KEY_F1: _walk()
		KEY_F2: _overview()
		KEY_F3:
			cutaway = not cutaway
			for room in manager.interior.rooms:
				room.get_node("Visuals/CeilingSlab").visible = not cutaway
		KEY_F4: _inspect(inspect_index + 1)
		KEY_F5: _replay()
		KEY_F7: _inspect_entrance()
		KEY_F8:
			DirAccess.make_dir_recursive_absolute("res://.godot/art-work/megashelter-interior")
			get_viewport().get_texture().get_image().save_png("res://.godot/art-work/megashelter-interior/preview.png")

func _exit_tree() -> void:
	Input.action_release("move_forward")
	Input.action_release("interact")

extends Node3D
var inside: PoiInterior
var player: CharacterBody3D
var status: Label
var running := false
var preview: Camera3D
var inspection_light: DirectionalLight3D
var cutaway := false
func _ready() -> void:
	DisplayServer.window_set_title("ApocalypseRV - Bunker Test")
	var canvas := CanvasLayer.new()
	canvas.layer = 25
	add_child(canvas)
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status.position = Vector2(24,-130)
	status.add_theme_font_size_override("font_size",16)
	canvas.add_child(status)
	inside = PoiInterior.new()
	var seed_value := 42
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rooms="): inside.room_count = int(arg.trim_prefix("--rooms="))
		if arg.begins_with("--floors="): inside.target_floors = int(arg.trim_prefix("--floors="))
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
	add_child(inside)
	if not await inside.build(seed_value):
		status.text = "FAIL: bunker build"
		return
	player = preload("res://player/player.tscn").instantiate()
	inside.add_child(player)
	player.transform = inside.spawn_transform()
	preview = Camera3D.new()
	add_child(preview)
	var bounds: AABB = inside.rooms[0].occupancy()
	for room in inside.rooms: bounds = bounds.merge(room.transform * room.occupancy())
	var extent := maxf(bounds.size.x,bounds.size.z)
	preview.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview.size = extent * 1.3
	preview.position = bounds.get_center() + Vector3(0.65,1,0.8)*extent
	preview.look_at(bounds.get_center())
	inspection_light = DirectionalLight3D.new()
	inspection_light.rotation_degrees = Vector3(-65,-30,0)
	inspection_light.light_energy = 1.2
	inspection_light.hide()
	add_child(inspection_light)
	status.text = "BUNKER / seed %d / %d rooms / %d floors\nF1 walk / F2 overview / F3 cutaway / F5 replay / R reset / F8 capture" % [seed_value,inside.rooms.size(),InteriorLayout.floor_count(inside.layout)]
	if "--replay" in OS.get_cmdline_user_args(): _replay.call_deferred()
func _replay() -> void:
	if running: return
	running = true
	player.camera.current = true
	player.set_physics_process(true)
	inspection_light.hide()
	var replay = preload("res://tests/bunker_replay.gd").new()
	var passed: bool = await replay.run(inside,player,func(text): status.text = text)
	status.text = "PASS / bunker traversal" if passed else "FAIL / inspect log"
	running = false
	if "--quit-after-replay" in OS.get_cmdline_user_args(): get_tree().quit(0 if passed else 1)
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or player == null: return
	if event.keycode == KEY_F1:
		player.camera.current = true
		player.set_physics_process(true)
		inspection_light.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.keycode == KEY_F2 and not running:
		preview.current = true
		player.set_physics_process(false)
		inspection_light.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.keycode == KEY_F3:
		cutaway = not cutaway
		for room in inside.rooms:
			for mesh in room.get_node("Visuals").get_children():
				if str(mesh.name).begins_with("Ceiling"): mesh.visible = not cutaway
	if event.keycode == KEY_F5: _replay()
	if event.keycode == KEY_R and not running: get_tree().reload_current_scene()
	if event.keycode == KEY_F8:
		get_viewport().get_texture().get_image().save_png("res://.godot/bunker-view.png")
		print("BUNKER_CAPTURE: .godot/bunker-view.png")
func _exit_tree() -> void:
	Input.action_release("move_forward")
	Input.action_release("interact")

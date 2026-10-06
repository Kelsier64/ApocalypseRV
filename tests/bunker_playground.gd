extends Node3D
var inside: PoiInterior
var player: CharacterBody3D
var status: Label
var running := false
var preview: Camera3D
var inspection_light: DirectionalLight3D
var cutaway := false
var art_inspect := false
var inspect_index := 0
var inspect_corner := 0
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
	art_inspect = "--art-inspect" in OS.get_cmdline_user_args()
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
	if art_inspect:
		# Isolated inspection fixture; production only supplies the loose world prop.
		for actor in inside.entities.get_children():
			if actor is Monster: actor.process_mode = Node.PROCESS_MODE_DISABLED
		var torch := preload("res://props/flashlight.tscn").instantiate() as Item
		inside.entities.add_child(torch)
		torch.interact(player)
		var first_room := 0
		for arg in OS.get_cmdline_user_args():
			if not arg.begins_with("--inspect-room="): continue
			var wanted := arg.trim_prefix("--inspect-room=")
			for i in inside.rooms.size():
				if inside.rooms[i].room_id == wanted:
					first_room = i
					break
		_inspect_room(first_room)
	if "--replay" in OS.get_cmdline_user_args(): _replay.call_deferred()

func _inspect_room(index: int) -> void:
	inspect_index = posmod(index, inside.rooms.size())
	var room := inside.rooms[inspect_index]
	player.complete_world_transition(Transform3D(room.global_basis, inside.navigation_anchor(inspect_index) + Vector3.UP * 0.1))
	player.camera.current = true
	inspection_light.hide()
	player.set_physics_process(true)
	_inspect_view()
	status.text = "ART INSPECT / %s / %s / %s\nF4 turn / F6 next / F7 previous / L flashlight / F8 capture" % [room.name, room.room_id, "DARK" if room.get_meta("bunker_dark", false) else "LIT"]
	print("BUNKER_ART_VIEW: %s %s dark=%s" % [room.name, room.room_id, room.get_meta("bunker_dark", false)])
func _inspect_view() -> void:
	var room := inside.rooms[inspect_index]
	var corners := [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	var corner: Vector2 = corners[inspect_corner]
	var target := room.to_global(Vector3(room.footprint.x * 0.33 * corner.x, 1.2, room.footprint.y * 0.33 * corner.y))
	player.look_at(Vector3(target.x, player.global_position.y, target.z))
	player.camera.look_at(target)
func _replay() -> void:
	if running: return
	running = true
	player.camera.current = true
	player.set_physics_process(true)
	inspection_light.hide()
	var paused_enemies: Array[Monster] = []
	for actor in inside.entities.get_children():
		if actor is Monster:
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			paused_enemies.append(actor)
	var replay = preload("res://tests/bunker_replay.gd").new()
	var passed: bool = await replay.run(inside,player,func(text): status.text = text)
	for actor in paused_enemies:
		if is_instance_valid(actor): actor.process_mode = Node.PROCESS_MODE_INHERIT
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
	if art_inspect and not running and event.keycode == KEY_F4:
		inspect_corner = (inspect_corner + 1) % 4
		_inspect_view()
	if art_inspect and not running and event.keycode == KEY_F6: _inspect_room(inspect_index + 1)
	if art_inspect and not running and event.keycode == KEY_F7: _inspect_room(inspect_index - 1)
	if event.keycode == KEY_R and not running: get_tree().reload_current_scene()
	if event.keycode == KEY_F8:
		get_viewport().get_texture().get_image().save_png("res://.godot/bunker-view.png")
		if art_inspect:
			var room := inside.rooms[inspect_index]
			var beam_on: bool = player.inventory.active_item().get("state", {}).get("flashlight", {}).get("on", false)
			var filename := "res://.godot/bunker-art-%s-%s.png" % [room.room_id, "on" if beam_on else "off"]
			get_viewport().get_texture().get_image().save_png(filename)
			print("BUNKER_CAPTURE: " + filename)
		print("BUNKER_CAPTURE: .godot/bunker-view.png")
func _exit_tree() -> void:
	Input.action_release("move_forward")
	Input.action_release("interact")

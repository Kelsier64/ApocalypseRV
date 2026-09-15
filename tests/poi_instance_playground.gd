extends Node3D
## Production scene replay. F6: exterior -> real E -> walk connector -> real E exit.
var running := false
var status: Label

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	status = Label.new()
	status.position = Vector2(24, 64)
	status.add_theme_font_size_override("font_size", 20)
	status.text = "F6: production POI round trip replay"
	layer.add_child(status)
	if "--replay" in OS.get_cmdline_user_args():
		_replay.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F6 and not running:
		_replay()

func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame

func _press_e() -> void:
	await _frames(20)
	Input.action_press("interact")
	await _frames(15)
	Input.action_release("interact")

func _walk_to(target: Vector3) -> bool:
	var player = $PoiInstances._player
	var deadline := Time.get_ticks_msec() + 18000
	while Vector2(player.position.x - target.x, player.position.z - target.z).length() > 0.4 and Time.get_ticks_msec() < deadline:
		player.look_at(Vector3(target.x, player.position.y, target.z))
		Input.action_press("move_forward")
		await get_tree().physics_frame
	Input.action_release("move_forward")
	return player.position.distance_to(target) < 1.0

func _replay() -> void:
	if running or not $PoiInstances.active_id.is_empty():
		return
	running = true
	var player = get_node("Player")
	var entrances := get_tree().get_nodes_in_group("poi_entrances")
	var building: Node3D
	for candidate in entrances:
		if absf(candidate.global_position.z + 45) < 1:
			building = candidate
	if building == null:
		push_error("FAIL: no starting POI")
		return
	player.global_transform = building.get_node("ReturnPoint").global_transform
	player.global_basis = building.global_basis
	player.camera.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	status.text = "REPLAY / exterior door"
	await _press_e()
	while $PoiInstances.busy:
		await get_tree().process_frame
	if $PoiInstances.interior == null:
		push_error("FAIL: exterior E did not enter")
		return
	status.text = "REPLAY / walking authored room + connector"
	var inside: PoiInterior = $PoiInstances.interior
	var neighbor: int = inside.layout.edges[0].y
	var okay := await _walk_to(Vector3.ZERO)
	okay = await _walk_to(inside.rooms[neighbor].position) and okay
	okay = await _walk_to(Vector3.ZERO) and okay
	okay = await _walk_to(Vector3(0, 0, 2.6)) and okay
	player.rotation.y = PI
	status.text = "REPLAY / exit door"
	await _press_e()
	while $PoiInstances.busy:
		await get_tree().process_frame
	okay = okay and $PoiInstances.active_id.is_empty()
	status.text = "PASS / entered, walked connector, returned to highway" if okay else "FAIL / inspect replay log"
	print(status.text)
	if not okay:
		push_error("FAIL: production POI replay")
	running = false

func _exit_tree() -> void:
	Input.action_release("move_forward")
	Input.action_release("interact")

extends "res://world/test_world.gd"
## Production scene replay. F6: exterior -> real E -> walk connector -> real E exit.
var running := false
var status: Label

func _ready() -> void:
	super._ready()
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_F7 and not running:
		_inspect_entrance()
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		get_viewport().get_texture().get_image().save_png("res://.godot/bunker-exterior.png")

func _inspect_entrance() -> void:
	if not $PoiInstances.active_id.is_empty(): return
	await wait_for_play()
	for building in get_tree().get_nodes_in_group("poi_entrances"):
		if absf(building.global_position.z + 45) >= 1: continue
		var player := get_node("Player") as Node3D
		player.complete_world_transition(building.global_transform * Transform3D(Basis.IDENTITY, Vector3(6,0.05,14)))
		player.look_at(Vector3(building.global_position.x, player.global_position.y, building.global_position.z))
		player.camera.look_at(building.global_position + Vector3.UP * 2.5)
		status.text = "BUNKER exterior / F6 round trip / F8 capture"
		return

func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame

func _press_e() -> void:
	await _frames(20)
	Input.action_press("interact")
	await _frames(15)
	Input.action_release("interact")

func _replay() -> void:
	if running or not $PoiInstances.active_id.is_empty():
		return
	running = true
	var player = get_node("Player")
	await wait_for_play()
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
	var walker = preload("res://tests/bunker_replay.gd").new()
	walker.interior = inside
	walker.player = player
	var neighbor: int = inside.layout.edges[0].y
	var okay: bool = await walker.route(inside.navigation_anchor(neighbor))
	okay = await walker.route(inside.spawn_transform().origin) and okay
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

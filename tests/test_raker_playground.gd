extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func key(scene: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	scene._input(event)
func run() -> void:
	var scene: Node3D = load("res://tests/raker_vehicle_playground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 75: await physics_frame
	check(scene.ready_to_drive and scene.monster is Raker and not scene.rv.freeze, "Test scene has live production monster and wheel-driven RV")
	check(scene.player.seated_in != null, "Player starts seated for driving")
	scene.monster.set_physics_process(false)
	key(scene, KEY_F2)
	key(scene, KEY_F2)
	key(scene, KEY_F2)
	for i in 120: await physics_frame
	check(scene.rv.road_speed() > .5, "Speed preset drives actual wheels forward")
	var before_turn: float = scene.rv.rotation.y
	Input.action_press("move_left")
	for i in 90: await physics_frame
	Input.action_release("move_left")
	check(absf(angle_difference(before_turn, scene.rv.rotation.y)) > .02, "A/D still turns the actual vehicle while cruise is active")
	key(scene, KEY_F3)
	check(scene.rv.handbrake, "Stop control sets handbrake")
	for clip in ["idle", "walk", "chase", "sprint"]:
		key(scene, KEY_F8)
		check(scene.monster.get_node("BodyMesh").animation_player.current_animation == "game/" + clip, "Preview control selects " + clip)
	check(scene.monster.position.x > scene.rv.position.x + 9 and absf(scene.monster.position.y + .25) < .001, "Preview stays on ground clear of vehicle")
	key(scene, KEY_F9)
	check(not scene.monster.get_node("BodyMesh").animation_player.is_playing(), "Preview can pause")
	key(scene, KEY_F6)
	check(not scene.preview and scene.monster.is_physics_processing(), "Respawn restores live AI")
	key(scene, KEY_F5)
	check(scene.player.seated_in == null and scene.player.camera.current, "Foot chase control exits seat")
	key(scene, KEY_F1)
	check(scene.player.seated_in != null and scene.observer.current, "Driving control returns to seat")
	scene.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: Raker vehicle playground wheel drive, controls, previews and actor resets")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

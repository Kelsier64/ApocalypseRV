extends SceneTree
## Capture the production ground grab from the player's normal first-person view.
func _init() -> void: run.call_deferred()
func run() -> void:
	var scene = load('res://tests/raker_vehicle_playground.tscn').instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 75: await physics_frame
	scene.setup_grab(0)
	var captured := false
	for i in 1200:
		await physics_frame
		if scene.player.is_grabbed():
			captured = true
			break
	if not captured:
		push_error('Production ground grab did not start')
		quit(1)
		return
	for i in 18: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png('res://art_source/monster_refined_v021/playground-first-person.png')
	print('PASS: production ground grab and first-person frame captured with rebuilt hands')
	scene.monster.grab.cancel('review_complete')
	quit()

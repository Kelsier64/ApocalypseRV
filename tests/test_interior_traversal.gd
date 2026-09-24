extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)
func _run() -> void:
	var inside := PoiInterior.new()
	inside.room_count = 12
	inside.target_floors = 3
	root.add_child(inside)
	current_scene = inside
	check(await inside.build(42),"Build three-floor fixture")
	if inside.rooms.is_empty(): quit(1); return
	var player: CharacterBody3D = preload("res://player/player.tscn").instantiate()
	inside.add_child(player)
	player.transform = inside.spawn_transform()
	var replay = preload("res://tests/bunker_replay.gd").new()
	check(await replay.run(inside, player),"Real continuous-input player/cargo route")
	var saved := inside.snapshot()
	check(CheckpointSchema.poi_error({"bunker": saved}).is_empty(),"Gameplay save validates")
	check(inside.explored.size() == inside.rooms.size(),"Every visited room explored")
	inside.free()
	await process_frame
	var restored := PoiInterior.new()
	root.add_child(restored)
	current_scene = restored
	check(await restored.build(999, bytes_to_var(var_to_bytes(saved))),"Restore serialized manifest with a different caller seed")
	check(restored.layout == saved.layout and restored.explored == saved.explored,"Exact layout and exploration preserved")
	check(restored.entities.get_child_count() == 1,"Player cargo persists without automatic spawning")
	restored.free()
	if failures.is_empty(): print("PASS: continuous all-room player/cargo traversal and serialized layout/exploration/drop restore")
	quit(0 if failures.is_empty() else 1)

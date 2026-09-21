extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	var inside := MaintenanceInterior.new()
	inside.room_count = 12
	root.add_child(inside)
	current_scene = inside
	check(await inside.build(42),"Build two-level fixture")
	var player: CharacterBody3D = preload("res://player/player.tscn").instantiate()
	inside.add_child(player)
	player.position = Vector3(0,0.05,2.8)
	var replay = preload("res://tests/interior_v2_replay.gd").new()
	check(await replay.run(inside,player),"Continuous-input gameplay route")
	var saved := inside.snapshot()
	check(CheckpointSchema.poi_error({"v2":saved}).is_empty(),"Gameplay snapshot validates")
	var encoded := var_to_bytes(saved)
	player.queue_free()
	await process_frame
	inside.free()
	await process_frame
	var restored := MaintenanceInterior.new()
	root.add_child(restored)
	current_scene = restored
	check(await restored.build(999,bytes_to_var(encoded)),"Restore persisted manifest rather than caller seed")
	check(restored.layout == saved.layout,"Exact geometry survives serialization")
	check(restored.objective_claimed and restored.shortcut_open,"Objective and hatch survive reload")
	check(restored.explored == saved.explored,"Exploration survives reload")
	check(restored.entities.get_child_count() == saved.actors.size(),"No reward duplication on reload")
	var path := NavigationServer3D.map_get_path(restored.get_world_3d().navigation_map,Vector3.ZERO,Vector3(27,0,0),true)
	var length := 0.0
	for i in range(1,path.size()): length += path[i].distance_to(path[i-1])
	check(path.size() > 1 and length < 35,"Reloaded open hatch has short navigation route: %s length=%f" % [path,length])
	restored.free()
	if failures.is_empty(): print("PASS: actual player/cargo/zombie stairs, E objective/hatch, serialized geometry/progress and open navigation")
	quit(0 if failures.is_empty() else 1)

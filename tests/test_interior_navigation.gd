extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	for count in [50,75,100]:
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		root.add_child(viewport)
		var interior := MaintenanceInterior.new()
		interior.room_count = count
		viewport.add_child(interior)
		check(await interior.build(1700+count),"Build full size %d" % count)
		var map := interior.get_world_3d().navigation_map
		for edge: Dictionary in interior.layout.links:
			var start := interior.navigation_anchor(edge.a)
			var end := interior.navigation_anchor(edge.b)
			var path := NavigationServer3D.map_get_path(map,start,end,true)
			check(path.size() >= 2 and path[-1].distance_to(end) < 1.0,"Full-size navigation %d link %s from=%s to=%s path=%s" % [count,edge,interior.layout.rooms[edge.a],interior.layout.rooms[edge.b],path])
		var tall := 0
		for room: Dictionary in interior.layout.rooms:
			if room.definition == "atrium": tall += 1
		var saved := interior.snapshot()
		check(saved.actors.size() <= interior.PROFILE.loot_budget+interior.PROFILE.enemy_budget,"Population budget independent of room count")
		print("V2_BENCH rooms=%d build_ms=%d nav_ms=%d actors=%d tall=%d static_memory=%d" % [count,interior.build_msec,interior.navigation_msec,saved.actors.size(),tall,OS.get_static_memory_usage()])
		viewport.free()
		await process_frame
		viewport = SubViewport.new()
		viewport.own_world_3d = true
		root.add_child(viewport)
		interior = MaintenanceInterior.new()
		viewport.add_child(interior)
		check(await interior.build(1700+count,saved),"Revisit full size %d" % count)
		check(interior.layout == saved.layout and interior.entities.get_child_count() == saved.actors.size(),"Full-size revisit geometry/population")
		print("V2_REVISIT rooms=%d build_ms=%d nav_ms=%d" % [count,interior.build_msec,interior.navigation_msec])
		viewport.free()
		await process_frame
	if failures.is_empty(): print("PASS: 50/75/100-room physical navigation for every link, fixed population budget and full-size reentry")
	quit(0 if failures.is_empty() else 1)

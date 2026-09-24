extends SceneTree
var failures: Array[String] = []

class InvalidAnchorInterior extends PoiInterior:
	func navigation_anchor(index: int) -> Vector3:
		return Vector3(100000, 0, 100000) if index == 1 else super.navigation_anchor(index)

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	for count in [10,20,30]:
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		root.add_child(viewport)
		var interior := PoiInterior.new()
		interior.room_count = count
		viewport.add_child(interior)
		check(await interior.build(1700+count),"Build full size %d" % count)
		var map := interior.get_world_3d().navigation_map
		for edge: Dictionary in interior.layout.links:
			var start := interior.navigation_anchor(edge.a)
			var end := interior.navigation_anchor(edge.b)
			var path := NavigationServer3D.map_get_path(map,start,end,true)
			check(path.size() >= 2 and path[-1].distance_to(end) < 1.0,"Full-size navigation %d link %s from=%s to=%s path=%s" % [count,edge,interior.layout.rooms[edge.a],interior.layout.rooms[edge.b],path])
		var saved := interior.snapshot()
		check(saved.actors.is_empty(),"No automatic population")
		print("BUNKER_BENCH rooms=%d floors=%d build_ms=%d nav_ms=%d static_memory=%d" % [count,InteriorLayout.floor_count(interior.layout),interior.build_msec,interior.navigation_msec,OS.get_static_memory_usage()])
		viewport.free()
		await process_frame
		viewport = SubViewport.new()
		viewport.own_world_3d = true
		root.add_child(viewport)
		interior = PoiInterior.new()
		viewport.add_child(interior)
		check(await interior.build(1700+count,saved),"Revisit full size %d" % count)
		check(interior.layout == saved.layout and interior.entities.get_child_count() == saved.actors.size(),"Full-size revisit geometry/population")
		print("BUNKER_REVISIT rooms=%d build_ms=%d nav_ms=%d" % [count,interior.build_msec,interior.navigation_msec])
		viewport.free()
		await process_frame
	var invalid := InvalidAnchorInterior.new()
	invalid.room_count = 10
	root.add_child(invalid)
	check(not await invalid.build(1710), "Navigation failure cancels the build instead of accepting disconnected rooms")
	invalid.free()
	if failures.is_empty(): print("PASS: 10/20/30-room physical navigation for every link, empty population, full-size reentry and navigation failure rejection")
	quit(0 if failures.is_empty() else 1)

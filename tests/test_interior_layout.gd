extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	var profile: InteriorProfile = InteriorLayout.PROFILE
	check(profile.validate().is_empty(), "Authoring contracts: " + str(profile.validate()))
	for seed_value in [42,43,4026586570]:
		var automatic := InteriorLayout.generate(seed_value)
		check(InteriorLayout.validate(automatic).is_empty(),"Random production room count replays identically from saved manifest")
	for seed_value in 100:
		var count := [12,50,75,100][seed_value%4] as int
		var layout := InteriorLayout.generate(seed_value,count)
		check(not layout.is_empty(), "Bounded generation fills budget seed=%d" % seed_value)
		if layout.is_empty(): continue
		check(layout.rooms.size() == count, "Exact room budget")
		check(InteriorLayout.generate(seed_value,count) == layout, "Deterministic manifest")
		var closed := InteriorLayout.distances(layout)
		var open := InteriorLayout.distances(layout,true)
		check(INF not in closed, "All rooms reachable while hatch is locked")
		check(open[9] < closed[9]*0.7, "Shortcut materially reduces depot carry route")
		for i in layout.rooms.size():
			var room: Dictionary = layout.rooms[i]
			var a: AABB = room.transform * profile.room(room.definition).describe().bounds
			for j in range(i+1,layout.rooms.size()):
				var other: Dictionary = layout.rooms[j]
				var b: AABB = other.transform * profile.room(other.definition).describe().bounds
				check(not a.grow(-0.01).intersects(b.grow(-0.01)), "No volume overlap, including tall rooms")
		for edge: Dictionary in layout.links:
			var a: Dictionary = layout.rooms[edge.a]
			var b: Dictionary = layout.rooms[edge.b]
			var sa: Transform3D = a.transform * profile.room(a.definition).describe().sockets[edge.sa].transform
			var sb: Transform3D = b.transform * profile.room(b.definition).describe().sockets[edge.sb].transform
			check(sa.origin.distance_to(sb.origin) < 0.01 and sa.basis.z.dot(sb.basis.z) < -0.999,"Matching 3D sockets")
	var saved := {"actors": [], "layout": InteriorLayout.generate(42,12), "objective_claimed": false, "shortcut_open": false, "explored": ["r000"]}
	check(CheckpointSchema.poi_error({"test":saved}).is_empty(),"New versioned progress validates")
	var corrupted := saved.duplicate(true)
	corrupted.layout.rooms[3].transform.origin.y += 6
	check(not CheckpointSchema.poi_error({"test":corrupted}).is_empty(),"Reject shifted saved geometry")
	corrupted = saved.duplicate(true)
	corrupted.layout.version = 999
	check(not CheckpointSchema.poi_error({"test":corrupted}).is_empty(),"Reject unknown generator")
	check(CheckpointSchema.poi_error({"old": {"actors": []}}).is_empty(),"Legacy snapshots remain valid")
	if failures.is_empty(): print("PASS: 100 seeds; authored catalog, 3D occupancy, sockets, loops, shortcut and versioned snapshots")
	quit(0 if failures.is_empty() else 1)

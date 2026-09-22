extends SceneTree
## Test the opening itself: a graph/nav path can silently go around a blocked door.
var failures: Array[String] = []
var sweeps := 0
var capsule: CapsuleShape3D

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func clear_opening(space: PhysicsDirectSpaceState3D, pose: Transform3D, side: int, offset: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, pose * Vector3(offset,capsule.height/2+0.05,1.5*side))
	if not space.intersect_shape(query,1).is_empty(): return false
	query.motion = -pose.basis.z * 3.0 * side
	return space.cast_motion(query)[0] > 0.999

func _run() -> void:
	var player: CharacterBody3D = preload("res://player/player.tscn").instantiate()
	capsule = player.get_node("CollisionShape3D").shape
	player.free()
	for fixture in [[42,50],[1775,75],[1800,100],[4026586570,0]]:
		var inside := MaintenanceInterior.new()
		inside.room_count = fixture[1]
		root.add_child(inside)
		check(await inside.build(fixture[0]),"Doorway fixture builds")
		# Static access contract; wandering actors are tested in traversal suites.
		for actor in inside.entities.get_children(): actor.free()
		await physics_frame
		var space := inside.get_world_3d().direct_space_state
		for link: Dictionary in inside.layout.links:
			if not link.gate.is_empty(): continue
			var socket := inside.rooms[link.a].get_socket(link.sa)
			for side in [-1,1]:
				for offset in [-0.8,0.0,0.8]:
					sweeps += 1
					check(clear_opening(space,socket.global_transform,side,offset),"Direct door crossing seed=%d rooms=%d/%d socket=%s side=%d offset=%f" % [fixture[0],link.a,link.b,link.sa,side,offset])
		var visuals: Array[MeshInstance3D] = []
		for room in inside.rooms:
			for mesh in room.find_children("*","MeshInstance3D",true,false):
				if mesh.mesh is BoxMesh: visuals.append(mesh)
		for room in inside.rooms:
			for holder in room.get_node("Collision").get_children():
				if not str(holder.name).begins_with("Sealed_"): continue
				var body := holder.get_child(0) as StaticBody3D
				var panel := body.get_child(0) as MeshInstance3D
				var collider := body.get_child(1) as CollisionShape3D
				check(collider.position == Vector3.ZERO,"Panel rendering offset does not move collision")
				var pose: Transform3D = holder.global_transform.affine_inverse()
				var own_bounds: AABB = pose * panel.global_transform * panel.mesh.get_aabb()
				for mesh in visuals:
					if mesh == panel: continue
					var box: AABB = pose * mesh.global_transform * mesh.mesh.get_aabb()
					# At eye height in this door, the own-room face must be in front
					# of the adjacent panel/wall, never coplanar or behind it.
					if box.position.x > -0.01 or box.end.x < 0.01 or box.position.y > 1.0 or box.end.y < 1.0: continue
					if box.end.z < -0.5 or box.end.z > 0.5: continue
					check(own_bounds.end.z > box.end.z+0.005,"No competing door face seed=%d seal=%s other=%s" % [fixture[0],holder.get_path(),mesh.get_path()])
		var gate_pose := inside.gate.global_transform
		check(not clear_opening(space,gate_pose,1,0),"Locked hatch blocks direct traversal")
		# A deliberately blocked edge must fail even though the global graph has loops.
		var socket := inside.rooms[0].get_socket(&"north")
		var obstruction := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3,3.5,0.2)
		shape.shape = box
		shape.position.y = 1.75
		obstruction.add_child(shape)
		inside.add_child(obstruction)
		obstruction.global_transform = socket.global_transform
		await physics_frame
		check(not clear_opening(space,socket.global_transform,1,0),"Direct sweep detects blocked edge instead of accepting a detour")
		obstruction.free()
		inside.shortcut_open = true
		inside.gate.completed = true
		inside._open_gate_geometry()
		await physics_frame
		await physics_frame
		for side in [-1,1]:
			check(clear_opening(space,gate_pose,side,0),"Released hatch is physically open on both sides")
		inside.free()
		await process_frame
	if failures.is_empty(): print("PASS: %d direct player-capsule door sweeps, non-overlapping door faces, blocked-edge detection and released hatch" % sweeps)
	quit(0 if failures.is_empty() else 1)

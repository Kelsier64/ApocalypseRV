extends RefCounted
## Place the branch on a closed socket after the room geometry is available.

const OPENING := Vector2(1.06, 2.32)
const DOOR_MATERIALS := {
	0: preload("res://world/poi_kit/materials/bunker/v2/concrete.tres"),
	1: preload("res://world/poi_kit/materials/bunker/v2/paint.tres"),
	2: preload("res://world/poi_kit/materials/bunker/v2/steel.tres"),
	4: preload("res://world/poi_kit/materials/bunker/v2/rubber.tres"),
}

static func choose(inside: Node3D) -> Dictionary:
	var seed := ("bunker-stair-access:v1:%d" % int(inside.layout.seed)).sha256_text().substr(0, 15).hex_to_int()
	if seed % 3 != 0: return {}
	var candidates: Array[Dictionary] = []
	for i in range(1, inside.rooms.size()):
		if InteriorLayout.definition(inside.layout, i, inside.profile).role != &"ordinary": continue
		for socket: PoiDoorSocket in inside.rooms[i].get_node("DoorSockets").get_children():
			var id := str(socket.socket_id)
			if not InteriorLayout.used(inside.layout, i, id):
				candidates.append({"room": i, "socket": id})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clearance := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.1, 1.5)
	clearance.shape = box
	clearance.collision_mask = 1
	var map: RID = inside.navigation.get_navigation_map()
	var space := inside.get_world_3d().direct_space_state
	while not candidates.is_empty():
		var candidate: Dictionary = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var room: PoiRoom = inside.rooms[candidate.room]
		var pose := room.global_transform * _door_pose(room, room.get_socket(StringName(candidate.socket)))
		clearance.transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 1.05))
		if not space.intersect_shape(clearance, 1).is_empty(): continue
		var landing := pose * Vector3(0, 0, 1.5)
		var nearest := NavigationServer3D.map_get_closest_point(map, landing)
		if absf(nearest.y - landing.y) > 0.65 or Vector2(nearest.x - landing.x, nearest.z - landing.z).length() > 0.3: continue
		var path := NavigationServer3D.map_get_path(map, inside.navigation_anchor(0), nearest, true)
		if path.size() < 2 or path[-1].distance_to(nearest) > 0.5: continue
		var sight := PhysicsRayQueryParameters3D.create(landing + Vector3.UP * 1.65, pose * Vector3(0, 1.65, 0.3), 1)
		if space.intersect_ray(sight).is_empty(): return candidate
	return {}

static func add_door(room: PoiRoom, socket: PoiDoorSocket) -> Transform3D:
	var pose := _door_pose(room, socket)
	var visuals := room.get_node("Visuals") as Node3D
	MegashelterInteriorKit.add_model(visuals, "StairAccess", visuals.transform.affine_inverse() * pose,
		MegashelterInteriorKit.pedestrian_door(), func(index: int) -> Material: return DOOR_MATERIALS[index])
	return room.global_transform * pose

static func _door_pose(room: PoiRoom, socket: PoiDoorSocket) -> Transform3D:
	return room.socket_transform(socket) * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.28))

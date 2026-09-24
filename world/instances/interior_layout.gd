extends RefCounted
class_name InteriorLayout
## Pure socket-frontier growth. A saved manifest is authoritative, never rerolled.
const VERSION := 3
const PROFILE = preload("res://world/instances/catalog/bunker.tres")

static func generate(seed_value: int, count := 0, profile: InteriorProfile = PROFILE, floors := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var drawn_count := rng.randi_range(profile.min_rooms, profile.max_rooms)
	var drawn_floors := rng.randi_range(1, profile.max_floors)
	count = drawn_count if count == 0 else clampi(count, 1, 30)
	floors = drawn_floors if floors == 0 else clampi(floors, 1, profile.max_floors)
	var data := {"version": VERSION, "profile": str(profile.profile_id), "seed": seed_value, "target_rooms": count, "target_floors": floors, "floor_spacing": profile.floor_spacing, "rooms": [], "links": [], "edges": []}
	for definition in profile.rooms:
		if definition.enabled and definition.role == &"entry":
			_append(data, definition, Transform3D.IDENTITY)
			break
	if data.rooms.is_empty(): return {}
	var frontier: Array = _ports(data, 0, profile)
	while data.rooms.size() < count and not frontier.is_empty():
		var index := rng.randi_range(0, frontier.size() - 1)
		var port: Dictionary = frontier[index]
		frontier.remove_at(index)
		if used(data, port.room, port.socket): continue
		var missing := floors - floor_count(data)
		var remaining: int = count - data.rooms.size()
		var stairs_first := missing > 0 and remaining >= 2 and (rng.randf() < 0.2 or remaining <= missing * 2 + 1)
		var previous: int = data.rooms.size()
		if stairs_first: _try_stairs(data, port, profile, rng)
		if previous == data.rooms.size(): _try_ordinary(data, port, profile, rng)
		if previous == data.rooms.size() and not stairs_first and missing > 0 and remaining >= 2:
			_try_stairs(data, port, profile, rng)
		# A failed port has tried every enabled room/socket. Other ports stay live.
		for added in range(previous, data.rooms.size()): frontier.append_array(_ports(data, added, profile))
	_close_loops(data, profile)
	return data

static func floor_count(data: Dictionary) -> int:
	var lowest := 0.0
	for room: Dictionary in data.rooms: lowest = minf(lowest, room.transform.origin.y)
	return 1 + roundi(-lowest / data.floor_spacing)

static func definition(data: Dictionary, index: int, profile: InteriorProfile = PROFILE) -> InteriorRoomDefinition:
	var room: Dictionary = data.rooms[index]
	return profile.room(room.definition, room.content_version)

static func _ports(data: Dictionary, index: int, profile: InteriorProfile) -> Array:
	var result: Array = []
	for socket: String in definition(data, index, profile).describe().sockets:
		if not used(data, index, socket): result.append({"room": index, "socket": socket})
	return result

static func _ordered(profile: InteriorProfile, rng: RandomNumberGenerator, role: StringName) -> Array:
	# Draw group then variant, without replacement. Adding variants preserves group frequency.
	var pools: Dictionary = {}
	for room in profile.rooms:
		if not room.enabled or room.role != role or room.weight <= 0: continue
		var group := str(room.selection_group)
		if role == &"ordinary" and profile.group_weights.get(group, 0.0) <= 0: continue
		if not pools.has(group): pools[group] = []
		pools[group].append(room)
	var result: Array = []
	while not pools.is_empty():
		var groups: Array = pools.keys()
		var weights: Array = []
		for group in groups: weights.append(profile.group_weights.get(group, 1.0))
		var selected: String = groups[_weighted(weights, rng)]
		weights.clear()
		for room: InteriorRoomDefinition in pools[selected]: weights.append(room.weight)
		var index := _weighted(weights, rng)
		result.append(pools[selected][index])
		pools[selected].remove_at(index)
		if pools[selected].is_empty(): pools.erase(selected)
	return result

static func _weighted(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for weight in weights: total += float(weight)
	var pick := rng.randf() * total
	for i in weights.size():
		pick -= float(weights[i])
		if pick < 0: return i
	return weights.size() - 1

static func _placements(data: Dictionary, port: Dictionary, candidate: InteriorRoomDefinition, profile: InteriorProfile) -> Array:
	var source: Dictionary = definition(data, port.room, profile).describe().sockets[port.socket]
	var target: Transform3D = data.rooms[port.room].transform * source.transform
	var result: Array = []
	var info := candidate.describe()
	for name: String in info.sockets:
		var own: Dictionary = info.sockets[name]
		if not _compatible(source, own): continue
		var pose: Transform3D = target * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * own.transform.affine_inverse()
		pose.origin = pose.origin.snapped(Vector3.ONE * 0.001)
		var level: float = -pose.origin.y / data.floor_spacing
		if not is_equal_approx(level, roundf(level)) or level < -0.001 or level > data.target_floors - 1: continue
		var bounds: AABB = pose * info.bounds
		var valid_levels := true
		for socket: Dictionary in info.sockets.values():
			var socket_level: float = -(pose * socket.transform).origin.y / data.floor_spacing
			if absf(socket_level - roundf(socket_level)) > 0.001 or socket_level < -0.001 or socket_level > data.target_floors - 1: valid_levels = false
		if not valid_levels or _overlaps(data, bounds, profile): continue
		result.append({"pose": pose, "socket": name})
	return result

static func _try_ordinary(data: Dictionary, port: Dictionary, profile: InteriorProfile, rng: RandomNumberGenerator) -> bool:
	for candidate: InteriorRoomDefinition in _ordered(profile, rng, &"ordinary"):
		var options := _placements(data, port, candidate, profile)
		if options.is_empty(): continue
		var option: Dictionary = options[rng.randi_range(0, options.size() - 1)]
		var index: int = data.rooms.size()
		_append(data, candidate, option.pose)
		_link(data, port.room, port.socket, index, option.socket)
		return true
	return false

static func _try_stairs(data: Dictionary, port: Dictionary, profile: InteriorProfile, rng: RandomNumberGenerator) -> bool:
	var old_floor_count := floor_count(data)
	for candidate: InteriorRoomDefinition in _ordered(profile, rng, &"stairs"):
		for option: Dictionary in _placements(data, port, candidate, profile):
			if roundi(-option.pose.origin.y / data.floor_spacing) != old_floor_count: continue
			var trial := data.duplicate(true)
			var index: int = trial.rooms.size()
			_append(trial, candidate, option.pose)
			_link(trial, port.room, port.socket, index, option.socket)
			for next: Dictionary in _ports(trial, index, profile):
				var local: Transform3D = candidate.describe().sockets[next.socket].transform
				if not is_zero_approx(local.origin.y): continue
				if _try_ordinary(trial, next, profile, rng):
					data.rooms = trial.rooms
					data.links = trial.links
					data.edges = trial.edges
					return true
	return false

static func _append(data: Dictionary, room: InteriorRoomDefinition, pose: Transform3D) -> void:
	data.rooms.append({"id": "r%03d" % data.rooms.size(), "definition": str(room.id), "content_version": room.content_version, "transform": pose, "connections": []})

static func _link(data: Dictionary, a: int, sa: String, b: int, sb: String) -> void:
	data.links.append({"a": a, "sa": sa, "b": b, "sb": sb})
	data.edges.append(Vector2i(a, b))
	data.rooms[a].connections.append(sa)
	data.rooms[b].connections.append(sb)

static func used(data: Dictionary, index: int, socket: String) -> bool:
	return socket in data.rooms[index].connections

static func _compatible(a: Dictionary, b: Dictionary) -> bool:
	return a.type == b.type and a.opening.is_equal_approx(b.opening)

static func _overlaps(data: Dictionary, bounds: AABB, profile: InteriorProfile) -> bool:
	for i in data.rooms.size():
		var other: AABB = data.rooms[i].transform * definition(data, i, profile).describe().bounds
		if bounds.grow(-0.002).intersects(other.grow(-0.002)): return true
	return false

static func _close_loops(data: Dictionary, profile: InteriorProfile) -> void:
	for a in data.rooms.size():
		var da := definition(data, a, profile).describe()
		for sa: String in da.sockets:
			if used(data, a, sa): continue
			for b in range(a + 1, data.rooms.size()):
				var db := definition(data, b, profile).describe()
				for sb: String in db.sockets:
					if used(data, a, sa) or used(data, b, sb): continue
					if _compatible(da.sockets[sa], db.sockets[sb]) and _aligned(data.rooms[a].transform * da.sockets[sa].transform, data.rooms[b].transform * db.sockets[sb].transform):
						_link(data, a, sa, b, sb)

static func _aligned(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.005 and a.basis.z.dot(b.basis.z) < -0.999 and a.basis.y.dot(b.basis.y) > 0.999

static func distances(data: Dictionary, from := 0) -> Array[float]:
	var result: Array[float] = []
	result.resize(data.rooms.size())
	result.fill(INF)
	result[from] = 0.0
	for iteration in data.rooms.size():
		var changed := false
		for edge: Dictionary in data.links:
			var cost: float = data.rooms[edge.a].transform.origin.distance_to(data.rooms[edge.b].transform.origin)
			for pair in [Vector2i(edge.a, edge.b), Vector2i(edge.b, edge.a)]:
				if result[pair.x] + cost < result[pair.y]:
					result[pair.y] = result[pair.x] + cost
					changed = true
		if not changed: break
	return result

static func validate(value: Variant, profile: InteriorProfile = PROFILE) -> String:
	if not value is Dictionary or not value.has_all(["version", "profile", "seed", "target_rooms", "target_floors", "floor_spacing", "rooms", "links", "edges"]): return "layout fields"
	if value.version != VERSION or value.profile != str(profile.profile_id) or not value.seed is int: return "layout version"
	if not value.target_rooms is int or value.target_rooms < 1 or value.target_rooms > 30 or not value.target_floors is int or value.target_floors < 1 or value.target_floors > 3: return "layout budget"
	if not (value.floor_spacing is float or value.floor_spacing is int) or not is_finite(value.floor_spacing) or value.floor_spacing <= 0: return "floor spacing"
	if not value.rooms is Array or value.rooms.is_empty() or value.rooms.size() > value.target_rooms or not value.links is Array or value.links.size() > 300 or not value.edges is Array: return "layout size"
	var partial := {"rooms": []}
	var connections: Array = []
	for i in value.rooms.size():
		var room: Variant = value.rooms[i]
		if not room is Dictionary or room.get("id") != "r%03d" % i or not room.get("definition") is String or not room.get("content_version") is int: return "room identity"
		var def := profile.room(room.definition, room.content_version)
		if def == null: return "missing room version"
		if (i == 0) != (def.role == &"entry"): return "entry role"
		if not room.get("transform") is Transform3D or not room.transform.is_finite() or not room.get("connections") is Array: return "room transform"
		var pose: Transform3D = room.transform
		if not pose.basis.y.is_equal_approx(Vector3.UP) or not pose.basis.is_equal_approx(Basis(Vector3.UP, roundf(pose.basis.get_euler().y / (PI/2)) * PI/2)): return "room rotation"
		if i == 0 and not pose.is_equal_approx(Transform3D.IDENTITY): return "entry transform"
		var level: float = -pose.origin.y / value.floor_spacing
		if absf(level - roundf(level)) > 0.001 or level < -0.001 or level >= value.target_floors: return "room floor"
		if _overlaps(partial, pose * def.describe().bounds, profile): return "room overlap"
		partial.rooms.append(room)
		connections.append([])
	var edges: Array = []
	for link in value.links:
		if not link is Dictionary or not link.get("a") is int or not link.get("b") is int or not link.get("sa") is String or not link.get("sb") is String: return "link fields"
		if link.a < 0 or link.b <= link.a or link.b >= value.rooms.size(): return "link indices"
		var da := definition(value, link.a, profile).describe()
		var db := definition(value, link.b, profile).describe()
		if not da.sockets.has(link.sa) or not db.sockets.has(link.sb) or link.sa in connections[link.a] or link.sb in connections[link.b]: return "link socket"
		if not _compatible(da.sockets[link.sa], db.sockets[link.sb]) or not _aligned(value.rooms[link.a].transform * da.sockets[link.sa].transform, value.rooms[link.b].transform * db.sockets[link.sb].transform): return "link alignment"
		connections[link.a].append(link.sa)
		connections[link.b].append(link.sb)
		edges.append(Vector2i(link.a, link.b))
	if edges != value.edges: return "edges mismatch"
	for i in value.rooms.size():
		if connections[i] != value.rooms[i].connections: return "connections mismatch"
		if definition(value, i, profile).role == &"stairs" and connections[i].size() < 2: return "unfinished stairs"
	for distance in distances(value):
		if is_inf(distance): return "disconnected room"
	return ""

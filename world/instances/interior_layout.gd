extends RefCounted
class_name InteriorLayout
## Versioned, deterministic room/socket graph. No scene-tree or global RNG effects.
const VERSION := 2
const PROFILE = preload("res://world/instances/catalog/maintenance_v2.tres")

static func generate(seed_value: int, count := 0, profile: InteriorProfile = PROFILE) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Always consume the count draw, including manifest validation with an
	# explicit count. Otherwise a production seed rebuilds different branches.
	var default_count := rng.randi_range(profile.min_rooms, profile.max_rooms)
	if count == 0: count = default_count
	count = clampi(count, 12, 100)
	var result := {"version": VERSION, "content_version": profile.content_version, "profile": str(profile.profile_id), "seed": seed_value, "rooms": [], "links": [], "edges": [], "objective": "r009", "gate": "return_hatch"}
	# A guaranteed two-stair loop. The depot is deep by walking distance, not altitude.
	var positions := [Vector3(0,0,0), Vector3(0,0,-13.5), Vector3(0,0,-31.5), Vector3(0,6,-45), Vector3(9,6,-45), Vector3(18,6,-45), Vector3(27,6,-45), Vector3(27,0,-31.5), Vector3(27,0,-13.5), Vector3(27,0,0), Vector3(18,0,0), Vector3(9,0,0)]
	var types := ["entry", "atrium", "stairs", "junction", "control", "utility", "junction", "stairs", "gallery", "depot", "junction", "junction"]
	for i in positions.size(): _append_room(result, types[i], Transform3D(Basis.IDENTITY, positions[i]), 0 if i < 3 else (1 if i < 8 else 2))
	var sockets := [["north","south"],["north","south"],["north","south"],["east","west"],["east","west"],["east","west"],["south","north"],["south","north"],["south","north"],["west","east"],["west","east"],["west","east"]]
	for i in 12: _link(result, i, sockets[i][0], (i+1)%12, sockets[i][1], "return_hatch" if i == 11 else "")
	var attempts := 0
	while result.rooms.size() < count and attempts < count * 150:
		attempts += 1
		var a := rng.randi_range(0, result.rooms.size()-1)
		var source: Dictionary = result.rooms[a]
		var source_sockets: Dictionary = profile.room(source.definition).describe().sockets
		var names: Array = source_sockets.keys()
		var source_name: String = names[rng.randi_range(0, names.size()-1)]
		if used(result, a, source_name): continue
		var definition := _choose(profile, rng)
		var description := definition.describe()
		var own_names: Array = description.sockets.keys()
		var own_name: String = own_names[rng.randi_range(0, own_names.size()-1)]
		var target_socket: Dictionary = source_sockets[source_name]
		var own_socket: Dictionary = description.sockets[own_name]
		if target_socket.type != own_socket.type or target_socket.opening != own_socket.opening: continue
		var pose: Transform3D = source.transform * target_socket.transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * own_socket.transform.affine_inverse()
		# Snap numerical noise, preserving all socket-defined rotations and offsets.
		pose.origin = pose.origin.snapped(Vector3.ONE * 0.001)
		var bounds: AABB = pose * description.bounds
		if bounds.position.y < -0.01 or bounds.end.y > profile.floor_spacing * profile.floor_count + 0.01: continue
		if _overlaps(result, bounds, profile): continue
		var b: int = result.rooms.size()
		_append_room(result, str(definition.id), pose, source.zone)
		_link(result, a, source_name, b, own_name)
	if result.rooms.size() != count: return {}
	# Close coincident free sockets; never invent a corridor through occupied space.
	for a in result.rooms.size():
		var da: Dictionary = profile.room(result.rooms[a].definition).describe()
		for sa: String in da.sockets:
			if used(result, a, sa): continue
			var ta: Transform3D = result.rooms[a].transform * da.sockets[sa].transform
			for b in range(a+1, result.rooms.size()):
				var db: Dictionary = profile.room(result.rooms[b].definition).describe()
				for sb: String in db.sockets:
					if used(result, b, sb) or used(result, a, sa): continue
					var tb: Transform3D = result.rooms[b].transform * db.sockets[sb].transform
					if ta.origin.distance_to(tb.origin) < 0.01 and ta.basis.z.dot(tb.basis.z) < -0.999 and da.sockets[sa].opening == db.sockets[sb].opening:
						# Optional cycles stay within a route zone so the hatch matters.
						if result.rooms[a].zone != result.rooms[b].zone: continue
						_link(result, a, sa, b, sb)
	return result

static func _choose(profile: InteriorProfile, rng: RandomNumberGenerator) -> InteriorRoomDefinition:
	var total := 0.0
	for definition in profile.rooms: total += definition.weight
	var pick := rng.randf() * total
	for definition in profile.rooms:
		pick -= definition.weight
		if pick < 0: return definition
	return profile.rooms[-1]

static func _append_room(result: Dictionary, definition: String, pose: Transform3D, zone: int) -> void:
	result.rooms.append({"id": "r%03d" % result.rooms.size(), "definition": definition, "transform": pose, "zone": zone, "connections": []})

static func _link(result: Dictionary, a: int, sa: String, b: int, sb: String, gate := "") -> void:
	result.links.append({"a": a, "sa": sa, "b": b, "sb": sb, "gate": gate})
	result.edges.append(Vector2i(a,b))
	result.rooms[a].connections.append(sa)
	result.rooms[b].connections.append(sb)

static func used(data: Dictionary, index: int, socket: String) -> bool:
	return socket in data.rooms[index].connections

static func _overlaps(data: Dictionary, bounds: AABB, profile: InteriorProfile) -> bool:
	var inner := bounds.grow(-0.01)
	for room: Dictionary in data.rooms:
		var other: AABB = room.transform * profile.room(room.definition).describe().bounds
		if inner.intersects(other.grow(-0.01)): return true
	return false

static func distances(data: Dictionary, gate_open := false, from := 0) -> Array[float]:
	var distances: Array[float] = []
	distances.resize(data.rooms.size())
	distances.fill(INF)
	distances[from] = 0.0
	for iteration in data.rooms.size():
		var changed := false
		for edge: Dictionary in data.links:
			if not gate_open and not edge.gate.is_empty(): continue
			var pa: Vector3 = data.rooms[edge.a].transform.origin
			var pb: Vector3 = data.rooms[edge.b].transform.origin
			var cost := pa.distance_to(pb)
			# Stair room centre represents the middle of its physical ramp.
			if data.rooms[edge.a].definition == "stairs" or data.rooms[edge.b].definition == "stairs": cost += 3.0
			if distances[edge.a] + cost < distances[edge.b]:
				distances[edge.b] = distances[edge.a] + cost
				changed = true
			if distances[edge.b] + cost < distances[edge.a]:
				distances[edge.a] = distances[edge.b] + cost
				changed = true
		if not changed: break
	return distances

static func validate(value: Variant, profile: InteriorProfile = PROFILE) -> String:
	if not value is Dictionary or not value.has_all(["version","content_version","profile","seed","rooms","links","edges","objective","gate"]): return "layout fields"
	if value.version != VERSION or value.content_version != profile.content_version or value.profile != str(profile.profile_id) or not value.seed is int: return "layout version"
	if not value.rooms is Array or value.rooms.size() < 12 or value.rooms.size() > 100 or not value.links is Array or value.links.size() > 400: return "layout size"
	for i in value.rooms.size():
		var room: Variant = value.rooms[i]
		if not room is Dictionary or room.get("id") != "r%03d" % i or not room.get("definition") is String or profile.room(room.definition) == null: return "room identity"
		if not room.get("transform") is Transform3D or not room.transform.is_finite(): return "room transform"
	# Reproduction verifies sockets, bounds, connectivity, catalog and exact version.
	# Saved manifest is still consumed on restore; never accept geometry drift.
	var expected := generate(value.seed, value.rooms.size(), profile)
	if expected != value: return "layout differs from pinned generator/content"
	return ""

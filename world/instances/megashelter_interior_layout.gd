extends RefCounted
class_name MegashelterInteriorLayout
## Small public shelter: reception -> common hall -> short service spine.
## Counts stay small; room sizes, rather than a maze, follow the exterior footprint.
static func generate(seed_value: int, exterior_area: float, profile: InteriorProfile) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("megashelter-interior:v1:%d" % seed_value).hash()
	var large := exterior_area >= 1400.0
	var suffix := "_large" if large else ""
	var count := clampi(3 + floori((exterior_area - 800.0) / 400.0), 3, 5)
	var data := {"version": InteriorLayout.VERSION, "profile": str(profile.profile_id), "seed": seed_value,
		"target_rooms": count + 3, "target_floors": 1, "floor_spacing": profile.floor_spacing,
		"rooms": [], "links": [], "edges": []}
	InteriorLayout._append(data, profile.room("reception"), Transform3D.IDENTITY)
	if not _attach(data, {"room": 0, "socket": "north"}, profile.room("common_hall" + suffix), "south", profile): return {}
	if not _attach(data, {"room": 1, "socket": "north"}, profile.room("service_spine"), "south", profile): return {}
	var functions := ["sleeping", "medical", "storage", "canteen", "services", "sanitary"]
	for i in range(functions.size() - 1, 0, -1):
		var pick := rng.randi_range(0, i)
		var swap: String = functions[i]
		functions[i] = functions[pick]
		functions[pick] = swap
	for i in count:
		var room := profile.room(functions[i] + suffix)
		var ports: Array = []
		# Public hall/service corridor branches first; rooms only extend a branch
		# when the wider module would overlap an existing wing.
		for index in range(1, data.rooms.size()): ports.append_array(InteriorLayout._ports(data, index, profile))
		var attached := false
		while not ports.is_empty():
			var end := 0
			while end < ports.size() and int(ports[end].room) <= 2: end += 1
			var pick := rng.randi_range(0, (end if end > 0 else ports.size()) - 1)
			var port: Dictionary = ports.pop_at(pick)
			var options := InteriorLayout._placements(data, port, room, profile)
			if options.is_empty(): continue
			var option: Dictionary = options[rng.randi_range(0, options.size() - 1)]
			var index: int = data.rooms.size()
			InteriorLayout._append(data, room, option.pose)
			InteriorLayout._link(data, port.room, port.socket, index, option.socket)
			attached = true
			break
		if not attached: return {}
	InteriorLayout._close_loops(data, profile)
	return data

static func _attach(data: Dictionary, port: Dictionary, room: InteriorRoomDefinition, socket: String, profile: InteriorProfile) -> bool:
	for option: Dictionary in InteriorLayout._placements(data, port, room, profile):
		if option.socket != socket: continue
		var index: int = data.rooms.size()
		InteriorLayout._append(data, room, option.pose)
		InteriorLayout._link(data, port.room, port.socket, index, socket)
		return true
	return false

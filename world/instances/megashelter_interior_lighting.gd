extends RefCounted
class_name MegashelterInteriorLighting
## Failed circuits are stable per saved room; entry and circulation stay lit.
const DARK_FRACTION := 0.5
const AMBIENT_ENERGY := BunkerLighting.AMBIENT_ENERGY

static func dark_room_ids(layout: Dictionary, profile: InteriorProfile) -> Array[String]:
	var candidates: Array[Dictionary] = []
	for room: Dictionary in layout.rooms:
		var definition := profile.room(room.definition, room.content_version)
		if definition == null or definition.role != &"ordinary" or definition.selection_group in [&"hall", &"passage", &"corridor"]: continue
		var rank := ("megashelter-lights-v1:%d:%s" % [int(layout.seed), room.id]).sha256_text()
		candidates.append({"id": str(room.id), "rank": rank})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.id < b.id if a.rank == b.rank else a.rank < b.rank)
	var result: Array[String] = []
	for i in roundi(candidates.size() * DARK_FRACTION): result.append(candidates[i].id)
	return result

static func apply(room: PoiRoom, definition: InteriorRoomDefinition, dark: bool) -> void:
	BunkerLighting.apply(room, definition, dark)
	room.set_meta("megashelter_dark", dark)

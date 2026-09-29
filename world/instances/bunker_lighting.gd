extends RefCounted
class_name BunkerLighting
## Version-2 room presentation. Keep this ranking stable for saved layouts.
const DARK_FRACTION := 0.6
const AMBIENT_ENERGY := 0.04
const LEGACY_AMBIENT_ENERGY := 0.22
const OFF_MATERIAL: Material = preload("res://world/poi_kit/materials/bunker/lamp_off.tres")

static func is_abandoned(layout: Dictionary) -> bool:
	return layout.rooms.any(func(room: Dictionary) -> bool: return room.content_version >= 2)

static func dark_room_ids(layout: Dictionary, profile: InteriorProfile = InteriorLayout.PROFILE) -> Array[String]:
	var candidates: Array[Dictionary] = []
	for room: Dictionary in layout.rooms:
		var definition := profile.room(room.definition, room.content_version)
		if room.content_version < 2 or definition == null or definition.role != &"ordinary": continue
		# Per-room ranking uses no layout/content/global RNG and survives tree order changes.
		var rank := ("bunker-lights-v1:%d:%s" % [int(layout.seed), room.id]).sha256_text()
		candidates.append({"id": str(room.id), "rank": rank})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.id < b.id if a.rank == b.rank else a.rank < b.rank)
	var result: Array[String] = []
	for i in roundi(candidates.size() * DARK_FRACTION): result.append(candidates[i].id)
	return result

static func apply(room: PoiRoom, definition: InteriorRoomDefinition, dark: bool) -> void:
	# Legacy instances keep their original lights and emissive materials.
	if definition.content_version < 2: return
	room.set_meta("bunker_dark", dark)
	for child in room.find_children("*", "Light3D", true, false):
		var light := child as Light3D
		light.visible = not dark
		light.shadow_enabled = true
		light.shadow_bias = 0.05
		light.distance_fade_enabled = true
		light.distance_fade_begin = 32.0
		light.distance_fade_length = 8.0
		if light is OmniLight3D:
			light.omni_range = minf(light.omni_range, 7.5)
	for child in room.find_children("LampTube*", "MeshInstance3D", true, false):
		if dark: child.material_override = OFF_MATERIAL

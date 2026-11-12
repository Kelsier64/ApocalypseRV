extends RefCounted
class_name InteriorProfiles
## Resolve only registered profiles; saved data cannot select arbitrary resources.
const BUNKER: InteriorProfile = preload("res://world/instances/catalog/bunker.tres")
const STAIR_DESTINATIONS := {
	&"bunker": {"weight": 75, "suffix": ":bunker", "title": "BUNKER"},
	&"bunker_dark_column_hall": {"weight": 25, "suffix": ":column-hall", "title": "COLUMN HALL"},
}

static func get_profile(id: StringName) -> InteriorProfile:
	match id:
		&"bunker": return BUNKER
		&"megashelter": return load("res://world/instances/catalog/megashelter.tres") as InteriorProfile
		&"megashelter_stairwell": return load("res://world/instances/catalog/megashelter_stairwell.tres") as InteriorProfile
		&"bunker_stairwell": return load("res://world/instances/catalog/bunker_stairwell.tres") as InteriorProfile
		&"bunker_dark_column_hall": return load("res://world/instances/catalog/bunker_dark_column_hall.tres") as InteriorProfile
	return null

static func is_passive(id: StringName) -> bool:
	return is_stairwell(id) or id == &"bunker_dark_column_hall"

static func is_stairwell(id: StringName) -> bool:
	return id in [&"megashelter_stairwell", &"bunker_stairwell"]

static func roll_stair_destination(seed_value: int) -> StringName:
	var total := 0
	for entry: Dictionary in STAIR_DESTINATIONS.values():
		total += entry.weight
	var roll := ("stair-destination:v1:%d" % seed_value).sha256_text().substr(0, 15).hex_to_int() % total
	for destination: StringName in STAIR_DESTINATIONS:
		roll -= STAIR_DESTINATIONS[destination].weight
		if roll < 0: return destination
	return &""

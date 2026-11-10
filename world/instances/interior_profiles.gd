extends RefCounted
class_name InteriorProfiles
## Resolve only registered profiles; saved data cannot select arbitrary resources.
const BUNKER: InteriorProfile = preload("res://world/instances/catalog/bunker.tres")

static func get_profile(id: StringName) -> InteriorProfile:
	match id:
		&"bunker": return BUNKER
		&"megashelter": return load("res://world/instances/catalog/megashelter.tres") as InteriorProfile
		&"megashelter_stairwell": return load("res://world/instances/catalog/megashelter_stairwell.tres") as InteriorProfile
		&"bunker_stairwell": return load("res://world/instances/catalog/bunker_stairwell.tres") as InteriorProfile
		&"bunker_dark_column_hall": return load("res://world/instances/catalog/bunker_dark_column_hall.tres") as InteriorProfile
	return null

static func is_passive(id: StringName) -> bool:
	return id in [&"megashelter_stairwell", &"bunker_stairwell", &"bunker_dark_column_hall"]

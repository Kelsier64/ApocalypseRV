extends RefCounted
class_name POIConfig

## Order is part of generation v3/v4 compatibility. Never insert walk-in assets here.
const GENERATION_IDS := ["maintenance", "warehouse", "pump", "research"]
const DEFINITIONS = [
	preload("res://world/poi_definitions/maintenance_legacy.tres"),
	preload("res://world/poi_definitions/maintenance.tres"),
	preload("res://world/poi_definitions/warehouse.tres"),
	preload("res://world/poi_definitions/pump.tres"),
	preload("res://world/poi_definitions/research.tres"),
	preload("res://world/poi_definitions/gas_station.tres"),
]

static func definition(id: StringName) -> PoiDefinition:
	for entry: PoiDefinition in DEFINITIONS:
		if entry.definition_id == id: return entry
	return null

static func definition_for_site(site: Dictionary) -> PoiDefinition:
	# Missing exterior is the existing v2 route; unknown explicit IDs never fall back.
	return definition(StringName(site.get("definition_id", site.get("exterior", "maintenance_legacy"))))

static func instance_titles() -> Array[String]:
	var result: Array[String] = []
	for id in GENERATION_IDS: result.append(definition(id).display_name)
	return result

static func scene_for_site(site: Dictionary) -> PackedScene:
	var entry := definition_for_site(site)
	if entry == null: return null
	return load(entry.scene_path) as PackedScene

static func supported_interior(profile: StringName) -> bool:
	return profile == &"maintenance_maze_v1"

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
	preload("res://world/poi_definitions/starting_shelter.tres"),
	preload("res://world/poi_definitions/roadside_wreck_0.tres"),
	preload("res://world/poi_definitions/roadside_wreck_1.tres"),
	preload("res://world/poi_definitions/roadside_wreck_2.tres"),
	preload("res://world/poi_definitions/roadside_camp_0.tres"),
	preload("res://world/poi_definitions/roadside_camp_1.tres"),
	preload("res://world/poi_definitions/roadside_camp_2.tres"),
	preload("res://world/poi_definitions/roadside_shed_0.tres"),
	preload("res://world/poi_definitions/roadside_shed_1.tres"),
	preload("res://world/poi_definitions/roadside_shed_2.tres"),
	preload("res://world/poi_definitions/roadside_checkpoint_0.tres"),
	preload("res://world/poi_definitions/roadside_checkpoint_1.tres"),
	preload("res://world/poi_definitions/roadside_checkpoint_2.tres"),
	preload("res://world/poi_definitions/roadside_cargo_0.tres"),
	preload("res://world/poi_definitions/roadside_cargo_1.tres"),
	preload("res://world/poi_definitions/roadside_cargo_2.tres"),
	preload("res://world/poi_definitions/roadside_rest_0.tres"),
	preload("res://world/poi_definitions/roadside_rest_1.tres"),
	preload("res://world/poi_definitions/roadside_rest_2.tres"),
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
	return profile == &"bunker"

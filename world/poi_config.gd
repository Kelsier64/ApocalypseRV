extends RefCounted
class_name POIConfig

## Stable random selection order for the current instance entrances.
const GENERATION_IDS := ["maintenance", "warehouse", "pump", "research"]
const DEFINITIONS = [
	preload("res://world/poi_definitions/maintenance.tres"),
	preload("res://world/poi_definitions/warehouse.tres"),
	preload("res://world/poi_definitions/pump.tres"),
	preload("res://world/poi_definitions/research.tres"),
	preload("res://world/poi_definitions/gas_station.tres"),
	preload("res://world/poi_definitions/starting_shelter.tres"),
	preload("res://world/poi_definitions/orientation_shelter.tres"),
	preload("res://world/poi_definitions/civilian_shelter.tres"),
	preload("res://world/poi_definitions/courtyard_shelter.tres"),
	preload("res://world/poi_definitions/modular_megashelter.tres"),
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
	return definition(StringName(site.get("definition_id", site.get("exterior", ""))))

static func instance_titles() -> Array[String]:
	var result: Array[String] = []
	for id in GENERATION_IDS: result.append(definition(id).display_name)
	return result

static func scene_for_site(site: Dictionary) -> PackedScene:
	var entry := definition_for_site(site)
	if entry == null: return null
	return load(entry.scene_path) as PackedScene

## Build the same exterior for live physics and neighbouring navigation geometry.
static func instantiate_site(site: Dictionary, include_visuals := true) -> Node3D:
	var scene := scene_for_site(site)
	if scene == null: return null
	var instance := scene.instantiate()
	var building := instance as Node3D
	if building == null:
		instance.free()
		return null
	if site.get("definition_id", "") == "modular_megashelter":
		var plan: Dictionary = site.get("exterior_plan", {})
		if plan.is_empty(): plan = MegashelterPlan.generate(int(site.seed))
		building.call("configure_exterior", plan, include_visuals)
		building.set_meta("navigation_solid_geometry", true)
	return building

static func supported_interior(profile: StringName) -> bool:
	return profile == &"bunker"

extends RefCounted
class_name FoodCatalog

const SCENES := [
	"res://props/food/canned_food.tscn",
	"res://props/food/energy_bar.tscn",
	"res://props/food/beef_jerky.tscn",
]
const DEFINITIONS := {
	"res://props/food/canned_food.tscn": preload("res://props/food/canned_food.tres"),
	"res://props/food/energy_bar.tscn": preload("res://props/food/energy_bar.tres"),
	"res://props/food/beef_jerky.tscn": preload("res://props/food/beef_jerky.tres"),
}

static func definition_for(scene_path: String) -> FoodDefinition:
	return DEFINITIONS.get(scene_path) as FoodDefinition

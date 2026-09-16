extends RefCounted
class_name RecipeCatalog

static func all() -> Array[RecipeDefinition]:
	return [preload("res://equipment/engine_standard_recipe.tres"), preload("res://equipment/engine_upgraded_recipe.tres"), preload("res://equipment/engine_repair_kit_recipe.tres"), preload("res://equipment/gasoline_recipe.tres"), preload("res://equipment/battery_recipe.tres"), preload("res://equipment/battery_large_recipe.tres"), preload("res://equipment/wheel_recipe.tres")]

static func find(id: String) -> RecipeDefinition:
	for recipe in all():
		if recipe.recipe_id == id or recipe.display_name == id:
			return recipe
	return null

static func display_data() -> Dictionary:
	var result := {}
	for recipe in all():
		result[recipe.display_name] = {"id": recipe.recipe_id, "scene": recipe.scene_path, "costs": recipe.costs, "power": recipe.power_cost}
	return result

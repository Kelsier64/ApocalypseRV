extends Resource
class_name RecipeDefinition

@export var recipe_id: String = "gasoline"
@export var display_name: String = "Gasoline Can"
@export var scene_path: String = "res://props/gas_can.tscn"
@export var costs: Dictionary = {"Unrefined Fuel": 5, "Metal Parts": 2}
@export var duration: float = 2.0
@export var power_cost: float = 0.6

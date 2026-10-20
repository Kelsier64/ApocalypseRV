extends "res://world/main_world.gd"
## Latest outdoor generation and the old garage, with `cheat true` defaults.

func _ready() -> void:
	super._ready()
	var rv: Chassis = get_node("NewRv/Chassis")
	rv.unlimited_fuel = true
	rv.unlimited_power = true
	rv.unlimited_materials = true

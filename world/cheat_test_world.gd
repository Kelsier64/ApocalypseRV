extends "res://world/main_world.gd"
## Latest outdoor generation and the old garage, with `cheat true` defaults.

func configure_tutorial_course() -> void:
	# This scene intentionally has no tutorial controller.
	pass

func _ready() -> void:
	super._ready()
	var rv: Chassis = get_node("NewRv/Chassis")
	rv.unlimited_fuel = true
	rv.unlimited_power = true
	rv.unlimited_materials = true

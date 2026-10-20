extends "res://world/main_world.gd"
## Disposable v10 garage world with the same defaults as `cheat true`.

func configure_tutorial_course() -> void:
	# This scene intentionally has no tutorial controller.
	pass

func _ready() -> void:
	super._ready()
	var rv: Chassis = get_node("NewRv/Chassis")
	rv.unlimited_fuel = true
	rv.unlimited_power = true
	rv.unlimited_materials = true

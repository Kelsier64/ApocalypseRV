extends "res://tests/test_moving_rv_climbing.gd"
## Retired duplicate suite: the base already defaults to this same Raker fixture.
## Keep this historical entry point directly runnable; select the base in suites.

func _init() -> void:
	monster_scene = preload("res://enemies/raker.tscn")
	super._init()

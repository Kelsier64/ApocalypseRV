extends "res://tests/test_moving_rv_climbing.gd"

func _init() -> void:
	monster_scene = preload("res://enemies/raker.tscn")
	super._init()

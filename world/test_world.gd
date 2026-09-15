extends Node3D

func _enter_tree() -> void:
	Checkpoint.prepare_world(self)

func _ready() -> void:
	Checkpoint.restore_world(self)

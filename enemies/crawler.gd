extends Monster
class_name Crawler
## Raker-derived quadruped; its low stance has independent gameplay and visuals.

func _ready() -> void:
	super._ready()
	stagger_amount = 0.0
	nav_agent.path_height_offset = 0.75

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_body_mesh.rotation = Vector3.ZERO

extends "res://world/world_generator.gd"
## Isolate real cleanup policy without the production generator's startup work.
func _ready() -> void: set_process(false)

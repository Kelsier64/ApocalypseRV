class_name SoundLoop
extends AudioStreamPlayer3D
## A continuous source its owner drives every frame with a level and a pitch.
## It starts at a random point of its loop from its own RNG, so several copies
## never play in phase, and it stops while the level is inaudible.

const SILENT_LEVEL := 0.003

## Volume at level 1.
@export var base_db := 0.0
## When true, each set_level routes the loop to Cabin or Exterior from where it
## is, like a SoundEvent; for sources that move in and out of the RV.
@export var occlusion_by_position := false

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## level is linear amplitude relative to base_db; 0 stops the loop.
func set_level(level: float, pitch := 1.0) -> void:
	if level < SILENT_LEVEL:
		if playing: stop()
		return
	# By path, as elsewhere: autoload names do not resolve in preloaded test scripts.
	if occlusion_by_position and is_inside_tree():
		bus = get_node("/root/Sfx").bus_at(global_position, get_world_3d())
	volume_db = base_db + linear_to_db(level)
	pitch_scale = pitch
	if not playing: play(_rng.randf() * stream.get_length())

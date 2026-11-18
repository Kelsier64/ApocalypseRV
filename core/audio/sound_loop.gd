class_name SoundLoop
extends AudioStreamPlayer3D
## A continuous source its owner drives every frame with a level and a pitch.
## It starts at a random point of its loop from its own RNG, so several copies
## never play in phase, and it stops while the level is inaudible.

const SILENT_LEVEL := 0.003

## Volume at level 1.
@export var base_db := 0.0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## level is linear amplitude relative to base_db; 0 stops the loop.
func set_level(level: float, pitch := 1.0) -> void:
	if level < SILENT_LEVEL:
		if playing: stop()
		return
	volume_db = base_db + linear_to_db(level)
	pitch_scale = pitch
	if not playing: play(_rng.randf() * stream.get_length())

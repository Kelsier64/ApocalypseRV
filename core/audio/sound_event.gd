class_name SoundEvent
extends Resource
## Spatial one-shots draw samples and pitch from the audio service's own RNG.

@export var samples: Array[AudioStream] = []
@export var bus: StringName = &"Effects"
@export var volume_db := -10.0
@export_range(0.0, 0.5) var pitch_variation := 0.0
@export_range(0.1, 100.0) var unit_size := 2.0
@export_range(1.0, 1000.0) var max_distance := 18.0

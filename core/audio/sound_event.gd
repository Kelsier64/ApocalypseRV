class_name SoundEvent
extends Resource
## Spatial one-shots draw samples and pitch from the audio service's own RNG.

@export var samples: Array[AudioStream] = []
@export var bus: StringName = &"Effects"
## When true, Sfx routes the event to Cabin or Exterior from where it plays and
## ignores bus. Turn it off for sounds with a fixed perspective, such as a door
## leaf that is heard the same from both sides.
@export var occlusion_by_position := true
@export var volume_db := -10.0
@export_range(0.0, 0.5) var pitch_variation := 0.0
@export var attenuation: SoundAttenuation = preload("res://assets/audio/attenuation/near.tres")
## A repeat of the same event inside this window is skipped, so bursts of
## contacts cannot fill the voice pool.
@export_range(0.0, 2.0) var cooldown_seconds := 0.0

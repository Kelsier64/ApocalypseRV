class_name SoundAttenuation
extends Resource
## Distance falloff shared by every sound of one kind. Presets live in
## assets/audio/attenuation/: near for hand-sized actions, vehicle for the RV and
## mounted equipment, loud for gunshots and explosions, distant for ambience heard
## from tens of metres away.

@export_range(0.1, 100.0) var unit_size := 2.0
@export_range(1.0, 1000.0) var max_distance := 18.0


func apply(player: AudioStreamPlayer3D) -> void:
	player.unit_size = unit_size
	player.max_distance = max_distance

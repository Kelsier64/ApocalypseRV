class_name MonsterFootfalls
extends RefCounted
## Turns the playback phase of a gait clip into footfalls, so steps land on the
## visible plants. plants maps a clip name to [phase, foot] pairs, phase 0 to 1
## through the clip; tests recompute the phases from the clips.

var plants: Dictionary
var _clip := &""
var _phase := 0.0


func _init(table: Dictionary) -> void:
	plants = table


## Feet that planted since the last call, for a cycle played either way. A
## changed clip starts over without a step.
func advance(clip: StringName, phase: float) -> Array[int]:
	var feet: Array[int] = []
	var previous := _phase
	var same_clip := clip == _clip
	_clip = clip
	_phase = phase
	if not same_clip or not plants.has(clip): return feet
	var moved := fposmod(phase - previous, 1.0)
	# Less than half a cycle backwards reads as walking backwards.
	var backwards := moved > 0.5
	var start := phase if backwards else previous
	if backwards: moved = 1.0 - moved
	for entry: Array in plants[clip]:
		var ahead := fposmod(float(entry[0]) - start, 1.0)
		if (ahead > 0.0 and ahead <= moved) if not backwards else (ahead >= 0.0 and ahead < moved):
			feet.append(int(entry[1]))
	return feet


## Phase of the clip an AnimationPlayer is playing, 0 to 1.
static func player_phase(player: AnimationPlayer) -> float:
	if player == null or player.current_animation_length <= 0.0: return 0.0
	return fposmod(player.current_animation_position / player.current_animation_length, 1.0)

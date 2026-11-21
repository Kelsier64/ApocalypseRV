extends RefCounted
## Helpers for checking monster sounds: which pooled one-shots are playing, and
## where a gait clip's feet actually land, read back from the clip itself.


## Pooled Sfx voices now playing a sample of event.
static func playing(sfx: Node, event: SoundEvent) -> int:
	var count := 0
	for voice: AudioStreamPlayer3D in sfx._voices:
		if voice.playing and voice.stream in event.samples: count += 1
	return count


static func stop_all(sfx: Node) -> void:
	for voice: AudioStreamPlayer3D in sfx._voices + sfx._echoes: voice.stop()


## Phases, 0 to 1, where bone first drops into the lowest 15% of its height
## range over the clip: the plant of that foot.
static func plant_phases(actor: Node, clip: String, bone: String, samples := 96) -> Array[float]:
	var skeleton: Skeleton3D = null
	for node in actor.find_children("*", "Skeleton3D", true, false):
		skeleton = node
		break
	var player: AnimationPlayer = null
	for node: AnimationPlayer in actor.find_children("*", "AnimationPlayer", true, false):
		if node.has_animation(clip):
			player = node
			break
	var phases: Array[float] = []
	if skeleton == null or player == null: return phases
	var mode := player.callback_mode_process
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var length := player.get_animation(clip).length
	var index := skeleton.find_bone(bone)
	player.play(clip, 0.0)
	var heights := PackedFloat32Array()
	for i in samples:
		player.seek(length * i / samples, true)
		player.advance(0.0)
		heights.append(skeleton.get_bone_global_pose(index).origin.y)
	player.callback_mode_process = mode
	var low := heights[0]
	var high := heights[0]
	for height in heights:
		low = minf(low, height)
		high = maxf(high, height)
	var plant := low + (high - low) * 0.15
	for i in samples:
		if heights[i] <= plant and heights[(i - 1 + samples) % samples] > plant:
			phases.append(float(i) / samples)
	return phases

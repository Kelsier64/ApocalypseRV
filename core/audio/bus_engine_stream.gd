class_name BusEngineStream
extends AudioStreamSynchronized
## Equal-length loops share a crank angle at every sample index. Godot mixes
## them on the audio thread at one playback speed, even during gear changes.

const BANK := preload("res://assets/audio/rv/bus_i6.wav")
const RPMS := [750.0, 1000.0, 1350.0, 1750.0, 2200.0, 2700.0, 3150.0, 3600.0]
const PEDALS := [0.0, 0.45, 1.0]
const FRAMES_PER_CYCLE := 2048
static var _loops: Array[AudioStreamWAV] = []


func _init() -> void:
	stream_count = RPMS.size() * PEDALS.size()
	if _loops.is_empty():
		var pcm := BANK.data
		@warning_ignore("integer_division")
		var bytes_per_loop := pcm.size() / stream_count
		for i in range(stream_count):
			var loop := AudioStreamWAV.new()
			loop.format = AudioStreamWAV.FORMAT_16_BITS
			loop.mix_rate = BANK.mix_rate
			loop.data = pcm.slice(i * bytes_per_loop, (i + 1) * bytes_per_loop)
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			@warning_ignore("integer_division")
			loop.loop_end = bytes_per_loop / 2
			_loops.append(loop)
	for i in range(stream_count):
		set_sync_stream(i, _loops[i])
	set_operating_point(RPMS.front(), 0.0)


static func pitch_for(rpm: float) -> float:
	return rpm / 120.0 * FRAMES_PER_CYCLE / BANK.mix_rate


func set_operating_point(rpm: float, pedal: float) -> void:
	var band := clampi(RPMS.bsearch(rpm) - 1, 0, RPMS.size() - 2)
	var row := clampi(PEDALS.bsearch(pedal) - 1, 0, PEDALS.size() - 2)
	var rpm_mix := clampf(inverse_lerp(RPMS[band], RPMS[band + 1], rpm), 0.0, 1.0)
	var load_mix := clampf(inverse_lerp(PEDALS[row], PEDALS[row + 1], pedal), 0.0, 1.0)
	for y in range(PEDALS.size()):
		var load_weight := maxf(0.0, 1.0 - absf(y - (row + load_mix)))
		for x in range(RPMS.size()):
			var rpm_weight := maxf(0.0, 1.0 - absf(x - (band + rpm_mix)))
			set_sync_stream_volume(y * RPMS.size() + x, linear_to_db(load_weight * rpm_weight))

class_name EngineGrainSynth
extends RefCounted
## Places recorded firing grains back to back at a requested firing rate.
## Runs of consecutive grains from the recording are kept while they fit, so the
## cylinder-to-cylinder unevenness of the source survives. Uses its own RNG.

## Grains whose native rate lies within this ratio are eligible without a jump.
const MATCH_TOLERANCE := 0.05
## A run continues while its next grain stays within this ratio of the target.
const FOLLOW_TOLERANCE := 0.07
const MAX_RESAMPLE := 0.25
## Throttle hysteresis between the coasting and the pulling grains.
const PULL_ON := 0.55
const PULL_OFF := 0.3

var bank: EngineGrainBank
var rng := RandomNumberGenerator.new()
var grains_started := 0
var pulling := false

var _pcm: PackedFloat32Array
var _idle_hz := 0.0
var _voice_grain := PackedInt32Array()
var _voice_pos := PackedFloat32Array()
var _voice_rate := PackedFloat32Array()
var _last_grain := -1


func _init(grain_bank: EngineGrainBank) -> void:
	bank = grain_bank
	_pcm = bank.pcm()
	var steady := 0
	for i in range(bank.size()):
		if bank.kinds[i] == EngineGrainBank.Kind.STEADY:
			_idle_hz += bank.firing_hz[i]
			steady += 1
	_idle_hz = _idle_hz / steady if steady > 0 else bank.min_hz()


## Firing rate of the recorded idle.
func idle_hz() -> float:
	return _idle_hz


func reset() -> void:
	_voice_grain.clear()
	_voice_pos.clear()
	_voice_rate.clear()
	_last_grain = -1


## Renders frames of mono audio while the firing rate glides from its last value
## to target_hz. throttle is 0 when coasting and 1 at full load.
func render(frames: int, start_hz: float, target_hz: float, throttle: float) -> PackedFloat32Array:
	if throttle > PULL_ON: pulling = true
	elif throttle < PULL_OFF: pulling = false
	var out := PackedFloat32Array()
	out.resize(frames)
	if _voice_grain.is_empty():
		_start_grain(start_hz, 0.0)
	var t := 0
	while t < frames:
		var newest := _voice_grain.size() - 1
		var period := float(bank.periods[_voice_grain[newest]])
		var until_next := ceili((period - _voice_pos[newest]) / _voice_rate[newest])
		var count := clampi(until_next, 0, frames - t)
		for voice in range(_voice_grain.size()):
			_mix_voice(voice, out, t, count)
		t += count
		if t < frames or until_next == count:
			# Carry the overshoot past the boundary over in output samples.
			var overshoot := maxf(0.0, _voice_pos[newest] - period) / _voice_rate[newest]
			_start_grain(lerpf(start_hz, target_hz, float(t) / frames), overshoot)
		_drop_finished()
	return out


func _mix_voice(voice: int, out: PackedFloat32Array, from: int, count: int) -> void:
	var grain := _voice_grain[voice]
	var base := bank.starts[grain]
	var end := float(bank.lengths[grain] - 1)
	var pos := _voice_pos[voice]
	var rate := _voice_rate[voice]
	for j in range(from, from + count):
		if pos >= end: break
		var index := int(pos)
		var a := _pcm[base + index]
		out[j] += a + (_pcm[base + index + 1] - a) * (pos - index)
		pos += rate
	_voice_pos[voice] = pos


func _start_grain(hz: float, offset_frames: float) -> void:
	var grain := _choose(hz)
	var rate := clampf(hz / bank.firing_hz[grain], 1.0 - MAX_RESAMPLE, 1.0 + MAX_RESAMPLE)
	_voice_grain.append(grain)
	_voice_pos.append(offset_frames * rate)
	_voice_rate.append(rate)
	_last_grain = grain
	grains_started += 1


func _choose(hz: float) -> int:
	var kind := EngineGrainBank.Kind.RISING if pulling else EngineGrainBank.Kind.FALLING
	if _last_grain >= 0:
		var next := bank.follows[_last_grain]
		if next >= 0 and absf(bank.firing_hz[next] / hz - 1.0) < FOLLOW_TOLERANCE \
				and _fits(bank.kinds[next], kind, hz):
			return next
	var options := bank.candidates(hz, MATCH_TOLERANCE)
	var fitting := PackedInt32Array()
	for grain in options:
		if _fits(bank.kinds[grain], kind, hz): fitting.append(grain)
	if fitting.is_empty(): fitting = options
	return fitting[rng.randi_range(0, fitting.size() - 1)]


func _fits(grain_kind: int, wanted: int, hz: float) -> bool:
	# Near idle the steady recording is the natural choice in either direction.
	if hz < _idle_hz * 1.15: return grain_kind == EngineGrainBank.Kind.STEADY or grain_kind == wanted
	return grain_kind == wanted


func _drop_finished() -> void:
	for voice in range(_voice_grain.size() - 2, -1, -1):
		if _voice_pos[voice] >= bank.lengths[_voice_grain[voice]] - 1:
			_voice_grain.remove_at(voice)
			_voice_pos.remove_at(voice)
			_voice_rate.remove_at(voice)

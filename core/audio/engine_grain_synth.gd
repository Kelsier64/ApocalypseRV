class_name EngineGrainSynth
extends RefCounted
## Places recorded firing grains back to back at a requested firing rate.
## The recording is followed grain by grain while it stays near the requested
## rate. Where it drifts away, the next grain is the closest match in level,
## brightness, rate and cylinder among a few random picks that were not played
## recently, so splices stay smooth without repeating. Uses its own RNG.

## Grains whose native rate lies within this ratio are eligible for a jump.
const MATCH_TOLERANCE := 0.05
## The recording keeps playing while its next grain stays within this ratio.
const FOLLOW_TOLERANCE := 0.05
const MAX_RESAMPLE := 0.25
## Throttle hysteresis between the coasting and the pulling grains.
const PULL_ON := 0.55
const PULL_OFF := 0.3
## Random candidates compared at every jump.
const JUMP_TRIES := 12
## Grains played this recently cost extra, so a held rate does not cycle.
const RECENT_GRAINS := 48
## Each of these steps costs one unit at a jump.
const LEVEL_STEP_DB := 2.0
const BRIGHTNESS_STEP_DB := 2.0
const KIND_COST := 1.5
const CYLINDER_COST := 1.0
const RECENT_COST := 4.0
const CYLINDERS := 4

var bank: EngineGrainBank
var rng := RandomNumberGenerator.new()
var grains_started := 0
var jumps := 0
var pulling := false

var _pcm: PackedFloat32Array
var _voice_grain := PackedInt32Array()
var _voice_pos := PackedFloat32Array()
var _voice_rate := PackedFloat32Array()
var _last_grain := -1
var _recent := PackedInt32Array()
var _recent_index := 0


func _init(grain_bank: EngineGrainBank) -> void:
	bank = grain_bank
	_pcm = bank.pcm()
	_recent.resize(RECENT_GRAINS)
	_recent.fill(-1)


## Firing rate of the recorded idle.
func idle_hz() -> float:
	return bank.idle_hz


## Chooses between pulling and coasting grains with hysteresis on the throttle.
func set_throttle(throttle: float) -> void:
	if throttle > PULL_ON: pulling = true
	elif throttle < PULL_OFF: pulling = false


func reset() -> void:
	_voice_grain.clear()
	_voice_pos.clear()
	_voice_rate.clear()
	_last_grain = -1
	_recent.fill(-1)


## Renders frames of mono audio while the firing rate glides from its last value
## to target_hz. throttle is 0 when coasting and 1 at full load.
func render(frames: int, start_hz: float, target_hz: float, throttle: float) -> PackedFloat32Array:
	set_throttle(throttle)
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
	_recent[_recent_index] = grain
	_recent_index = (_recent_index + 1) % RECENT_GRAINS
	grains_started += 1


func _choose(hz: float) -> int:
	var kind := EngineGrainBank.Kind.RISING if pulling else EngineGrainBank.Kind.FALLING
	# The grain the recording would play next is the reference for a jump.
	var reference := _last_grain
	if _last_grain >= 0:
		var next := bank.follows[_last_grain]
		if next >= 0:
			if absf(bank.firing_hz[next] / hz - 1.0) < FOLLOW_TOLERANCE and _fits(bank.kinds[next], kind):
				return next
			reference = next
	var options := bank.candidates(hz, MATCH_TOLERANCE)
	if reference < 0 or options.size() == 1:
		return options[rng.randi_range(0, options.size() - 1)]
	jumps += 1
	var best := options[0]
	var best_cost := INF
	for attempt in range(JUMP_TRIES):
		var grain := options[rng.randi_range(0, options.size() - 1)]
		var cost := _jump_cost(grain, reference, hz, kind)
		if cost < best_cost:
			best = grain
			best_cost = cost
	return best


func _jump_cost(grain: int, reference: int, hz: float, kind: int) -> float:
	var cost := absf(bank.levels[grain] - bank.levels[reference]) / LEVEL_STEP_DB
	cost += absf(bank.brightness[grain] - bank.brightness[reference]) / BRIGHTNESS_STEP_DB
	cost += absf(log(bank.firing_hz[grain] / hz)) / MATCH_TOLERANCE
	if not _fits(bank.kinds[grain], kind): cost += KIND_COST
	var cylinder := bank.cylinders[_last_grain]
	if cylinder >= 0 and bank.cylinders[grain] >= 0 and bank.cylinders[grain] != (cylinder + 1) % CYLINDERS:
		cost += CYLINDER_COST
	if grain in _recent: cost += RECENT_COST
	return cost


## Steady grains (the idle and the tops of the recorded revs) fit either way.
func _fits(grain_kind: int, wanted: int) -> bool:
	return grain_kind == EngineGrainBank.Kind.STEADY or grain_kind == wanted


func _drop_finished() -> void:
	for voice in range(_voice_grain.size() - 2, -1, -1):
		if _voice_pos[voice] >= bank.lengths[_voice_grain[voice]] - 1:
			_voice_grain.remove_at(voice)
			_voice_pos.remove_at(voice)
			_voice_rate.remove_at(voice)

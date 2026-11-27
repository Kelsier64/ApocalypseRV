extends RefCounted
class_name WorldWeather
## Simulation seconds, never wall time. RNG is isolated from world generation.
signal changed
const MIN_DURATION := 8640.0
const MAX_DURATION := 17280.0
const TRANSITION := 720.0
const CLEAR_CHANCE := 0.05
const NO_RAIN_CHANCE := 0.5
const LIGHT_RAIN_THRESHOLD := 0.8
const NO_FOG_CHANCE := 0.2
const LIGHT_FOG_THRESHOLD := 0.6
const MEDIUM_FOG_THRESHOLD := 0.85
const FOG_NONE := 0.0
const FOG_LIGHT := 0.5
const FOG_MEDIUM := 1.0
const FOG_HEAVY := 2.0
const FOG_LEVELS := [FOG_NONE, FOG_LIGHT, FOG_MEDIUM, FOG_HEAVY]
var rng := RandomNumberGenerator.new()
var source := Vector3.ZERO # clear, rain, fog
var target := Vector3.ZERO
var transition_elapsed := TRANSITION
var remaining := MIN_DURATION
var initialized := false
## Scripted takes can animate the sample while the simulation segment is frozen.
var sample_override := Vector3.INF

func initialize(world_seed: int) -> void:
	if initialized: return
	rng.seed = world_seed ^ 0x57454154484552
	remaining = rng.randf_range(MIN_DURATION, MAX_DURATION)
	initialized = true

static func choose(clear_roll: float, rain_roll: float, fog_roll: float) -> Vector3:
	if clear_roll < CLEAR_CHANCE: return Vector3(1, 0, 0)
	var fog := FOG_NONE
	if fog_roll >= MEDIUM_FOG_THRESHOLD: fog = FOG_HEAVY
	elif fog_roll >= LIGHT_FOG_THRESHOLD: fog = FOG_MEDIUM
	elif fog_roll >= NO_FOG_CHANCE: fog = FOG_LIGHT
	return Vector3(0, 0 if rain_roll < NO_RAIN_CHANCE else (1 if rain_roll < LIGHT_RAIN_THRESHOLD else 2), fog)

func sample() -> Vector3:
	if sample_override.is_finite(): return sample_override
	return source.lerp(target, smoothstep(0.0, TRANSITION, transition_elapsed))

## Emitted before a new segment replaces the current one, while sample() and the
## RNG state still describe the outgoing segment. Listeners must not draw.
signal changing

static func initial_rng_state(world_seed: int) -> int:
	var probe := WorldWeather.new()
	probe.initialize(world_seed)
	return probe.rng.state

func set_weather(value: Vector3, immediate := false) -> void:
	changing.emit()
	_replace(value, immediate)

func _replace(value: Vector3, immediate: bool) -> void:
	source = sample()
	sample_override = Vector3.INF
	target = value
	transition_elapsed = TRANSITION if immediate else 0.0
	remaining = rng.randf_range(MIN_DURATION, MAX_DURATION)
	changed.emit()

func advance(seconds: float) -> void:
	if not is_finite(seconds) or seconds < 0: return
	while seconds > 0:
		var step := minf(seconds, remaining)
		transition_elapsed = minf(TRANSITION, transition_elapsed + step)
		remaining -= step
		seconds -= step
		if remaining <= 0:
			changing.emit()
			_replace(choose(rng.randf(), rng.randf(), rng.randf()), false)

func description() -> String:
	if target.x > 0.5: return "Clear"
	var result := "Overcast"
	if target.y > 0: result += " · " + ("Light rain" if target.y == 1 else "Heavy rain")
	if target.z > 0: result += " · " + ("Light fog" if target.z == FOG_LIGHT else ("Moderate fog" if target.z == FOG_MEDIUM else "Dense fog"))
	return result

func capture() -> Dictionary:
	return {"source": source, "target": target, "transition_elapsed": transition_elapsed, "remaining": remaining, "rng_state": rng.state}

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or not data.has_all(["source", "target", "transition_elapsed", "remaining", "rng_state"]): return false
	for key in ["source", "target"]:
		if not data[key] is Vector3: return false
		var v: Vector3 = data[key]
		if not v.is_finite() or v.x < 0 or v.x > 1 or v.y < 0 or v.y > 2 or v.z < 0 or v.z > 2: return false
	var t: Vector3 = data.target
	if t.x != roundf(t.x) or t.y != roundf(t.y) or t.z not in FOG_LEVELS: return false
	if t.x == 1 and (t.y != 0 or t.z != 0): return false
	for key in ["transition_elapsed", "remaining"]:
		if not (data[key] is int or data[key] is float) or not is_finite(float(data[key])): return false
	return data.transition_elapsed >= 0 and data.transition_elapsed <= TRANSITION and data.remaining > 0 and data.remaining <= MAX_DURATION and data.rng_state is int

func restore(data: Dictionary) -> bool:
	if not valid_state(data): return false
	sample_override = Vector3.INF
	source = data.source
	target = data.target
	transition_elapsed = data.transition_elapsed
	remaining = data.remaining
	rng.state = data.rng_state
	initialized = true
	changed.emit()
	return true

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
# Keep legacy saved strengths: old light fog becomes medium, heavy stays heavy.
const FOG_NONE := 0.0
const FOG_LIGHT := 0.5
const FOG_MEDIUM := 1.0
const FOG_HEAVY := 2.0
const FOG_LEVELS := [FOG_NONE, FOG_LIGHT, FOG_MEDIUM, FOG_HEAVY]
# Permanent landscape haze conceals streamed scenery even in clear weather.
const BASE_MIST_BEGIN := 24.0
const BASE_MIST_END := 230.0
var rng := RandomNumberGenerator.new()
var source := Vector3.ZERO # clear, rain, fog
var target := Vector3.ZERO
var transition_elapsed := TRANSITION
var remaining := MIN_DURATION
var initialized := false

## v14 atmosphere, evaluated from the current natural/deviation weather blend.
## Weather thickens the permanent landscape haze; clear skies never expose loads.
static func mist_profile(conditions: Vector3, _volumetric: bool) -> Dictionary:
	var clear := clampf(conditions.x, 0.0, 1.0)
	var fog := clampf(conditions.z, FOG_NONE, FOG_HEAVY)
	var light := clampf(fog / FOG_LIGHT, 0.0, 1.0)
	var medium := clampf((fog - FOG_LIGHT) / (FOG_MEDIUM - FOG_LIGHT), 0.0, 1.0)
	var heavy := clampf((fog - FOG_MEDIUM) / (FOG_HEAVY - FOG_MEDIUM), 0.0, 1.0)
	# Restore the original low mist; distance fog takes over at light fog so
	# volume scattering cannot reveal already concealed geometry.
	var volume_weight := (1.0 - clear) * (1.0 - light)
	return {
		"depth_begin": lerpf(BASE_MIST_BEGIN, 8.0, light),
		"depth_end": lerpf(lerpf(lerpf(BASE_MIST_END, 220.0, light), 110.0, medium), 38.0, heavy),
		"depth_curve": 1.0,
		"white_strength": 1.0,
		"global_density": (0.0025 + conditions.y * 0.0005) * volume_weight,
		"local_density": 0.14 * volume_weight,
	}

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
	return source.lerp(target, smoothstep(0.0, TRANSITION, transition_elapsed))

func set_weather(value: Vector3, immediate := false) -> void:
	source = sample()
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
			set_weather(choose(rng.randf(), rng.randf(), rng.randf()))

func description() -> String:
	if target.x > 0.5: return "晴天"
	var result := "陰天"
	if target.y > 0: result += "・" + ("小雨" if target.y == 1 else "大雨")
	if target.z > 0: result += "・" + ("小霧" if target.z == FOG_LIGHT else ("中霧" if target.z == FOG_MEDIUM else "大霧"))
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
	source = data.source
	target = data.target
	transition_elapsed = data.transition_elapsed
	remaining = data.remaining
	rng.state = data.rng_state
	initialized = true
	changed.emit()
	return true

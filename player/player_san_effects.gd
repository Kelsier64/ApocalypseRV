extends CanvasLayer
class_name PlayerSanEffects
## Transient effects for the controlled player and their active driving seat.

signal vision_blink_reopening(severity: float)

enum InputMode { NONE, WALK, DRIVE }
enum VisionProfile { NEGATIVE, MONOCHROME, OVERSATURATED, SPACE_WARP, COLOR_SPLIT, TUNNEL_VISION }

const THRESHOLD := 20.0
const LONG_BLINK_THRESHOLD := 0.0
const DELAY_RATE := 0.22
const MISDIRECTION_RATE := 0.27
const LONG_BLINK_RATE := 0.15

var _rng := RandomNumberGenerator.new()
var _control := InputMode.NONE
var _overlay: ColorRect
var _eyelids := ShaderMaterial.new()
var _blink_wait := -1.0
var _blink_duration := 1.0
var _blink_remaining := 0.0
var _long_blink_wait := -1.0
var _long_blink := false
var _vision_blinks_left := 0
var _vision_elapsed := 0.0
var _vision_strength := 0.0
var _vision_profile := -1
var _vision_viewport: Viewport
var _delay_wait := 0.0
var _delay_remaining := 0.0
var _delay_seconds := 0.0
var _last_input := Vector2.ZERO
var _delayed_input := Vector2.ZERO
# Each sample stores the command and the remaining episode time at delivery.
var _pending_input: Array[Vector3] = []
var _misdirection_wait := 0.0
var _misdirection_remaining := 0.0
var _misdirection_duration := 0.0
var _misdirection_strength := 0.0
var _sway_period := 1.0
var _sway_phase := 0.0
var _side := 1.0
@onready var _video := get_node("/root/GameSettings")

func _ready() -> void:
	layer = 1
	_overlay = ColorRect.new()
	_overlay.mouse_filter = ColorRect.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(ColorRect.PRESET_FULL_RECT)
	_eyelids.shader = preload("res://player/san_eyelids.gdshader")
	_overlay.material = _eyelids
	_overlay.hide()
	add_child(_overlay)

func _exit_tree() -> void:
	_clear_vision_grade()

func advance(delta: float, san: float, control: InputMode) -> void:
	if control == InputMode.NONE or san >= THRESHOLD:
		if _control != InputMode.NONE: reset()
		return
	if control != _control:
		_reset_direction()
		_control = control
	# Use the full deficit so hostile SAN loss below zero still raises the rate.
	var deficit := THRESHOLD - san
	var severity := deficit / (THRESHOLD + deficit)
	var long_blinks_enabled := san <= LONG_BLINK_THRESHOLD
	if not long_blinks_enabled: _clear_long_blink()
	_advance_blink(delta, severity, long_blinks_enabled)
	_update_vision_grade(delta)
	_advance_direction(delta, severity)

func _advance_blink(delta: float, severity: float, long_blinks_enabled: bool) -> void:
	if _blink_wait < 0.0: _blink_wait = _rng.randf_range(0.55, 1.45)
	if long_blinks_enabled and _long_blink_wait < 0.0: _long_blink_wait = 0.28 + 0.72 * _roll_wait()
	var previous_remaining := _blink_remaining
	var open_time := maxf(0.0, delta - _blink_remaining)
	_blink_remaining = maxf(0.0, _blink_remaining - delta)
	var previous_open_duration := _blink_open_duration()
	# Switch while the lids still cover the screen so reopening reveals the change.
	if previous_remaining > previous_open_duration and _blink_remaining <= previous_open_duration:
		_advance_vision_on_blink(severity)
		vision_blink_reopening.emit(severity)
	if _blink_remaining == 0.0:
		_long_blink = false
		_blink_wait = maxf(0.0, _blink_wait - open_time / lerpf(6.0, 0.9, severity))
		if long_blinks_enabled: _long_blink_wait -= open_time * severity * LONG_BLINK_RATE
		if long_blinks_enabled and _long_blink_wait <= 0.0:
			_long_blink = true
			_long_blink_wait = 0.28 + 0.72 * _roll_wait()
			_blink_duration = _sample_long_blink_duration(severity)
			_blink_remaining = _blink_duration
		elif _blink_wait == 0.0:
			_blink_wait = _rng.randf_range(0.55, 1.45)
			_blink_duration = lerpf(0.12, 0.85, _sample_episode(severity))
			_blink_remaining = _blink_duration
	var elapsed := _blink_duration - _blink_remaining
	var close_time := 0.18 if _long_blink else _blink_duration * 0.32
	var closure := smoothstep(0.0, close_time, elapsed) * smoothstep(0.0, _blink_open_duration(), _blink_remaining)
	_eyelids.set_shader_parameter("closure", closure)
	_overlay.visible = _blink_remaining > 0.0

func _blink_open_duration() -> float:
	return 0.38 if _long_blink else _blink_duration * 0.52

func _advance_vision_on_blink(severity: float) -> void:
	# Severity reaches 0.5 at zero SAN. From there the original odds apply.
	var probability_scale := minf(2.0 * severity, 1.0)
	if _vision_profile < 0:
		if _rng.randf() < lerpf(0.19, 0.62, severity) * probability_scale:
			_start_vision(_roll_vision_profile(), severity)
		return
	_vision_blinks_left -= 1
	if _vision_blinks_left > 0: return
	if _rng.randf() < lerpf(0.10, 0.60, severity) * probability_scale:
		_start_vision(_roll_vision_profile(), severity)
	else:
		_end_vision()

func _roll_vision_profile() -> int:
	var last_profile := VisionProfile.size() - 1
	if _vision_profile < 0: return _rng.randi_range(0, last_profile)
	var profile := _rng.randi_range(0, last_profile - 1)
	# Skip the active profile when the episode is switching directly to another.
	return profile + 1 if profile >= _vision_profile else profile

func _start_vision(profile: int, severity: float) -> void:
	_vision_profile = profile
	_vision_strength = lerpf(0.38, 1.0, _sample_episode(severity))
	_vision_blinks_left = mini(4, 2 + floori(3.0 * _sample_episode(severity)))
	_vision_elapsed = 0.0

func _end_vision() -> void:
	_vision_profile = -1
	_vision_blinks_left = 0
	_vision_elapsed = 0.0
	_clear_vision_grade()

func _update_vision_grade(delta: float) -> void:
	if _vision_profile < 0: return
	_vision_elapsed += delta
	var viewport := get_viewport()
	if _vision_viewport != viewport:
		_clear_vision_grade()
		_vision_viewport = viewport
	_video.set_san_vision(viewport, _vision_profile, _vision_strength, _vision_elapsed)

func _clear_long_blink() -> void:
	if _long_blink: _blink_remaining = 0.0
	_long_blink = false
	_long_blink_wait = -1.0

func _clear_vision_grade() -> void:
	if is_instance_valid(_vision_viewport) and is_instance_valid(_video):
		_video.set_san_vision(_vision_viewport, 0, 0.0, 0.0)
	_vision_viewport = null

func _advance_direction(delta: float, severity: float) -> void:
	# Exponential wait budgets give each eligible effect a rate set by the
	# current SAN, even if SAN changes partway through the wait.
	_delay_remaining = maxf(0.0, _delay_remaining - delta)
	_misdirection_remaining = maxf(0.0, _misdirection_remaining - delta)
	if _delay_remaining == 0.0:
		_pending_input.clear()
		_delay_wait -= delta * severity * DELAY_RATE
		if _delay_wait <= 0.0:
			_delay_wait = _roll_wait()
			_delay_seconds = lerpf(0.42, 0.95, _sample_episode(severity))
			_delay_remaining = lerpf(2.0, 4.5, _sample_episode(severity))
			_delayed_input = _last_input
	if _misdirection_remaining == 0.0:
		_misdirection_wait -= delta * severity * MISDIRECTION_RATE
		if _misdirection_wait <= 0.0:
			_misdirection_wait = _roll_wait()
			_misdirection_duration = lerpf(1.1, 3.4, _sample_episode(severity))
			_misdirection_remaining = _misdirection_duration
			_misdirection_strength = lerpf(0.12, 1.0, _sample_episode(severity))
			_sway_period = _rng.randf_range(0.75, 1.35)
			_sway_phase = _rng.randf_range(0.0, TAU)
			_side = -1.0 if _rng.randf() < 0.5 else 1.0

func _roll_wait() -> float:
	return -log(maxf(_rng.randf(), 0.000001))

func _sample_long_blink_duration(severity: float) -> float:
	var mean := lerpf(2.6, 6.2, severity)
	var duration := _rng.randfn(mean, 2.8)
	# Reject the tails outside the range so samples never pile up at either limit.
	while duration < 1.5 or duration > 16.0:
		duration = _rng.randfn(mean, 2.8)
	return duration

func _sample_episode(severity: float) -> float:
	# Every SAN has the same range. Lower SAN weights the draw toward larger values.
	return pow(_rng.randf(), lerpf(3.8, 0.38, severity))

func _misdirection_weight() -> float:
	if _misdirection_remaining <= 0.0: return 0.0
	var elapsed := _misdirection_duration - _misdirection_remaining
	var envelope := smoothstep(0.0, 0.22, elapsed) * smoothstep(0.0, 0.30, _misdirection_remaining)
	var sway := 0.5 + 0.5 * sin(TAU * elapsed / _sway_period + _sway_phase)
	return _misdirection_strength * envelope * sway * sway

func walk_direction(input: Vector2) -> Vector2:
	if _control != InputMode.WALK: return input
	var direction := _delay_input(input)
	if _misdirection_remaining <= 0.0: return direction
	var pull := _side * _misdirection_weight() * (0.38 + 0.40 * direction.length())
	return (direction + Vector2(pull, 0.0)).limit_length()

func driving_input(turn: float, throttle: float) -> Vector2:
	var input := Vector2(turn, throttle)
	if _control != InputMode.DRIVE: return input
	if _delay_remaining > 0.0 and input.y < _last_input.y:
		# Easing off the pedal or braking cancels buffered acceleration.
		_delayed_input.y = minf(_delayed_input.y, input.y)
		for index in _pending_input.size():
			var sample := _pending_input[index]
			sample.y = minf(sample.y, input.y)
			_pending_input[index] = sample
	var applied := _delay_input(input)
	if _misdirection_remaining <= 0.0: return applied
	var weight := _misdirection_weight()
	var response := 1.0 - 2.0 * pow(weight, 1.7)
	var pull := _side * weight * 0.55 * (1.0 - absf(applied.x))
	applied.x = clampf(applied.x * response + pull, -1.0, 1.0)
	return applied

func _input_delay() -> float:
	# Shorten the lag as the episode ends while keeping queued samples in order.
	return minf(_delay_seconds, 0.75 * _delay_remaining)

func _delay_input(input: Vector2) -> Vector2:
	if _delay_remaining > 0.0 and not input.is_equal_approx(_last_input):
		_pending_input.append(Vector3(input.x, input.y, _delay_remaining - _input_delay()))
	_last_input = input
	if _delay_remaining <= 0.0: return input
	while not _pending_input.is_empty() and _pending_input[0].z >= _delay_remaining:
		var sample: Vector3 = _pending_input.pop_front()
		_delayed_input = Vector2(sample.x, sample.y)
	return _delayed_input

func reset() -> void:
	_control = InputMode.NONE
	_blink_wait = -1.0
	_blink_remaining = 0.0
	if _overlay != null: _overlay.hide()
	_clear_long_blink()
	_end_vision()
	_reset_direction()

func _reset_direction() -> void:
	_delay_wait = _roll_wait()
	_delay_remaining = 0.0
	_last_input = Vector2.ZERO
	_pending_input.clear()
	_misdirection_wait = _roll_wait()
	_misdirection_remaining = 0.0

extends CanvasLayer
class_name PlayerSanEffects
## Transient effects for the controlled player and their active driving seat.

enum InputMode { NONE, WALK, DRIVE }

const THRESHOLD := 20.0
const DELAY_RATE := 0.22
const MISDIRECTION_RATE := 0.27

var _rng := RandomNumberGenerator.new()
var _control := InputMode.NONE
var _overlay: ColorRect
var _eyelids := ShaderMaterial.new()
var _blink_wait := 0.0
var _blink_duration := 1.0
var _blink_remaining := 0.0
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

func _ready() -> void:
	layer = 1
	_overlay = ColorRect.new()
	_overlay.mouse_filter = ColorRect.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(ColorRect.PRESET_FULL_RECT)
	_eyelids.shader = preload("res://player/san_eyelids.gdshader")
	_overlay.material = _eyelids
	_overlay.hide()
	add_child(_overlay)

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
	_advance_blink(delta, severity)
	_advance_direction(delta, severity)

func _advance_blink(delta: float, severity: float) -> void:
	if _blink_wait <= 0.0: _blink_wait = _rng.randf_range(0.72, 1.28)
	_blink_wait -= delta / lerpf(6.0, 0.9, severity)
	_blink_remaining = maxf(0.0, _blink_remaining - delta)
	if _blink_wait <= 0.0:
		_blink_wait = _rng.randf_range(0.72, 1.28)
		_blink_duration = _rng.randf_range(0.12, 0.22)
		_blink_remaining = _blink_duration
	var progress := 1.0 - _blink_remaining / _blink_duration
	var closure := smoothstep(0.0, 0.32, progress) * (1.0 - smoothstep(0.48, 1.0, progress))
	_eyelids.set_shader_parameter("closure", closure)
	_overlay.visible = _blink_remaining > 0.0

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
	_blink_wait = 0.0
	_blink_remaining = 0.0
	if _overlay != null: _overlay.hide()
	_reset_direction()

func _reset_direction() -> void:
	_delay_wait = _roll_wait()
	_delay_remaining = 0.0
	_last_input = Vector2.ZERO
	_pending_input.clear()
	_misdirection_wait = _roll_wait()
	_misdirection_remaining = 0.0

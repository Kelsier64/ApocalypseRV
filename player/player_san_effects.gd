extends CanvasLayer
class_name PlayerSanEffects
## Transient effects for the controlled player and their active driving seat.

enum InputMode { NONE, WALK, DRIVE }

const THRESHOLD := 20.0

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
# Each sample stores the direction and the remaining episode time at delivery.
var _pending_input: Array[Vector3] = []
var _misdirection_wait := 0.0
var _misdirection_remaining := 0.0
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
	var severity := 1.0 - clampf(san / THRESHOLD, 0.0, 1.0)
	_advance_blink(delta, severity)
	_advance_direction(delta, severity)

func _advance_blink(delta: float, severity: float) -> void:
	if _blink_wait <= 0.0: _blink_wait = _rng.randf_range(0.72, 1.28)
	_blink_wait -= delta / lerpf(7.0, 3.75, severity)
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
	# Independent clocks accumulate faster at low SAN. Short episodes can overlap.
	var input_interval := lerpf(90.0, 36.0, severity)
	if _delay_wait <= 0.0: _delay_wait = _rng.randf_range(0.75, 1.25)
	if _misdirection_wait <= 0.0: _misdirection_wait = _rng.randf_range(0.75, 1.25)
	_delay_wait -= delta / input_interval
	_misdirection_wait -= delta / input_interval
	_delay_remaining = maxf(0.0, _delay_remaining - delta)
	_misdirection_remaining = maxf(0.0, _misdirection_remaining - delta)
	if _delay_remaining == 0.0: _pending_input.clear()
	if _delay_wait <= 0.0:
		_delay_wait = _rng.randf_range(0.75, 1.25)
		_delay_seconds = _rng.randf_range(0.15, 0.25)
		_delay_remaining = _rng.randf_range(0.55, 0.75)
		_delayed_input = _last_input
	if _misdirection_wait <= 0.0:
		_misdirection_wait = _rng.randf_range(0.75, 1.25)
		_misdirection_remaining = _rng.randf_range(0.3, 0.5)
		_side = -1.0 if _rng.randf() < 0.5 else 1.0

func walk_direction(input: Vector2) -> Vector2:
	if _control != InputMode.WALK: return input
	var direction := _delay_direction(input)
	if _misdirection_remaining <= 0.0: return direction
	if direction.is_zero_approx(): return Vector2(_side * 0.35, 0.0)
	return direction.orthogonal() * _side

func steering(turn: float) -> float:
	if _control != InputMode.DRIVE: return turn
	var delayed := _delay_direction(Vector2(turn, 0.0))
	var direction := delayed.x if _delay_remaining > 0.0 else turn
	if _misdirection_remaining <= 0.0: return direction
	return _side * 0.45 if is_zero_approx(direction) else -direction

func _delay_direction(input: Vector2) -> Vector2:
	if _delay_remaining > 0.0 and not input.is_equal_approx(_last_input):
		_pending_input.append(Vector3(input.x, input.y, _delay_remaining - _delay_seconds))
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
	_delay_wait = 0.0
	_delay_remaining = 0.0
	_last_input = Vector2.ZERO
	_pending_input.clear()
	_misdirection_wait = 0.0
	_misdirection_remaining = 0.0

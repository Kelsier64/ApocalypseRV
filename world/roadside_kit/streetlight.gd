extends Node3D
class_name RoadsideStreetlight

enum Fault { STEADY, DIP, BURST }

# At this elevation the outdoor clock's twilight blend reaches full night.
const NIGHT_ELEVATION := -0.16
const LENS_ENERGY := 0.85

var _clock: WorldClock
var _tint := Color("ffe3bc")
var _fault := Fault.STEADY
var _rng := RandomNumberGenerator.new()
var _night := false
var _flicker: Tween
var _light_energy: float
var _level := 0.0:
	set(value):
		_level = value
		_light.light_energy = _light_energy * value
		_light.visible = value > 0.0
		_lens.emission_energy_multiplier = LENS_ENERGY * value
@onready var _light: SpotLight3D = $Light
@onready var _lens: StandardMaterial3D = $Lens.material_override

func configure(clock: WorldClock, tint: Color, fault: int, flicker_seed: int) -> void:
	_clock = clock
	_tint = tint
	_fault = fault as Fault
	_rng.seed = flicker_seed

func _ready() -> void:
	_light_energy = _light.light_energy
	_light.light_color = _tint
	_lens.emission = _tint
	_level = 0.0
	if _clock != null:
		_clock.minute_changed.connect(_on_minute_changed)
		_update_night()

func _on_minute_changed(_day: int, _hour: int, _minute: int) -> void:
	_update_night()

func _update_night() -> void:
	var night := _clock.sun_direction().y <= NIGHT_ELEVATION
	if night == _night: return
	_night = night
	if _flicker != null:
		_flicker.kill()
		_flicker = null
	_level = 1.0 if _night else 0.0
	if _night and _fault != Fault.STEADY: _schedule_flicker(true)

func _schedule_flicker(first: bool) -> void:
	_flicker = create_tween()
	if _fault == Fault.DIP:
		_flicker.tween_interval(_rng.randf_range(2.0, 10.0) if first else _rng.randf_range(7.0, 18.0))
		_fade_to(_rng.randf_range(0.35, 0.60), 0.10)
		_flicker.tween_interval(_rng.randf_range(0.10, 0.22))
		_fade_to(1.0, 0.12)
	else:
		_flicker.tween_interval(_rng.randf_range(3.0, 12.0) if first else _rng.randf_range(14.0, 28.0))
		for i in range(_rng.randi_range(3, 4)):
			_fade_to(_rng.randf_range(0.15, 0.45), _rng.randf_range(0.08, 0.12))
			_flicker.tween_interval(_rng.randf_range(0.12, 0.22))
			_fade_to(1.0, _rng.randf_range(0.08, 0.12))
			_flicker.tween_interval(_rng.randf_range(0.36, 0.64))
		_fade_to(0.0, 0.10)
		_flicker.tween_interval(_rng.randf_range(1.0, 2.0))
		_fade_to(1.0, 0.50)
	_flicker.finished.connect(_schedule_flicker.bind(false))

func _fade_to(level: float, duration: float) -> void:
	_flicker.tween_property(self, "_level", level, duration)

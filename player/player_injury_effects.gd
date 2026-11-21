extends CanvasLayer

enum Cause { IMPACT, CRASH, BLAST, STARVATION }

const IMPACT_ONSET_DELAY := 0.04
const CRASH_ONSET_DELAY := 0.01
const CABIN_JOLT_BEFORE_BLACKOUT := 0.05
const BLACKOUT_THRESHOLD := 0.20
const SEVERE_INJURY := 0.40
const SEVERED_LIMB_FLOOR := 0.32
const MAX_BLACKOUT_SECONDS := 0.40
const RETURN_LIGHT_SECONDS := 0.20
const MAX_VISUAL_SECONDS := 3.2
const MAX_RING_SECONDS := 4.1
const RINGING := preload("res://assets/audio/player/tinnitus.wav")

var _age := 0.0
var _episode_start := 0.0
var _black_start := -1.0
var _black_end := -1.0
var _dim_at := -1.0
var _dim_peak := 0.0
var _focus_peak := 0.0
var _focus_onset := 0.0
var _focus_start := 0.0
var _focus_end := 0.0
var _ring_start := -1.0
var _ring_end := 0.0
var _ring_peak := 0.0
var _fatigue := 0.0
var _stumbled_at := -1.0
var _shade: ColorRect
var _tone: AudioStreamPlayer
var _grade: ShaderMaterial
var _muffle: AudioEffectLowPassFilter

@onready var _actor := get_parent()
@onready var _video := get_node("/root/GameSettings")

func _ready() -> void:
	layer = 10
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_shade.hide()
	_tone = AudioStreamPlayer.new()
	# Ringing is inside the head, so the World muffle it accompanies leaves it clear.
	_tone.bus = &"Self"
	_tone.stream = RINGING
	add_child(_tone)
	set_process(false)

func play_hit(fraction: float, cause: Cause, severed_limb := false, follows_cabin_jolt := false) -> void:
	if cause == Cause.STARVATION:
		_fatigue = maxf(_fatigue, 0.18)
		set_process(true)
		return

	var severity := maxf(fraction, SEVERED_LIMB_FLOOR if severed_limb else 0.0)
	var strong := clampf(inverse_lerp(BLACKOUT_THRESHOLD, SEVERE_INJURY, severity), 0.0, 1.0)
	var delay := CRASH_ONSET_DELAY if cause == Cause.CRASH else IMPACT_ONSET_DELAY
	if follows_cabin_jolt: delay = CABIN_JOLT_BEFORE_BLACKOUT
	var onset := _age + delay
	if _age >= _focus_end:
		_episode_start = _age
		_black_start = -1.0
		_black_end = -1.0
		_focus_onset = onset
	if severity >= BLACKOUT_THRESHOLD and _black_start < 0.0:
		_black_start = onset
		_black_end = onset + lerpf(0.15, MAX_BLACKOUT_SECONDS, strong)
	elif _black_start < 0.0:
		_dim_at = onset
		_dim_peak = 0.52 * smoothstep(0.07, BLACKOUT_THRESHOLD, severity)
	if severity >= SEVERE_INJURY and _age >= _stumbled_at + 0.23:
		_stumbled_at = _age

	var duration := 0.18 + 0.53 * smoothstep(0.01, 0.15, severity) + 1.21 * smoothstep(0.15, BLACKOUT_THRESHOLD, severity) + 1.28 * strong
	var focus := lerpf(0.05, 0.92, smoothstep(0.0, SEVERE_INJURY, severity))
	if focus >= _focus_at(_age):
		_focus_peak = focus
		_focus_start = maxf(onset, _black_end + RETURN_LIGHT_SECONDS * 0.5)
		_focus_end = maxf(_focus_end, minf(_age + duration, _episode_start + MAX_VISUAL_SECONDS))

	var ring := smoothstep(0.12, SEVERE_INJURY, severity)
	if ring > 0.0:
		if _ring_start < 0.0 or _age >= _ring_end:
			_ring_start = onset
			_ring_peak = 0.0
		var tail := 0.9 if cause == Cause.BLAST else 0.0
		_ring_end = maxf(_ring_end, minf(_age + duration + tail, _episode_start + MAX_RING_SECONDS))
		_ring_peak = maxf(_ring_peak, ring * (1.0 if cause == Cause.BLAST else 0.72))
	set_process(true)

func _focus_at(at: float) -> float:
	if at < _focus_onset or at >= _focus_end: return 0.0
	var fade := smoothstep(_focus_start, _focus_end, at)
	return _focus_peak * (1.0 - fade)

func _black_at(at: float) -> float:
	if _black_start < 0.0 or at < _black_start: return 0.0
	return 1.0 - smoothstep(_black_end, _black_end + RETURN_LIGHT_SECONDS, at)

func stride_scale() -> float:
	if _stumbled_at < 0.0: return 1.0
	return lerpf(0.66, 1.0, smoothstep(_stumbled_at, _stumbled_at + 0.23, _age))

func _process(delta: float) -> void:
	_age += delta
	_fatigue = move_toward(_fatigue, 0.0, delta * 0.12)
	if _age >= maxf(_focus_end, _ring_end) and _fatigue <= 0.0:
		reset()
		return

	var seat: Node3D = _actor.seated_in
	var view: Camera3D = seat.seat_camera if is_instance_valid(seat) else _actor.camera
	if not is_instance_valid(view) or not view.is_current():
		_clear_presentation()
		return

	var focus := _focus_at(_age)
	var black := _black_at(_age)
	var dim := _dim_peak * (1.0 - smoothstep(_dim_at, _dim_at + 0.26, _age)) if _age >= _dim_at else 0.0
	var grade_rect: ColorRect = _video.viewport_effect(get_viewport())
	var grade := grade_rect.material as ShaderMaterial if grade_rect != null else null
	if grade != _grade:
		_clear_grade()
		_grade = grade
	if _grade != null:
		_grade.set_shader_parameter("injury_focus", focus)
		_grade.set_shader_parameter("injury_fatigue", _fatigue)
	_shade.color.a = maxf(black, dim)
	_shade.visible = _shade.color.a > 0.0

	if DisplayServer.get_name() != "headless":
		_update_audio(maxf(black, focus))

func _update_audio(pressure: float) -> void:
	var ring := 0.0
	if _ring_start >= 0.0 and _age >= _ring_start and _age < _ring_end:
		var fade_in := smoothstep(_ring_start, _ring_start + 0.07, _age)
		var fade_out := 1.0 - smoothstep(_ring_start + 0.10, _ring_end, _age)
		ring = _ring_peak * fade_in * fade_out
	if ring > 0.001:
		_tone.volume_db = linear_to_db(0.22 * ring)
		if not _tone.playing: _tone.play()
	elif _tone.playing:
		_tone.stop()

	set_consciousness_muffle(pressure)

func set_consciousness_muffle(pressure: float) -> void:
	if pressure < 0.10:
		_clear_muffle()
		return
	if _muffle == null:
		_muffle = AudioEffectLowPassFilter.new()
		_muffle.resonance = 0.5
		AudioServer.add_bus_effect(AudioServer.get_bus_index(&"World"), _muffle)
	# The shallow filter softens environmental detail while the ringing is audible.
	_muffle.cutoff_hz = lerpf(22000.0, 950.0, smoothstep(0.10, 1.0, pressure))

func _clear_muffle() -> void:
	if _muffle == null: return
	var bus := AudioServer.get_bus_index(&"World")
	for index in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) == _muffle:
			AudioServer.remove_bus_effect(bus, index)
			break
	_muffle = null

func _clear_grade() -> void:
	if _grade != null:
		_grade.set_shader_parameter("injury_focus", 0.0)
		_grade.set_shader_parameter("injury_fatigue", 0.0)
		_grade = null

func _clear_presentation() -> void:
	_clear_grade()
	_clear_muffle()
	_shade.hide()
	_tone.stop()

func reset() -> void:
	_clear_presentation()
	_age = 0.0
	_episode_start = 0.0
	_black_start = -1.0
	_black_end = -1.0
	_dim_at = -1.0
	_dim_peak = 0.0
	_focus_peak = 0.0
	_focus_onset = 0.0
	_focus_start = 0.0
	_focus_end = 0.0
	_ring_start = -1.0
	_ring_end = 0.0
	_ring_peak = 0.0
	_fatigue = 0.0
	_stumbled_at = -1.0
	set_process(false)

func _exit_tree() -> void:
	reset()

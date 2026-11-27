extends Item
class_name DispatchSpeaker

const SCENE := "res://equipment/dispatch_speaker.tscn"
const KNOB := preload("res://assets/audio/events/dispatch_speaker/knob.tres")
const KEY := preload("res://assets/audio/events/dispatch_speaker/key.tres")
const LIFT := preload("res://assets/audio/events/dispatch_speaker/lift.tres")
const HANG := preload("res://assets/audio/events/dispatch_speaker/hang.tres")
const LEVEL_NAMES := ["Low", "Medium", "High"]
const ZERO_ANGLE := 55.0

@export var level_db: Vector3
@export var power_draw: float
@export var minimum_signal: float
@export var clear_signal: float
@export var dropout_interval: Vector2
@export var dropout_depth_db: float
@export var fade_seconds: float
## Local answers the receiver speaks from the broadcast word bank.
@export var replies: PackedStringArray

@onready var schedule: BroadcastSchedule = $SignalTimer
@onready var speaker: AudioStreamPlayer3D = $Speaker
@onready var noise: AudioStreamPlayer3D = $Static
@onready var knob := $Model.find_child("VolumeKnob", true, false) as Node3D
@onready var pilot := $Model.find_child("PilotLens", true, false) as MeshInstance3D
@onready var meter := $Model.find_child("MeterBezel", true, false) as MeshInstance3D
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _dial_lit: StandardMaterial3D

var level := 1
var strength := 0.0
var powered := false
var replying := false
var _reply_index := 0
var _rng := RandomNumberGenerator.new()
var _sample_in := 0.0
var _jitter := 0.0
var _drop_in := 0.0
var _drop_db := 0.0
var _fading := false
var _fade_left := 0.0

func _ready() -> void:
	super._ready()
	_lamp_on = _backlit_material(pilot, 0.85)
	_lamp_off = pilot.mesh.surface_get_material(0).duplicate()
	_lamp_off.albedo_color = Color(0.45, 0.33, 0.25)
	_dial_lit = _backlit_material(meter, 0.26)
	schedule.timeout.connect(receive)
	speaker.finished.connect(_finished)
	availability_changed.connect(_availability_changed)
	_update_controls()
	set_process(false)

func _backlit_material(part: MeshInstance3D, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = part.mesh.surface_get_material(0).duplicate()
	material.emission_enabled = true
	material.emission_texture = material.albedo_texture
	material.emission_energy_multiplier = energy
	return material

func _update_controls() -> void:
	pilot.material_override = _lamp_on if powered else _lamp_off
	meter.material_override = _dial_lit if powered else null
	knob.rotation_degrees.z = (1 - level) * 42.0 if enabled else 80.0

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	level = 1
	if is_node_ready():
		_on_service_stopped()

func _availability_changed() -> void:
	if not can_operate(): _on_service_stopped()
	_update_controls()

func step_work(delta: float) -> void:
	var supplied := can_operate() and consume_rv_power(power_draw * delta)
	if supplied == powered: return
	if not supplied:
		_on_service_stopped()
		return
	powered = true
	_sample()
	_update_controls()
	schedule.start_first()
	set_process(true)

func _on_service_stopped() -> void:
	if schedule == null: return
	var sfx := get_node_or_null("/root/Sfx")
	if sfx: sfx.stop_from(self)
	powered = false
	replying = false
	_fading = false
	_drop_db = 0.0
	_drop_in = 0.0
	strength = 0.0
	schedule.stop()
	speaker.stop()
	noise.stop()
	$Needle.rotation_degrees.z = ZERO_ANGLE
	_update_controls()
	set_process(false)

func _sample() -> void:
	_sample_in = 0.5
	# Resolve within this world even when a playground wraps it in another scene.
	var world: Node = self
	while world != null and not world.has_meta("entity_domain"):
		world = world.get_parent()
	var coverage := world.get_node_or_null("DeviationPressure") as DeviationPressure if world != null else null
	strength = coverage.signal_strength_at(global_position) if coverage else 1.0
	_jitter = _rng.randf_range(-2.8, 2.8) * (1.0 - strength)
	if strength < minimum_signal and speaker.playing and not replying and not _fading:
		_fading = true
		_fade_left = fade_seconds

func _process(delta: float) -> void:
	_sample_in -= delta
	if _sample_in <= 0.0: _sample()
	var angle := lerpf(ZERO_ANGLE, -ZERO_ANGLE, strength) + _jitter
	$Needle.rotation_degrees.z = lerpf($Needle.rotation_degrees.z, angle, 1.0 - exp(-7.0 * delta))
	var base := level_db[level] + _exterior_gain()
	if _fading:
		_fade_left = maxf(0, _fade_left - delta)
		speaker.volume_db = base + linear_to_db(maxf(0.0001, _fade_left / fade_seconds))
		if _fade_left <= 0.0:
			speaker.stop()
			_finished()
	elif speaker.playing:
		_drop_in -= delta
		if _drop_in <= 0.0:
			_drop_in = _rng.randf_range(dropout_interval.x, dropout_interval.y)
			_drop_db = -dropout_depth_db if _rng.randf() > strength else 0.0
		var loss := 0.0 if replying or strength >= clear_signal else _drop_db * (1.0 - strength)
		speaker.volume_db = move_toward(speaker.volume_db, base + loss, 135.0 * delta)
	var hiss := 0.0 if replying else 1.0 - strength
	if hiss <= 0.001:
		noise.stop()
	else:
		noise.volume_db = base + linear_to_db(hiss) - (5.0 if speaker.playing else 21.0)
		if not noise.playing: noise.play()

func _exterior_gain() -> float:
	var camera := get_viewport().get_camera_3d()
	var vehicle_audio := get_connected_rv().get_node_or_null("Audio") if powered else null
	if camera == null or vehicle_audio == null or not vehicle_audio.contains_cabin_point(global_position): return 0.0
	if vehicle_audio.contains_cabin_point(camera.global_position): return 0.0
	return -14.0 * vehicle_audio.shell_cover()

func receive() -> void:
	if not powered or replying: return
	schedule.stop()
	if strength < minimum_signal:
		schedule.start_next()
		return
	_fading = false
	speaker.stream = schedule.draw()
	if speaker.stream:
		speaker.volume_db = level_db[level] + _exterior_gain()
		speaker.play()
		BroadcastCaptions.show_for(speaker, schedule.caption)

func _finished() -> void:
	if replying: _cue(HANG, $HandsetCollision.position)
	replying = false
	_fading = false
	if powered: schedule.start_next()

func aims_at_handset(point: Vector3) -> bool:
	var local: Vector3 = to_local(point) - $HandsetCollision.position
	var half: Vector3 = $HandsetCollision.shape.size * 0.5 + Vector3.ONE * 0.001
	return AABB(-half, 2.0 * half).has_point(local)

func use_panel(point: Vector3) -> String:
	if aims_at_handset(point): return key_handset()
	return cycle_volume()

func interact(player: Node3D) -> String:
	if not is_fixed: return super.interact(player)
	return cycle_volume()

func cycle_volume() -> String:
	if not enabled:
		level = 0
		set_enabled(true)
	elif level == 2:
		set_enabled(false)
	else:
		level += 1
		_update_controls()
	_cue(KNOB, knob.position)
	return "Speaker: " + LEVEL_NAMES[level] if enabled else "Speaker off"

func key_handset() -> String:
	var at: Vector3 = $HandsetCollision.position
	_cue(KEY, at)
	if not powered or not can_operate() or not get_connected_rv().has_usable_power(0.000001): return "Handset clicks"
	if replying: return "Line busy"
	_cue(LIFT, at)
	schedule.stop()
	noise.stop()
	_fading = false
	replying = true
	speaker.stream = schedule.speak(WordBank.tokenize(replies[_reply_index]))
	_reply_index = (_reply_index + 1) % replies.size()
	speaker.volume_db = level_db[level] + _exterior_gain()
	speaker.play()
	BroadcastCaptions.show_for(speaker, schedule.caption)
	return "Receive only"

func _cue(event: SoundEvent, at: Vector3) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx: sfx.play(event, self, at)

func get_status() -> String:
	if not enabled: return "Off"
	if not powered or not can_operate(): return "No power: disabled, removed or damaged"
	if strength < minimum_signal: return "No signal"
	return "Weak signal" if strength < clear_signal else "Receiving"

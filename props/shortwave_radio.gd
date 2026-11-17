extends Item
class_name ShortwaveRadio

const SCENE := "res://props/shortwave_radio.tscn"
const FIRST_SIGNAL_DELAY := Vector2(3.0, 7.0)
const SIGNAL_GAP := Vector2(18.0, 42.0)

@export var transmissions: Array[AudioStream] = []
@export var unlit_lamp: Material
@export var lit_lamp: Material

@onready var _signal_timer: Timer = $SignalTimer
@onready var _speaker: AudioStreamPlayer3D = $Speaker
@onready var _switch: AudioStreamPlayer3D = $Switch
@onready var _lamp: MeshInstance3D = $PilotLamp

var _carried := false
var _rng := RandomNumberGenerator.new()
var _last_signal := -1

func _ready() -> void:
	super._ready()
	_rng.randomize()
	visibility_changed.connect(_update_power)
	availability_changed.connect(_update_power)
	_signal_timer.timeout.connect(_receive)
	_speaker.finished.connect(_schedule_next)
	_update_power()

func set_carried() -> void:
	_carried = true

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	if not state.has("enabled"): enabled = false
	_update_power()

func toggle_power() -> void:
	if condition <= 0.0 or not is_visible_in_tree() or is_being_placed or (presentation_only and not _carried): return
	set_enabled(not enabled)
	_switch.play()

func interact(player: Node3D) -> String:
	if not is_fixed: return super.interact(player)
	toggle_power()
	return "Radio on" if enabled else "Radio off"

func _can_receive() -> bool:
	return (
		enabled and condition > 0.0 and not is_destroyed and not is_queued_for_deletion()
		and not is_being_placed and not is_instance_valid(processing_owner)
		and is_visible_in_tree() and (not presentation_only or _carried)
	)

func _update_power() -> void:
	if not is_node_ready(): return
	var powered := _can_receive()
	_lamp.material_override = lit_lamp if powered else unlit_lamp
	if not powered:
		_signal_timer.stop()
		_speaker.stop()
		_switch.stop()
	elif _signal_timer.is_stopped() and not _speaker.playing and not transmissions.is_empty():
		_signal_timer.start(_rng.randf_range(FIRST_SIGNAL_DELAY.x, FIRST_SIGNAL_DELAY.y))

func _receive() -> void:
	if not _can_receive() or transmissions.is_empty(): return
	# Draw from every clip except the one just heard.
	var count := transmissions.size()
	var exclude_last := _last_signal >= 0 and count > 1
	var index := _rng.randi_range(0, count - (2 if exclude_last else 1))
	if exclude_last and index >= _last_signal: index += 1
	_last_signal = index
	_speaker.stream = transmissions[index]
	_speaker.play()

func _schedule_next() -> void:
	if _can_receive():
		_signal_timer.start(_rng.randf_range(SIGNAL_GAP.x, SIGNAL_GAP.y))

func _on_service_stopped() -> void:
	_signal_timer.stop()
	_speaker.stop()
	_switch.stop()

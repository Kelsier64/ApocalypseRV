extends Node3D
## White apparition sounds. A soft breath marks its appearance; from then until
## it vanishes a faint whisper hangs on it, louder and easier to place as it
## closes, so the player can tell it is behind them without turning to look.

const APPEAR: SoundEvent = preload("res://assets/audio/events/apparitions/white_appear.tres")
const PRESENCE: AudioStream = preload("res://assets/audio/apparitions/white_presence.wav")
const CHEST := Vector3(0.0, 2.0, 0.0)
const FADE_IN_SECONDS := 2.0
const FADE_OUT_SECONDS := 0.4
## Panning strength near and far: the whisper only narrows to a direction as
## the apparition closes in.
const PANNING := Vector2(1.0, 0.35)
const PANNING_RANGE := Vector2(10.0, 55.0)

var actor: WhiteApparition
var presence: SoundLoop
var _level := 0.0


func _ready() -> void:
	actor = get_parent()
	presence = SoundLoop.new()
	presence.name = "Presence"
	presence.stream = PRESENCE
	presence.base_db = -18.0
	presence.position = CHEST
	presence.occlusion_by_position = true
	preload("res://assets/audio/attenuation/presence.tres").apply(presence)
	add_child(presence)
	actor.emerged.connect(_on_emerged)


func _process(delta: float) -> void:
	var present := actor.is_present() and actor.visible
	_level = move_toward(_level, 1.0, delta / FADE_IN_SECONDS) if present else move_toward(_level, 0.0, delta / FADE_OUT_SECONDS)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var distance := camera.global_position.distance_to(presence.global_position)
		presence.panning_strength = lerpf(PANNING.x, PANNING.y, smoothstep(PANNING_RANGE.x, PANNING_RANGE.y, distance))
	presence.set_level(_level)


func _on_emerged() -> void:
	get_node("/root/Sfx").play(APPEAR, actor, CHEST)

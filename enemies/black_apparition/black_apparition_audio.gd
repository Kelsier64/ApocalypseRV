extends Node3D
## Black apparition sounds. Watching from the dark it only breathes, quietly
## enough to be heard within a few metres; enraged it shrieks once and every
## running footfall is placed. Retired, it is silent.

const SHRIEK: SoundEvent = preload("res://assets/audio/events/apparitions/black_shriek.tres")
const STEP: SoundEvent = preload("res://assets/audio/events/apparitions/black_step.tres")
const BREATHING: AudioStream = preload("res://assets/audio/apparitions/black_breathing.wav")
const MOUTH := Vector3(0.0, 2.3, 0.0)
## The visual's running cycle: the left foot lands at 0, the right at 0.5.
const PLANTS := {&"stride": [[0.0, 0], [0.5, 1]]}
## Stride weight below which the legs barely move and land no step.
const MIN_STRIDE_WEIGHT := 0.3

var actor: BlackApparition
var breathing: SoundLoop
var footfalls := MonsterFootfalls.new(PLANTS)
var _phase := BlackApparition.Phase.HIDDEN
var _level := 0.0


func _ready() -> void:
	actor = get_parent()
	breathing = SoundLoop.new()
	breathing.name = "Breathing"
	breathing.stream = BREATHING
	breathing.base_db = -16.0
	breathing.position = MOUTH
	breathing.occlusion_by_position = true
	preload("res://assets/audio/attenuation/breath.tres").apply(breathing)
	add_child(breathing)


func _physics_process(delta: float) -> void:
	var phase := actor.phase
	if phase == BlackApparition.Phase.FRENZIED and _phase != BlackApparition.Phase.FRENZIED:
		get_node("/root/Sfx").play(SHRIEK, actor, MOUTH)
	_phase = phase
	var observing := phase == BlackApparition.Phase.OBSERVING and actor.visible
	# Fade in over a second; stop at once on a rage or retirement.
	_level = move_toward(_level, 1.0, delta) if observing else 0.0
	breathing.set_level(_level)
	var visual: Node = actor.get_node_or_null("Visual")
	if phase != BlackApparition.Phase.FRENZIED or visual == null or visual.stride_weight() < MIN_STRIDE_WEIGHT:
		footfalls.advance(&"", 0.0)
		return
	if not footfalls.advance(&"stride", visual.stride_phase()).is_empty():
		get_node("/root/Sfx").play(STEP, actor)

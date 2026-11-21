extends Node3D
## Heavy Slender Speaker footfalls on its shared walk and run cycle, placed at
## the landing foot. They carry only to the giant attenuation's range, so from
## far away the loudspeaker melody stays the only warning.

const STEP: SoundEvent = preload("res://assets/audio/events/slender_speaker/step.tres")
## Plant phases of the shared cycle, between those of the walk and run clips.
const PLANTS := {&"gait": [[0.44, 0], [0.94, 1]]}
const FEET := ["foot.L", "foot.R"]
## The footfalls must still be plainly audible this far away.
const HEARD_WITHIN := 80.0

var actor: SlenderSpeaker
var footfalls := MonsterFootfalls.new(PLANTS)


func _ready() -> void:
	actor = get_parent()


func _physics_process(_delta: float) -> void:
	var phase := actor.gait_phase()
	if phase < 0.0 or actor.visual == null or actor.visual.get("available") != true:
		footfalls.advance(&"", 0.0)
		return
	for foot in footfalls.advance(&"gait", phase):
		get_node("/root/Sfx").play(STEP, actor, actor.to_local(actor.visual.bone_world(FEET[foot]).origin))

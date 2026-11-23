extends Node3D
## Raker sounds. Footfalls follow the gait clips; growls and clicks come every
## few seconds while it wanders or hunts, so it gives itself away at middle
## distance; every sweep and grab starts with its own tell, early enough to dodge
## by ear. Timing and sample picks use this node's RNG, never gameplay randomness.

const STEP: SoundEvent = preload("res://assets/audio/events/raker/step.tres")
const GROWL: SoundEvent = preload("res://assets/audio/events/raker/growl.tres")
const CLICK: SoundEvent = preload("res://assets/audio/events/raker/click.tres")
const WINDUP: SoundEvent = preload("res://assets/audio/events/raker/windup.tres")
const LUNGE: SoundEvent = preload("res://assets/audio/events/raker/lunge.tres")
## Seconds between idle vocals while wandering and while chasing.
const WANDER_VOCAL_SECONDS := Vector2(5.0, 10.0)
const CHASE_VOCAL_SECONDS := Vector2(2.5, 5.0)
## Mouth height for vocals and tells.
const MOUTH := Vector3(0.0, 2.2, 0.0)
## Vocals and tells must still be plainly audible this far away.
const VOCAL_HEARD_WITHIN := 30.0
## Plant phases of the gait clips, from the foot bones' lowest points.
const PLANTS := {
	&"game/walk": [[0.18, 0], [0.68, 1]],
	&"game/chase": [[0.21, 0], [0.71, 1]],
	&"game/sprint": [[0.28, 0], [0.78, 1]],
	&"game/crouch_walk": [[0.17, 0], [0.67, 1]],
}
const FEET := ["foot_L", "foot_R"]

var actor: Raker
var footfalls := MonsterFootfalls.new(PLANTS)
var vocal_in := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	actor = get_parent()
	_rng.randomize()
	vocal_in = _rng.randf_range(WANDER_VOCAL_SECONDS.x, WANDER_VOCAL_SECONDS.y)
	actor.attack_started.connect(_on_attack_started)


func _physics_process(delta: float) -> void:
	if actor.is_dead or actor.ragdoll.is_busy():
		footfalls.advance(&"", 0.0)
		return
	_footfalls()
	# Hold vocals through a strike or grab so they never cover its tell.
	if actor.grab.busy() or actor.strike_elapsed >= 0.0: return
	vocal_in -= delta
	if vocal_in > 0.0: return
	var chasing := actor.ai_state != Monster.State.WANDER
	var gap := CHASE_VOCAL_SECONDS if chasing else WANDER_VOCAL_SECONDS
	vocal_in = _rng.randf_range(gap.x, gap.y)
	get_node("/root/Sfx").play(GROWL if _rng.randf() < 0.6 else CLICK, actor, MOUTH)


func _footfalls() -> void:
	var visual: Node = actor.get_node_or_null("BodyMesh")
	if visual == null or actor.locomotion_state != Monster.LocomotionState.NORMAL or not actor.is_on_floor():
		footfalls.advance(&"", 0.0)
		return
	var player: AnimationPlayer = visual.get("animation_player")
	for foot in footfalls.advance(player.current_animation, MonsterFootfalls.player_phase(player)):
		get_node("/root/Sfx").play(STEP, actor, actor.to_local(visual.bone_world_position(FEET[foot])))


func _on_attack_started(clip: String, _duration: float) -> void:
	if clip.begins_with("grab_") and clip.ends_with("_reach"):
		get_node("/root/Sfx").play(LUNGE, actor, MOUTH)
	elif clip in ["attack_left", "attack_right", "crouch_attack", "attack_door", "attack_down"]:
		get_node("/root/Sfx").play(WINDUP, actor, MOUTH)

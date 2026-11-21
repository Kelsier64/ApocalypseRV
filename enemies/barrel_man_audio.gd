extends Node3D
## Barrel man sounds. A disguised or retracting barrel is silent, so it still
## passes for an ordinary one. Waking from the disguise clangs, the chase knocks
## and sloshes on each footfall, and the proximity fuse hisses up in pitch until
## the blast. A restored barrel never replays the wake.

const WAKE: SoundEvent = preload("res://assets/audio/events/barrel_man/wake.tres")
const STEP: SoundEvent = preload("res://assets/audio/events/barrel_man/step.tres")
const FUSE: AudioStream = preload("res://assets/audio/barrel_man/fuse.wav")
## Fuse pitch at arming and at the blast.
const FUSE_PITCH := Vector2(0.85, 1.6)
## Plant phases of the gait clips, from the foot bones' lowest points.
const PLANTS := {
	&"game/run": [[0.49, 0], [0.99, 1]],
	&"game/sprint": [[0.49, 0], [0.99, 1]],
}

var actor: BarrelMan
var fuse: SoundLoop
var footfalls := MonsterFootfalls.new(PLANTS)
var _phase := -1


func _ready() -> void:
	actor = get_parent()
	fuse = SoundLoop.new()
	fuse.name = "FuseHiss"
	fuse.stream = FUSE
	fuse.base_db = -10.0
	fuse.occlusion_by_position = true
	preload("res://assets/audio/attenuation/steps.tres").apply(fuse)
	add_child(fuse)


func _physics_process(_delta: float) -> void:
	var phase := actor.phase
	# The first tick only records the phase, so a restored barrel stays quiet.
	if _phase == BarrelMan.Phase.DISGUISED and phase == BarrelMan.Phase.RISING:
		get_node("/root/Sfx").play(WAKE, actor, Vector3.UP * 0.5)
	_phase = phase
	var remaining := actor.proximity_fuse_remaining
	var duration := actor.settings.proximity_fuse_duration
	if remaining >= 0.0 and not actor.is_dead and duration > 0.0:
		fuse.set_level(1.0, lerpf(FUSE_PITCH.x, FUSE_PITCH.y, 1.0 - remaining / duration))
	else:
		fuse.set_level(0.0)
	var visual: Node = actor.get_node_or_null("BodyMesh")
	if phase != BarrelMan.Phase.CHASE or visual == null or not actor.is_on_floor():
		footfalls.advance(&"", 0.0)
		return
	var player: AnimationPlayer = visual.get("animation_player")
	if player == null: return
	if not footfalls.advance(player.current_animation, MonsterFootfalls.player_phase(player)).is_empty():
		get_node("/root/Sfx").play(STEP, actor)

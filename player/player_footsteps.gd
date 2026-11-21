extends Node
## The player's own footfalls: one step per stride walked on a floor, chosen by
## the surface underfoot, louder sprinting and quieter crouched, and a heavier
## step on landing. Steps play where the sole meets the floor, so Sfx routes them
## to Cabin or Exterior like any other source. Crawling, climbing, flying and
## sitting make no steps.

const Kind := FootstepSurface.Kind
const EVENTS := {
	Kind.ASPHALT: preload("res://assets/audio/events/player/step_asphalt.tres"),
	Kind.GRAVEL: preload("res://assets/audio/events/player/step_gravel.tres"),
	Kind.DIRT: preload("res://assets/audio/events/player/step_dirt.tres"),
	Kind.GRASS: preload("res://assets/audio/events/player/step_grass.tres"),
	Kind.WOOD: preload("res://assets/audio/events/player/step_wood.tres"),
	Kind.METAL: preload("res://assets/audio/events/player/step_metal.tres"),
	Kind.CONCRETE: preload("res://assets/audio/events/player/step_concrete.tres"),
}
## Metres walked between footfalls at each gait.
const STRIDE := {&"walk": 1.9, &"sprint": 2.6, &"crouch": 1.0}
## Level of each gait against the event's own volume, in dB.
const GAIN := {&"walk": 0.0, &"sprint": 4.0, &"crouch": -9.0}
## Below this ground speed the player is standing still.
const MOVING_SPEED := 0.4
## Fraction of a stride already counted when the player starts to move, so the
## first step lands soon after the first press.
const START_STRIDE := 0.7
## Airborne time before touching down counts as a landing, and its extra level.
const LANDING_AIR_SECONDS := 0.3
const LANDING_GAIN := 5.0
## The floor probe runs from this high above the player origin to this far below.
const PROBE_ABOVE := 1.0
const PROBE_BELOW := 0.6
## Height of the sound above the floor contact.
const SOURCE_HEIGHT := 0.15

## The Player node; it has no class_name, so its members are reached dynamically.
var player: CharacterBody3D
var _normal_locomotion: int
var _walking_modes: Array = []
var _sprint_speed: float
## The most recent footfall's surface and gain, and the count so far, for tests
## and playground readouts.
var last_surface: Kind = Kind.CONCRETE
var last_gain_db := 0.0
var steps_taken := 0
var _travel := 0.0
var _air := 0.0


func _ready() -> void:
	player = get_parent()
	var script: Script = player.get_script()
	_normal_locomotion = script.LocomotionState.NORMAL
	_walking_modes = [script.PlayerMode.NORMAL, script.PlayerMode.PLACING]
	# Halfway between walking and sprinting: injuries shorten either stride.
	_sprint_speed = (script.SPEED + script.SPRINT_SPEED) * 0.5


func _physics_process(delta: float) -> void:
	if not _walking():
		_travel = STRIDE[&"walk"] * START_STRIDE
		_air = 0.0
		return
	if not player.is_on_floor():
		_air += delta
		return
	var gait := gait()
	if _air >= LANDING_AIR_SECONDS:
		step(GAIN[gait] + LANDING_GAIN)
		_travel = 0.0
	_air = 0.0
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if speed < MOVING_SPEED:
		_travel = STRIDE[gait] * START_STRIDE
		return
	_travel += speed * delta
	if _travel >= STRIDE[gait]:
		_travel = fmod(_travel, STRIDE[gait])
		step(GAIN[gait])


## The gait that sets stride and level now: walk, sprint or crouch.
func gait() -> StringName:
	if player.call(&"is_crouching"): return &"crouch"
	if Vector2(player.velocity.x, player.velocity.z).length() > _sprint_speed: return &"sprint"
	return &"walk"


## Plays one footfall on the floor below, if there is one.
func step(gain_db := 0.0) -> bool:
	var hit := _floor()
	if hit.is_empty(): return false
	last_surface = FootstepSurface.classify(hit.collider, hit.position, hit.normal)
	last_gain_db = gain_db
	steps_taken += 1
	# Ankle height, so a step on the cabin floor sits inside the cabin box and routes to Cabin.
	var at: Vector3 = hit.position + Vector3.UP * SOURCE_HEIGHT
	return get_node("/root/Sfx").play(EVENTS[last_surface], player, player.to_local(at), gain_db)


func _walking() -> bool:
	# Seated, dead, grabbed or executed, resting and menu modes do not move the
	# body, so its velocity is stale there; placing equipment still walks.
	return player.get(&"locomotion_state") == _normal_locomotion and player.call(&"get_player_mode") in _walking_modes \
		and not player.call(&"is_crawling") and not player.call(&"is_executing")


func _floor() -> Dictionary:
	var origin := player.global_position
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * PROBE_ABOVE, origin + Vector3.DOWN * PROBE_BELOW, player.collision_mask, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query)

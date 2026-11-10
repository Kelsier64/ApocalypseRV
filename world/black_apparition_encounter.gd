extends Node3D
class_name BlackApparitionEncounter
## One transient encounter, owned by the player's current World3D.

const SCENE := preload("res://enemies/black_apparition/black_apparition.tscn")
const Perception := preload("res://core/apparition_perception.gd")

@onready var _domain := get_parent() as Node3D
@onready var _start := _domain.get_node_or_null("StartRun") as StartRun
@onready var _instances := _domain.get_node_or_null("PoiInstances") as PoiInstanceManager
@onready var _clock := _domain.get_node_or_null("WorldClock") as WorldClock

var _indoors := false
var _interior_player: CharacterBody3D
var _player: CharacterBody3D
var _actor: BlackApparition
var _delay := 0.0
var _rng := RandomNumberGenerator.new()

static func attach_interior(domain: Node3D, player: CharacterBody3D) -> BlackApparitionEncounter:
	var encounter := BlackApparitionEncounter.new()
	encounter.name = "BlackApparitionEncounter"
	encounter._indoors = true
	encounter._interior_player = player
	domain.add_child(encounter)
	return encounter

func _physics_process(delta: float) -> void:
	if not _indoors:
		if _instances.busy: return
		if not _instances.active_id.is_empty():
			_clear()
			return
	var player := _interior_player if _indoors else _domain.get_node_or_null("Player") as CharacterBody3D
	if not WorldEntities.same_world(_domain, player) or player.is_queued_for_deletion() or player.get("is_player_dead") == true:
		_clear()
		return
	if not PlayerSurvival.simulation_active(player): return
	if not _indoors and _start.phase not in ["started", "closing", "sealed"]: return
	if _player != player:
		_clear()
		_player = player
		_delay = _new_delay()

	var hour := 0.0 if _indoors else _clock.hour_of_day()
	var daylight := not _indoors and hour >= 6.0 and hour < 18.0
	if is_instance_valid(_actor):
		_actor.set_daylight(daylight)
		if _actor.phase != BlackApparition.Phase.HIDDEN: return
		_actor.queue_free()
		_actor = null
		_delay = _new_delay()
	if daylight or Perception.player_camera(_domain, player) == null: return
	_delay -= delta
	if _delay > 0.0: return

	var actor := SCENE.instantiate() as BlackApparition
	var container := self if _indoors else WorldEntities.get_container(_domain)
	container.add_child(actor)
	actor.configure(player, _indoors)
	if actor.try_emerge():
		_actor = actor
	else:
		actor.queue_free()
		_delay = _rng.randf_range(15.0, 30.0) if _indoors else _rng.randf_range(45.0, 90.0)

func _new_delay() -> float:
	return _rng.randf_range(60.0, 120.0) if _indoors else _rng.randf_range(300.0, 540.0)

func _clear() -> void:
	if is_instance_valid(_actor): _actor.queue_free()
	_actor = null
	_player = null

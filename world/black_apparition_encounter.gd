extends Node
## One transient encounter, owned by the player's current World3D.

const SCENE := preload("res://enemies/black_apparition/black_apparition.tscn")
const Perception := preload("res://core/apparition_perception.gd")

@onready var world := get_parent() as Node3D
@onready var start := world.get_node("StartRun") as StartRun
@onready var instances := world.get_node("PoiInstances") as PoiInstanceManager
@onready var clock := world.get_node("WorldClock") as WorldClock

var _domain: Node3D
var _player: CharacterBody3D
var _actor: BlackApparition
var _delay := 0.0
var _rng := RandomNumberGenerator.new()

func _physics_process(delta: float) -> void:
	if instances.busy: return
	var interior := instances.interior
	var indoors := is_instance_valid(interior) and instances.state == PoiInstanceManager.State.INDOOR
	var domain: Node3D = interior if indoors else world
	var player := domain.get_node_or_null("Player") as CharacterBody3D
	if not WorldEntities.same_world(domain, player) or player.is_queued_for_deletion() or player.get("is_player_dead") == true:
		_clear()
		return
	if not PlayerSurvival.simulation_active(player) or start.phase not in ["started", "closing", "sealed"]: return
	if not is_instance_valid(_domain) or _domain != domain or _player != player:
		_clear()
		_domain = domain
		_player = player
		_delay = _new_delay(indoors)

	var hour := clock.hour_of_day()
	var daylight := not indoors and hour >= 6.0 and hour < 18.0
	if is_instance_valid(_actor):
		_actor.set_daylight(daylight)
		if _actor.phase != BlackApparition.Phase.HIDDEN: return
		_actor.queue_free()
		_actor = null
		_delay = _new_delay(indoors)
	if daylight or Perception.player_camera(domain, player) == null: return
	_delay -= delta
	if _delay > 0.0: return

	var actor := SCENE.instantiate() as BlackApparition
	WorldEntities.get_container(domain).add_child(actor)
	actor.configure(player, indoors)
	if actor.try_emerge():
		_actor = actor
	else:
		actor.queue_free()
		_delay = _rng.randf_range(15.0, 30.0) if indoors else _rng.randf_range(45.0, 90.0)

func _new_delay(indoors: bool) -> float:
	return _rng.randf_range(60.0, 120.0) if indoors else _rng.randf_range(300.0, 540.0)

func _clear() -> void:
	if is_instance_valid(_actor): _actor.queue_free()
	_actor = null
	_player = null
	_domain = null

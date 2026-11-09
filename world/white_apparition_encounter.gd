extends Node3D
## Owns the transient outdoor apparition for this world.

const APPARITION_SCENE := preload("res://enemies/white_apparition/white_apparition.tscn")
const INITIAL_DELAY_MIN := 25.0
const INITIAL_DELAY_MAX := 40.0

@onready var world := get_parent() as Node3D
@onready var generator := world.get_node("WorldGenerator")
@onready var start := world.get_node("StartRun") as StartRun
@onready var instances := world.get_node("PoiInstances") as PoiInstanceManager

var _rng := RandomNumberGenerator.new()
var _initial_delay := -1.0
var _apparition: WhiteApparition

func _ready() -> void:
	_rng.randomize()

func _physics_process(delta: float) -> void:
	var player := world.get_node_or_null("Player") as Node3D
	if not _outdoor_player_available(player):
		_reset_encounter()
		return
	if is_instance_valid(_apparition): return
	if player.get("in_ui_mode") or player.get("settings_open") or player.is_grabbed(): return
	if not WorldEntities.same_world(player, player.get_viewport().get_camera_3d()): return
	if _initial_delay < 0.0:
		_initial_delay = _rng.randf_range(INITIAL_DELAY_MIN, INITIAL_DELAY_MAX)
	_initial_delay -= delta
	if _initial_delay > 0.0: return
	var container := WorldEntities.get_container(world)
	_apparition = APPARITION_SCENE.instantiate() as WhiteApparition
	container.add_child(_apparition)
	_apparition.configure(player)
	_initial_delay = -1.0

func _outdoor_player_available(player: Node3D) -> bool:
	return world.get("play_ready") and not generator.restoring_entities \
		and start.phase in ["started", "closing", "sealed"] \
		and not instances.busy and instances.active_id.is_empty() \
		and WorldEntities.same_world(world, player) and not player.is_queued_for_deletion() \
		and not player.get("is_player_dead")

func _reset_encounter() -> void:
	if is_instance_valid(_apparition): _apparition.queue_free()
	_apparition = null
	_initial_delay = -1.0


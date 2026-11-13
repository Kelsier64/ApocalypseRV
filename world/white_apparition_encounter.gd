extends Node3D
## Owns the transient outdoor apparition for this world.

const APPARITION_SCENE := preload("res://enemies/white_apparition/white_apparition.tscn")

@onready var world := get_parent() as Node3D
@onready var generator := world.get_node("WorldGenerator")
@onready var start := world.get_node("StartRun") as StartRun
@onready var instances := world.get_node("PoiInstances") as PoiInstanceManager
@onready var clock := world.get_node("WorldClock") as WorldClock

var _apparition: WhiteApparition

func _physics_process(_delta: float) -> void:
	if instances.busy or not instances.active_id.is_empty():
		if is_instance_valid(_apparition): _apparition.suspend_outdoors()
		return
	var player := world.get_node_or_null("Player") as Node3D
	if not _outdoor_player_available(player):
		_reset_encounter()
		return
	if not is_instance_valid(_apparition):
		var container := WorldEntities.get_container(world)
		_apparition = APPARITION_SCENE.instantiate() as WhiteApparition
		container.add_child(_apparition)
	_apparition.configure(player, clock)
	_apparition.set_physics_process(true)

func _outdoor_player_available(player: Node3D) -> bool:
	return world.get("play_ready") and not generator.restoring_entities \
		and start.phase in ["started", "closing", "sealed"] \
		and WorldEntities.same_world(world, player) and not player.is_queued_for_deletion() \
		and not player.get("is_player_dead")

func _reset_encounter() -> void:
	if is_instance_valid(_apparition): _apparition.queue_free()
	_apparition = null


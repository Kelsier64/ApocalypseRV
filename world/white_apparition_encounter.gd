extends Node3D
## Owns the transient outdoor apparition for this world.

const APPARITION_SCENE := preload("res://enemies/white_apparition/white_apparition.tscn")

@onready var world := get_parent() as Node3D
@onready var generator := world.get_node("WorldGenerator")
@onready var start := world.get_node("StartRun") as StartRun
@onready var instances := world.get_node("PoiInstances") as PoiInstanceManager

var _apparition: WhiteApparition

func _physics_process(_delta: float) -> void:
	var player := world.get_node_or_null("Player") as Node3D
	if not _outdoor_player_available(player):
		_reset_encounter()
		return
	if is_instance_valid(_apparition): return
	var container := WorldEntities.get_container(world)
	_apparition = APPARITION_SCENE.instantiate() as WhiteApparition
	container.add_child(_apparition)
	_apparition.configure(player)

func _outdoor_player_available(player: Node3D) -> bool:
	return world.get("play_ready") and not generator.restoring_entities \
		and start.phase in ["started", "closing", "sealed"] \
		and not instances.busy and instances.active_id.is_empty() \
		and WorldEntities.same_world(world, player) and not player.is_queued_for_deletion() \
		and not player.get("is_player_dead")

func _reset_encounter() -> void:
	if is_instance_valid(_apparition): _apparition.queue_free()
	_apparition = null


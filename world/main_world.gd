extends "res://world/test_world.gd"
## Production world keeps the shared checkpoint/readiness contract.
var fresh_start := true

func _enter_tree() -> void:
	super._enter_tree()
	var generator := get_node("WorldGenerator")
	fresh_start = not generator.restoring_entities
	if not fresh_start: return
	if generator.world_seed < 0:
		generator.world_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	var field := WorldField.new(generator.world_seed, generator.profile)
	var site := field.stop(0)
	# Set both actors before child ready/physics, while the first chunk is built.
	get_node("Player").transform = site.building * Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-4, 1.5, -1))
	get_node("NewRv").transform = site.building * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.8, -1))

func _ready() -> void:
	super._ready()
	get_node("StartRun").apply_actor_state()

func _terrain_ready(generator: Node) -> bool:
	if not super._terrain_ready(generator): return false
	for entry in generator.active_chunks:
		if not entry.node.navigation_ready: return false
	return true

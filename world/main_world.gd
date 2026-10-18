extends "res://world/test_world.gd"
## Production world keeps the shared checkpoint/readiness contract.
var fresh_start := true
var _initial_placement_done := false

func _enter_tree() -> void:
	super._enter_tree()
	configure_tutorial_course()
	# Checkpoint commit reparents this prepared world and re-enters the tree.
	# Initial placement belongs only to the first entry, never to a transfer.
	if _initial_placement_done: return
	_initial_placement_done = true
	var generator := get_node("WorldGenerator")
	fresh_start = not generator.restoring_entities
	if not fresh_start: return
	if generator.world_seed < 0:
		generator.world_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	var field := WorldField.new(generator.world_seed, generator.profile)
	var site := field.stop(0)
	var version: int = generator.profile.generation_version
	var spawn_z := -41.0 if version >= 12 else (-388.0 if version == 11 else -1.0)
	# Set both actors before child ready/physics, while the first chunk is built.
	get_node("Player").transform = site.building * Transform3D(Basis(Vector3.UP, 0.0 if version >= 12 else -PI / 2.0), Vector3(0 if version >= 12 else -4, 1.5, spawn_z))
	get_node("NewRv").transform = site.building * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.8, -10.0 if version >= 12 else spawn_z))
	if version >= 12:
		get_node("NewRv/Chassis").current_fuel = 0.0
		get_node("NewRv/Chassis").starter_kits = false
	elif version == 11:
		var vehicle := get_node("NewRv/Chassis")
		vehicle.current_fuel = 40.0
		var terminal: Item = load("res://equipment/training_terminal.tscn").instantiate()
		terminal.name = "TrainingTerminal"
		terminal.position = Vector3(-1.74, 1.38, -3.05)
		terminal.rotation = Vector3(0, PI / 2.0, 0)
		terminal.initial_support = NodePath("../LeftFront")
		vehicle.add_child(terminal)

func configure_tutorial_course() -> void:
	# Select before child ready, including isolated checkpoint preparation.
	var tutorial := get_node("StartRun/Tutorial")
	var orientation: bool = get_node("WorldGenerator").profile.generation_version >= 12
	var course := load("res://world/tutorial_shelter/orientation_controller.gd" if orientation else "res://world/tutorial_shelter/tutorial_controller.gd")
	if tutorial.get_script() != course: tutorial.set_script(course)

func _ready() -> void:
	super._ready()
	get_node("StartRun").apply_actor_state()

func _terrain_ready(generator: Node) -> bool:
	if not super._terrain_ready(generator): return false
	for entry in generator.active_chunks:
		if not entry.node.navigation_ready: return false
	return true

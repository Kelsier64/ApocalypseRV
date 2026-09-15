extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var actor := Node3D.new()
	var player := Node3D.new()
	player.position.x = 10.0
	var chassis := Node3D.new()
	chassis.add_to_group(Groups.CHASSIS)
	chassis.position.x = 5.0
	var equipment := Node3D.new()
	equipment.add_to_group(Groups.EQUIPMENT)
	equipment.position.x = 1.0
	var structures := [equipment, chassis]
	var touching := func(node: Node3D) -> bool: return node == equipment
	var selected := CombatTargeting.select_target([player], structures, false, Vector3.ZERO, actor, null, touching)
	_expect(selected.get("node") == player, "Ground combat prioritizes players over nearby structure.")
	selected = CombatTargeting.select_target([], structures, false, Vector3.ZERO, actor, null, touching)
	_expect(selected.get("node") == chassis, "Ground structure selection prioritizes chassis over equipment.")
	selected = CombatTargeting.select_target([player], structures, true, Vector3.ZERO, actor, null, touching)
	_expect(selected.get("node") == equipment, "Climbing chooses only contacting structures, ignoring player.")
	selected = CombatTargeting.select_target([player], structures, true, Vector3.ZERO, actor, equipment, touching)
	_expect(selected.is_empty(), "Underfoot structure cannot bypass its separate attack authorization.")
	var child := Node3D.new()
	equipment.add_child(child)
	selected = CombatTargeting.select_target([], [equipment, child], false, Vector3.ZERO, actor, child, touching)
	_expect(selected.is_empty(), "Underfoot exclusion includes ancestors and descendants.")
	_expect(CombatTargeting.nearest([null, actor, player], Vector3.ZERO, actor) == player, "Nearest ignores null and self.")
	actor.free()
	player.free()
	chassis.free()
	equipment.free()
	if failures.is_empty():
		print("PASS: combat targeting policy")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

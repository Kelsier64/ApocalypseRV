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
	equipment.add_to_group(Groups.ITEMS)
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
	var immune := Item.new()
	immune.current_health = immune.max_health
	immune.is_fixed = true
	immune.add_to_group(Groups.MONSTER_DAMAGEABLE)
	_expect(not CombatTargeting.is_live_target(immune), "Items remain immune even with a stale damageable group.")
	_expect(CombatTargeting.build_target(immune, "structure").is_empty(), "Items cannot enter attack target records.")
	var monster := Monster.new()
	monster.attack_timer = 0.0
	monster._execute_attack_on_target({"node": immune, "target_type": "structure"})
	_expect(immune.current_health == immune.max_health and monster.attack_timer == 0.0, "Stale item target dispatch cannot damage or spend attack cooldown.")
	var collider := Node3D.new()
	immune.add_child(collider)
	chassis.add_child(immune)
	_expect(monster._resolve_underfoot_damageable_from_collider(collider) == null, "Collider resolution stops at an immune item before its chassis ancestor.")
	monster.free()
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

extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var player: CharacterBody3D = load("res://player/player.gd").new()
	_expect(InputMap.has_action("sprint"), "Sprint input action exists.")
	var shift_event := InputEventKey.new()
	shift_event.physical_keycode = KEY_SHIFT
	_expect(InputMap.event_is_action(shift_event, "sprint"), "Physical Shift triggers sprint.")
	Input.action_press("sprint")
	_expect(player._can_sprint(true), "Moving player can sprint at full stamina.")
	_expect(not player._can_sprint(false), "Standing player does not sprint.")
	player._update_stamina(1.0, true)
	_expect(is_equal_approx(player.current_stamina, 80.0), "Sprinting drains stamina per second.")
	player._update_stamina(0.5, false)
	_expect(is_equal_approx(player.current_stamina, 80.0), "Recovery waits after exertion.")
	player._update_stamina(0.5, false)
	player._update_stamina(1.0, false)
	_expect(is_equal_approx(player.current_stamina, 98.0), "Stamina recovers after delay.")
	_expect(player._spend_stamina(15.0), "Jump can spend enough stamina.")
	player.current_stamina = 14.0
	_expect(not player._spend_stamina(15.0), "Jump is blocked when stamina is insufficient.")
	_expect(is_equal_approx(player.current_stamina, 14.0), "Failed jump leaves stamina unchanged.")
	player.current_stamina = 1.0
	player._update_stamina(1.0, true)
	_expect(player.stamina_exhausted and not player._can_sprint(true), "Empty stamina stops sprinting.")
	player._update_stamina(1.0, false)
	player._update_stamina(1.0, false)
	player._update_stamina(1.0, false)
	_expect(not player.stamina_exhausted and player._can_sprint(true), "Sprint returns after exhaustion threshold.")
	Input.action_release("sprint")
	_expect(not player._can_sprint(true), "Releasing sprint returns to walking.")
	player.free()
	await _test_movement()
	if failures.is_empty():
		print("PASS: player stamina rules")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_movement() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	arena.add_child(floor_body)
	var actor: CharacterBody3D = load("res://player/player.tscn").instantiate()
	arena.add_child(actor)
	for i in range(30):
		await physics_frame
	_expect(actor.is_on_floor(), "Player lands on a real physics floor.")
	Input.action_press("move_forward")
	for i in range(4):
		await physics_frame
	var walk_speed := Vector2(actor.velocity.x, actor.velocity.z).length()
	Input.action_press("sprint")
	for i in range(4):
		await physics_frame
	var run_speed := Vector2(actor.velocity.x, actor.velocity.z).length()
	_expect(is_equal_approx(walk_speed, actor.SPEED), "Walking uses normal movement speed.")
	_expect(is_equal_approx(run_speed, actor.SPRINT_SPEED), "Shift raises actual movement speed.")
	_expect(actor.current_stamina < actor.MAX_STAMINA, "Running consumes stamina during physics movement.")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var stamina_before_jump: float = actor.current_stamina
	Input.action_press("jump")
	for i in range(2):
		await physics_frame
	_expect(actor.velocity.y > 0.0, "Space gives the grounded player upward velocity.")
	_expect(actor.current_stamina <= stamina_before_jump - actor.JUMP_STAMINA_COST, "Real jump spends stamina.")
	Input.action_release("jump")
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0, "transform": Transform3D.IDENTITY})
	_expect(actor.current_stamina == actor.MAX_STAMINA, "Old checkpoint state restores full stamina.")
	arena.queue_free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

extends SceneTree

var failures: Array[String] = []
var player: CharacterBody3D
var raker: Raker

func _init() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func _steps(count: int) -> void:
	for step in count:
		await physics_frame
		await process_frame

func _capture() -> void:
	player.grab_control.immunity = 0.0
	raker.grab.victim = player
	raker.grab._change(raker.grab.Phase.HOLD)
	_expect(player.begin_grab(raker, 10), "Raker captures flashlight holder")

func _release() -> void:
	raker.grab.cancel()
	player.set_physics_process(false)

func _check_beam(note: String) -> void:
	var beam := player.held_item_node.get_node("Beam") as SpotLight3D
	var toward_face := (raker.grab_face_position() - beam.global_position).normalized()
	_expect(beam.is_visible_in_tree(), note + ": flashlight remains visible and lit")
	_expect((-beam.global_basis.z).normalized().dot(toward_face) > .98, note + ": beam illuminates captor's face")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	raker = load("res://enemies/raker.tscn").instantiate()
	world.add_child(raker)
	raker.set_physics_process(false)
	player.add_item("Flashlight", false, "res://props/flashlight.tscn", {"flashlight": {"charge": 100.0, "on": false}})
	await _steps(12)
	player._toggle_flashlight()
	# Capture from front, side and behind: the body need not face its captor.
	for position in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		raker.position = position
		_capture()
		await _steps(12)
		_check_beam("Hold")
		var before: float = player.inventory.active_item().state.flashlight.charge
		player._advance_flashlight(1.5)
		_expect(is_equal_approx(player.inventory.active_item().state.flashlight.charge, before - .5), "Grabbed flashlight drains normally")
		player._toggle_flashlight()
		_expect(player.inventory.active_item().state.flashlight.on, "Struggle input cannot toggle the flashlight")
		raker.grab._change(raker.grab.Phase.BITE)
		raker.grab.elapsed = .1
		await _steps(6)
		_check_beam("Bite")
		_release()
		await _steps(12)
		var beam := player.held_item_node.get_node("Beam") as SpotLight3D
		_expect(beam.is_visible_in_tree() and not player.grab_control.keep_flashlight, "Release preserves light and clears grab override")
		_expect((-beam.global_basis.z).normalized().dot(-player.global_basis.z) > .95, "Release restores ordinary forward aim")
	player._toggle_flashlight()
	_capture()
	await _steps(3)
	player._advance_flashlight(10.0)
	_expect(not player.held_item_node.get_node("Beam").is_visible_in_tree() and not player.inventory.active_item().state.flashlight.on, "Previously switched-off light stays off during grab")
	_release()
	await _steps(3)
	player._toggle_flashlight()
	player.enter_ui_mode()
	_capture()
	await _steps(3)
	_expect(not player.grab_control.keep_flashlight and not player.held_item_node.get_node("Beam").is_visible_in_tree(), "UI-suppressed light is not activated by capture")
	_release()
	await _steps(3)
	player._advance_flashlight(0.0)
	_capture()
	await _steps(3)
	player._advance_flashlight(300.0)
	_expect(player.inventory.active_item().state.flashlight.charge == 0.0 and not player.held_item_node.get_node("Beam").is_visible_in_tree(), "Battery depletion extinguishes grabbed light")
	_release()
	world.free()
	if failures.is_empty(): print("PASS: flashlight persists and targets Raker through hold/bite, drains, and restores on release")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

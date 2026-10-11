extends SceneTree
func _init() -> void: run.call_deferred()
func run() -> void:
	var fixture: Node3D = load("res://tests/rear_pressure_playground.tscn").instantiate()
	root.add_child(fixture)
	current_scene = fixture
	for step in range(9000):
		if fixture.ready_for_test: break
		await physics_frame
	var ok: bool = fixture.ready_for_test and await fixture.traverse()
	fixture.free()
	await process_frame
	if ok: print("PASS: production player walks actual rear collision corridor and connected navigation to z120")
	else: push_error("FAIL: production rear wreck traversal")
	quit(0 if ok else 1)

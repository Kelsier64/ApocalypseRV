extends SceneTree
## Slicing must preserve geometry and collision, including every forest trunk.
const WAIT = preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var reference: Dictionary = {}
	for gradual in [false, true]:
		var chunk := ChunkGenerator.new()
		chunk.set_meta("skip_actors", true)
		world.add_child(chunk)
		await chunk.generate(WorldField.new(42), 0, POISpawner.new(), gradual)
		var ground := chunk.get_node("Ground") as MeshInstance3D
		var body := chunk.get_node("ForestTrunks") as StaticBody3D
		var poses: Array[Transform3D] = []
		for shape: CollisionShape3D in body.get_children():
			poses.append(shape.transform)
			check(shape.shape is BoxShape3D and not shape.disabled, "Trunks retain active box collision")
		check(body.is_inside_tree() and body.collision_layer == 1, "Completed forest participates in physics")
		var snapshot := {"faces": ground.mesh.get_faces(), "trunks": poses, "decorations": chunk.decoration_positions.duplicate()}
		if gradual:
			check(snapshot == reference, "Sliced and immediate generation produce identical ground and forest")
		else:
			reference = snapshot
		if not await WAIT.navigation_ready(self, [chunk]):
			check(false, "Navigation bake/publication timed out (gradual=%s)" % gradual)
			quit(1)
			return
		chunk.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: sliced generation preserves ground geometry, forest placements and active collision")
	quit(0 if failures.is_empty() else 1)

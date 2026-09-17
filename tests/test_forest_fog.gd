extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func _run() -> void:
	for seed_value in range(20):
		var field := WorldField.new(seed_value)
		var loot := field.loot_plan(0).duplicate()
		var poses := ForestFog.plans(field, 0)
		check(poses == ForestFog.plans(WorldField.new(seed_value), 0), "Fog placement repeatable for seed %d" % seed_value)
		check(field.loot_plan(0) == loot, "Fog RNG does not change loot")
		for pose in poses:
			check(floori(-pose.position.z / field.profile.chunk_length) == 0, "Fog belongs to exactly one streaming band")
			check(pose.size.y >= 10 and pose.size.x > 0 and pose.size.z > 0, "Fog volumes have stable thickness")
	var field := WorldField.new(42)
	var route: PackedVector3Array = field.stop(0).route
	var plans := ForestFog.plans(field, 0)
	for i in range(2, route.size() - 2, 2):
		check(plans.any(func(p): return (p.position - Vector3.UP * 2.5).distance_to(route[i]) < 0.01), "Raised trail mist is anchored above actual route, not valley floor")
	var chunk := ChunkGenerator.new()
	chunk.field = field
	chunk.band = 0
	root.add_child(chunk)
	ForestFog.build(chunk)
	if ForestFog.supported():
		check(chunk.has_node("ForestFog") and chunk.get_node("ForestFog").get_child_count() == plans.size(), "Supported renderer builds local volumes")
	else:
		check(not chunk.has_node("ForestFog"), "Fallback renderer does not create unsupported volumes")
	chunk.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: deterministic local fog, trail height, band ownership and renderer fallback")
	quit(0 if failures.is_empty() else 1)

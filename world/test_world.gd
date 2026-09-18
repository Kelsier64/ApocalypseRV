extends Node3D
signal ready_for_play
var play_ready := false
var restore_result: Dictionary = {"ok": true}

func _enter_tree() -> void:
	set_meta("entity_domain", true)
	if not has_meta("checkpoint_staging"): Checkpoint.prepare_world(self)

func _ready() -> void:
	if not has_meta("checkpoint_staging"): restore_result = Checkpoint.restore_world(self)
	_mark_ready.call_deferred()

func wait_for_play(timeout_ms := 60000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not play_ready and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return play_ready and restore_result.ok

func _mark_ready() -> void:
	var generator := get_node("WorldGenerator")
	while true:
		while not _terrain_ready(generator):
			await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().process_frame
		# Streaming may retire a chunk while we await navigation synchronization.
		# Inspect the current set each time; never retain a node across an await.
		if _terrain_ready(generator): break
	if not restore_result.ok or not is_instance_valid(generator.player): return
	play_ready = true
	ready_for_play.emit()

func _terrain_ready(generator: Node) -> bool:
	if generator.building or generator.active_chunks.is_empty(): return false
	for chunk in generator.active_chunks:
		if not is_instance_valid(chunk.node): return false
		var navigation: NavigationRegion3D = chunk.node.navigation
		if is_instance_valid(navigation) and NavigationServer3D.is_baking_navigation_mesh(navigation.navigation_mesh): return false
	return true

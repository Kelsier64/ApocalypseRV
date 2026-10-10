extends Node3D
signal ready_for_play
var play_ready := false
var restore_result: Dictionary = {"ok": true}
var _ready_physics_frame := -1

func _enter_tree() -> void:
	set_meta("entity_domain", true)
	if not has_meta("checkpoint_staging"): Checkpoint.prepare_world(self)
	if is_node_ready() and not play_ready: _mark_ready.call_deferred()

func _exit_tree() -> void:
	_ready_physics_frame = -1
	if get_tree().process_frame.is_connected(_poll_ready):
		get_tree().process_frame.disconnect(_poll_ready)

func _ready() -> void:
	if not has_meta("checkpoint_staging"): restore_result = Checkpoint.restore_world(self)
	_mark_ready.call_deferred()

func wait_for_play(timeout_ms := 60000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not play_ready and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return play_ready and restore_result.ok

func _mark_ready() -> void:
	if not is_inside_tree() or play_ready: return
	# A bound signal connection is removed when this world is freed. Unlike
	# a coroutine awaiting the global tree, cancellation cannot resume a dead
	# world. Signals also run while checkpoint staging disables node processing.
	if not get_tree().process_frame.is_connected(_poll_ready):
		get_tree().process_frame.connect(_poll_ready)

func _poll_ready() -> void:
	var generator := get_node("WorldGenerator")
	# Inspect the current streaming set each frame; keep only the frame number,
	# never a chunk that may retire while navigation is synchronizing.
	if not _terrain_ready(generator):
		_ready_physics_frame = -1
		return
	if _ready_physics_frame < 0:
		_ready_physics_frame = Engine.get_physics_frames()
		return
	if Engine.get_physics_frames() <= _ready_physics_frame: return
	get_tree().process_frame.disconnect(_poll_ready)
	if not restore_result.ok or not is_instance_valid(generator.player): return
	play_ready = true
	ready_for_play.emit()

func _terrain_ready(generator: Node) -> bool:
	if generator.building or generator.active_chunks.is_empty(): return false
	for chunk in generator.active_chunks:
		if not is_instance_valid(chunk.node) or not chunk.node.navigation_ready: return false
	return true

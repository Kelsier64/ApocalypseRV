extends Node
class_name OrientationRecovery
## Full-world lesson entrances are independent of the mutable current lesson.
## The controller serializes capture() only when include_retry is true.
var controller: Node
var entry_snapshot: Dictionary = {}
var _boundary := -1
var _entrance_evidence: Dictionary = {}
var _entrance_pending := false
var _stable_seconds := 0.0
var _manual_synced := false

func _ready() -> void:
	_connect_progress()

func _connect_progress() -> void:
	if controller != null and not controller.progress_changed.is_connected(_observe_progress):
		controller.progress_changed.connect(_observe_progress)

func _world() -> Node:
	return controller._world()

func _checkpoint() -> Node:
	return get_node_or_null("/root/Checkpoint")

func boundary() -> int:
	return int(controller.workshop.step) if controller.flags.workshop_entered else 0

func capture() -> Dictionary:
	return entry_snapshot.duplicate(true)

func restore(snapshot: Dictionary) -> void:
	entry_snapshot = snapshot.duplicate(true)
	_boundary = -1
	_entrance_evidence.clear()
	_entrance_pending = false
	_stable_seconds = 0.0
	_manual_synced = false
	_connect_progress()

func _evidence() -> Dictionary:
	var evidence := {"flags": controller.flags.duplicate(true), "workshop": controller.workshop.capture()}
	# Enter and an unfinished boot are progress too, even before the course's
	# boot_complete signal. Internal power consumption is not lesson evidence.
	if boundary() == 0:
		var terminal: Item = controller.designated_terminal()
		if terminal != null:
			var boot: Dictionary = terminal.boot_state()
			for key in ["boot_started", "boot_elapsed", "initialized"]:
				evidence[key] = boot.get(key)
	return evidence

func _observe_progress() -> void:
	if not controller.initialized() or controller.workshop == null or not controller.workshop.configured: return
	if controller.status != "active": return
	var next := boundary()
	var evidence := _evidence()
	if next != _boundary:
		# Restored snapshots already own their original entrance. Only a new
		# boundary discards it; ordinary same-step progress must never replace it.
		if _boundary >= 0: entry_snapshot.clear()
		_boundary = next
		_entrance_evidence = evidence
		_entrance_pending = entry_snapshot.is_empty()
		# Run only after the native transaction has returned. The next physics
		# tick is a fallback when a modal operation is still finishing.
		tick.call_deferred()
	elif _entrance_pending and evidence != _entrance_evidence:
		if next > 0:
			# Optional references can finish together or in any order. Preserve
			# their next settled guide boundary, including a batch of extra salvage.
			_entrance_evidence = evidence
		else:
			# Reception remains mandatory; do not relabel a partial boot as its
			# original entrance. Existing captured boundaries are never overwritten.
			_entrance_pending = false
			_stable_seconds = 0.0

func tick(delta := 0.0) -> void:
	_connect_progress()
	if not controller.initialized() or _world() == null or _world().has_meta("checkpoint_staging"): return
	if controller.status in ["completed", "skipped"]:
		if not _manual_synced: unlock_manual(controller.status)
		return
	if not controller._active_world() or _world().get("play_ready") != true: return
	_observe_progress()
	var checkpoint := _checkpoint()
	var player: Node = _world().get_node_or_null("Player")
	var vehicle: Chassis = controller.designated_rv()
	if checkpoint == null or checkpoint.loading or player == null or vehicle == null: return
	if player.settings_open or player.get_player_mode() not in [player.PlayerMode.NORMAL, player.PlayerMode.UI] or not controller.get_parent().save_block_reason().is_empty():
		_stable_seconds = 0.0
		return
	if vehicle.linear_velocity.length() > 0.25 or vehicle.angular_velocity.length() > 0.1:
		_stable_seconds = 0.0
		return
	_stable_seconds += delta if delta > 0.0 else get_physics_process_delta_time()
	if not _entrance_pending or not entry_snapshot.is_empty(): return
	if _stable_seconds < 0.5: return
	# Checkpoint also rejects terrain/navigation publication, POI transitions,
	# previews, grabs and every native vehicle operation. Never write the file.
	var snapshot: Dictionary = checkpoint.capture_world(_world(), false, true)
	if snapshot.is_empty(): return
	entry_snapshot = snapshot
	_entrance_pending = false
	controller.progress_changed.emit()

func can_restart() -> bool:
	var checkpoint := _checkpoint()
	return controller.initialized() and controller.status == "active" and controller._active_world() and _normal_player() and not entry_snapshot.is_empty() and checkpoint != null and not checkpoint.loading

func restart_stage() -> bool:
	if not can_restart(): return false
	# Transactional staging retains the current world on rejection or timeout.
	return await _checkpoint().load_snapshot(_world(), entry_snapshot.duplicate(true))

func can_skip() -> bool:
	var checkpoint := _checkpoint()
	return controller.initialized() and controller.status == "active" and controller._active_world() and _normal_player() and checkpoint != null and not checkpoint.loading

func _normal_player() -> bool:
	var player: Node = _world().get_node_or_null("Player")
	return player != null and player.get_player_mode() == player.PlayerMode.NORMAL

func skip_tutorial() -> bool:
	if not can_skip(): return false
	var player: Node = _world().get_node_or_null("Player")
	if player == null or player.settings_open or player.get_player_mode() != player.PlayerMode.NORMAL: return false
	controller.status = "skipped"
	entry_snapshot.clear()
	_entrance_pending = false
	unlock_manual("skipped")
	controller.get_parent().apply_tutorial_gates()
	controller.progress_changed.emit()
	return true

func unlock_manual(result: String) -> void:
	if result not in ["completed", "skipped"]: return
	_manual_synced = true
	_unlock_live(_world(), result)
	var player: Node = _world().get_node_or_null("Player")
	if player != null:
		_unlock_records(player.inventory.items, result)
		player.refresh_inventory()
	for vehicle in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if _world().is_ancestor_of(vehicle): _unlock_records(vehicle.stored_items, result)
	var generator := _world().get_node_or_null("WorldGenerator")
	if generator != null: _unlock_records(generator.dormant_items, result)
	var manager := _world().get_node_or_null("PoiInstances")
	if manager != null: _unlock_records(manager.saved_instances, result)

func _unlock_live(node: Node, result: String) -> void:
	# Includes inventory reader and held presentation; a later live-state sync
	# must not overwrite the unlocked record with the old locked presentation.
	if node is TrainingTerminal and node.persistent_id == controller.terminal_id and not node.is_queued_for_deletion(): node.unlock_manual(result)
	for child in node.get_children(): _unlock_live(child, result)

func _unlock_records(value: Variant, result: String) -> void:
	if value is Dictionary:
		if value.get("id", "") == controller.terminal_id and value.get("training_terminal") is Dictionary:
			# Mutate only completion. In particular, retain portable v2 identity,
			# internal charge, partial boot and original dock-lock evidence.
			value.training_terminal.manual_unlocked = true
			value.training_terminal.completion = result
		for child in value.values(): _unlock_records(child, result)
	elif value is Array:
		for child in value: _unlock_records(child, result)

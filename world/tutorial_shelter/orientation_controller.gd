extends Node
class_name OrientationController
## The v12 reception lesson owns its evidence independently of the v11 course.
signal progress_changed
const COURSE := "two_room_orientation"
const STATE_VERSION := 2
const TERMINAL_SCENE := "res://equipment/training_terminal.tscn"
const ROOM_DIVIDER_Z := -26.0
var stage := 1
var status := "active"
var terminal_id := ""
var rv_id := ""
var workshop: OrientationWorkshop
var flags := {"boot_complete": false, "terminal_taken": false, "workshop_entered": false}
var _previous_player := Vector3.INF
var _disabled := false

func _ready() -> void:
	_ensure_workshop()
	add_to_group("tutorial_controller")
	var world := _world()
	if world != null and world.has_signal("ready_for_play"):
		world.ready_for_play.connect(_on_world_ready)

func _world() -> Node3D:
	return get_parent().get_parent() as Node3D if get_parent() != null else null

func _on_world_ready() -> void:
	if not _active_world(): return
	if initialized():
		_sync_dock_marker()
		_prepare_workshop()
		return
	if _disabled or _world().get("fresh_start") != true: return
	var building: Node = get_parent().get("shelter")
	if not is_instance_valid(building): return
	var support := building.get_node_or_null("Collision/TerminalSupport")
	if support != null:
		var identity: Variant = support.get_meta("training_terminal_dock", "")
		if identity is String: configure(identity)
	_prepare_workshop()

func _ensure_workshop() -> void:
	if workshop != null: return
	workshop = OrientationWorkshop.new()
	workshop.name = "Workshop"
	workshop.controller = self
	add_child(workshop)

func _prepare_workshop() -> void:
	_ensure_workshop()
	if not initialized() or workshop.configured: return
	if _world().get("fresh_start") != true and not workshop.migration_pending: return
	var vehicle := designated_rv()
	if vehicle != null: workshop.prepare(vehicle, workshop.migration_pending)

func _sync_dock_marker() -> void:
	var building: Node = get_parent().get("shelter")
	if not initialized() or not is_instance_valid(building): return
	var support := building.get_node_or_null("Collision/TerminalSupport")
	if support != null: support.set_meta("training_terminal_dock", terminal_id)

func configure(identity: String) -> void:
	if identity.is_empty() or initialized() or _disabled: return
	terminal_id = identity
	progress_changed.emit()

func initialized() -> bool:
	return not _disabled and not terminal_id.is_empty()

func _active_world() -> bool:
	var world := _world()
	return world != null and not world.has_meta("checkpoint_staging") and get_parent().get("phase") == "preparing"

func _accepts_player(player: Node3D) -> bool:
	var world := _world()
	return initialized() and _active_world() and status == "active" and player != null and player == world.get_node_or_null("Player") and WorldEntities.same_world(world, player)

func designated_terminal() -> Item:
	if not initialized() or not is_inside_tree(): return null
	for item in get_tree().get_nodes_in_group(Groups.ITEMS):
		if item is Item and item.persistent_id == terminal_id and not item.presentation_only and not item.is_queued_for_deletion() and _world().is_ancestor_of(item) and WorldEntities.same_world(_world(), item): return item
	return null

func designated_rv() -> Chassis:
	if _world() == null: return null
	if rv_id.is_empty():
		var original := _world().get_node_or_null("NewRv/Chassis") as Chassis
		if original != null: return original
		# v1 had no vehicle ID. Checkpoint restoration reparents chassis roots;
		# migrate only the sole vehicle physically inside the locked workshop.
		if workshop == null or not workshop.migration_pending or not is_inside_tree(): return null
		var building := get_parent().get("shelter") as Node3D
		if not is_instance_valid(building): return null
		var candidates: Array[Chassis] = []
		for vehicle in get_tree().get_nodes_in_group(Groups.CHASSIS):
			if not vehicle is Chassis or vehicle.is_queued_for_deletion() or not _world().is_ancestor_of(vehicle) or not WorldEntities.same_world(_world(), vehicle): continue
			var point := building.to_local(vehicle.global_position)
			if absf(point.x) < 19.0 and point.z >= ROOM_DIVIDER_Z and point.z < 14.0 and point.y >= -1.0 and point.y < 8.0: candidates.append(vehicle)
		if candidates.size() != 1: return null
		rv_id = candidates[0].persistent_id
		return candidates[0]
	if not is_inside_tree(): return null
	for vehicle in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if vehicle is Chassis and vehicle.persistent_id == rv_id and not vehicle.is_queued_for_deletion() and _world().is_ancestor_of(vehicle) and WorldEntities.same_world(_world(), vehicle): return vehicle
	return null

func terminal_initialized(identity: String, player: Node3D) -> void:
	if not _accepts_player(player) or identity != terminal_id or flags.boot_complete: return
	var terminal := designated_terminal()
	if terminal == null or not terminal.can_operate() or not terminal.has_method("has_completed_boot") or not terminal.has_completed_boot(): return
	var ui: Node = terminal.get("ui_instance")
	if terminal.get("current_user") != player or not is_instance_valid(ui) or not ui.visible or not player.get("in_ui_mode"): return
	flags.boot_complete = true
	progress_changed.emit()

func terminal_in_inventory(player: Node3D) -> bool:
	if not _accepts_player(player): return false
	var inventory: PlayerInventory = player.get("inventory")
	if inventory == null: return false
	for entry: Dictionary in inventory.items:
		if entry.get("scene_path", "") != TERMINAL_SCENE: continue
		var state: Dictionary = entry.get("state", {})
		var boot: Dictionary = state.get("training_terminal", {})
		if state.get("id", "") == terminal_id and boot.get("version") == 2 and boot.get("initialized") == true and ItemState.valid(TERMINAL_SCENE, state): return true
	return false

func terminal_docked_pickup(identity: String, player: Node3D) -> void:
	# TrainingTerminal calls only after its original dock and the native inventory
	# transaction succeeded. Generic acquisition/removing signals are insufficient.
	if not _accepts_player(player) or identity != terminal_id or not flags.boot_complete or flags.terminal_taken: return
	var terminal := designated_terminal()
	if terminal == null or terminal.is_fixed or not terminal.support_lost or terminal.is_destroyed or terminal.current_health <= 0.0 or terminal.is_being_placed: return
	if not terminal_in_inventory(player): return
	flags.terminal_taken = true
	_previous_player = Vector3.INF
	progress_changed.emit()

func conditions_viewed(_identity: String, _player: Node3D) -> void:
	pass # Merely opening or reading the UI never initializes the system.

func inner_gate_unlocked() -> bool:
	return initialized() and flags.terminal_taken

func terminal_page() -> Dictionary:
	if not initialized() or not flags.boot_complete:
		return {"available": false, "stage": 1, "title": "System initialization required"}
	if flags.workshop_entered:
		_ensure_workshop()
		return workshop.page()
	return {"available": true, "stage": 1, "title": "Take your field terminal",
		"conditions": [{"id": "terminal_taken", "label": "Take this terminal with you.", "complete": flags.terminal_taken}],
		"steps": ["Close this interface, then hold F while looking at the terminal to remove it into your inventory.", "Carry the same terminal through the open door into the workshop."],
		"reference": ["Esc: close the terminal.", "Hold F: remove the fixed terminal.", "T: read the selected terminal from your inventory."]}

func _physics_process(_delta: float) -> void:
	if not _active_world(): return
	if not initialized():
		_on_world_ready()
		return
	_sync_dock_marker()
	_prepare_workshop()
	if workshop != null and workshop.configured: workshop.tick()
	if flags.workshop_entered or not flags.terminal_taken: return
	var player := _world().get_node_or_null("Player") as Node3D
	var building := get_parent().get("shelter") as Node3D
	if not _accepts_player(player) or not is_instance_valid(building) or _world().get("play_ready") != true: return
	var point := building.to_local(player.global_position)
	# Observe a short, continuous crossing through the real doorway, excluding
	# restoration/teleports and entry through the building's sides or roof.
	if _previous_player.is_finite() and point.distance_to(_previous_player) < 2.0 and absf(point.x) <= 3.5 and absf(_previous_player.x) <= 3.5 and point.y >= 0.0 and point.y <= 5.0 and _previous_player.z < ROOM_DIVIDER_Z and point.z >= ROOM_DIVIDER_Z:
		flags.workshop_entered = true
		stage = 2
		progress_changed.emit()
	_previous_player = point

func save_state() -> Dictionary:
	if not initialized(): return {}
	_ensure_workshop()
	return {"version": STATE_VERSION, "course": COURSE, "stage": stage, "status": status, "terminal_id": terminal_id, "rv_id": rv_id, "flags": flags.duplicate(true), "workshop": workshop.capture()}

func capture(_include_retry := true) -> Dictionary:
	return save_state()

static func validation_error(value: Variant) -> String:
	if not value is Dictionary: return "state"
	var version: Variant = value.get("version")
	var fields := ["version", "course", "stage", "status", "terminal_id", "flags"]
	if version == STATE_VERSION: fields.append_array(["rv_id", "workshop"])
	if value.size() != fields.size() or not value.has_all(fields): return "fields"
	if not value.version is int or value.version not in [1, STATE_VERSION]: return "version"
	if not value.course is String or value.course != COURSE: return "course"
	if not value.stage is int or value.stage not in [1, 2]: return "stage"
	if not value.status is String or value.status != "active": return "status"
	if not value.terminal_id is String or value.terminal_id.is_empty(): return "terminal_id"
	var saved: Variant = value.flags
	var names := ["boot_complete", "terminal_taken", "workshop_entered"]
	if not saved is Dictionary or saved.size() != names.size() or not saved.has_all(names): return "flags"
	for key in names:
		if not saved[key] is bool: return "flags." + key
	if saved.terminal_taken and not saved.boot_complete: return "flags.terminal_taken"
	if saved.workshop_entered and not saved.terminal_taken: return "flags.workshop_entered"
	if (value.stage == 2) != saved.workshop_entered: return "stage"
	if version == STATE_VERSION:
		if not value.rv_id is String: return "rv_id"
		var error := OrientationWorkshop.validation_error(value.workshop)
		if not error.is_empty(): return "workshop." + error
		if value.workshop.configured and value.rv_id.is_empty(): return "rv_id"
		if value.rv_id == value.terminal_id: return "rv_id.alias"
		var references: Array = []
		references.append_array(value.workshop.output_ids)
		references.append_array(value.workshop.targets.values())
		if not value.workshop.empty_can_id.is_empty(): references.append(value.workshop.empty_can_id)
		if value.terminal_id in references or not value.rv_id.is_empty() and value.rv_id in references: return "workshop.id.alias"
		if not saved.workshop_entered and value.workshop.step != 1: return "workshop.step"
	return ""

static func validate_state(value: Variant) -> bool:
	return validation_error(value).is_empty()

func apply_state(data: Dictionary) -> bool:
	if not validate_state(data): return false
	_disabled = false
	stage = data.stage
	status = data.status
	terminal_id = data.terminal_id
	rv_id = data.get("rv_id", "")
	flags = data.flags.duplicate(true)
	_ensure_workshop()
	if data.version == 1:
		var initial := OrientationWorkshop.new()
		initial.migration_pending = true
		workshop.restore(initial.capture())
		initial.free()
	else: workshop.restore(data.workshop)
	_previous_player = Vector3.INF
	progress_changed.emit()
	return true

func restore(data: Dictionary) -> void:
	if data.is_empty():
		_disabled = true
		return
	apply_state(data)

func can_restart() -> bool: return false
func restart_stage() -> bool: return false
func can_skip() -> bool: return false
func skip_tutorial() -> bool: return false
func departure_block_reason() -> String: return "Prepare the vehicle before departure"
func departure_started() -> void: pass
func departure_completed() -> void: pass

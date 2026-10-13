extends Node
class_name TutorialController
## Persistent lesson owner. Devices present this state; they never own progress.
signal progress_changed
const TERMINAL_SCENE := "res://equipment/training_terminal.tscn"
const FLASHLIGHT_SCENE := "res://props/flashlight.tscn"
const MARKER_Z := [-372.0, -342.0]
const PARKING := AABB(Vector3(-3.5, -1, -371), Vector3(7, 8, 18))
var stage := 1
var status := "active"
var terminal_id := ""
var rv_id := ""
var flashlight_id := ""
var flags := {"viewed": false, "flashlight": false, "marker_index": 0, "reversed": false, "parked": false}
var entry_snapshot: Dictionary = {}
var legacy_disabled := false
var _previous := Vector3.INF
var _reverse_distance := 0.0
var _park_seconds := 0.0
var _park_min := Vector2.ZERO
var _park_max := Vector2.ZERO
var _snapshot_seconds := 0.0
var workshop: TutorialWorkshop
var service: TutorialService

func _ensure_workshop() -> void:
	if workshop != null: return
	workshop = TutorialWorkshop.new()
	workshop.name = "Workshop"
	workshop.controller = self
	add_child(workshop)
	service = TutorialService.new()
	service.name = "Service"
	service.controller = self
	add_child(service)

func initialized() -> bool:
	return not terminal_id.is_empty() and not legacy_disabled

func _ready() -> void:
	_ensure_workshop()
	_world().ready_for_play.connect(_on_world_ready)

func _on_world_ready() -> void:
	if legacy_disabled or _world().has_meta("checkpoint_staging") or not _run().is_tutorial_shelter(): return
	if _world().fresh_start:
		_initialize()
		_capture_entry()

func _capture_entry() -> void:
	if not initialized() or not entry_snapshot.is_empty(): return
	if stage == 7 and not service.configured: return
	var player := _world().get_node("Player")
	var generator := _world().get_node("WorldGenerator")
	if player.get_player_mode() != player.PlayerMode.NORMAL or player.settings_open or generator.building: return
	if not _run().save_block_reason().is_empty(): return
	var snapshot: Dictionary = _checkpoint().capture_world(_world(), false)
	if not snapshot.is_empty():
		entry_snapshot = snapshot
		progress_changed.emit()

func _world() -> Node3D:
	return get_parent().get_parent()

func _run() -> StartRun:
	return get_parent()

func _checkpoint() -> Node:
	return get_node("/root/Checkpoint")

func capture(include_retry := true) -> Dictionary:
	if not initialized(): return {}
	var data := {"version": 3 if workshop != null and workshop.prepared() else 1, "stage": stage, "status": status, "terminal_id": terminal_id,
		"rv_id": rv_id, "flashlight_id": flashlight_id, "flags": flags.duplicate(true)}
	if data.version == 3:
		data["workshop"] = workshop.capture()
		data["service"] = service.capture()
	if include_retry and not entry_snapshot.is_empty(): data["entry_snapshot"] = entry_snapshot.duplicate(true)
	return data

func restore(data: Dictionary) -> void:
	_ensure_workshop()
	legacy_disabled = data.is_empty()
	if legacy_disabled: return
	stage = data.stage
	status = data.status
	terminal_id = data.terminal_id
	rv_id = data.rv_id
	flashlight_id = data.flashlight_id
	flags = data.flags.duplicate(true)
	entry_snapshot = data.get("entry_snapshot", {}).duplicate(true)
	workshop.restore(data.get("workshop", {}))
	service.restore(data.get("service", {}))
	_upgrade_entry()
	_previous = Vector3.INF
	_reverse_distance = 4.0 if flags.reversed else 0.0
	_park_seconds = 0.0
	progress_changed.emit()

func _upgrade_entry() -> void:
	if not workshop.prepared() or entry_snapshot.is_empty(): return
	var saved: Dictionary = entry_snapshot.start_state.tutorial
	if saved.version >= 3: return
	# Older phase-three saves could capture bay 7 before its faults existed.
	# This lesson requires a fresh boundary after its single setup transaction.
	if stage == 7 and not service.configured:
		entry_snapshot.clear()
		return
	saved.version = 3
	saved["service"] = service.capture()

func terminal_page() -> Dictionary:
	if not initialized(): return {"available": false, "stage": 1, "title": "Preparing training records"}
	if stage >= 7: return service.page()
	if stage >= 2 and workshop != null and workshop.prepared(): return workshop.page()
	return {"available": true, "stage": 1, "title": "Basic operation and driving",
		"conditions": [
			{"id": "viewed", "label": "Inspect this terminal's Conditions page", "complete": flags.viewed},
			{"id": "flashlight", "label": "Pick up the shelter flashlight", "complete": flags.flashlight},
			{"id": "markers", "label": "Drive through lane markers 01 and 02 in order (%d/2)" % flags.marker_index, "complete": flags.marker_index == 2},
			{"id": "reversed", "label": "Reverse into the marked parking bay", "complete": flags.reversed},
			{"id": "parked", "label": "Park fully inside, stop, apply handbrake and switch off the engine", "complete": flags.parked}],
		"steps": ["Collect the flashlight from the first bay's supply area.", "Board the RV using the side ladder; inspect the terminal inside the front cabin.",
			"Take the driver's seat. Start the engine, release the handbrake and drive along the central lane.",
			"Cross both numbered floor markers. Stop beyond 02, then select reverse.",
			"Reverse at least four metres into the outlined parking bay. Stop completely, apply the handbrake and shut down the engine.",
			"When every condition is recorded, the first bay gate opens automatically."],
		"reference": ["E: pick up loose items. Hold E: use a fixed terminal or take the driver's seat.",
			"W/S: throttle / foot brake. A/D: steer. Space: toggle handbrake. B: start / stop engine.",
			"Z: reverse. X: neutral. C: first gear. E: leave the seat.", "Esc: close the terminal. Restart Stage is available in the Esc menu."]}

func conditions_viewed(identity: String, player: Node3D) -> void:
	if not initialized() or stage != 1 or identity != terminal_id or player != _world().get_node("Player"): return
	# The successful presentation is checked at the device boundary as well as here.
	var terminal := designated_terminal()
	if terminal == null or terminal.get("current_user") != player: return
	var ui: Node = terminal.get("ui_instance")
	if ui == null or not ui.visible or ui.get("current_page") != "conditions" or not player.in_ui_mode: return
	flags.viewed = true
	progress_changed.emit()

func designated_terminal() -> Item:
	for item in get_tree().get_nodes_in_group(Groups.ITEMS):
		if item is Item and item.persistent_id == terminal_id and _world().is_ancestor_of(item) and WorldEntities.same_world(_world(), item): return item
	return null

func designated_rv() -> Chassis:
	for vehicle in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if vehicle is Chassis and vehicle.persistent_id == rv_id and _world().is_ancestor_of(vehicle) and WorldEntities.same_world(_world(), vehicle): return vehicle
	return null

func _item_acquired(identity: String, scene: String) -> void:
	if workshop != null: workshop.acquired(identity, scene)
	if stage == 1 and initialized() and identity == flashlight_id and scene == FLASHLIGHT_SCENE:
		flags.flashlight = true
		progress_changed.emit()

func _connect_player() -> void:
	var player := _world().get_node("Player")
	if not player.item_acquired.is_connected(_item_acquired): player.item_acquired.connect(_item_acquired)

func _initialize() -> void:
	var vehicle: Chassis = _world().get_node_or_null("NewRv/Chassis")
	if vehicle == null: return
	var terminal: Item = vehicle.get_node_or_null("TrainingTerminal")
	if terminal == null or not terminal.can_operate(): return
	var flashlight: Item
	for actor in _world().get_node("WorldEntities").get_children():
		if actor is Item and actor.scene_file_path == FLASHLIGHT_SCENE: flashlight = actor
	if flashlight == null: return
	terminal_id = terminal.persistent_id
	rv_id = vehicle.persistent_id
	flashlight_id = flashlight.persistent_id
	workshop.prepare(vehicle)
	_connect_player()
	_run().apply_tutorial_gates()
	progress_changed.emit()

func _physics_process(delta: float) -> void:
	if legacy_disabled or not _run().is_tutorial_shelter() or _world().has_meta("checkpoint_staging"): return
	if not _world().play_ready or not is_instance_valid(_run().shelter): return
	if not initialized():
		if _world().fresh_start: _initialize()
		return
	_connect_player()
	var vehicle := designated_rv()
	if vehicle == null or _run().phase != "preparing": return
	if not workshop.prepared(): workshop.prepare(vehicle)
	_upgrade_entry()
	workshop.bind_events(vehicle)
	service.bind_events(vehicle)
	# Preparation reserves are direct state floors, never successful transactions.
	if vehicle.current_fuel < 10.0: vehicle.current_fuel = 10.0
	var socket := vehicle.get_battery_socket()
	if socket != null and socket.installed_battery != null and socket.installed_battery.condition > 0:
		socket.installed_battery.charge = maxf(socket.installed_battery.charge, minf(20.0, socket.installed_battery.capacity))
	if status != "active": return
	if stage == 7 and not service.configure_if_ready(vehicle): return
	if entry_snapshot.is_empty():
		_snapshot_seconds += delta
		if _snapshot_seconds >= 0.5 and vehicle.linear_velocity.length() < 0.25 and vehicle.angular_velocity.length() < 0.1:
			_snapshot_seconds = 0.0
			_capture_entry()
		return # No actions count before a usable stage entry exists.
	if stage == 1: _sample_driving(vehicle, delta)
	elif stage <= 6 and workshop.complete(): _advance_stage()
	elif stage == 7 and service.complete(): _advance_stage()

func _advance_stage() -> void:
	stage += 1
	entry_snapshot.clear()
	_snapshot_seconds = 0.0
	_run().apply_tutorial_gates()
	progress_changed.emit()

func _sample_driving(vehicle: Chassis, delta: float) -> void:
	var player := _world().get_node("Player")
	var building: Node3D = _run().shelter
	var position := building.to_local(vehicle.global_position)
	var seated: bool = is_instance_valid(player.seated_in) and player.seated_in.get_connected_rv() == vehicle
	var forward := -vehicle.global_basis.z.normalized()
	var displacement := position - _previous if _previous.is_finite() else Vector3.ZERO
	var continuous := _previous.is_finite() and displacement.length() <= vehicle.max_speed * delta * 2.0 + 0.05
	var driving: bool = seated and not player.is_gameplay_input_blocked() and vehicle.energy.engine_running and not vehicle.handbrake
	if driving and continuous and vehicle.linear_velocity.length() > 0.4 and forward.dot(building.global_basis.z) > 0.85:
		if vehicle.gear > 0 and vehicle.linear_velocity.dot(forward) > 0.3 and flags.marker_index < 2:
			var line: float = MARKER_Z[flags.marker_index]
			if absf(position.x) <= 2.5 and absf(_previous.x) <= 2.5 and _previous.z < line and position.z >= line:
				flags.marker_index += 1
				progress_changed.emit()
		if flags.marker_index == 2 and vehicle.gear == -1 and vehicle.linear_velocity.dot(forward) < -0.3 and displacement.z < 0:
			_reverse_distance += -displacement.z
			if _reverse_distance >= 4.0 and _fully_parked(vehicle): flags.reversed = true
	_previous = position if seated else Vector3.INF
	# Brake-constrained wheels can oscillate around rest. Match the RV's existing
	# low-speed docking tolerance, but require the entire parking interval to
	# remain within 10 cm so continuous slow rolling cannot finish the lesson.
	var grounded := 0
	for wheel: VehicleWheel3D in vehicle.installed_wheels:
		if wheel != null and wheel.is_in_contact(): grounded += 1
	var parked: bool = flags.marker_index == 2 and flags.reversed and _fully_parked(vehicle) and grounded >= 3 and vehicle.road_speed() <= 0.2 and vehicle.angular_velocity.length() <= 0.05 and vehicle.handbrake and not vehicle.energy.engine_running
	if parked:
		var point := Vector2(position.x, position.z)
		if is_zero_approx(_park_seconds):
			_park_min = point
			_park_max = point
		else:
			_park_min = _park_min.min(point)
			_park_max = _park_max.max(point)
			if (_park_max - _park_min).length() > 0.1:
				_park_seconds = 0.0
				_park_min = point
				_park_max = point
	_park_seconds = _park_seconds + delta if parked else 0.0
	flags.parked = _park_seconds >= 1.0
	if flags.viewed and flags.flashlight and flags.parked:
		_advance_stage()

func _fully_parked(vehicle: Chassis) -> bool:
	if (-vehicle.global_basis.z).dot(_run().shelter.global_basis.z) < 0.85: return false
	return _fully_inside(vehicle, PARKING)

func _fully_inside(vehicle: Chassis, region: AABB) -> bool:
	var frame: Transform3D = _run().shelter.global_transform.affine_inverse()
	for node: CollisionShape3D in vehicle.find_children("*", "CollisionShape3D", true, false):
		if node.disabled or node.shape == null: continue
		var bounds := node.shape.get_debug_mesh().get_aabb()
		var pose := frame * node.global_transform
		for corner in range(8):
			var point := pose * bounds.get_endpoint(corner)
			if point.x < region.position.x or point.x > region.end.x or point.z < region.position.z or point.z > region.end.z: return false
	return true

func can_restart() -> bool:
	return initialized() and status == "active" and not entry_snapshot.is_empty() and not _checkpoint().loading

func restart_stage() -> bool:
	if not can_restart(): return false
	return await _checkpoint().load_snapshot(_world(), entry_snapshot.duplicate(true))

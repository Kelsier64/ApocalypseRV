extends Node
class_name StartRun
## One phase owner survives chunk reconstruction and checkpoint world transfers.
signal phase_changed(phase: String)
const STABLE_PHASES := ["preparing", "started", "sealed"]
const GATE_SCRIPT = preload("res://world/starting_shelter/garage_gate.gd")
const BUTTON_SCRIPT = preload("res://world/starting_shelter/garage_button.gd")
var phase := "preparing"
var gate: ShelterGarageGate
var shelter: Node3D
var shelter_site: Dictionary = {}
var _spawn_applied := false
var _departure_check := 0.0
var _status: Label
var _bay_gates: Array[ShelterGarageGate] = []
var _bay_gate_states: Array[bool] = []
const BAY_GATE_COUNT := 8

static func valid_state(data: Variant) -> bool:
	return data is Dictionary and data.get("version") is int and data.version == 1 and data.get("phase") is String and data.phase in STABLE_PHASES and (not data.has("bay_gates") or valid_bay_gates(data.bay_gates)) and (not data.has("tutorial") or CheckpointSchema.tutorial_error(data.tutorial).is_empty())

static func valid_bay_gates(data: Variant) -> bool:
	return data is Array and data.size() == BAY_GATE_COUNT and data.all(func(value): return value is bool)

func is_tutorial_shelter() -> bool:
	var generator := get_parent().get_node_or_null("WorldGenerator")
	return generator != null and generator.profile != null and generator.profile.generation_version >= 11

func capture(include_retry := true) -> Dictionary:
	var data := {"version": 1, "phase": phase}
	if is_tutorial_shelter():
		_remember_bay_gates()
		data["bay_gates"] = _bay_gate_states.duplicate()
		var tutorial := get_node_or_null("Tutorial")
		if tutorial != null:
			var progress: Dictionary = tutorial.capture(include_retry)
			if not progress.is_empty(): data["tutorial"] = progress
	return data

func restore(data: Dictionary) -> void:
	if not valid_state(data): return
	phase = data.phase
	_bay_gate_states.assign(data.get("bay_gates", []))
	_spawn_applied = true
	var tutorial := get_node_or_null("Tutorial")
	if tutorial != null: tutorial.restore(data.get("tutorial", {}))
	if is_inside_tree():
		_apply_simulation()
		_apply_gate()
		_apply_bay_gates()
		apply_tutorial_gates()
		_update_status()
		if is_instance_valid(shelter): shelter.get_node("GarageButton").sync_phase()

func save_block_reason() -> String:
	if phase in ["opening", "closing"] or (is_instance_valid(gate) and not gate.stable()):
		return "Wait for the exit gate to stop before saving" if is_tutorial_shelter() else "車庫大門仍在移動，請等待大門停妥後保存"
	for bay_gate in _bay_gates:
		if is_instance_valid(bay_gate) and not bay_gate.stable():
			return "Wait for all bay gates to stop before saving"
	return ""

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(24, 220)
	_status.add_theme_font_size_override("font_size", 18)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status)
	_apply_simulation()
	_update_status()

func bind_shelter(building: Node3D, site: Dictionary) -> void:
	if is_instance_valid(shelter) and shelter == building: return
	_remember_bay_gates()
	_bay_gates.clear()
	shelter = building
	shelter_site = site.duplicate(true)
	var gate_node := building.get_node("GarageGate")
	gate_node.set_script(GATE_SCRIPT)
	gate = gate_node as ShelterGarageGate
	gate.configure()
	gate.opened.connect(_on_opened)
	gate.closed.connect(_on_closed)
	gate.obstructed.connect(_on_obstructed)
	var button := building.get_node("GarageButton")
	button.set_script(BUTTON_SCRIPT)
	button.configure(self)
	_apply_gate()
	if site.get("definition_id", "") == "tutorial_shelter":
		for index in range(BAY_GATE_COUNT):
			var bay_gate := building.get_node("Gates/Gate%02d" % (index + 1)) as ShelterGarageGate
			_bay_gates.append(bay_gate)
			bay_gate.opened.connect(_remember_bay_gates)
			bay_gate.closed.connect(_remember_bay_gates)
		_apply_bay_gates()
		for index in range(BAY_GATE_COUNT):
			for suffix in ["Inside", "Outside"]:
				building.get_node("Switches/Gate%02d%s" % [index + 1, suffix]).configure_tutorial(self, index)
		apply_tutorial_gates()
	_update_status()
	var world := get_parent() as Node3D
	if not _spawn_applied and world.get("fresh_start") == true:
		_spawn_applied = true
		world.get_node("Player").global_transform = building.get_node("PlayerSpawn").global_transform
		var rv: Chassis = world.get_node("NewRv/Chassis")
		rv.global_transform = building.get_node("RVSpawn").global_transform
		rv.linear_velocity = Vector3.ZERO
		rv.angular_velocity = Vector3.ZERO

func begin_run(player: Node3D) -> String:
	var tutorial := is_tutorial_shelter()
	if phase != "preparing": return "Journey already started" if tutorial else "旅程已開始"
	var world := get_parent() as Node3D
	if not world.get("play_ready") or not is_instance_valid(gate): return "World is preparing; please wait" if tutorial else "世界仍在準備，請稍候"
	if not world.is_ancestor_of(player) or not WorldEntities.same_world(world, player): return ""
	if tutorial_active():
		var reason: String = get_node("Tutorial").departure_block_reason()
		if not reason.is_empty(): return reason
	if player.has_method("get_player_mode") and player.get_player_mode() != player.PlayerMode.NORMAL: return "Finish the current interaction first" if tutorial else "請先結束目前操作"
	_set_phase("opening")
	gate.move_to(true)
	if tutorial_active(): get_node("Tutorial").departure_started()
	return "Journey started | Exit opening; it seals permanently after departure" if tutorial else "旅程開始｜車庫大門開啟中；離開後將永久封閉"

func _remember_bay_gates() -> void:
	if not valid_bay_gates(_bay_gate_states):
		_bay_gate_states.assign([false, false, false, false, false, false, false, false])
	if _bay_gates.size() != BAY_GATE_COUNT: return
	for index in range(BAY_GATE_COUNT):
		var bay_gate := _bay_gates[index]
		if is_instance_valid(bay_gate) and bay_gate.stable():
			_bay_gate_states[index] = bay_gate.is_open()

func _apply_bay_gates() -> void:
	if _bay_gates.size() != BAY_GATE_COUNT: return
	if not valid_bay_gates(_bay_gate_states):
		_bay_gate_states.assign([false, false, false, false, false, false, false, false])
	for index in range(BAY_GATE_COUNT):
		_bay_gates[index].snap(_bay_gate_states[index])

func tutorial_active() -> bool:
	return tutorial_enabled() and get_node("Tutorial").status == "active"

func tutorial_enabled() -> bool:
	var tutorial := get_node_or_null("Tutorial")
	return is_tutorial_shelter() and tutorial != null and tutorial.initialized()

func bay_unlocked(index: int) -> bool:
	return not tutorial_active() or index < get_node("Tutorial").stage - 1

func apply_tutorial_gates() -> void:
	if not tutorial_enabled() or _bay_gates.size() != BAY_GATE_COUNT: return
	for index in range(BAY_GATE_COUNT):
		var open := bay_unlocked(index)
		_bay_gate_states[index] = open
		if open and _bay_gates[index].target < 0.5: _bay_gates[index].move_to(true)
		elif not open: _bay_gates[index].snap(false)

func register_actor(actor: Monster) -> void:
	actor.process_mode = Node.PROCESS_MODE_DISABLED if phase == "preparing" else Node.PROCESS_MODE_INHERIT

func apply_actor_state() -> void:
	for actor in get_tree().get_nodes_in_group(Groups.MONSTERS):
		if actor is Monster and get_parent().is_ancestor_of(actor) and WorldEntities.same_world(get_parent(), actor): register_actor(actor)
	_apply_simulation()

func _apply_simulation() -> void:
	var clock: WorldClock = get_parent().get_node_or_null("WorldClock")
	if clock:
		clock.running = phase != "preparing"
		clock.weather_running = phase != "preparing"
	if is_inside_tree():
		for actor in get_tree().get_nodes_in_group(Groups.MONSTERS):
			if actor is Monster and get_parent().is_ancestor_of(actor) and WorldEntities.same_world(get_parent(), actor): register_actor(actor)

func _apply_gate() -> void:
	if not is_instance_valid(gate): return
	gate.snap(phase in ["opening", "started", "closing"])
	if phase == "opening":
		gate.snap(false)
		gate.move_to(true)
	elif phase == "closing": gate.move_to(false)

func _set_phase(value: String) -> void:
	phase = value
	_apply_simulation()
	_update_status()
	phase_changed.emit(phase)

func _on_opened() -> void:
	if phase == "opening": _set_phase("started")

func _on_closed() -> void:
	if phase != "closing": return
	if tutorial_enabled() and not departure_clear():
		_set_phase("opening")
		gate.move_to(true)
		return
	_set_phase("sealed")
	if tutorial_active(): get_node("Tutorial").departure_completed()

func _on_obstructed() -> void:
	if phase == "closing":
		_set_phase("started")
		_departure_check = 1.0
		if _status: _status.text = "車庫大門受阻，已重新開啟｜請移開門口物品"

func _physics_process(delta: float) -> void:
	if phase != "started" or not is_instance_valid(gate) or not gate.is_open(): return
	_departure_check -= delta
	if _departure_check > 0.0: return
	_departure_check = 0.25
	if departure_clear() and not gate.sweep_occupied():
		_set_phase("closing")
		gate.move_to(false)

func departure_clear() -> bool:
	if not is_instance_valid(gate): return false
	var world := get_parent() as Node3D
	var player: Node3D = world.get_node_or_null("Player")
	if player == null or gate.to_local(player.global_position).z < 8.0: return false
	if tutorial_enabled():
		var designated: Chassis = get_node("Tutorial").designated_rv()
		return designated != null and vehicle_clear(designated)
	var vehicle_seen := false
	for vehicle in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if not vehicle is Chassis or not world.is_ancestor_of(vehicle) or not WorldEntities.same_world(world, vehicle): continue
		vehicle_seen = true
		if not vehicle_clear(vehicle): return false
	return vehicle_seen

func vehicle_clear(vehicle: Chassis) -> bool:
	# Include every installed collision shape, even equipment protruding behind RV.
	var shapes := vehicle.find_children("*", "CollisionShape3D", true, false)
	for shape_node: CollisionShape3D in shapes:
		if shape_node.disabled or shape_node.shape == null: continue
		var bounds: AABB = shape_node.shape.get_debug_mesh().get_aabb()
		var pose := gate.global_transform.affine_inverse() * shape_node.global_transform
		for corner in range(8):
			if (pose * bounds.get_endpoint(corner)).z < 8.0: return false
	return gate.to_local(vehicle.global_position).z >= 8.0

func _update_status() -> void:
	if not _status: return
	_status.visible = not is_tutorial_shelter()
	if not _status.visible:
		_status.text = ""
		return
	match phase:
		"preparing": _status.text = "整備區｜時間暫停\n裝載所需物資後，按下大門旁的啟程按鈕\n離開後車庫永久封閉，留下的物資將無法取回"
		"opening": _status.text = "旅程開始｜大門開啟中"
		"started": _status.text = "駛離車庫後，大門將永久封閉"
		"closing": _status.text = "車庫大門正在永久封閉"
		"sealed": _status.text = "車庫已封閉｜沿公路繼續前進"

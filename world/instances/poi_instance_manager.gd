extends Node
class_name PoiInstanceManager
## Root world keeps simulating. Only the player changes World3D/viewport.
var active_id: String = ""
var interior: PoiInterior
var viewport: SubViewport
enum State { OUTDOOR, ENTERING, INDOOR, LEAVING, FAILED }
var state := State.OUTDOOR
var operation := 0
var transition_timeout_ms := 60000
var _deadline := 0
var last_error := ""
var interior_factory: Callable
var busy := false
var saved_instances: Dictionary = {}
var stream_anchor := Vector3.ZERO
var active_title: String = "MAINTENANCE"
var _player: Node3D
var _home: Node
var _return_transform := Transform3D.IDENTITY
var _layer: CanvasLayer
var _display: TextureRect
var _status: Label

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	_display = TextureRect.new()
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.hide()
	_layer.add_child(_display)
	_status = Label.new()
	_status.position = Vector2(24, 50)
	_status.add_theme_font_size_override("font_size", 22)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_status)

func register_entrance(building: Node3D, seed_value: int, stable_id: String = "") -> void:
	var door := building.get_node_or_null(NodePath(building.get_meta("poi_entrance_path", ^"Entrance"))) as PoiEntrance
	if door == null: return
	var id := stable_id if not stable_id.is_empty() else "%d:%s" % [seed_value, building.global_position]
	door.entry_requested.connect(func(player: Node3D, _destination: StringName) -> void:
		enter.call_deferred(player, building, id, seed_value))
	building.set_meta("poi_id", id)
	building.set_meta("poi_seed", seed_value)
	building.add_to_group("poi_entrances")

func enter(player: Node3D, building: Node3D, id: String, seed_value: int) -> void:
	if busy or not active_id.is_empty() or not is_instance_valid(building) or not is_instance_valid(player):
		return
	var return_point := building.get_node_or_null(NodePath(building.get_meta("poi_return_path", ^"ReturnPoint"))) as Marker3D
	if return_point == null:
		return
	if not player.enter_ui_mode():
		return
	busy = true
	state = State.ENTERING
	operation += 1
	var token := operation
	_deadline = Time.get_ticks_msec() + transition_timeout_ms
	_player = player
	_home = player.get_parent()
	stream_anchor = player.global_position
	_return_transform = return_point.global_transform
	# Face away from the building on return, with a clear area in front.
	_return_transform.basis = building.global_basis * Basis(Vector3.UP, PI)
	active_id = id
	active_title = str(building.get_meta("poi_title", "MAINTENANCE"))
	_status.text = "Preparing %s..." % active_title
	await get_tree().process_frame
	if not _valid_operation(token): return
	viewport = SubViewport.new()
	viewport.name = "InteriorViewport"
	viewport.own_world_3d = true
	viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var saved: Dictionary = saved_instances.get(id, {})
	var profile: StringName = building.get_meta("poi_interior_profile", &"bunker")
	if not POIConfig.supported_interior(profile):
		cancel_transition("Unsupported interior profile")
		return
	# Only explicitly identified pre-bunker snapshots are discarded.
	if CheckpointSchema.legacy_poi(saved):
		saved_instances.erase(id)
	interior = interior_factory.call() if interior_factory.is_valid() else PoiInterior.new()
	viewport.add_child(interior)
	var build_result := {"done": false, "ok": false}
	_build_interior(interior, seed_value, saved_instances.get(id, {}), build_result)
	while not build_result.done and token == operation:
		await get_tree().process_frame
	if token != operation: return
	if not build_result.ok or not _valid_operation(token):
		cancel_transition("Interior could not be prepared")
		return
	interior.exit_door.entry_requested.connect(func(_actor: Node3D, _destination: StringName) -> void:
		leave.call_deferred())
	_player.reparent(interior)
	_reset_player(interior.spawn_transform())
	_display.texture = viewport.get_texture()
	_display.show()
	_player.exit_ui_mode()
	busy = false
	state = State.INDOOR
	_status.text = "%s / %d ROOMS   |   %s" % [active_title, interior.rooms.size(), "Return to B1 ENTRY to exit"]
	print("POI ENTER: ", id, " rooms=", interior.rooms.size())

func _build_interior(room: PoiInterior, seed_value: int, saved: Dictionary, result: Dictionary) -> void:
	result.ok = await room.build(seed_value, saved)
	result.done = true

func leave() -> void:
	if busy or active_id.is_empty() or not is_instance_valid(_player) or not _player.enter_ui_mode():
		return
	busy = true
	state = State.LEAVING
	operation += 1
	var token := operation
	_deadline = Time.get_ticks_msec() + transition_timeout_ms
	_status.text = "Returning to highway..."
	# Capture after deferred deaths/pickups, so an exit cannot resurrect them.
	await get_tree().process_frame
	if not _valid_operation(token): return
	saved_instances[active_id] = interior.snapshot()
	_player.reparent(_home)
	_reset_player(_safe_return_transform())
	_display.hide()
	_display.texture = null
	viewport.queue_free()
	viewport = null
	interior = null
	print("POI EXIT: ", active_id)
	active_id = ""
	_status.text = ""
	_player.exit_ui_mode()
	busy = false
	state = State.OUTDOOR

func _safe_return_transform() -> Transform3D:
	var result := _return_transform
	var space := (_home as Node3D).get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = [_player.get_rid()]
	for distance in [0.0, 1.5, 3.0, 4.5]:
		var candidate: Vector3 = _return_transform.origin - _return_transform.basis.z * distance
		var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 3, candidate + Vector3.DOWN * 6)
		ray.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		candidate.y = hit.position.y + 0.05
		query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP)
		if space.intersect_shape(query, 1).is_empty():
			result.origin = candidate
			return result
	# Entrance landing is static and pinned; a high spawn avoids dynamic overlap.
	result.origin.y += 2.5
	return result

func _reset_player(at: Transform3D) -> void:
	_player.complete_world_transition(at)

func _valid_operation(token: int) -> bool:
	if token != operation: return false
	if not is_instance_valid(_player) or not is_instance_valid(_home) or _player.current_player_health <= 0:
		cancel_transition("Transition cancelled: player unavailable")
		return false
	return true

func cancel_transition(reason := "Transition cancelled") -> void:
	operation += 1
	last_error = reason
	if is_instance_valid(_player) and is_instance_valid(_home):
		if _player.get_parent() != _home:
			_player.reparent(_home)
			_reset_player(_safe_return_transform())
		_player.exit_ui_mode()
	_display.hide()
	_display.texture = null
	if is_instance_valid(interior): interior.cancelled = true
	if is_instance_valid(viewport): _retire_viewport(viewport, interior)
	viewport = null
	interior = null
	active_id = ""
	busy = false
	state = State.FAILED
	_status.text = reason

func _retire_viewport(retired: SubViewport, room: PoiInterior) -> void:
	retired.process_mode = Node.PROCESS_MODE_DISABLED
	retired.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Let an in-flight native bake finish before releasing its geometry.
	if is_instance_valid(room) and is_instance_valid(room.navigation):
		var mesh := room.navigation.navigation_mesh
		while mesh != null and NavigationServer3D.is_baking_navigation_mesh(mesh):
			await get_tree().process_frame
	if is_instance_valid(retired): retired.queue_free()

func _exit_tree() -> void:
	operation += 1
	if is_instance_valid(interior): interior.cancelled = true

func _process(_delta: float) -> void:
	if busy:
		if Time.get_ticks_msec() >= _deadline:
			cancel_transition("Transition timed out; retry the entrance")
		elif not _valid_operation(operation):
			return
	if is_instance_valid(viewport):
		var size := Vector2i(get_viewport().get_visible_rect().size)
		if size != viewport.size:
			viewport.size = size

func _input(event: InputEvent) -> void:
	if is_instance_valid(viewport) and not busy:
		viewport.push_input(event, true)

extends Node
class_name PoiInstanceManager
## Root world keeps simulating. Only the player changes World3D/viewport.
var active_id: String = ""
var interior: PoiInterior
var viewport: SubViewport
var busy := false
var saved_instances: Dictionary = {}
var stream_anchor := Vector3.ZERO
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
	_status.position = Vector2(24, 24)
	_status.add_theme_font_size_override("font_size", 22)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_status)

func register_entrance(building: Node3D, seed_value: int, stable_id: String = "") -> void:
	var door := building.get_node("Entrance") as PoiEntrance
	var id := stable_id if not stable_id.is_empty() else "%d:%s" % [seed_value, building.global_position]
	door.entry_requested.connect(func(player: Node3D, _destination: StringName) -> void:
		enter.call_deferred(player, building, id, seed_value))
	building.set_meta("poi_id", id)
	building.set_meta("poi_seed", seed_value)
	building.add_to_group("poi_entrances")

func enter(player: Node3D, building: Node3D, id: String, seed_value: int) -> void:
	if busy or not active_id.is_empty() or not is_instance_valid(building):
		return
	if not player.enter_ui_mode():
		return
	busy = true
	_player = player
	_home = player.get_parent()
	stream_anchor = player.global_position
	_return_transform = building.get_node("ReturnPoint").global_transform
	# Face away from the building on return, with a clear area in front.
	_return_transform.basis = building.global_basis * Basis(Vector3.UP, PI)
	active_id = id
	_status.text = "Preparing maintenance maze..."
	await get_tree().process_frame
	viewport = SubViewport.new()
	viewport.name = "InteriorViewport"
	viewport.own_world_3d = true
	viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	interior = PoiInterior.new()
	viewport.add_child(interior)
	await interior.build(seed_value, saved_instances.get(id, {}))
	interior.exit_door.entry_requested.connect(func(_actor: Node3D, _destination: StringName) -> void:
		leave.call_deferred())
	_player.reparent(interior)
	_reset_player(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 2.8)))
	_display.texture = viewport.get_texture()
	_display.show()
	_player.exit_ui_mode()
	busy = false
	_status.text = "MAINTENANCE / %d ROOMS   |   Return to R001 to exit" % interior.rooms.size()
	print("POI ENTER: ", id, " rooms=", interior.rooms.size())

func leave() -> void:
	if busy or active_id.is_empty() or not _player.enter_ui_mode():
		return
	busy = true
	_status.text = "Returning to highway..."
	# Capture after deferred deaths/pickups, so an exit cannot resurrect them.
	await get_tree().process_frame
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
	_player.global_transform = at
	_player.velocity = Vector3.ZERO
	_player.locomotion_state = _player.LocomotionState.NORMAL
	_player.active_climb_rv = null
	_player.rv_support.clear()
	_player.released_carrier_velocity = Vector3.ZERO
	_player.climb_carrier_velocity = Vector3.ZERO
	_player.camera.rotation = Vector3.ZERO
	_player.camera.current = true
	_player.reset_physics_interpolation()

func _process(_delta: float) -> void:
	if is_instance_valid(viewport):
		var size := Vector2i(get_viewport().get_visible_rect().size)
		if size != viewport.size:
			viewport.size = size

func _input(event: InputEvent) -> void:
	if is_instance_valid(viewport) and not busy:
		viewport.push_input(event, true)

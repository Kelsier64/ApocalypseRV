extends RigidBody3D
class_name Item
## Unified world actor; inventory previews never own world services.
enum BottomFace { DOWN, UP, FRONT, BACK, LEFT, RIGHT }
@export var item_name: String = "Unknown Item"
@export var equipment_name: String:
	get: return item_name
	set(value): item_name = value
@export var definition: ItemDefinition
@export var is_large: bool = false
@export var enabled: bool = true
@export var initial_support: NodePath
@export var bottom_face: BottomFace = BottomFace.DOWN
@export var ghost_material: Material
@export var scrap_yields: Dictionary = {}
@export var hold_position: Vector3 = Vector3.ZERO
@export var hold_rotation: Vector3 = Vector3.ZERO
@export var hold_scale: Vector3 = Vector3.ONE
@export var max_health: float = 100.0
@export var can_be_destroyed: bool = true
@export var destroy_on_zero_health: bool = true
signal availability_changed
signal removing
var persistent_id: String = InstanceIds.create()
var _condition: float = 100.0
var condition: float:
	get: return _get_condition()
	set(value): _set_condition(clampf(value, 0.0, 100.0))
var current_health: float:
	get: return condition * max_health / 100.0
	set(value): condition = clampf(value * 100.0 / maxf(max_health, 0.001), 0.0, 100.0)
var is_destroyed: bool = false
var is_fixed: bool = false
var presentation_only: bool = false
var is_being_placed: bool = false
var processing_owner: Node = null
var support_lost: bool = false
var mount_support: Node3D = null
var original_materials: Dictionary = {}
var _collision_exception_objects: Array = []
var _connected_rv_cache: Node3D
var _world_transfer := false
var _service_stopped := false
var _support_release_pending := false
var _release_velocity := Vector3.ZERO
var _state_restored := false

func _get_condition() -> float:
	return _condition

func _set_condition(value: float) -> void:
	_condition = value

func _ready() -> void:
	if definition == null:
		definition = ItemDefinition.new()
		definition.display_name = item_name
		definition.weight = mass
		definition.health = max_health
		definition.is_large = is_large
		definition.requires_rv_connection = false
		definition.scrap_yields = scrap_yields.duplicate(true)
	if definition:
		item_name = definition.display_name
		mass = definition.weight
		max_health = definition.health
		is_large = definition.is_large
		if not _state_restored: scrap_yields = definition.scrap_yields.duplicate(true)
	if ghost_material == null:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.2, 0.8, 0.2, 0.4)
		ghost_material = material
	remove_from_group(Groups.MONSTER_DAMAGEABLE)
	if presentation_only:
		freeze = true
		collision_layer = 0
		collision_mask = 0
		return
	add_to_group(Groups.ITEMS)
	_initialize_mount.call_deferred()

func _initialize_mount() -> void:
	if presentation_only or is_being_placed or is_fixed or _state_restored: return
	var rv := RVConnection.resolve(get_parent())
	if rv != null and definition != null and definition.requires_rv_connection:
		var support := get_node_or_null(initial_support) as Node3D if not initial_support.is_empty() else rv
		confirm_placement(global_transform, rv, support if support != null else rv)

func capture_item_state() -> Dictionary:
	return {"id": persistent_id, "condition": condition, "scrap_yields": scrap_yields.duplicate(true),
		"recycle_result": get_meta("recycle_result", {}).duplicate(true), "enabled": enabled,
		"service": capture_service_state()}

func restore_item_state(state: Dictionary) -> void:
	_state_restored = true
	persistent_id = state.get("id", persistent_id)
	condition = clampf(float(state.get("condition", 100.0)), 0.0, 100.0)
	enabled = bool(state.get("enabled", true))
	if state.has("scrap_yields"): scrap_yields = state.scrap_yields.duplicate(true)
	elif definition != null: scrap_yields = definition.scrap_yields.duplicate(true)
	if not state.get("recycle_result", {}).is_empty(): set_meta("recycle_result", state.recycle_result.duplicate(true))
	restore_service_state(state.get("service", {}))

func capture_service_state() -> Dictionary:
	return {}

func restore_service_state(_state: Dictionary) -> void:
	pass

func can_pickup(player: Node3D) -> bool:
	if presentation_only or is_being_placed or is_queued_for_deletion() or _support_release_pending: return false
	if is_instance_valid(processing_owner): return false
	if player.is_gameplay_input_blocked() or player.get_player_mode() != player.PlayerMode.NORMAL: return false
	if not player.can_use_hands(2 if is_large else 1): return false
	if "current_driver" in self and is_instance_valid(get("current_driver")): return false
	if player.inventory.items.size() >= PlayerInventory.MAX_SLOTS: return false
	if is_large:
		for entry: Dictionary in player.inventory.items:
			if entry.get("is_large", false): return false
	return true

func pickup(player: Node3D) -> String:
	if not can_pickup(player): return "無法拾取：背包已滿、雙手不可用或物品正在使用"
	if scene_file_path.is_empty(): return "無法拾取：物品沒有可保存的場景"
	if not player.add_prop_item(self, scene_file_path): return "無法拾取：請先空出背包或大型物品欄位"
	queue_free()
	return "已拾取 " + item_name

func prepare_pickup() -> void:
	support_lost = true
	_stop_service_once()
	is_fixed = false
	set_mount_support(null)
	removing.emit()
	_unregister_rv()

func interact(player: Node3D) -> String:
	return pickup(player) if not is_fixed else "長按 F 2 秒解除固定並拾取"

func get_interaction_prompt(player: Node3D) -> String:
	if is_instance_valid(processing_owner): return item_name + "｜正在分解"
	if not player.can_use_hands(2 if is_large else 1): return item_name + "｜需要" + ("兩隻手臂" if is_large else "可用手臂")
	return item_name if is_fixed else item_name + "｜E 拾取"

func can_operate() -> bool:
	return not presentation_only and is_fixed and enabled and not support_lost and not is_being_placed and not is_destroyed and current_health > 0.0 and get_connected_rv() != null

func set_enabled(value: bool) -> void:
	enabled = value
	availability_changed.emit()

func _on_service_stopped() -> void:
	pass

func _stop_service_once() -> void:
	if presentation_only or _service_stopped: return
	_service_stopped = true
	_on_service_stopped()

func begin_world_transfer() -> void:
	_world_transfer = true

func end_world_transfer() -> void:
	_world_transfer = false
	refresh_rv_connection()

func get_connected_rv() -> Node3D:
	if presentation_only or not is_fixed: return null
	if RVConnection.is_rv(_connected_rv_cache) and _connected_rv_cache.is_ancestor_of(self): return _connected_rv_cache
	return refresh_rv_connection()

func refresh_rv_connection() -> Node3D:
	var previous := _connected_rv_cache
	_connected_rv_cache = RVConnection.resolve(get_parent()) if is_fixed and not presentation_only else null
	if previous != _connected_rv_cache:
		if is_instance_valid(previous) and previous.has_method("unregister_equipment"): previous.unregister_equipment(self)
		if _connected_rv_cache != null and _connected_rv_cache.has_method("register_equipment"): _connected_rv_cache.register_equipment(self)
	return _connected_rv_cache

func _unregister_rv() -> void:
	if is_instance_valid(_connected_rv_cache) and _connected_rv_cache.has_method("unregister_equipment"): _connected_rv_cache.unregister_equipment(self)
	_connected_rv_cache = null

func consume_rv_power(amount: float) -> bool:
	if not can_operate(): return false
	return amount <= 0.0 or get_connected_rv().consume_power(amount)

func confirm_placement(pose: Transform3D, parent: Node3D, support: Node3D = null) -> void:
	ItemMount.attach(self, pose, parent, support if support != null else parent)

func set_mount_support(support: Node3D) -> void:
	ItemMount.set_support(self, support)

func _support_removed() -> void:
	if _world_transfer or _support_release_pending or not is_inside_tree() or is_queued_for_deletion(): return
	_support_release_pending = true
	_release_velocity = ClimbMath.point_velocity(get_connected_rv(), global_position)
	support_lost = true
	_stop_service_once()
	removing.emit()
	detach_from_support.call_deferred()

func detach_from_support() -> void:
	ItemMount.release(self)

func get_placement_bounds() -> AABB:
	var bounds := AABB()
	var found := false
	for child in get_children():
		if child is CollisionShape3D and child.shape:
			var part: AABB = child.transform * child.shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(part) if found else part
			found = true
	return bounds if found else AABB(-Vector3.ONE * 0.5, Vector3.ONE)

func get_bottom_face_correction() -> Basis:
	match bottom_face:
		BottomFace.UP: return Basis(Vector3.RIGHT, PI)
		BottomFace.BACK: return Basis(Vector3.RIGHT, PI / 2.0)
		BottomFace.FRONT: return Basis(Vector3.RIGHT, -PI / 2.0)
		BottomFace.LEFT: return Basis(Vector3.FORWARD, PI / 2.0)
		BottomFace.RIGHT: return Basis(Vector3.FORWARD, -PI / 2.0)
	return Basis.IDENTITY

func _add_collision_exceptions_with_ancestors(start: Node) -> void:
	var current := start
	while current != null and current is Node3D:
		if current is CollisionObject3D and not _collision_exception_objects.has(current):
			add_collision_exception_with(current)
			_collision_exception_objects.append(current)
		current = current.get_parent()

func _clear_tracked_collision_exceptions() -> void:
	for other in _collision_exception_objects:
		if is_instance_valid(other): remove_collision_exception_with(other)
	_collision_exception_objects.clear()

func _apply_ghost_material(node: Node) -> void:
	if node is GeometryInstance3D:
		original_materials[node] = node.material_override
		node.material_override = ghost_material
	for child in node.get_children(): _apply_ghost_material(child)

func restore_original_materials(node: Node) -> void:
	if node is GeometryInstance3D and original_materials.has(node): node.material_override = original_materials[node]
	for child in node.get_children(): restore_original_materials(child)

func take_damage(amount: float) -> void:
	if presentation_only or amount <= 0.0 or not is_finite(amount) or not can_be_destroyed or is_destroyed: return
	current_health = maxf(0.0, current_health - amount)
	availability_changed.emit()
	if current_health <= 0.0:
		_stop_service_once()
		if destroy_on_zero_health: _destroy_equipment()

func _destroy_equipment() -> void:
	if is_destroyed: return
	is_destroyed = true
	removing.emit()
	_stop_service_once()
	_on_before_destroy()
	queue_free()

## Explicit smash damage, separate from ordinary monster damage immunity.
## Return true only when destruction clears the hand's collision path.
func damage_from_giant_smash(amount: float) -> bool:
	if presentation_only or is_being_placed or is_destroyed or is_queued_for_deletion() or is_instance_valid(processing_owner): return false
	if amount <= 0.0 or not is_finite(amount): return false
	current_health = maxf(0.0, current_health - amount)
	availability_changed.emit()
	if current_health > 0.0: return false
	# Physics queries in this same smash must see the opening before queue_free.
	collision_layer = 0
	collision_mask = 0
	hide()
	_destroy_equipment()
	return true

func _on_before_destroy() -> void:
	pass

func needs_repair() -> bool:
	return not is_destroyed and current_health < max_health

func repair_health(amount: float) -> void:
	if is_destroyed: return
	current_health = minf(max_health, current_health + maxf(amount, 0.0))
	if current_health > 0.0: _service_stopped = false
	availability_changed.emit()

func _exit_tree() -> void:
	if _world_transfer or presentation_only: return
	_stop_service_once()
	_unregister_rv()

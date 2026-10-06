extends RefCounted
class_name ItemMount
## Support is separate from scene ownership, so unloading a chunk cannot delete cargo.
static func set_support(item: Item, support: Node3D) -> void:
	if is_instance_valid(item.mount_support):
		if item.mount_support.tree_exiting.is_connected(item._support_removed): item.mount_support.tree_exiting.disconnect(item._support_removed)
		if item.mount_support.has_signal("removing") and item.mount_support.removing.is_connected(item._support_removed): item.mount_support.removing.disconnect(item._support_removed)
	item.mount_support = support if support != item else null
	if is_instance_valid(item.mount_support):
		item.mount_support.tree_exiting.connect(item._support_removed)
		if item.mount_support.has_signal("removing"): item.mount_support.removing.connect(item._support_removed)

static func attach(item: Item, pose: Transform3D, parent: Node3D, support: Node3D) -> void:
	if item.presentation_only or not is_instance_valid(parent) or not is_instance_valid(support): return
	var rv := RVConnection.resolve(parent)
	var owner: Node3D = rv if rv != null else WorldEntities.get_container(item)
	if owner == null: return
	item._world_transfer = true
	if item.get_parent() != owner: item.reparent(owner)
	item._world_transfer = false
	item.global_transform = pose
	item.is_fixed = true
	item.is_being_placed = false
	item.support_lost = false
	item._support_release_pending = false
	item._service_stopped = false
	item.freeze = true
	item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.collision_layer = 1
	item.collision_mask = 0
	item._clear_tracked_collision_exceptions()
	item._add_collision_exceptions_with_ancestors(owner)
	set_support(item, support)
	item.refresh_rv_connection()
	item.restore_original_materials(item)
	item.original_materials.clear()
	item.visible = true
	item.availability_changed.emit()

static func release(item: Item) -> void:
	if not item.is_inside_tree() or item.is_queued_for_deletion() or item.presentation_only: return
	var velocity: Vector3 = item._release_velocity if item._support_release_pending else ClimbMath.point_velocity(item.get_connected_rv(), item.global_position)
	var owner := WorldEntities.get_container(item)
	if owner == null or owner.is_queued_for_deletion(): return
	item.support_lost = true
	item._stop_service_once()
	if not item._support_release_pending: item.removing.emit()
	set_support(item, null)
	item.is_fixed = false
	item.is_being_placed = false
	item._support_release_pending = false
	item._world_transfer = true
	if item.get_parent() != owner: item.reparent(owner)
	item._world_transfer = false
	item._clear_tracked_collision_exceptions()
	item.refresh_rv_connection()
	item.freeze = false
	item.collision_layer = 3
	item.collision_mask = 1
	item.linear_velocity = velocity
	item.visible = true
	item.restore_original_materials(item)
	item.original_materials.clear()
	item.availability_changed.emit()

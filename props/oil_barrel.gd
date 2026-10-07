extends Item
class_name OilBarrel
## Ordinary cargo stays an Item; only real vehicle contact ignites it.
var _explosion_queued := false

func _ready() -> void:
	super._ready()
	if presentation_only:
		set_physics_process(false)
		return
	contact_monitor = true
	max_contacts_reported = 16
	continuous_cd = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	_receive_body_contact(body)

func _physics_process(_delta: float) -> void:
	# Frozen placed cargo and moving frozen RV panels cannot emit dynamic-body
	# contacts. Query only the actual barrel volume, never a forward probe.
	if not freeze or not _can_ignite(): return
	for child in get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.collision_mask = 1
		query.collide_with_areas = false
		query.exclude = [get_rid()]
		query.margin = .003
		for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
			if _receive_body_contact(hit.collider): return

func _receive_body_contact(body: Node) -> bool:
	if not body is CollisionObject3D or body is Area3D or body is CharacterBody3D: return false
	# Secured external gear (such as a ladder) moves as part of the RV. Loose
	# cargo/held previews cannot impersonate the vehicle through scene ancestry.
	var rv: Node3D
	var owner: Node = body
	while owner != null:
		if owner is Item:
			if not owner.is_fixed or owner.presentation_only or owner.is_being_placed: return false
			rv = owner.get_connected_rv()
			break
		owner = owner.get_parent()
	if owner == null: rv = RVConnection.resolve(body)
	if rv == null: return false
	var normal: Vector3 = (global_position - body.global_position).normalized()
	return receive_vehicle_body_contact(rv, normal, global_position)

func _can_ignite() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and not is_destroyed \
		and not presentation_only and not is_being_placed and not _world_transfer \
		and not is_instance_valid(processing_owner)

func receive_vehicle_body_contact(rv: Node3D, normal: Vector3, point: Vector3) -> bool:
	if not rv is Chassis or not WorldEntities.same_world(self, rv): return false
	# Cargo secured to this RV is not an obstacle it has struck.
	if get_connected_rv() == rv: return false
	if _explosion_queued: return true
	if not _can_ignite() or not normal.is_finite() or not point.is_finite(): return false
	_explosion_queued = true
	is_destroyed = true
	current_health = 0.0
	set_physics_process(false)
	var approach := maxf(0.0, (rv.vehicle_impact_point_velocity(point) - linear_velocity).dot(normal))
	rv.queue_explosive_item_impact(self, normal, point, approach)
	# Keep the source alive until deferred damage collects the complete shield
	# snapshot, but the destruction latch already prevents pickup and saving.
	_resolve_explosion.call_deferred(global_position, weakref(rv))
	return true

func can_pickup(player: Node3D) -> bool:
	return not is_destroyed and super.can_pickup(player)

func _resolve_explosion(origin: Vector3, vehicle_ref: WeakRef) -> void:
	collision_layer = 0
	collision_mask = 0
	for child in get_children():
		if child is CollisionShape3D: child.disabled = true
	_stop_service_once()
	set_mount_support(null)
	removing.emit()
	_unregister_rv()
	var rv := vehicle_ref.get_ref() as Node3D
	BarrelExplosion.explode(self, origin, rv)
	queue_free()

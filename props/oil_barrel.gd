extends Item
class_name OilBarrel
## Cargo ignites on a hard vehicle impact or landing after a two-metre fall.
@export var vehicle_explosion_speed: float = 3.0
@export var fall_explosion_height: float = 2.0
var _explosion_queued := false
var _incoming_velocity := Vector3.ZERO
var _incoming_angular_velocity := Vector3.ZERO
var _sample_position := Vector3.INF
var _fall_peak_y := 0.0
var _fall_sampled := false
var _restored_fall_height := 0.0

func _ready() -> void:
	super._ready()
	if presentation_only:
		set_physics_process(false)
		return
	max_contacts_reported = 16
	contact_monitor = true
	continuous_cd = true

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _can_ignite() or freeze or is_fixed:
		_reset_fall()
		return
	var position := state.transform.origin
	# Restores and world transfers can move a body without a physical fall.
	if _sample_position.is_finite() and position.distance_to(_sample_position) > maxf(1.0, _incoming_velocity.length() * state.step * 4.0):
		_reset_fall()
	if not _fall_sampled:
		_fall_peak_y = position.y + _restored_fall_height
		_restored_fall_height = 0.0
		_fall_sampled = true
		_incoming_velocity = state.linear_velocity
		_incoming_angular_velocity = state.angular_velocity
	_fall_peak_y = maxf(_fall_peak_y, position.y)
	var supported := false
	for contact in state.get_contact_count():
		var body := state.get_contact_collider_object(contact) as Node
		if not body is CollisionObject3D or body is Area3D: continue
		# Godot's direct-body contact positions/normals are in world space.
		var normal := state.get_contact_local_normal(contact).normalized()
		var point := state.get_contact_local_position(contact)
		if _receive_body_contact(body, normal, point): return
		if normal.y > 0.5: supported = true
	if supported:
		if _fall_peak_y - position.y >= fall_explosion_height:
			_queue_explosion()
			return
		_fall_peak_y = position.y
	_sample_position = position
	_incoming_velocity = state.linear_velocity
	_incoming_angular_velocity = state.angular_velocity

func _physics_process(_delta: float) -> void:
	if not _can_ignite() or freeze or is_fixed: _reset_fall()
	# Frozen placed cargo and frozen RV panels need a shape overlap query.
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
		var hits := get_world_3d().direct_space_state.intersect_shape(query, 32)
		for hit in hits:
			var body := hit.collider as CollisionObject3D
			if body == null: continue
			# Restrict the rest query to this overlapping body, including when
			# the ground is the nearest contact of a mounted world barrel.
			var exclusions: Array[RID] = [get_rid()]
			for other in hits:
				if other.collider != body: exclusions.append(other.rid)
			query.exclude = exclusions
			var rest := get_world_3d().direct_space_state.get_rest_info(query)
			query.exclude = [get_rid()]
			if not rest.is_empty() and _receive_body_contact(body, rest.normal, rest.point): return

func _receive_body_contact(body: Node, normal: Vector3, point: Vector3) -> bool:
	if not body is CollisionObject3D or body is Area3D or body is CharacterBody3D: return false
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
	return receive_vehicle_body_contact(rv, normal, point)

func _can_ignite() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and not is_destroyed \
		and not presentation_only and not is_being_placed and not _world_transfer \
		and not is_instance_valid(processing_owner)

func receive_vehicle_body_contact(rv: Node3D, normal: Vector3, point: Vector3) -> bool:
	if not rv is Chassis or not WorldEntities.same_world(self, rv): return false
	if get_connected_rv() == rv: return false
	if _explosion_queued: return true
	if not _can_ignite() or not normal.is_finite() or normal.is_zero_approx() or not point.is_finite(): return false
	var direction := normal.normalized()
	var mounted_rv := get_connected_rv() as Chassis
	var velocity := mounted_rv.vehicle_impact_point_velocity(point) if mounted_rv != null else ClimbMath.point_velocity(self, point)
	if not freeze and _sample_position.is_finite():
		var incoming := _incoming_velocity + _incoming_angular_velocity.cross(point - global_transform * center_of_mass)
		# Either callback can arrive after Jolt has already resolved the impact.
		if incoming.dot(direction) < velocity.dot(direction): velocity = incoming
	var approach := maxf(0.0, (rv.vehicle_impact_point_velocity(point) - velocity).dot(direction))
	if approach < vehicle_explosion_speed: return false
	_queue_explosion(rv)
	rv.queue_explosive_item_impact(self, direction, point, approach)
	return true

func _queue_explosion(rv: Node3D = null) -> void:
	if _explosion_queued or not _can_ignite(): return
	_explosion_queued = true
	is_destroyed = true
	current_health = 0.0
	set_physics_process(false)
	_resolve_explosion.call_deferred(global_position, weakref(rv) if rv != null else null)

func _reset_fall() -> void:
	_fall_sampled = false
	_restored_fall_height = 0.0
	_sample_position = Vector3.INF
	_incoming_velocity = Vector3.ZERO
	_incoming_angular_velocity = Vector3.ZERO

func begin_world_transfer() -> void:
	_reset_fall()
	super.begin_world_transfer()

func confirm_placement(pose: Transform3D, parent: Node3D, support: Node3D = null) -> void:
	_reset_fall()
	super.confirm_placement(pose, parent, support)

func prepare_pickup() -> void:
	_reset_fall()
	super.prepare_pickup()

func capture_service_state() -> Dictionary:
	if freeze or is_fixed or not _can_ignite(): return {}
	var height := maxf(0.0, _fall_peak_y - global_position.y) if _fall_sampled else _restored_fall_height
	return {"fall_height": height} if height > 0.0 else {}

func restore_service_state(state: Dictionary) -> void:
	_reset_fall()
	_restored_fall_height = maxf(0.0, float(state.get("fall_height", 0.0)))

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
	var rv := vehicle_ref.get_ref() as Node3D if vehicle_ref != null else null
	BarrelExplosion.explode(self, origin, rv)
	queue_free()

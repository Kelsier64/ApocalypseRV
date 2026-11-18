extends Item
class_name RecoveryJack

const RATCHET_SOUND: SoundEvent = preload("res://assets/audio/events/rv/jack_ratchet.tres")
const SCENE := "res://props/recovery_jack.tscn"
const REACH := 3.9
const MAX_START_SPEED := 0.65
const MAX_START_SPIN := 0.6
const LIFTING := "Lifting RV"
const FOOT_HALF_SIZE := Vector2(0.143, 0.125)
const FOOT_OFFSET := 0.005
const SADDLE_HEIGHT := 0.578
const SHOE_REACH := 0.025
const SHOE_GAP := 0.008
const MIN_EXTENSION := -0.055
const MAX_EXTENSION := 2.70
const PUMP_SPEED := 0.8
const RETRACT_SPEED := 1.4
const HINGE_TIME := 0.24

signal lift_finished(message: String)

@onready var model: Node3D = $Model
@onready var ram: Node3D = $Model/Stroke
@onready var saddle: Node3D = $Model/Stroke/Saddle
@onready var rods: Array[Node3D] = [
	$Model/Stroke/OuterRod, $Model/Stroke/SecondRod, $Model/Stroke/ThirdRod,
	$Model/Stroke/FourthRod, $Model/Stroke/FifthRod, $Model/Stroke/Plunger
]
@onready var _folded_pose := model.transform
@onready var _stowed_ram_basis := ram.basis
@onready var _saddle_home := saddle.position.y
@onready var _stowed_saddle_basis := saddle.basis
@onready var _rod_home := rods.map(func(rod: Node3D) -> float: return rod.position.y)

var _vehicle: Chassis
var _axis := Vector3.ZERO
var _inverted_stage := false
var _driver: WeakRef
var _elapsed := 0.0
var _return_to_inventory := false
var _was_frozen := false
var _contact_body: Node3D
var _contact_local := Transform3D.IDENTITY
var _shoe_query := _shoe_clearance_query([])
var _extension := 0.0
var _pump_travel := 0.0
var _released := false
var _release_basis := Basis.IDENTITY
var _release_saddle_basis := Basis.IDENTITY
var _fold_time := 0.0

static func deployment_target(player: Node3D, collider: Node) -> Chassis:
	if not is_instance_valid(collider) or collider.is_queued_for_deletion(): return null
	if not player.can_use_hands() or player.inventory.active_item().get("scene_path") != SCENE: return null
	var rv := ClimbMath.find_rv_ancestor(collider) as Chassis
	return rv if rv != null and rv.rollover_state() != Chassis.Rollover.UPRIGHT else null

static func deploy_from_inventory(player: Node3D, rv: Chassis) -> Dictionary:
	if deployment_target(player, rv) != rv or player.is_gameplay_input_blocked() or player.get_player_mode() != player.PlayerMode.NORMAL:
		return {"message": "Select the Recovery Jack"}
	if not WorldEntities.same_world(player, rv): return {"message": "Move beside the RV"}
	var data: Dictionary = player.inventory.active_item()
	if data.state.get("condition", 0.0) <= 0.0: return {"message": "Recovery Jack is damaged"}
	if not _is_stopped(rv): return {"message": "Wait for the RV to stop"}
	if _lift_in_progress(rv): return {"message": "The RV is already being lifted"}
	var forward := rv.global_basis.z.slide(Vector3.UP).normalized()
	var side := Vector3.UP.cross(forward)
	var beside := (player.global_position - rv.global_position).dot(side)
	if absf(beside) < 1.7: return {"message": "Stand beside the RV"}
	var outward := side * signf(beside)
	if rv.rollover_state() == Chassis.Rollover.SIDE and not _can_lift_from(rv, forward * signf(beside)):
		return {"message": "Move to the other side of the RV"}
	var placement := _find_deployment(player, rv, forward, outward)
	if placement.is_empty():
		return {"message": "Move beside the RV where the ground is firm and clear"}
	var jack := (load(SCENE) as PackedScene).instantiate() as RecoveryJack
	jack.restore_item_state(data.state)
	var parent := WorldEntities.get_container(player)
	jack.transform = parent.global_transform.affine_inverse() * placement.pose
	parent.add_child(jack)
	player.consume_active_item()
	jack._return_to_inventory = true
	jack._begin_lift(player, rv, forward * signf(beside), placement)
	return {"message": LIFTING, "jack": jack}

static func _find_deployment(player: Node3D, rv: Chassis, forward: Vector3, outward: Vector3, loose_jack := RID()) -> Dictionary:
	var along := clampf((player.global_position - rv.global_position).dot(forward), -4.8, 4.8)
	var space := player.get_world_3d().direct_space_state
	var excluded: Array[RID] = [player.get_rid()]
	if loose_jack.is_valid(): excluded.append(loose_jack)
	var shoe_query := _shoe_clearance_query(excluded)
	var inverted := rv.rollover_state() == Chassis.Rollover.INVERTED
	var right := rv.global_basis.x
	var local_edge := Vector3(1.85 * signf(right.dot(outward)), 1.99, along) if inverted \
		else Vector3(1.44 * signf(right.dot(Vector3.DOWN)), 2.54, along)
	for offset in [0.0, -0.6, 0.6, -1.15, 1.15]:
		local_edge.z = clampf(along + offset, -4.8, 4.8)
		var edge := rv.to_global(local_edge)
		var face := space.intersect_ray(PhysicsRayQueryParameters3D.create(edge + outward * 0.55, edge - outward * 0.42, 1, excluded))
		if face.is_empty() or ClimbMath.find_rv_ancestor(face.collider) != rv: continue
		var contact: Vector3 = face.position
		var inward: Vector3 = -face.normal
		var lateral := forward.slide(inward).normalized()
		var surface := Transform3D(Basis(lateral, inward, lateral.cross(inward)), contact)
		if not _shoe_is_clear(space, shoe_query, surface): continue
		var pose := _find_footing(space, player.global_position, surface, outward, excluded)
		if pose != Transform3D.IDENTITY:
			var body := face.collider as Node3D
			return {"pose": pose, "body": body, "contact": body.global_transform.affine_inverse() * surface}
	return {}

static func _shoe_clearance_query(excluded: Array[RID]) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.115, 0.062, 0.092)
	query.shape = box
	query.collision_mask = 3
	query.exclude = excluded
	return query

static func _shoe_is_clear(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, surface: Transform3D) -> bool:
	query.transform = surface.translated_local(Vector3.DOWN * (SHOE_GAP + 0.031))
	return space.intersect_shape(query, 1).is_empty()

static func _find_footing(space: PhysicsDirectSpaceState3D, player_position: Vector3, surface: Transform3D,
		outward: Vector3, excluded: Array[RID]) -> Transform3D:
	var clearance := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0 * FOOT_HALF_SIZE.x + 0.015, 0.12, 2.0 * FOOT_HALF_SIZE.y + 0.015)
	clearance.shape = box
	clearance.collision_mask = 3
	clearance.exclude = excluded
	var contact := surface.translated_local(Vector3.DOWN * (SHOE_REACH + SHOE_GAP)).origin
	for offset in [0.20, 0.28, 0.34, 0.44, 0.54]:
		var candidate := surface.origin + outward * float(offset)
		var pose := _foot_pose(space, candidate, outward, excluded)
		if pose == Transform3D.IDENTITY or pose.origin.distance_to(player_position) > 2.9: continue
		clearance.transform = pose.translated_local(Vector3.UP * 0.061)
		if not space.intersect_shape(clearance, 1).is_empty(): continue
		var socket := pose * Vector3(0.0, 0.111, 0.004)
		var rod := contact - socket
		if rod.length() < SADDLE_HEIGHT or rod.dot(pose.basis.y) < rod.length() * 0.6: continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(socket, contact - rod.normalized() * 0.025, 1, excluded)).is_empty(): continue
		return pose
	return Transform3D.IDENTITY

static func _foot_pose(space: PhysicsDirectSpaceState3D, candidate: Vector3, outward: Vector3, excluded: Array[RID]) -> Transform3D:
	var ground := _ground_point(space, candidate + Vector3.UP * 0.5, candidate - Vector3.UP * 1.9, excluded)
	if ground.is_empty(): return Transform3D.IDENTITY
	var up: Vector3 = ground.normal
	var basis := Basis.looking_at(outward.slide(up), up)
	var pose := Transform3D(basis, ground.position)
	var rise := 0.0
	for x in [-FOOT_HALF_SIZE.x, FOOT_HALF_SIZE.x]:
		for z in [-FOOT_HALF_SIZE.y, FOOT_HALF_SIZE.y]:
			var corner: Vector3 = pose * Vector3(x, 0.0, z)
			var support := _ground_point(space, corner + up * 0.075, corner - up * 0.075, excluded)
			if support.is_empty(): return Transform3D.IDENTITY
			var height := up.dot(support.position - corner)
			if absf(height) > 0.035: return Transform3D.IDENTITY
			rise = maxf(rise, height)
	return pose.translated_local(Vector3.UP * (rise + FOOT_OFFSET))

static func _is_stopped(rv: Chassis) -> bool:
	return not rv.freeze and rv.linear_velocity.length() <= MAX_START_SPEED and rv.angular_velocity.length() <= MAX_START_SPIN

static func _lift_in_progress(rv: Chassis) -> bool:
	for item in rv.get_tree().get_nodes_in_group(Groups.ITEMS):
		if item is RecoveryJack and item._vehicle == rv: return true
	return false

static func _can_lift_from(rv: Chassis, axis: Vector3) -> bool:
	return axis.dot(rv.global_basis.y.cross(Vector3.UP)) >= 0.0

func can_pickup(player: Node3D) -> bool:
	return not is_lifting() and super.can_pickup(player)

func is_lifting() -> bool:
	return is_instance_valid(_vehicle)

func lift_prompt() -> String:
	return "Jack retracting. Stay clear of the RV." if _released else "Lifting RV… Stay beside the jack."

func interact_hold(player: Node3D) -> String:
	if presentation_only or is_destroyed or is_fixed or is_lifting() or not player.can_use_hands(): return "Recovery Jack unavailable"
	if not _base_is_supported(): return "Set the jack on firm ground"
	var distance := REACH
	var target: Chassis
	for candidate in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if not candidate is Chassis or not WorldEntities.same_world(self, candidate): continue
		if candidate.rollover_state() == Chassis.Rollover.UPRIGHT or not _is_stopped(candidate): continue
		var separation: float = _station(candidate).distance_to(global_position)
		if separation < distance:
			target = candidate
			distance = separation
	if target == null: return "Set the jack beside a stopped, overturned RV"
	if _lift_in_progress(target): return "The RV is already being lifted"
	var station := _station(target)
	var forward := target.global_basis.z.slide(Vector3.UP).normalized()
	var side := Vector3.UP.cross(forward)
	if side.is_zero_approx(): return "Move the jack beside the RV"
	var access := (global_position - station).dot(side)
	if absf(access) < 1.7: return "Move the jack out beside the RV"
	var axis := forward * signf(access)
	if target.rollover_state() == Chassis.Rollover.SIDE and not _can_lift_from(target, axis):
		return "Move the jack to the other side to lift the RV"
	var placement := _find_deployment(player, target, forward, side * signf(access), get_rid())
	if placement.is_empty(): return "Move beside the RV where the ground is firm and clear"
	_begin_lift(player, target, axis, placement)
	return LIFTING

func _begin_lift(player: Node3D, target: Chassis, axis: Vector3, placement: Dictionary) -> void:
	_vehicle = target
	_axis = axis
	_inverted_stage = target.rollover_state() == Chassis.Rollover.INVERTED
	_contact_body = placement.body
	_contact_local = placement.contact
	_shoe_query.exclude = [get_rid(), player.get_rid()]
	_pump_travel = MIN_EXTENSION
	_released = false
	_fold_time = 0.0
	_driver = weakref(player)
	_elapsed = 0.0
	_was_frozen = freeze
	freeze = true
	$Collision.set_deferred("disabled", true)
	model.global_transform = placement.pose
	_set_extension(MIN_EXTENSION)
	model.reset_physics_interpolation()
	target.sleeping = false
	target.feedback(RATCHET_SOUND, target.to_local(load_surface().origin))

func load_surface() -> Transform3D:
	return _contact_body.global_transform * _contact_local

func _physics_process(delta: float) -> void:
	if _driver == null: return
	var player := _driver.get_ref() as Node3D
	_elapsed += delta
	if not WorldEntities.same_world(self, _vehicle) or _elapsed > 10.0 or not WorldEntities.same_world(self, player) or not player.can_use_hands() or player.global_position.distance_to(model.global_position) > 4.5:
		_finish_lift("Lift interrupted. Pick up the jack to try again.")
		return
	var upright := _vehicle.global_basis.y.dot(Vector3.UP)
	var impulse_speed := _vehicle.angular_velocity.dot(_axis)
	var target_up_dot := -0.02 if _inverted_stage else 0.72
	if _released and _fold_time >= HINGE_TIME and upright >= target_up_dot and (not _inverted_stage or (absf(impulse_speed) < 0.12 and _vehicle.linear_velocity.length() < 0.4)):
		_vehicle.feedback(RATCHET_SOUND, _vehicle.to_local(model.global_position))
		_finish_lift("Move beside the RV for the second lift." if _inverted_stage else "RV recovered.", true)
		return
	if not _released and upright >= (-0.82 if _inverted_stage else 0.70):
		_released = true
		_release_basis = ram.basis
		_release_saddle_basis = saddle.basis
	if _released:
		_set_extension(move_toward(_extension, 0.0, RETRACT_SPEED * delta))
		if is_zero_approx(_extension):
			_fold_time = minf(_fold_time + delta, HINGE_TIME)
			var fold := smoothstep(0.0, HINGE_TIME, _fold_time)
			ram.basis = _release_basis.slerp(_stowed_ram_basis, fold)
			saddle.basis = _release_saddle_basis.slerp(_stowed_saddle_basis, fold)
		if not _inverted_stage or upright < -0.30: return
		# Bleed off excess roll as the RV settles onto its side after the ram unloads.
		var desired_speed := maxf(0.0, (target_up_dot - upright) * 2.0)
		var torque := minf(0.0, desired_speed - impulse_speed) * _vehicle.mass * 18.0
		_vehicle.apply_torque(_axis * torque)
		var slide := _vehicle.linear_velocity.slide(Vector3.UP)
		_vehicle.apply_central_force(-slide * _vehicle.mass * 3.0)
		return
	if not is_instance_valid(_contact_body) or _contact_body.is_queued_for_deletion() or ClimbMath.find_rv_ancestor(_contact_body) != _vehicle:
		_finish_lift("The jack lost its support point. Reposition and try again.")
		return
	var surface := load_surface()
	if not _shoe_is_clear(get_world_3d().direct_space_state, _shoe_query, surface):
		_finish_lift("The jack head is obstructed. Reposition and try again.")
		return
	var contact := surface.translated_local(Vector3.DOWN * (SHOE_REACH + SHOE_GAP)).origin
	if _elapsed <= HINGE_TIME:
		_aim_ram(contact, surface.basis, smoothstep(0.0, HINGE_TIME, _elapsed))
		return
	var rod := contact - ram.global_position
	var gap := rod.length() - SADDLE_HEIGHT
	if gap > MAX_EXTENSION + 0.10 or gap < MIN_EXTENSION or rod.normalized().dot(model.global_basis.y) < 0.45:
		_finish_lift("The jack lost its support point. Reposition and try again.")
		return
	_aim_ram(contact, surface.basis)
	_pump_travel = minf(_pump_travel + delta * PUMP_SPEED, MAX_EXTENSION)
	_set_extension(clampf(minf(_pump_travel, gap), MIN_EXTENSION, MAX_EXTENSION))
	var compression := maxf(0.0, _pump_travel - gap)
	if compression <= 0.0: return
	var direction := rod.normalized()
	var contact_speed := ClimbMath.point_velocity(_vehicle, surface.origin).dot(direction)
	var pressure := clampf(compression * 34.0 - contact_speed * 2.9, 0.0, 16.0)
	_vehicle.apply_force(direction * _vehicle.mass * pressure, surface.origin - _vehicle.global_position)

func _aim_ram(contact: Vector3, shoe_basis: Basis, weight := 1.0) -> void:
	var direction := ram.global_position.direction_to(contact)
	var lateral := model.global_basis.x.slide(direction).normalized()
	var aim := Basis(lateral, direction, lateral.cross(direction).normalized())
	ram.basis = _stowed_ram_basis.slerp(model.global_basis.inverse() * aim, weight)
	saddle.basis = _stowed_saddle_basis.slerp(ram.global_basis.inverse() * shoe_basis, weight)

func _set_extension(distance: float) -> void:
	_extension = distance
	for i in rods.size():
		rods[i].position.y = _rod_home[i] + distance * float(i + 1) / float(rods.size())
	saddle.position.y = _saddle_home + distance

func _station(rv: Chassis) -> Vector3:
	var local := rv.to_local(global_position)
	return rv.to_global(Vector3(0, 1.25, clampf(local.z, -4.8, 4.8)))

func _base_is_supported() -> bool:
	var point := global_position
	return not _ground_point(get_world_3d().direct_space_state, point + Vector3.UP * 0.1, point - Vector3.UP * 0.35, [get_rid()]).is_empty()

static func _ground_point(space: PhysicsDirectSpaceState3D, above: Vector3, below: Vector3, exclude: Array[RID]) -> Dictionary:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(above, below, 1, exclude))
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.64 or not hit.collider is StaticBody3D or ClimbMath.find_rv_ancestor(hit.collider) != null:
		return {}
	return hit

func _finish_lift(message: String, completed := false) -> void:
	var player := _driver.get_ref() as Node3D
	var pack_up := completed and _return_to_inventory
	_driver = null
	_vehicle = null
	_contact_body = null
	_return_to_inventory = false
	freeze = _was_frozen
	$Collision.set_deferred("disabled", false)
	model.transform = _folded_pose
	ram.basis = _stowed_ram_basis
	saddle.basis = _stowed_saddle_basis
	_set_extension(0.0)
	model.reset_physics_interpolation()
	if pack_up:
		if is_instance_valid(player) and can_pickup(player):
			pickup(player)
		if not is_queued_for_deletion():
			message += " Pick up the jack."
	lift_finished.emit(message)

func _on_service_stopped() -> void:
	if _driver != null: _finish_lift("Recovery Jack unavailable")

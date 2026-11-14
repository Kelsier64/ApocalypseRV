extends Item
class_name RecoveryJack

const SCENE := "res://props/recovery_jack.tscn"
const REACH := 3.9
const MAX_START_SPEED := 0.65
var _vehicle: Chassis
var _axis := Vector3.ZERO
var _inverted_stage := false
var _driver: WeakRef
var _elapsed := 0.0

func interact_hold(player: Node3D) -> String:
	if presentation_only or is_destroyed or _vehicle or not player.can_use_hands(): return "Recovery Jack unavailable"
	if not _base_is_supported(): return "Set the jack on firm ground"
	var distance := REACH
	var target: Chassis
	for candidate in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if not candidate is Chassis or not WorldEntities.same_world(self, candidate): continue
		if candidate.rollover_state() == Chassis.Rollover.UPRIGHT or candidate.freeze: continue
		if candidate.linear_velocity.length() > MAX_START_SPEED or candidate.angular_velocity.length() > 0.6: continue
		var separation: float = _station(candidate).distance_to(global_position)
		if separation < distance:
			target = candidate
			distance = separation
	if target == null: return "Set the jack beside a stopped, overturned RV"
	var station := _station(target)
	var forward := target.global_basis.z.slide(Vector3.UP).normalized()
	var side := Vector3.UP.cross(forward)
	if side.is_zero_approx(): return "Move the jack beside the RV"
	var access := (global_position - station).dot(side)
	if absf(access) < 1.7: return "Move the jack out beside the RV"
	_inverted_stage = target.rollover_state() == Chassis.Rollover.INVERTED
	_axis = forward * signf(side.cross(Vector3.UP).dot(forward) * access)
	if not _inverted_stage and _axis.dot(target.global_basis.y.cross(Vector3.UP)) < 0.0:
		return "Move the jack to the other side to lift the RV"
	_vehicle = target
	_driver = weakref(player)
	_elapsed = 0.0
	target.sleeping = false
	target.feedback("mechanical", target.to_local(station))
	return "Lifting RV"

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_vehicle):
		_vehicle = null
		return
	var player := _driver.get_ref() as Node3D
	_elapsed += delta
	if _elapsed > 10.0 or not is_instance_valid(player) or not player.can_use_hands() or player.global_position.distance_to(global_position) > 4.5:
		_vehicle = null
		return
	var upright := _vehicle.global_basis.y.dot(Vector3.UP)
	var crosswise := Vector3.UP.cross(_axis)
	var impulse_speed := _vehicle.angular_velocity.dot(_axis)
	var target_up_dot := -0.02 if _inverted_stage else 0.72
	if upright >= target_up_dot and (not _inverted_stage or (absf(impulse_speed) < 0.12 and _vehicle.linear_velocity.length() < 0.4)):
		_vehicle.feedback("mechanical")
		_vehicle = null
		return
	var station := _station(_vehicle)
	if station.distance_to(global_position) > REACH + 4.0:
		_vehicle = null
		return
	var up := _vehicle.global_basis.y
	var right := _vehicle.global_basis.x
	if _inverted_stage and upright > -0.85:
		# Oppose the remaining angular momentum with the supported edge before releasing.
		var desired_speed := clampf((target_up_dot - upright) * 2.0, -0.65, 0.65)
		var torque := (desired_speed - impulse_speed) * _vehicle.mass * 18.0
		_vehicle.apply_torque(_axis * torque)
		var slide := _vehicle.linear_velocity.slide(Vector3.UP)
		_vehicle.apply_central_force(-slide * _vehicle.mass * 3.0)
	var corner := station + up * (2.6 if up.dot(crosswise) > 0.0 else 0.0) + right * (1.85 * signf(right.dot(crosswise)))
	var lift := clampf(_vehicle.mass * 9.8 * (1.02 - impulse_speed * 2.0), 0.0, _vehicle.mass * 11.0)
	if _inverted_stage and upright > -0.85: lift *= clampf((target_up_dot - upright) * 2.4, 0.0, 1.0)
	_vehicle.apply_force(Vector3.UP * lift, corner - _vehicle.global_position)

func _station(rv: Chassis) -> Vector3:
	var local := rv.to_local(global_position)
	return rv.to_global(Vector3(0, 1.25, clampf(local.z, -4.8, 4.8)))

func _base_is_supported() -> bool:
	var point := global_position
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.1, point - Vector3.UP * 0.35, 1, [get_rid()])
	var ground := get_world_3d().direct_space_state.intersect_ray(query)
	return not ground.is_empty() and ground.normal.dot(Vector3.UP) >= 0.64 and ClimbMath.find_rv_ancestor(ground.collider) == null

func _on_service_stopped() -> void:
	_vehicle = null

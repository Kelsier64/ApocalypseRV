extends Monster
class_name Raker
## Telegraphed player grabs and structure strikes using shared RV locomotion.
signal attack_started(clip: String, duration: float)
signal reaction_started
signal death_started

const STANDING_HEIGHT := 2.18
const CROUCH_HEIGHT := 1.6
const FOOT_OFFSET := 0.25
const SWEEP_CONTACT := 0.72
enum PursuitGait { STALK, RUN, VEHICLE_SPRINT }
@export var vehicle_sprint_margin := 1.2
@export var vehicle_sprint_cap := 18.0
@export var vehicle_sprint_acceleration := 10.0
@export var ground_turn_rate := 4.2 # radians / second
var steering_delta := 1.0 / 60.0
var reversal_side := 0.0
var pursuit_gait := PursuitGait.STALK
var vehicle_sprint_speed := 0.0
var crouched := false
var running_pursuit := false
var ground_chase_speed := 0.0
var strike_elapsed := -1.0
var strike_contact := SWEEP_CONTACT
var strike_duration := 1.2
var strike_target: Dictionary = {}
var strike_direction := Vector3.FORWARD
var strike_resolved := false
var strike_clip := ""
var next_left := true
var reaction_remaining := 0.0
var death_remaining := 2.0
var grab: Node

func _ready() -> void:
	super._ready()
	grab = preload("res://enemies/raker_grab.gd").new()
	add_child(grab)
	stagger_amount = 0.0
	body_collision_shape.shape = body_collision_shape.shape.duplicate()
	$HitBox/HitBoxShape.shape = $HitBox/HitBoxShape.shape.duplicate()
	nav_agent.height = STANDING_HEIGHT

func _physics_process(delta: float) -> void:
	# Re-entered only by actual ground chase; attacks, climbing and loss of
	# target cannot leave the sprint animation latched on.
	pursuit_gait = PursuitGait.STALK
	if is_dead:
		# Corpses still fall when their supporting roof disappears.
		if not is_on_floor(): velocity.y -= gravity * delta
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		death_remaining -= delta
		if death_remaining <= 0: queue_free()
		return
	reaction_remaining = maxf(0, reaction_remaining - delta)
	if not grab.busy(): _update_posture()
	grab.tick(delta)
	_tick_strike(delta)
	super._physics_process(delta)
	if ai_state != State.CHASE or locomotion_state != LocomotionState.NORMAL:
		pursuit_gait = PursuitGait.STALK
	if pursuit_gait != PursuitGait.VEHICLE_SPRINT:
		vehicle_sprint_speed = 0.0
	# All visible sway belongs to the authored bones.
	_body_mesh.rotation = Vector3.ZERO

func _process_wander(delta: float) -> bool:
	steering_delta = delta
	if grab.busy() or strike_elapsed >= 0 or reaction_remaining > 0:
		velocity.x = 0
		velocity.z = 0
		return false
	return super._process_wander(delta)

func _process_chase(delta: float, destination: Vector3) -> bool:
	steering_delta = delta
	if grab.busy() or strike_elapsed >= 0 or reaction_remaining > 0:
		velocity.x = 0
		velocity.z = 0
		return false
	var configured_speed := move_speed
	# Close distance at a run, then stalk into attack range. Separate enter/exit
	# distances prevent a timer or small target movements from flipping gait.
	var distance := (destination - global_position).slide(Vector3.UP).length()
	if distance > 4.5: running_pursuit = true
	elif distance < 2.8: running_pursuit = false
	var desired_speed := 0.7 if crouched else (3.4 if running_pursuit else 1.45)
	ground_chase_speed = move_toward(Vector2(velocity.x, velocity.z).length(), desired_speed, delta * 6.0)
	move_speed = minf(ground_chase_speed, 0.7) if crouched else ground_chase_speed
	pursuit_gait = PursuitGait.RUN if move_speed > 2.0 else PursuitGait.STALK
	var sprint_target := _vehicle_sprint_target_speed()
	if sprint_target > 0.0:
		if vehicle_sprint_speed <= 0.0:
			vehicle_sprint_speed = minf(Vector2(velocity.x, velocity.z).length(), sprint_target)
		vehicle_sprint_speed = minf(sprint_target, move_toward(vehicle_sprint_speed, sprint_target, vehicle_sprint_acceleration * delta))
		move_speed = vehicle_sprint_speed
		pursuit_gait = PursuitGait.VEHICLE_SPRINT
	else:
		vehicle_sprint_speed = 0.0
	var moving := super._process_chase(delta, destination)
	move_speed = configured_speed
	if not moving or locomotion_state != LocomotionState.NORMAL:
		pursuit_gait = PursuitGait.STALK
		vehicle_sprint_speed = 0.0
	return moving

func _face_movement_direction() -> void:
	# Shared navigation supplies the desired velocity. Turn the actor first,
	# then move along that facing; the old controller changed velocity instantly
	# while easing the body, producing sideways/backward running on corners.
	if crouched or locomotion_state != LocomotionState.NORMAL or is_instance_valid(rv_support.rv):
		super._face_movement_direction()
		return
	var desired := velocity.slide(Vector3.UP)
	var speed := desired.length()
	if speed < .0001: return
	var direction := desired / speed
	var target_yaw := atan2(-direction.x, -direction.z)
	var yaw_error := angle_difference(global_rotation.y, target_yaw)
	if absf(yaw_error) < deg_to_rad(100): reversal_side = 0.0
	elif absf(yaw_error) > deg_to_rad(150) and is_zero_approx(reversal_side):
		reversal_side = 1.0 if yaw_error >= 0 else -1.0
	var step := ground_turn_rate * steering_delta
	# Targets crossing the exact rear direction must not alternate the chosen
	# left/right half-turn each tick. Release the choice once facing the target.
	var yaw := global_rotation.y + reversal_side * step if not is_zero_approx(reversal_side) else rotate_toward(global_rotation.y, target_yaw, step)
	global_rotation = Vector3(0, yaw, 0)
	var forward := -global_basis.z
	# Turn in place when the target is behind; brake into sharp corners.
	var alignment := maxf(0, forward.dot(direction))
	var motion := forward * speed * alignment
	velocity.x = motion.x
	velocity.z = motion.z

func _vehicle_sprint_target_speed() -> float:
	var rv := boarding.target_vehicle
	if is_dead or crouched or strike_elapsed >= 0 or reaction_remaining > 0 or boarding.recovery > 0:
		return 0.0
	if locomotion_state != LocomotionState.NORMAL or is_instance_valid(rv_support.rv) or is_instance_valid(boarding.cabin_vehicle):
		return 0.0
	if not is_instance_valid(rv) or rv.is_queued_for_deletion() or not WorldEntities.same_world(self, rv): return 0.0
	if not is_instance_valid(target_player) or not WorldEntities.same_world(self, target_player): return 0.0
	if not _is_node_on_specific_rv_surface(target_player, rv) or _is_on_rv_surface(): return 0.0
	# Production road_speed samples displacement: spinning wheels against a wall
	# must not grant a stationary vehicle a high-speed pursuer.
	var speed: float = rv.road_speed() if rv.has_method("road_speed") else ClimbMath.point_velocity(rv, rv.global_position).slide(Vector3.UP).length()
	if speed < (3.0 if vehicle_sprint_speed > 0.0 else 4.0): return 0.0
	return minf(speed + maxf(0.0, vehicle_sprint_margin), maxf(0.0, vehicle_sprint_cap))

func _process_attack(delta: float) -> void:
	if grab.busy() or strike_elapsed >= 0 or reaction_remaining > 0:
		if locomotion_state == LocomotionState.NORMAL:
			velocity.x = 0
			velocity.z = 0
		return
	super._process_attack(delta)

func _execute_attack_on_target(data: Dictionary) -> void:
	if is_dead or grab.busy() or attack_timer > 0 or strike_elapsed >= 0 or reaction_remaining > 0: return
	var victim: Variant = data.get("node")
	if not is_instance_valid(victim) or not victim.has_method("take_damage"): return
	if not boarding.can_attack(self, victim): return
	if victim.has_method("can_be_grabbed") and victim.locomotion_state == victim.LocomotionState.NORMAL:
		if locomotion_state == LocomotionState.NORMAL and grab.start(victim): attack_timer = attack_cooldown
		return
	strike_target = data.duplicate()
	strike_elapsed = 0
	strike_resolved = false
	strike_direction = -global_basis.z
	strike_clip = "attack_left" if next_left else "attack_right"
	next_left = not next_left
	strike_duration = 1.2
	strike_contact = SWEEP_CONTACT
	match str(data.get("attack_source", "")):
		"underfoot":
			strike_clip = "attack_down"
			strike_duration = 1.4
			strike_contact = 0.98
		"door_breach":
			strike_clip = "attack_door"
			strike_contact = 0.78
		_:
			if crouched:
				strike_clip = "crouch_attack"
				strike_contact = 0.6
	attack_timer = attack_cooldown
	attack_started.emit(strike_clip, strike_duration)

func _tick_strike(delta: float) -> void:
	if strike_elapsed < 0: return
	strike_elapsed += delta
	if not strike_resolved and strike_elapsed >= strike_contact:
		strike_resolved = true
		var victim: Variant = strike_target.get("node")
		if is_instance_valid(victim) and _strike_still_valid(victim):
			victim.take_damage(contact_damage)
			attack_landed.emit(victim, _resolve_attack_source_label(strike_target))
	if strike_elapsed >= strike_duration:
		strike_elapsed = -1
		strike_target = {}

func _strike_still_valid(victim: Node3D) -> bool:
	if not is_instance_valid(victim) or victim.is_queued_for_deletion(): return false
	if not WorldEntities.same_world(self, victim) or not boarding.can_attack(self, victim): return false
	var source := str(strike_target.get("attack_source", ""))
	if source == "door_breach":
		return locomotion_state == LocomotionState.CLIMBING and boarding.valid_door(self) and victim == boarding.door
	if not _can_attack_combat_target(strike_target, _has_attack_line_of_sight_to_target(victim)): return false
	if source == "underfoot": return victim == _get_underfoot_raycast_target()
	var offset := (victim.global_position - global_position).slide(Vector3.UP)
	# Locked facing: sidestepping behind the swing really avoids damage.
	return offset.length() < 0.1 or strike_direction.dot(offset.normalized()) >= cos(deg_to_rad(65))

func _update_posture() -> void:
	var low := false
	for rv in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if not WorldEntities.same_world(self, rv): continue
		var local: Vector3 = rv.to_local(global_position)
		if absf(local.x) >= 3.5 or absf(local.z) >= 6.8 or local.y >= 2.0: continue
		if locomotion_state == LocomotionState.NORMAL:
			low = true
			# Keep closing the gap outside a moving RV; crouching several metres
			# before contact would reduce a vehicle sprint to 0.7 m/s.
			var moving_rv := ClimbMath.point_velocity(rv, rv.global_position).slide(Vector3.UP).length() > 3.0
			if rv.has_method("road_speed"): moving_rv = rv.road_speed() > 3.0
			if moving_rv and not boarding.cabin.inside(self, rv): low = false
		else:
			# Clamber over the sill of a real opening with the low capsule.
			# Standing up mid-transfer would reject the doorway and climb the roof.
			for opening in boarding.cabin.openings(rv):
				var point: Vector3 = opening.point
				if Vector2(local.x-point.x,local.z-point.z).length() < 1.5:
					low = true
		if low: break
	if crouched and not low and not can_stand(): low = true
	set_crouched(low)

func can_stand() -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = body_collision_shape.shape.radius
	shape.height = STANDING_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform * Transform3D(Basis.IDENTITY, Vector3(0, FOOT_OFFSET + STANDING_HEIGHT * 0.5 + 0.025, 0))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func set_crouched(value: bool) -> void:
	if crouched == value: return
	crouched = value
	attack_range = 1.6 if crouched else 1.15
	var height := CROUCH_HEIGHT if crouched else STANDING_HEIGHT
	body_collision_shape.shape.height = height
	body_collision_shape.position.y = FOOT_OFFSET + height * 0.5
	$HitBox/HitBoxShape.shape.height = height
	$HitBox.position.y = body_collision_shape.position.y
	nav_agent.height = height
	boarding.cabin.request_repath()

func take_damage(amount: float) -> void:
	if is_dead: return
	if amount >= 8: grab.cancel("damaged")
	super.take_damage(amount)
	if not is_dead and amount >= 8:
		pursuit_gait = PursuitGait.STALK
		vehicle_sprint_speed = 0.0
		strike_elapsed = -1
		strike_target = {}
		reaction_remaining = .3
		reaction_started.emit()

func die() -> void:
	if is_dead: return
	grab.cancel("death")
	is_dead = true
	pursuit_gait = PursuitGait.STALK
	vehicle_sprint_speed = 0.0
	strike_elapsed = -1
	strike_target = {}
	if locomotion_state == LocomotionState.CLIMBING: _abort_climb("death")
	_spawn_loot()
	death_started.emit()
	$HitBox.set_deferred("monitoring", false)

func grab_face_position() -> Vector3:
	var visual := $BodyMesh
	if visual.pose_modifier.world_positions.has("face"): return visual.bone_world_position("face")
	return visual.skeleton.to_global(visual.pose_modifier.face_position(visual.skeleton))

func grab_shoulder_position(side: int) -> Vector3:
	return $BodyMesh.bone_world_position("upper_arm_R" if side > 0 else "upper_arm_L")

func can_grab_from(origin: Vector3, victim: Node3D) -> bool:
	if not victim.has_method("can_be_grabbed"): return true
	return grab.approach_clear(origin, victim)

func _can_attack_combat_target(data: Dictionary, has_line_of_sight: bool = true) -> bool:
	if not super._can_attack_combat_target(data, has_line_of_sight): return false
	var victim: Node3D = data.get("node")
	if is_instance_valid(grab) and is_instance_valid(victim) and victim.has_method("can_be_grabbed") and victim.locomotion_state == victim.LocomotionState.NORMAL:
		return grab.busy() or can_grab_from(global_position, victim)
	return true


extends Monster
class_name SlenderSpeaker
## Visual-only giant. Inherited Raker combat/boarding code is never processed.
enum Phase { PATROL, CONFIRM, CHASE, SEARCH, SMASH, GRAB, LIFT, HOLD, CRUSH, RECOVER, STAGGER }
const ArmIK := preload("res://enemies/slender_speaker/slender_speaker_arm_ik.gd")
const VehicleFollow := preload("res://enemies/slender_speaker/slender_speaker_vehicle_follow.gd")
@export var settings: SlenderSpeakerSettings = SlenderSpeakerSettings.new()
var phase: Phase = Phase.PATROL
var phase_elapsed := 0.0
var target_vehicle: Node3D
var last_seen_position := Vector3.ZERO
var home_position := Vector3.ZERO
var giant_navigation_map: RID
var _sense_remaining := 0.0
var _visible_target := false
var _lost_seconds := 0.0
var _patrol_index := 0
var _animation_time := 0.0
var _animation_clip := ""
var _stagger_remaining := 0.0
var _stagger_cooldown := 0.0
var _strike_locked := false
var _strike_point := Vector3.ZERO
var _strike_correction := Vector3.ZERO
var _strike_resolved := false
var _strike_obstruction_pose: Array[Transform3D] = []
var _strike_contact_collider: Node
var _strike_contact_probe := Vector3.ZERO
var _grab_contact := Vector3.ZERO
var _grab_hand_contact := Vector3.ZERO
var _grab_end_wrists: Dictionary = {}
var _seated_capture_pose: Array[Transform3D] = []
var _execution_socket_offset := Vector3.ZERO
var _grab_correction := Vector3.ZERO
var _grab_locked := false
var _previous_hands: Dictionary = {}
var _grab_touched := false
var _grab_hands_touched: Dictionary = {}
var _grab_blocked := false
var _grab_blocking_hits: Array[Dictionary] = []
var _execution_player: Node3D
var _execution_resolved := false
var _music_fade := 0.0
var _music_tail := false
var _scan_direction := 1.0
var _last_target_refresh := 0.0
var _recovery_source: Phase = Phase.CRUSH
var _recovery_pose: Array[Transform3D] = []
var _recovery_lift_time := 0.0
var _gait_phase := 0.0
var _gait_blend := 0.0
var _locomotion_clip := "idle_play"
var _locomotion_transition_pose: Array[Transform3D] = []
var _locomotion_transition_elapsed := 1.0
var _locomotion_transitions := 0
var _vehicle_follow := VehicleFollow.new()
var _follow_plan: Dictionary = {}
var _moving_smash := false
var _smash_entry_pose: Array[Transform3D] = []
var _attack_feet: Dictionary = {}
var _attack_gait_pose: Array[Transform3D] = []
var _strike_stopped_socket := Vector3.ZERO
var _strike_panel_socket := Vector3.ZERO
var _strike_panel_probe := Vector3.ZERO
@onready var visual: Node3D = get_node_or_null("BodyMesh")
@onready var execution_anchor: Node3D = get_node_or_null("ExecutionAnchor")
@onready var execution_focus: Node3D = get_node_or_null("ExecutionFocus")
@onready var patrol_music: AudioStreamPlayer3D = get_node_or_null("PatrolMusic")
@onready var execution_music: AudioStreamPlayer3D = get_node_or_null("ExecutionMusic")

func _ready() -> void:
	enable_boarding_visual = false
	contact_damage = 0.0
	super._ready()
	add_to_group("slender_speaker")
	home_position = global_position
	last_seen_position = global_position
	if nav_agent: nav_agent.path_height_offset = 0.0
	if nav_agent != null and giant_navigation_map.is_valid(): nav_agent.set_navigation_map(giant_navigation_map)
	for pair in [[patrol_music, "res://assets/audio/slender_speaker/patrol.wav"], [execution_music, "res://assets/audio/slender_speaker/execution.wav"]]:
		if pair[0] != null and ResourceLoader.exists(pair[1]):
			var stream: AudioStream = load(pair[1]).duplicate()
			if stream is AudioStreamWAV: stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if pair[0] == patrol_music else AudioStreamWAV.LOOP_DISABLED
			pair[0].stream = stream
	if patrol_music != null and patrol_music.stream != null: patrol_music.play()
	if execution_music != null: execution_music.finished.connect(_on_execution_music_finished)
	_sample("idle_play", 0.0)

func _enter_tree() -> void:
	if is_node_ready(): _resume_patrol_after_transfer.call_deferred()

func _resume_patrol_after_transfer() -> void:
	if is_inside_tree() and patrol_music != null and patrol_music.stream != null and not is_instance_valid(_execution_player):
		patrol_music.volume_db = -8.0
		patrol_music.play()

func set_giant_navigation_map(map: RID) -> void:
	if map == giant_navigation_map: return
	giant_navigation_map = map
	if nav_agent: nav_agent.set_navigation_map(map)

func reset_after_restore() -> void:
	_cancel_execution("restore")
	target_player = null
	target_vehicle = null
	_visible_target = false
	home_position = global_position
	_set_phase(Phase.PATROL)

func is_execution_active() -> bool:
	return is_instance_valid(_execution_player) or phase == Phase.GRAB

func can_save() -> bool:
	return not is_execution_active()

func take_damage(_amount: float) -> void:
	pass # Deliberately invincible in the first release.

func die() -> void:
	pass

func _physics_process(delta: float) -> void:
	phase_elapsed += delta
	_stagger_cooldown = maxf(0.0, _stagger_cooldown - delta)
	_sense_remaining -= delta
	if _sense_remaining <= 0.0 and not phase in [Phase.LIFT, Phase.HOLD, Phase.CRUSH]:
		_refresh_sight()
		_sense_remaining = 0.1
	_update_music(delta)
	var desired := Vector3.ZERO
	match phase:
		Phase.PATROL:
			if _visible_target: _set_phase(Phase.CONFIRM)
			else:
				var angle := float(_patrol_index) * 2.399963
				var point := home_position + Vector3(cos(angle), 0, sin(angle)) * 22.0
				if global_position.slide(Vector3.UP).distance_to(point.slide(Vector3.UP)) < 2.0: _patrol_index += 1
				desired = _navigate(point, settings.patrol_speed, delta)
		Phase.CONFIRM:
			if not _visible_target: _set_phase(Phase.PATROL)
			elif phase_elapsed >= settings.confirm_time: _set_phase(Phase.CHASE)
		Phase.CHASE:
			if not _visible_target:
				_lost_seconds += delta
				if _lost_seconds >= 0.4: _set_phase(Phase.SEARCH)
			else:
				_lost_seconds = 0.0
				var target_point := _target_point()
				var gap := global_position.slide(Vector3.UP).distance_to(target_point.slide(Vector3.UP))
				var facing := _facing_dot(target_point)
				if is_instance_valid(target_player) and gap <= 2.7 and facing > 0.985 and _player_can_be_executed():
					_begin_grab()
				elif is_instance_valid(target_player) and gap <= 3.0 and facing <= 0.985:
					var direction := (target_point - global_position).slide(Vector3.UP).normalized()
					rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), deg_to_rad(settings.near_turn_degrees) * delta)
				elif is_instance_valid(target_vehicle):
					desired = _follow_vehicle(delta)
					if _follow_plan.get("can_attack", false) and _facing_dot(_follow_plan.surface_point) > .85:
						_begin_smash()
				else: desired = _navigate(target_point, 12.0, delta)
		Phase.SEARCH:
			if _visible_target: _set_phase(Phase.CONFIRM)
			elif phase_elapsed >= settings.search_seconds:
				target_player = null
				target_vehicle = null
				_set_phase(Phase.PATROL)
			else:
				if global_position.slide(Vector3.UP).distance_to(last_seen_position.slide(Vector3.UP)) < 3.0:
					var turning := settings.fast_turn_degrees if velocity.slide(Vector3.UP).length() > 7.0 else settings.near_turn_degrees
					rotation.y += deg_to_rad(turning) * delta * _scan_direction
				else: desired = _navigate(last_seen_position, settings.patrol_speed, delta)
		Phase.SMASH:
			if _moving_smash and _visible_target: desired = _follow_vehicle(delta)
		Phase.GRAB: _advance_grab()
		Phase.LIFT, Phase.HOLD, Phase.CRUSH: _advance_execution()
		Phase.RECOVER:
			if _moving_smash and _recovery_source == Phase.SMASH and _visible_target: desired = _follow_vehicle(delta)
		Phase.STAGGER:
			if phase_elapsed >= settings.stagger_seconds: _set_phase(Phase.CHASE if _visible_target else Phase.SEARCH)
	if phase in [Phase.PATROL, Phase.CHASE, Phase.SEARCH]:
		var speed := velocity.slide(Vector3.UP).length()
		_animate_locomotion(delta, speed)
	_move_swept(desired, delta)
	# Sample after world movement so a moving fist sweeps its complete path,
	# including this tick's translation, against the locked world impact point.
	if phase == Phase.SMASH: _advance_smash(delta)
	elif phase == Phase.RECOVER:
		_advance_recovery(delta)
		if phase_elapsed >= settings.smash_recovery: _set_phase(Phase.CHASE if _visible_target else Phase.SEARCH)
	_update_audio_positions()

func _set_phase(next: Phase) -> void:
	if next == Phase.RECOVER:
		_recovery_source = phase
		_recovery_lift_time = phase_elapsed if phase == Phase.LIFT else 0.0
		_recovery_pose = _capture_pose()
	phase = next
	phase_elapsed = 0.0
	_previous_hands.clear()
	var moving_attack := _moving_smash and (next == Phase.SMASH or (next == Phase.RECOVER and _recovery_source == Phase.SMASH))
	if next in [Phase.SMASH, Phase.GRAB, Phase.LIFT, Phase.HOLD, Phase.CRUSH, Phase.RECOVER, Phase.STAGGER] and not moving_attack:
		velocity.x = 0.0
		velocity.z = 0.0
	if not next in [Phase.SMASH, Phase.RECOVER]: _moving_smash = false

func _capture_pose() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	if visual == null or visual.get("available") != true: return result
	var s: Skeleton3D = visual.skeleton
	for i in s.get_bone_count(): result.append(Transform3D(Basis(s.get_bone_pose_rotation(i)), s.get_bone_pose_position(i)))
	return result

func _blend_from_pose(start: Array[Transform3D], weight: float) -> void:
	if start.is_empty() or visual == null or visual.get("available") != true: return
	var s: Skeleton3D = visual.skeleton
	for i in mini(start.size(), s.get_bone_count()):
		s.set_bone_pose_position(i, start[i].origin.lerp(s.get_bone_pose_position(i), weight))
		s.set_bone_pose_rotation(i, start[i].basis.get_rotation_quaternion().slerp(s.get_bone_pose_rotation(i), weight))
	s.force_update_all_bone_transforms()

func _advance_recovery(delta: float = 0.0) -> void:
	match _recovery_source:
		Phase.SMASH:
			_sample_smash_motion(minf(settings.smash_windup + phase_elapsed, _duration("smash")), delta)
			var wrist := _bone_position("hand.R")
			var correction := _strike_correction * (1.0 - smoothstep(0.0, settings.smash_recovery, phase_elapsed))
			_adapt_crouch(correction.y)
			_correct_hand("R", wrist + correction - _bone_position("hand.R"))
		Phase.GRAB:
			_sample("grab_miss", minf(1.05 + phase_elapsed, _duration("grab_miss")))
			var correction := _grab_correction * (1.0 - smoothstep(0.0, .95, phase_elapsed))
			var wrists := {"R": _bone_position("hand.R"), "L": _bone_position("hand.L")}
			_adapt_crouch(correction.y)
			for side in ["R", "L"]: _correct_hand(side, wrists[side] + correction - _bone_position("hand." + side))
		Phase.LIFT:
			var lowering := minf(.8, maxf(.15, _recovery_lift_time))
			if phase_elapsed < lowering:
				_sample("lift", _recovery_lift_time * (1.0 - smoothstep(0.0, lowering, phase_elapsed)))
			else: _sample("grab_miss", minf(1.05 + phase_elapsed - lowering, _duration("grab_miss")))
		_:
			_sample("retract", minf(phase_elapsed, _duration("retract")))
	var transition_seconds := settings.smash_recovery if _recovery_source == Phase.SMASH and not _strike_obstruction_pose.is_empty() and not _strike_contact_collider is RVStructurePanel else .22
	_blend_from_pose(_recovery_pose, smoothstep(0.0, transition_seconds, phase_elapsed))
	if _moving_smash:
		# The authored clip returns to a tall idle. While following a vehicle,
		# recover into the live gait instead, including its pelvis and torso.
		_blend_from_pose(_attack_gait_pose, 1.0 - smoothstep(0.0, settings.smash_recovery, phase_elapsed))
		_apply_attack_feet()

func _animate_locomotion(delta: float, speed: float) -> void:
	# Normalized leg phase survives the different walk/run clip durations.
	# Hysteresis keeps small acceleration/terrain fluctuations from restarting
	# transitions every frame around the previous 7m/s threshold.
	var clip := "run" if speed >= 8.0 or (_locomotion_clip == "run" and speed > 6.0) else "walk" if speed > .25 or (_locomotion_clip == "walk" and speed > .12) else "scan" if phase == Phase.SEARCH else "idle_play"
	if clip != _locomotion_clip or _animation_clip != clip:
		_locomotion_transition_pose = _capture_pose()
		_locomotion_transition_elapsed = 0.0
		_locomotion_transitions += 1
		_locomotion_clip = clip
	_locomotion_transition_elapsed += delta
	if clip in ["walk", "run"]:
		_sample_gait(delta, speed)
	else:
		_animation_time += delta
		_sample(clip, fmod(_animation_time, _duration(clip)))
	_blend_from_pose(_locomotion_transition_pose, smoothstep(0.0, .22, _locomotion_transition_elapsed))

func _sample_gait(delta: float, speed: float) -> void:
	# Both clips share a continuous foot phase. Blend their authored stride
	# distances as well as their poses so crossing 8 m/s cannot drop cadence.
	_gait_blend = move_toward(_gait_blend, smoothstep(4.0, 12.0, speed), delta * 4.0)
	var stride := lerpf(_duration("walk") * 4.0, _duration("run") * 10.0, _gait_blend)
	_gait_phase = fposmod(_gait_phase + delta * speed / maxf(.001, stride), 1.0)
	_sample("walk", _gait_phase * _duration("walk"))
	if _gait_blend > .0001:
		var walking := _capture_pose()
		_sample("run", _gait_phase * _duration("run"))
		_blend_from_pose(walking, _gait_blend)
	_animation_clip = _locomotion_clip

func _player_can_be_executed() -> bool:
	return is_instance_valid(target_player) and target_player.has_method("can_be_executed") and target_player.can_be_executed()

func _target_point() -> Vector3:
	if is_instance_valid(target_player): return _player_contact(target_player)
	if is_instance_valid(target_vehicle): return _vehicle_surface(target_vehicle)
	return last_seen_position

func _player_contact(player: Node3D) -> Vector3:
	return player.execution_contact_position() if player.has_method("execution_contact_position") else player.global_position + Vector3.UP

func _facing_dot(point: Vector3) -> float:
	var direction := (point - global_position).slide(Vector3.UP).normalized()
	return (-global_basis.z).dot(direction)

func _refresh_sight() -> void:
	_visible_target = false
	var best := INF
	var seen_player: Node3D
	var seen_vehicle: Node3D
	for candidate in get_tree().get_nodes_in_group(Groups.PLAYER):
		if not candidate is Node3D or not WorldEntities.same_world(self, candidate) or candidate.get("is_player_dead") == true: continue
		var point := _player_contact(candidate)
		var distance := global_position.distance_to(point)
		if distance < best and can_see(candidate, point):
			seen_player = candidate
			best = distance
	var visible_player := seen_player
	for candidate in get_tree().get_nodes_in_group(Groups.RV):
		if not candidate is Node3D or not WorldEntities.same_world(self, candidate): continue
		var moving := ClimbMath.point_velocity(candidate, candidate.global_position).slide(Vector3.UP).length() > 0.25
		if not moving and candidate != target_vehicle: continue
		var point := _vehicle_surface(candidate)
		var distance := global_position.distance_to(point)
		if distance < best and can_see(candidate, point):
			seen_player = null
			seen_vehicle = candidate
			best = distance
	if seen_player != null:
		target_player = seen_player
		var seat: Node = seen_player.get("seated_in")
		target_vehicle = RVConnection.resolve(seat) if is_instance_valid(seat) else null
		_visible_target = true
	elif seen_vehicle != null:
		target_vehicle = seen_vehicle
		if visible_player != null and RVConnection.resolve(visible_player.get("seated_in")) == seen_vehicle:
			target_player = visible_player
		# Keep a remembered seated driver for an eventual aperture grab.
		elif is_instance_valid(target_player) and RVConnection.resolve(target_player.get("seated_in")) != target_vehicle: target_player = null
		_visible_target = true
	if _visible_target: last_seen_position = _target_point()

func can_see(target: Node3D, point: Vector3) -> bool:
	var origin := _focus_position()
	var direction := point - origin
	if direction.length() > settings.sight_range: return false
	var forward := -global_basis.z
	if visual != null and visual.get("available") == true:
		forward = visual.bone_world("socket_focus").basis.y.normalized()
	# Height alone must not take a nearby ground target out of the cone.
	if forward.slide(Vector3.UP).normalized().dot(direction.slide(Vector3.UP).normalized()) < cos(deg_to_rad(settings.sight_half_angle_degrees)): return false
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, point, collision_mask, [get_rid()]))
	return hit.is_empty() or _belongs_to(hit.collider, target) or (RVConnection.is_rv(target) and RVConnection.resolve(hit.collider) == target)

func _belongs_to(node: Node, ancestor: Node) -> bool:
	var cursor := node
	while is_instance_valid(cursor):
		if cursor == ancestor: return true
		cursor = cursor.get_parent()
	return false

func _vehicle_surface(vehicle: Node3D) -> Vector3:
	var nearest := vehicle.global_position + Vector3.UP
	var distance := INF
	for part in get_tree().get_nodes_in_group(Groups.MONSTER_DAMAGEABLE):
		if not part is RVStructurePanel or part.is_destroyed or part.get_connected_rv() != vehicle: continue
		var d := global_position.distance_squared_to(part.global_position)
		if d < distance:
			nearest = part.global_position
			distance = d
	return nearest

func _follow_vehicle(delta: float) -> Vector3:
	_follow_plan.clear()
	if not is_instance_valid(target_vehicle) or not WorldEntities.same_world(self, target_vehicle): return Vector3.ZERO
	_follow_plan = _vehicle_follow.update(self, target_vehicle, delta)
	if _follow_plan.is_empty(): return Vector3.ZERO
	return _navigate(_follow_plan.navigation_point, float(_follow_plan.speed), delta)

func _attack_surface() -> Vector3:
	if not _follow_plan.is_empty() and is_instance_valid(target_vehicle): return _follow_plan.surface_point
	return _vehicle_surface(target_vehicle) if is_instance_valid(target_vehicle) else _strike_point

func _capture_attack_feet(delta: float) -> void:
	_attack_feet.clear()
	if not _moving_smash or visual == null or visual.get("available") != true: return
	var speed := velocity.slide(Vector3.UP).length()
	var clip := "run" if speed >= 8.0 or (_locomotion_clip == "run" and speed > 6.0) else "walk"
	_locomotion_clip = clip
	_sample_gait(delta, speed)
	_attack_gait_pose = _capture_pose()
	for side in ["R", "L"]: _attack_feet[side] = _bone_position("foot." + side)

func _apply_attack_feet() -> void:
	if visual == null or visual.get("available") != true: return
	for side in _attack_feet: ArmIK.reach(visual.skeleton, side, _attack_feet[side], true)

func _sample_smash_motion(time: float, delta: float) -> void:
	_capture_attack_feet(delta)
	_sample("smash", time)
	if _moving_smash:
		if time < .22: _blend_from_pose(_smash_entry_pose, smoothstep(0.0, .22, time))
		var downswing := smoothstep(settings.smash_windup - settings.smash_lock_seconds, settings.smash_windup, time)
		_blend_attack_lower_body(downswing)
		if downswing > 0.0: _apply_attack_feet()

func _blend_attack_lower_body(attack_weight: float) -> void:
	if _attack_gait_pose.is_empty(): return
	var skeleton: Skeleton3D = visual.skeleton
	for bone_name in ["pelvis", "thigh.R", "shin.R", "foot.R", "thigh.L", "shin.L", "foot.L"]:
		var index := skeleton.find_bone(bone_name)
		if index < 0: continue
		var gait := _attack_gait_pose[index]
		skeleton.set_bone_pose_position(index, gait.origin.lerp(skeleton.get_bone_pose_position(index), attack_weight))
		skeleton.set_bone_pose_rotation(index, gait.basis.get_rotation_quaternion().slerp(skeleton.get_bone_pose_rotation(index), attack_weight))
	skeleton.force_update_all_bone_transforms()

func _navigate(point: Vector3, speed: float, delta: float) -> Vector3:
	if not giant_navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(giant_navigation_map) <= 0 or nav_agent == null: return Vector3.ZERO
	if nav_agent.target_position.distance_to(point) > 1.0 or phase_elapsed < delta * 1.5: nav_agent.target_position = point
	var next := nav_agent.get_next_path_position()
	var direction := (next - global_position).slide(Vector3.UP).normalized()
	if direction.length_squared() < 0.1: return Vector3.ZERO
	var desired_angle := atan2(-direction.x, -direction.z)
	var turning := settings.fast_turn_degrees if velocity.slide(Vector3.UP).length() > 7.0 else settings.near_turn_degrees
	var previous_angle := rotation.y
	rotation.y = rotate_toward(rotation.y, desired_angle, deg_to_rad(turning) * delta)
	# Turning demand reduces the target speed even after the body has aligned
	# with a curved path. Tiny steering corrections retain straight-line pace.
	var yaw_rate := absf(rad_to_deg(angle_difference(previous_angle, rotation.y))) / maxf(delta, .000001)
	var turn_weight := smoothstep(5.0, settings.fast_turn_degrees, yaw_rate)
	var corner_speed := minf(speed, settings.chase_speed) * lerpf(1.0, settings.turn_speed_ratio, turn_weight)
	var alignment := maxf(0.0, (-global_basis.z).dot(direction))
	return -global_basis.z * corner_speed * alignment

func _move_swept(desired: Vector3, delta: float) -> void:
	var current := velocity.slide(Vector3.UP)
	var target := desired.slide(Vector3.UP).limit_length(settings.chase_speed)
	var rate := settings.braking if target.length_squared() < current.length_squared() else settings.acceleration
	if target.length_squared() < current.length_squared() and is_instance_valid(target_vehicle) and _visible_target and phase in [Phase.CHASE, Phase.SMASH, Phase.RECOVER]:
		rate = minf(rate, VehicleFollow.FOLLOW_BRAKING)
	var horizontal := current.move_toward(target, rate * delta).limit_length(settings.chase_speed)
	if is_instance_valid(target_vehicle):
		horizontal = _vehicle_follow.constrain_velocity(self, target_vehicle, horizontal, delta).limit_length(settings.chase_speed)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor(): velocity.y -= gravity * delta
	else: velocity.y = minf(velocity.y, 0.0)
	contact_approach_velocity = velocity
	contact_sample_frame = Engine.get_physics_frames()
	# CharacterBody motion uses a continuous shape sweep at the 60 km/h cap.
	move_and_slide()
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		var rv := RVConnection.resolve(hit.get_collider())
		if rv != null: receive_vehicle_body_contact(rv, hit.get_normal(), hit.get_position())

func _begin_smash() -> void:
	_moving_smash = velocity.slide(Vector3.UP).length() > .25 or (is_instance_valid(target_vehicle) and ClimbMath.point_velocity(target_vehicle, target_vehicle.global_position).slide(Vector3.UP).length() > .25)
	_smash_entry_pose = _capture_pose()
	_set_phase(Phase.SMASH)
	_strike_locked = false
	_strike_resolved = false
	_strike_obstruction_pose.clear()
	_strike_contact_collider = null
	_strike_point = _attack_surface()
	_sample("smash", settings.smash_windup)
	_strike_correction = _strike_point - _bone_position("socket_strike_R")
	_sample("smash", 0.0)
	if _moving_smash: _blend_from_pose(_smash_entry_pose, 0.0)
	_previous_hands["strike"] = _bone_position("socket_strike_R")

func _advance_smash(delta: float = 0.0) -> void:
	if not _strike_obstruction_pose.is_empty():
		# Every first collider stops the real hand path, including a car panel.
		# Once touched, the hand rides that physical panel until impact settles.
		# Aim remains fixed before contact; this is not a new target selection.
		if _moving_smash and is_instance_valid(_strike_contact_collider) and _strike_contact_collider is RVStructurePanel:
			var contact_socket: Vector3 = _strike_contact_collider.to_global(_strike_panel_socket)
			var obstruction := sweep_hand(_strike_stopped_socket, contact_socket, .34, [_strike_contact_collider.get_rid()])
			if not obstruction.is_empty():
				_strike_resolved = true
				_set_phase(Phase.RECOVER)
				return
			_strike_stopped_socket = contact_socket
			_strike_contact_probe = _strike_contact_collider.to_global(_strike_panel_probe)
		_capture_attack_feet(delta)
		_blend_from_pose(_strike_obstruction_pose, 0.0)
		if _moving_smash:
			_apply_attack_feet()
			_correct_hand("R", _strike_stopped_socket - _bone_position("socket_strike_R"))
			if _bone_position("socket_strike_R").distance_to(_strike_stopped_socket) > .35:
				_strike_resolved = true
				_set_phase(Phase.RECOVER)
				return
		if phase_elapsed >= settings.smash_windup:
			_resolve_stopped_smash()
			_set_phase(Phase.RECOVER)
		return
	if not _strike_locked and is_instance_valid(target_vehicle):
		_strike_point = _attack_surface()
		if phase_elapsed >= settings.smash_windup - settings.smash_lock_seconds:
			_strike_locked = true
			if _moving_smash:
				_strike_point += ClimbMath.point_velocity(target_vehicle, _strike_point) * settings.smash_lock_seconds
			_sample("smash", settings.smash_windup)
			_strike_correction = _strike_point - _bone_position("socket_strike_R")
	if _moving_smash:
		# The endpoint remains fixed in world space after locking even though
		# the actor keeps walking. Vehicle acceleration/steering can evade it.
		_sample("smash", settings.smash_windup)
		_strike_correction = _strike_point - _bone_position("socket_strike_R")
	_sample_smash_motion(minf(phase_elapsed, settings.smash_windup), delta)
	var reach_start := settings.smash_windup - settings.smash_lock_seconds if _moving_smash else .3
	var reach_weight := smoothstep(reach_start, settings.smash_windup, phase_elapsed)
	var wrist := _bone_position("hand.R")
	_adapt_crouch(_strike_correction.y * reach_weight)
	_correct_hand("R", wrist + _strike_correction * reach_weight - _bone_position("hand.R"))
	var current := _bone_position("socket_strike_R")
	var previous: Vector3 = _previous_hands.get("strike", current)
	var path_hit := sweep_hand(previous, current, 0.34)
	if not path_hit.is_empty():
		var safe := maxf(0.0, float(path_hit.get("safe_fraction", 0.0)) - .002)
		_correct_hand("R", previous.lerp(current, safe) - current)
		_strike_obstruction_pose = _capture_pose()
		_strike_stopped_socket = _bone_position("socket_strike_R")
		_strike_contact_collider = path_hit.get("collider")
		_strike_contact_probe = path_hit.get("point", current) + path_hit.get("normal", Vector3.ZERO) * .338
		if _strike_contact_collider is RVStructurePanel:
			_strike_panel_socket = _strike_contact_collider.to_local(_strike_stopped_socket)
			_strike_panel_probe = _strike_contact_collider.to_local(_strike_contact_probe)
		_previous_hands["strike"] = _bone_position("socket_strike_R")
		if phase_elapsed >= settings.smash_windup:
			_resolve_stopped_smash()
			_set_phase(Phase.RECOVER)
		return
	if not _strike_resolved and phase_elapsed + 0.000001 >= settings.smash_windup:
		if not path_hit.is_empty(): resolve_smash_hit(path_hit.get("collider"))
	_previous_hands["strike"] = current
	if phase_elapsed >= settings.smash_windup:
		# Endpoint overlap is still a physical contact; no target proximity hit.
		if not _strike_resolved:
			var hit := sweep_hand(current, current, 0.34)
			if not hit.is_empty(): resolve_smash_hit(hit.get("collider"))
		_set_phase(Phase.RECOVER)

func _resolve_stopped_smash() -> void:
	if _strike_resolved: return
	if is_instance_valid(_strike_contact_collider) and _strike_contact_collider is RVStructurePanel:
		var hit := sweep_hand(_strike_contact_probe, _strike_contact_probe, .34)
		if hit.get("collider") == _strike_contact_collider:
			resolve_smash_hit(_strike_contact_collider)
			return
	_strike_resolved = true

func resolve_smash_hit(collider: Node) -> bool:
	if _strike_resolved: return false
	_strike_resolved = true
	if not collider is RVStructurePanel or collider.is_destroyed: return false
	if not WorldEntities.same_world(self, collider): return false
	collider.take_damage(collider.current_health)
	attack_landed.emit(collider, "slender_speaker_smash")
	return true

func _begin_grab() -> void:
	_set_phase(Phase.GRAB)
	_grab_locked = false
	_grab_touched = false
	_grab_hands_touched.clear()
	_seated_capture_pose.clear()
	_grab_blocked = false
	_grab_blocking_hits.clear()
	_grab_contact = _player_contact(target_player)
	_grab_hand_contact = _grab_contact
	if target_player.has_method("is_crawling") and target_player.is_crawling():
		_grab_hand_contact.y = maxf(_grab_contact.y, global_position.y + 0.75)
	_sample("grab", settings.grab_windup)
	_grab_correction = _grab_hand_contact - _bone_position("socket_grip_R")
	_grab_end_wrists = {"R": _bone_position("hand.R") + _grab_correction, "L": _bone_position("hand.L") + _grab_correction}
	_sample("grab", 0.0)
	for side in ["R", "L"]:
		for bone in _hand_contact_bones(side): _previous_hands[bone] = _bone_position(bone)

func _advance_grab() -> void:
	if not _player_can_be_executed():
		_set_phase(Phase.RECOVER)
		return
	if not _seated_capture_pose.is_empty():
		# A seated grip closes only until both hands reach the torso. Preserve
		# that actual contact pose rather than forcing fingers into its seat back.
		_blend_from_pose(_seated_capture_pose, 0.0)
		if phase_elapsed >= settings.grab_windup: _finish_grab()
		return
	if not _grab_locked:
		_grab_contact = _player_contact(target_player)
		_grab_hand_contact = _grab_contact
		if target_player.has_method("is_crawling") and target_player.is_crawling():
			_grab_hand_contact.y = maxf(_grab_contact.y, global_position.y + 0.75)
		if phase_elapsed >= settings.grab_windup - 0.25:
			_grab_locked = true
			_sample("grab", settings.grab_windup)
			_grab_correction = _grab_hand_contact - _bone_position("socket_grip_R")
			_grab_end_wrists = {"R": _bone_position("hand.R") + _grab_correction, "L": _bone_position("hand.L") + _grab_correction}
	_sample("grab", minf(phase_elapsed, settings.grab_windup))
	var weight := smoothstep(0.0, settings.grab_windup, phase_elapsed)
	var wrists := {"R": _bone_position("hand.R"), "L": _bone_position("hand.L")}
	_adapt_crouch(_grab_correction.y * weight)
	for side in ["R", "L"]:
		var desired: Vector3 = wrists[side] + _grab_correction * weight
		var forward := -global_basis.z
		var end_distance: float = (_grab_end_wrists[side] - global_position).dot(forward)
		var outside_distance := lerpf(0.34, -0.55, smoothstep(0.0, settings.grab_windup * 0.3, phase_elapsed))
		var reach_distance := lerpf(outside_distance, end_distance, smoothstep(settings.grab_windup * 0.85, settings.grab_windup, phase_elapsed))
		desired += forward * (reach_distance - (desired - global_position).dot(forward))
		desired.y += minf(0.8, maxf(0.0, _grab_correction.y * 0.5)) * pow(sin(PI * clampf(phase_elapsed / settings.grab_windup, 0.0, 1.0)), 2.0)
		_correct_hand(side, desired - _bone_position("hand." + side))
		for bone in _hand_contact_bones(side):
			var current := _bone_position(bone)
			var previous: Vector3 = _previous_hands.get(bone, current)
			var touched := _hand_hits_player(previous, current, 0.13, side, bone)
			if _grab_locked and touched:
				_grab_touched = true
				_grab_hands_touched[side] = true
			_previous_hands[bone] = _bone_position(bone)
	if is_instance_valid(target_player.get("seated_in")) and not _grab_blocked and _grab_hands_touched.size() == 2 and _hand_currently_touches_player("R") and _hand_currently_touches_player("L"):
		_seated_capture_pose = _capture_pose()
	if phase_elapsed >= settings.grab_windup: _finish_grab()

func _finish_grab() -> void:
	# The whole chest aperture has to be clear, not just a hairline sight ray.
	var socket := _bone_position("socket_grip_R")
	var exclude_player: Array[RID] = []
	if target_player is CollisionObject3D: exclude_player.append(target_player.get_rid())
	var clearance_contact := _player_contact(target_player)
	if target_player.has_method("is_crawling") and target_player.is_crawling(): clearance_contact.y = maxf(clearance_contact.y, global_position.y + 0.30)
	var clearance := sweep_hand(socket, clearance_contact, 0.26, exclude_player)
	if not _grab_blocked and _grab_hands_touched.size() == 2 and _hand_currently_touches_player("R") and _hand_currently_touches_player("L") and clearance.is_empty() and socket.distance_to(_player_contact(target_player)) < 0.65:
		_start_execution()
	else: _set_phase(Phase.RECOVER)

func _hand_contact_bones(side: String) -> Array[String]:
	var result: Array[String] = []
	for finger in ["index", "middle", "ring", "little", "thumb"]:
		for section in [1, 2, 3]: result.append("finger_%s_%02d.%s" % [finger, section, side])
	return result

func _hand_currently_touches_player(side: String) -> bool:
	# Earlier contact during the locked reach cannot capture an evading player.
	# Check both final hands again at the exact ownership transition.
	for bone in _hand_contact_bones(side):
		var point := _bone_position(bone)
		var hit := sweep_hand(point, point, .13)
		if not hit.is_empty() and _belongs_to(hit.get("collider"), target_player): return true
		if is_instance_valid(target_player.get("seated_in")) and point.distance_to(_player_contact(target_player)) <= .35:
			# Seated torso shape is disabled; the same actual posed proxy used by
			# the approach sweep supplies its contact volume. Shell clearance is
			# still independently required before acquiring ownership.
			return true
	return false

func _hand_hits_player(from: Vector3, to: Vector3, radius: float, side := "", bone := "") -> bool:
	var hit := sweep_hand(from, to, radius)
	# A seated body has no active physics RID shape. Put its posed torso proxy
	# into the same first-contact ordering, rather than checking it only after
	# all seat geometry. The nearer opaque shell still wins this comparison.
	if is_instance_valid(target_player.get("seated_in")):
		var entry := _sphere_entry(from, to, _player_contact(target_player), radius + 0.22)
		var blocking: float = float(hit.get("safe_fraction", 0.0)) if not hit.is_empty() else INF
		if entry <= 1.0 and entry <= blocking + 0.00001: return true
	if not hit.is_empty():
		if _belongs_to(hit.get("collider"), target_player): return true
		if _grab_hands_touched.has(side) and not bone.is_empty():
			# Contact fingers conform to the backing wall after reaching the torso.
			# Clamp the joint's remaining sweep, keeping actual hand geometry out.
			var index: int = visual.skeleton.find_bone(bone)
			var pose: Transform3D = visual.skeleton.get_bone_global_pose(index)
			var safe: float = maxf(0.0, float(hit.get("safe_fraction", 0.0)) - 0.002)
			pose.origin = visual.skeleton.to_local(from.lerp(to, safe))
			ArmIK._set_global(visual.skeleton, index, pose)
			return false
		_grab_blocked = true
		if _grab_blocking_hits.size() < 6:
			_grab_blocking_hits.append({"time": phase_elapsed, "node": String(hit.collider.get_path()) if hit.get("collider") != null else "", "from": from, "to": to})
		return false
	# Seat ownership disables the player's locomotion capsule. Its actual posed
	# torso still has volume: sweep this finger against a 22cm chest proxy.
	if not is_instance_valid(target_player.get("seated_in")): return false
	var chest := _player_contact(target_player)
	var motion := to - from
	var t := clampf((chest - from).dot(motion) / maxf(motion.length_squared(), 0.000001), 0.0, 1.0)
	if from.lerp(to, t).distance_to(chest) > radius + 0.22: return false
	# A proxy overlap cannot bypass any shell/window or narrower opening.
	var excluded: Array[RID] = []
	if target_player is CollisionObject3D: excluded.append(target_player.get_rid())
	return sweep_hand(from, to, 0.26, excluded).is_empty()

func _sphere_entry(from: Vector3, to: Vector3, center: Vector3, radius: float) -> float:
	var offset := from - center
	var motion := to - from
	var c := offset.length_squared() - radius * radius
	if c <= 0.0: return 0.0
	var a := motion.length_squared()
	if a < 0.000001: return INF
	var b := offset.dot(motion)
	var discriminant := b * b - a * c
	if discriminant < 0.0: return INF
	var entry := (-b - sqrt(discriminant)) / a
	return entry if entry >= 0.0 and entry <= 1.0 else INF

func _start_execution() -> bool:
	if not is_instance_valid(target_player) or execution_anchor == null or execution_focus == null: return false
	execution_anchor.global_position = _player_contact(target_player)
	_execution_socket_offset = execution_anchor.global_position - _bone_position("socket_grip_R")
	execution_focus.global_position = _focus_position()
	if not target_player.begin_execution(self, execution_anchor, execution_focus):
		_set_phase(Phase.RECOVER)
		return false
	_execution_player = target_player
	_execution_resolved = false
	# Preserve the authored-to-contact correction for the first lift frame.
	# The current socket already includes IK, so recomputing here would erase it.
	if _execution_player.get("grab_control") != null:
		var control: Node = _execution_player.grab_control
		if not control.released.is_connected(_on_player_released): control.released.connect(_on_player_released)
	# This event follows successful ownership, in the same physics frame.
	_music_tail = false
	_music_fade = 0.1
	if execution_music != null and execution_music.stream != null: execution_music.play(0.0)
	_set_phase(Phase.LIFT)
	return true

func _advance_execution() -> void:
	if not is_instance_valid(_execution_player) or not WorldEntities.same_world(self, _execution_player) or not _execution_player.is_executing():
		_cancel_execution("invalid_owner")
		_set_phase(Phase.RECOVER)
		return
	var correction := Vector3.ZERO
	match phase:
		Phase.LIFT:
			_sample("lift", minf(phase_elapsed, settings.lift_seconds))
			correction = _grab_correction * (1.0 - smoothstep(0.0, settings.lift_seconds, phase_elapsed))
		Phase.HOLD: _sample("hold", minf(phase_elapsed, settings.hold_seconds))
		Phase.CRUSH: _sample("crush", minf(phase_elapsed, settings.crush_seconds))
	var wrists := {"R": _bone_position("hand.R"), "L": _bone_position("hand.L")}
	_adapt_crouch(correction.y)
	for side in ["R", "L"]: _correct_hand(side, wrists[side] + correction - _bone_position("hand." + side))
	execution_anchor.global_position = _bone_position("socket_grip_R") + _execution_socket_offset
	execution_focus.global_position = _focus_position()
	if phase == Phase.LIFT and phase_elapsed + 0.000001 >= settings.lift_seconds:
		var overshoot := maxf(0.0, phase_elapsed - settings.lift_seconds)
		_set_phase(Phase.HOLD)
		phase_elapsed = overshoot
	elif phase == Phase.HOLD and phase_elapsed + 0.000001 >= settings.hold_seconds:
		var overshoot := maxf(0.0, phase_elapsed - settings.hold_seconds)
		_set_phase(Phase.CRUSH)
		phase_elapsed = overshoot
	elif phase == Phase.CRUSH and phase_elapsed + 0.000001 >= settings.crush_seconds and not _execution_resolved:
		_execution_resolved = true
		_execution_player.complete_execution(self)
		_disconnect_player()
		_execution_player = null
		_music_tail = true
		_set_phase(Phase.RECOVER)

func _on_player_released(reason: String) -> void:
	if _execution_resolved: return
	if is_instance_valid(_execution_player):
		_cancel_execution(reason)
		_set_phase(Phase.RECOVER)

func _disconnect_player() -> void:
	if is_instance_valid(_execution_player) and _execution_player.get("grab_control") != null:
		var control: Node = _execution_player.grab_control
		if control.released.is_connected(_on_player_released): control.released.disconnect(_on_player_released)

func _cancel_execution(reason: String) -> void:
	var player := _execution_player
	_disconnect_player()
	_execution_player = null
	if is_instance_valid(player) and player.has_method("cancel_execution"): player.cancel_execution(self, reason)
	_music_tail = false
	_music_fade = 0.0
	if execution_music != null: execution_music.stop()
	if patrol_music != null and patrol_music.is_inside_tree() and patrol_music.stream != null:
		patrol_music.volume_db = -8.0
		if not patrol_music.playing: patrol_music.play()

func _exit_tree() -> void:
	_cancel_execution("owner_removed")
	if patrol_music != null: patrol_music.stop()
	if execution_music != null: execution_music.stop()

func _focus_position() -> Vector3:
	return _bone_position("socket_focus") if visual != null and visual.get("available") == true else global_position + Vector3.UP * 13.85

func _bone_position(name: String) -> Vector3:
	return visual.bone_world(name).origin if visual != null and visual.get("available") == true else global_position + Vector3.UP

func _correct_hand(side: String, offset: Vector3) -> void:
	if visual == null or visual.get("available") != true or offset.length_squared() < 0.000001: return
	ArmIK.reach(visual.skeleton, side, _bone_position("hand." + side) + offset)

func _adapt_crouch(height_correction: float) -> void:
	if height_correction >= 0.0 or visual == null or visual.get("available") != true: return
	var s: Skeleton3D = visual.skeleton
	var index := s.find_bone("pelvis")
	if index < 0: return
	var feet := {"R": _bone_position("foot.R"), "L": _bone_position("foot.L")}
	var pelvis := s.get_bone_global_pose(index)
	pelvis.origin += s.global_basis.inverse() * Vector3.UP * maxf(-1.1, height_correction)
	ArmIK._set_global(s, index, pelvis)
	for side in ["R", "L"]: ArmIK.reach(s, side, feet[side], true)

func _sample(clip: String, time: float) -> void:
	if visual != null and visual.get("available") == true:
		visual.sample(clip, time)
	_animation_clip = clip

func _duration(clip: String) -> float:
	return maxf(0.01, visual.duration(clip)) if visual != null and visual.get("available") == true else 1.0

func sweep_hand(from: Vector3, to: Vector3, radius: float, extra_exclude: Array[RID] = []) -> Dictionary:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = from
	query.collision_mask = collision_mask
	var excluded: Array[RID] = [get_rid()]
	excluded.append_array(extra_exclude)
	query.exclude = excluded
	var space := get_world_3d().direct_space_state
	var overlap := space.get_rest_info(query)
	if not overlap.is_empty(): return _with_collider(overlap)
	query.motion = to - from
	if query.motion.length_squared() < 0.000001: return {}
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= 1.0: return {}
	query.transform.origin = from.lerp(to, minf(1.0, fractions[1] + 0.002 / maxf(query.motion.length(), 0.002)))
	query.motion = Vector3.ZERO
	var hit := _with_collider(space.get_rest_info(query))
	if not hit.is_empty(): hit["safe_fraction"] = fractions[0]
	return hit

func _with_collider(hit: Dictionary) -> Dictionary:
	if not hit.is_empty() and hit.has("collider_id"): hit["collider"] = instance_from_id(hit.collider_id)
	return hit

func receive_vehicle_body_contact(rv: Node3D, normal: Vector3, point: Vector3) -> bool:
	if is_instance_valid(_execution_player) or _stagger_cooldown > 0.0 or not WorldEntities.same_world(self, rv): return false
	var relative := ClimbMath.point_velocity(rv, point) - _contact_world_velocity()
	if rv.has_method("vehicle_impact_point_velocity"): relative = rv.vehicle_impact_point_velocity(point) - _contact_world_velocity()
	if relative.dot(normal) < settings.impact_speed: return false
	_stagger_cooldown = settings.stagger_cooldown
	_set_phase(Phase.STAGGER)
	return true

func _apply_vehicle_contact(rv: Node3D, normal: Vector3, point: Vector3) -> bool:
	return receive_vehicle_body_contact(rv, normal, point)

func _on_hitbox_body_entered(_body: Node3D) -> void:
	# Monster's predictive Area is wider than our physical capsule. Stagger
	# accepts only the chassis/CharacterBody's actual collision callbacks.
	pass

func _update_music(delta: float) -> void:
	if _music_fade > 0.0:
		_music_fade = maxf(0.0, _music_fade - delta)
		if patrol_music != null:
			patrol_music.volume_db = linear_to_db(maxf(0.0001, _music_fade / 0.1)) - 8.0
			if _music_fade <= 0.0: patrol_music.stop()

func _update_audio_positions() -> void:
	var position_world := _focus_position()
	if patrol_music != null: patrol_music.global_position = position_world
	if execution_music != null: execution_music.global_position = position_world

func _on_execution_music_finished() -> void:
	if not _music_tail: return
	_music_tail = false
	if execution_music != null: execution_music.stop()
	if patrol_music != null and patrol_music.is_inside_tree() and patrol_music.stream != null:
		patrol_music.volume_db = -8.0
		patrol_music.play()

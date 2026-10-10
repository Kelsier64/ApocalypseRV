extends Monster
class_name SlenderSpeaker
## Visual-only giant. Inherited Raker combat/boarding code is never processed.
enum Phase { PATROL, CONFIRM, CHASE, SEARCH, SMASH, GRAB, LIFT, HOLD, CRUSH, RECOVER, STAGGER }
const ArmIK := preload("res://enemies/slender_speaker/slender_speaker_arm_ik.gd")
const VehicleFollow := preload("res://enemies/slender_speaker/slender_speaker_vehicle_follow.gd")
const ParkedAttack := preload("res://enemies/slender_speaker/slender_speaker_parked_attack.gd")
const Encounter := preload("res://enemies/slender_speaker/slender_speaker_encounter.gd")
const HeadLook := preload("res://enemies/slender_speaker/slender_speaker_look.gd")
const FootContact := preload("res://enemies/slender_speaker/slender_speaker_foot_contact.gd")
@export var settings: SlenderSpeakerSettings = SlenderSpeakerSettings.new()
var _encounter := Encounter.new()
var _observation: Dictionary = {}
var _encounter_decision: Dictionary = {}
var _action_context: Dictionary = {}
var _decision_generation := -1
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
var _patrol_obstacle: Dictionary = {}
var _patrol_route: Dictionary = {}
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
var _smash_cleared_rids: Array[RID] = []
var _smash_damaged_item_rids: Array[RID] = []
var _smash_cleared_items: Array[String] = []
var _grab_contact := Vector3.ZERO
var _grab_hand_contact := Vector3.ZERO
var _grab_tracking_origin := Vector3.ZERO
var _grab_authored_contact := Vector3.ZERO
var _grab_end_wrists: Dictionary = {}
var _grab_lift_wrists: Dictionary = {}
var _execution_socket_offset := Vector3.ZERO
var _execution_capture_position := Vector3.ZERO
var _grab_correction := Vector3.ZERO
var _grab_locked := false
var _previous_hands: Dictionary = {}
var _grab_safe_hands: Dictionary = {}
var _grab_capture_sweep: Dictionary = {}
var _previous_palms: Dictionary = {}
var _grab_cleared_rids: Array[RID] = []
var _grab_cleared_obstacles: Array[Dictionary] = []
var _grab_touched := false
var _grab_hands_touched: Dictionary = {}
var _grab_blocked_bones: Dictionary = {}
var _grab_last_fraction := INF
var _grab_capture_pose: Array[Transform3D] = []
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
var _parked_attack := ParkedAttack.new()
var _parked_plan: Dictionary = {}
var _parked_approach_memory: Dictionary = {}
var _parked_approach_remaining := 0.0
var _parked_facing_waypoint := Vector3.INF
var _parked_move_goal := Vector3.INF
var _parked_progress_goal := Vector3.INF
var _parked_progress_distance := INF
var _parked_progress_angle := INF
var _parked_stall_seconds := 0.0
var _parked_recovery_point := Vector3.INF
var _parked_recovery_seconds := 0.0
var _parked_recovery_context: Dictionary = {}
var _parked_recoveries := 0
var _head_look := HeadLook.new()
var _foot_contact := FootContact.new()
var _body_turn_rate := 0.0
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
	_foot_contact.reset()
	_encounter.reset()
	_encounter_decision.clear()
	_observation.clear()
	_action_context.clear()
	_decision_generation = -1
	target_player = null
	target_vehicle = null
	_parked_attack.reset()
	_vehicle_follow.reset()
	_follow_plan.clear()
	_sense_remaining = 0.0
	_parked_plan.clear()
	_parked_approach_memory.clear()
	_parked_approach_remaining = 0.0
	_patrol_obstacle.clear()
	_patrol_route = {}
	_parked_facing_waypoint = Vector3.INF
	_parked_recovery_point = Vector3.INF
	_parked_recovery_seconds = 0.0
	_parked_recovery_context.clear()
	_reset_parked_progress()
	_head_look.reset()
	_body_turn_rate = 0.0
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
	var starting_yaw := rotation.y
	_parked_move_goal = Vector3.INF
	phase_elapsed += delta
	_parked_approach_remaining = maxf(0.0, _parked_approach_remaining - delta)
	_stagger_cooldown = maxf(0.0, _stagger_cooldown - delta)
	_sense_remaining -= delta
	if _sense_remaining <= 0.0:
		_refresh_sight()
		_sense_remaining = 0.1
	_update_encounter(delta)
	_update_music(delta)
	var desired := Vector3.ZERO
	match phase:
		Phase.PATROL:
			if _encounter_decision.get("intent") == "search": _set_phase(Phase.SEARCH)
			elif _visible_target: _set_phase(Phase.CONFIRM)
			else:
				var angle := float(_patrol_index) * 2.399963
				var point := home_position + Vector3(cos(angle), 0, sin(angle)) * 22.0
				if global_position.slide(Vector3.UP).distance_to(point.slide(Vector3.UP)) < 2.0: _patrol_index += 1
				desired = _navigate_around_vehicles(point, settings.patrol_speed, delta)
		Phase.CONFIRM:
			if not _visible_target: _set_phase(Phase.SEARCH if _encounter_decision.get("intent") == "search" else Phase.PATROL)
			elif phase_elapsed >= settings.confirm_time: _set_phase(Phase.CHASE)
		Phase.CHASE:
			desired = _chase_encounter(delta)
		Phase.SEARCH:
			if _encounter_decision.get("intent", "none") == "none": _set_phase(Phase.PATROL)
			elif _encounter_decision.get("intent") != "search": _set_phase(Phase.CHASE)
			else: desired = _search_encounter(delta)
		Phase.SMASH:
			if _moving_smash and _vehicle_is_observed(target_vehicle): desired = _follow_vehicle(delta)
		Phase.GRAB: _advance_grab(delta)
		Phase.LIFT, Phase.HOLD, Phase.CRUSH: _advance_execution()
		Phase.RECOVER:
			if _moving_smash and _recovery_source == Phase.SMASH and _vehicle_is_observed(target_vehicle): desired = _follow_vehicle(delta)
		Phase.STAGGER:
			if phase_elapsed >= settings.stagger_seconds: _set_phase(Phase.CHASE if _visible_target else Phase.SEARCH)
	_body_turn_rate = angle_difference(starting_yaw, rotation.y) / maxf(delta, .000001)
	if phase in [Phase.PATROL, Phase.CHASE, Phase.SEARCH]:
		var speed := velocity.slide(Vector3.UP).length()
		_animate_locomotion(delta, speed)
	_move_swept(desired, delta)
	_update_parked_progress(delta)
	# Sample after world movement so a moving fist sweeps its complete path,
	# including this tick's translation, against the locked world impact point.
	if phase == Phase.SMASH: _advance_smash(delta)
	elif phase == Phase.RECOVER:
		_advance_recovery(delta)
		if phase_elapsed >= settings.smash_recovery: _set_phase(Phase.CHASE if _visible_target else Phase.SEARCH)
	_update_head_look(delta)
	_foot_contact.update(self, delta)
	_update_audio_positions()

func _chase_encounter(delta: float) -> Vector3:
	var intent: String = _encounter_decision.get("intent", "none")
	if intent == "none":
		_set_phase(Phase.PATROL)
		return Vector3.ZERO
	if intent == "search":
		_set_phase(Phase.SEARCH)
		return _search_encounter(delta)
	if intent == "vehicle_assault":
		var motion := _follow_vehicle(delta)
		if _follow_plan.get("status") == "ready" and _facing_dot(_follow_plan.surface_point) > .85:
			_begin_smash("vehicle_assault")
		return motion
	if intent == "cabin":
		if _parked_recovery_point != Vector3.INF:
			_parked_recovery_seconds -= delta
			if global_position.slide(Vector3.UP).distance_to(_parked_recovery_point.slide(Vector3.UP)) > .3 and _parked_recovery_seconds > 0.0:
				return _navigate(_parked_recovery_point, 1.5, delta, .2)
			_parked_recovery_point = Vector3.INF
			_parked_recovery_context.clear()
		if not _vehicle_is_observed(target_vehicle): return _search_encounter(delta)
		var occupant: Node3D = target_player if _encounter_decision.get("player_visible", false) and can_see_player(target_player) else null
		# Losing current sight cannot turn a known survivor into an unknown
		# cabin/roof search during the sensory cache's remaining fraction.
		if is_instance_valid(target_player) and occupant == null: return _search_encounter(delta)
		_parked_plan = _parked_attack.update(self, target_vehicle, delta, occupant)
		if _parked_plan.get("status") in ["approach", "ready"]:
			_remember_cabin_plan()
			return _follow_parked_vehicle(delta)
		# A missing route, no visible occupant, or no selected roof is not
		# permission to damage a different part of the vehicle.
		return _follow_vehicle(delta) if _vehicle_is_observed(target_vehicle) else Vector3.ZERO
	if intent == "ground" and is_instance_valid(target_player) and can_see_player(target_player):
		var point := _player_contact(target_player)
		var gap := global_position.slide(Vector3.UP).distance_to(point.slide(Vector3.UP))
		var facing := _facing_dot(point)
		if gap <= 2.7 and facing > .985 and _player_can_be_executed():
			_begin_grab()
			return Vector3.ZERO
		if gap <= 3.0 and facing <= .985:
			var direction := (point - global_position).slide(Vector3.UP).normalized()
			rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), deg_to_rad(settings.near_turn_degrees) * delta)
			return Vector3.ZERO
		return _navigate_visible_player(point, delta)
	return _search_encounter(delta)

func _remember_cabin_plan() -> void:
	var occupant: Node3D = _parked_plan.occupant
	_parked_approach_memory = {
		"navigation_point": _parked_plan.navigation_point,
		"surface_point": _parked_plan.surface_point,
		"facing_point": _parked_plan.get("facing_point", _parked_plan.surface_point),
		"standoff_point": _parked_plan.standoff_point,
		"route_frame": _parked_plan.route_frame,
		"route_shell": _parked_plan.route_shell,
		"body_margin": _parked_plan.get("body_margin", VehicleFollow.BODY_MARGIN),
		"arrival_radius": _parked_plan.get("arrival_radius", .015),
		"release_radius": _parked_plan.get("release_radius", .045),
		"arrival_longitudinal": _parked_plan.get("arrival_longitudinal", .015),
		"release_longitudinal": _parked_plan.get("release_longitudinal", .045),
		"vehicle_id": target_vehicle.get_instance_id(),
		"occupant_id": occupant.get_instance_id() if is_instance_valid(occupant) else 0,
		"smash": is_instance_valid(_parked_plan.get("roof")),
	}
	if _parked_plan.get("turn_in_place", false):
		# Record the observed place where this reachable survivor or roof
		# prompted a turn, rather than the RV's drifting waypoint.
		# Brief cone loss may complete that turn at this fixed point;
		# memory still cannot authorize any attack or read live targets.
		_parked_approach_memory.navigation_point = global_position
		_parked_approach_memory.standoff_point = global_position
		_parked_approach_memory.turn_in_place = true
	_parked_approach_remaining = settings.search_seconds

func _search_encounter(delta: float) -> Vector3:
	# Search can clear an actually visible roof above the last observed cabin
	# point. This never authorizes a blind grab or a vehicle/chassis assault.
	_parked_plan.clear()
	if _parked_recovery_point != Vector3.INF:
		_parked_recovery_seconds -= delta
		if global_position.slide(Vector3.UP).distance_to(_parked_recovery_point.slide(Vector3.UP)) > .3 and _parked_recovery_seconds > 0.0:
			return _navigate(_parked_recovery_point, 1.5, delta, .2)
		_parked_recovery_point = Vector3.INF
		_parked_recovery_context.clear()
	if _encounter_decision.get("roof_inspection", false) and _vehicle_is_observed(target_vehicle):
		var inspection := _parked_attack.update(self, target_vehicle, delta, null, _encounter_decision.get("search_point", _encounter_decision.point))
		if inspection.get("status") in ["approach", "ready"] and is_instance_valid(inspection.get("roof")):
			_parked_plan = inspection
			_remember_cabin_plan()
			return _follow_parked_vehicle(delta)
	if not _parked_approach_memory.is_empty() and _parked_approach_remaining > 0.0:
		if _vehicle_is_observed(target_vehicle) and _parked_approach_memory.has("route_frame"):
			var old_frame: Transform3D = _parked_approach_memory.route_frame
			var right := target_vehicle.global_basis.x.slide(Vector3.UP).normalized()
			var frame := Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)), target_vehicle.global_position)
			for key in ["surface_point", "facing_point", "navigation_point", "standoff_point"]:
				if _parked_approach_memory.get("turn_in_place", false) and key in ["navigation_point", "standoff_point"]: continue
				_parked_approach_memory[key] = frame * (old_frame.affine_inverse() * Vector3(_parked_approach_memory[key]))
			_parked_approach_memory.route_frame = frame
		return _follow_parked_approach(_parked_approach_memory, delta)
	if _vehicle_is_observed(target_vehicle): return _follow_vehicle(delta)
	if global_position.slide(Vector3.UP).distance_to(last_seen_position.slide(Vector3.UP)) < 3.0:
		var turn_speed := settings.fast_turn_degrees if velocity.slide(Vector3.UP).length() > 7.0 else settings.near_turn_degrees
		rotation.y += deg_to_rad(turn_speed) * delta * _scan_direction
		return Vector3.ZERO
	return _navigate_visible_player(last_seen_position, delta)

func _update_head_look(delta: float) -> void:
	var point := Vector3.INF
	if phase in [Phase.CONFIRM, Phase.CHASE, Phase.SEARCH]:
		if is_instance_valid(target_player) and can_see_player(target_player):
			point = _player_contact(target_player)
		elif not _parked_approach_memory.is_empty() and _parked_approach_remaining > 0.0:
			point = _parked_approach_memory.surface_point
		elif _visible_target or phase == Phase.SEARCH:
			point = last_seen_position
	_head_look.update(self, point, delta)

func _set_phase(next: Phase) -> void:
	if next != Phase.PATROL:
		_patrol_obstacle.clear()
		_patrol_route.clear()
	if next in [Phase.PATROL, Phase.CONFIRM, Phase.CHASE, Phase.SEARCH, Phase.STAGGER]:
		_action_context.clear()
	if next not in [Phase.CHASE, Phase.SEARCH, Phase.STAGGER]:
		_parked_recovery_point = Vector3.INF
		_parked_recovery_context.clear()
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
			_adapt_smash_crouch(wrist + correction, correction.y)
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
	var transition_seconds := settings.smash_recovery if _recovery_source == Phase.SMASH and not _strike_obstruction_pose.is_empty() and not _is_smash_vehicle_contact(_strike_contact_collider) else .22
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
	var clip := "run" if speed >= 8.0 or (_locomotion_clip == "run" and speed > 6.0) else "walk" if speed > .035 else "scan" if phase == Phase.SEARCH else "idle_play"
	if speed < .8 and absf(_body_turn_rate) > deg_to_rad(5.0):
		clip = "turn_left" if _body_turn_rate > 0.0 else "turn_right"
	if clip != _locomotion_clip or _animation_clip != clip:
		_locomotion_transition_pose = _capture_pose()
		_locomotion_transition_elapsed = 0.0
		_locomotion_transitions += 1
		_locomotion_clip = clip
	_locomotion_transition_elapsed += delta
	if clip in ["walk", "run"]:
		_sample_gait(delta, speed)
	elif clip in ["turn_left", "turn_right"]:
		_animation_time += delta * clampf(absf(_body_turn_rate) / deg_to_rad(60.0), .25, 1.5)
		_sample(clip, fmod(_animation_time, _duration(clip)))
	else:
		_animation_time += delta
		_sample(clip, fmod(_animation_time, _duration(clip)))
	_blend_from_pose(_locomotion_transition_pose, smoothstep(0.0, .22, _locomotion_transition_elapsed))

func _sample_gait(delta: float, speed: float) -> void:
	# Both clips share a continuous foot phase. Blend their authored stride
	# distances as well as their poses so crossing 8 m/s cannot drop cadence.
	_gait_blend = move_toward(_gait_blend, smoothstep(4.0, 12.0, speed), delta * 4.0)
	var stride := lerpf(_duration("walk") * 4.0, _duration("run") * 10.0, _gait_blend)
	var gait_direction := -1.0 if velocity.slide(Vector3.UP).dot(-global_basis.z) < -.1 else 1.0
	_gait_phase = fposmod(_gait_phase + gait_direction * delta * speed / maxf(.001, stride), 1.0)
	_sample("walk", _gait_phase * _duration("walk"))
	if _gait_blend > .0001:
		var walking := _capture_pose()
		_sample("run", _gait_phase * _duration("run"))
		_blend_from_pose(walking, _gait_blend)
	_animation_clip = _locomotion_clip

func _player_can_be_executed() -> bool:
	return is_instance_valid(target_player) and WorldEntities.same_world(self, target_player) and target_player.has_method("can_be_executed") and target_player.can_be_executed()

func _target_point() -> Vector3:
	if is_instance_valid(target_player) and can_see_player(target_player): return _player_contact(target_player)
	return _encounter_decision.get("point", last_seen_position)

func _player_contact(player: Node3D) -> Vector3:
	return player.execution_contact_position() if player.has_method("execution_contact_position") else player.global_position + Vector3.UP

func _facing_dot(point: Vector3) -> float:
	var direction := (point - global_position).slide(Vector3.UP).normalized()
	return (-global_basis.z).dot(direction)

func _refresh_sight() -> void:
	var best := INF
	var seen_player: Node3D
	var seen_vehicle: Node3D
	var player_vehicle: Node3D
	var player_point := Vector3.ZERO
	var vehicle_point := Vector3.INF
	var preferred: Node3D = _encounter_decision.get("player")
	for candidate in get_tree().get_nodes_in_group(Groups.PLAYER):
		if not candidate is Node3D or not WorldEntities.same_world(self, candidate) or candidate.get("is_player_dead") == true: continue
		if not can_see_player(candidate): continue
		var point := _player_contact(candidate)
		var distance := global_position.distance_to(point)
		if candidate == preferred:
			seen_player = candidate
			player_point = point
			break
		if distance < best:
			seen_player = candidate
			player_point = point
			best = distance
	if seen_player != null:
		player_vehicle = _parked_attack.vehicle_for_visible_player(self, seen_player)
		seen_vehicle = player_vehicle
		if seen_vehicle != null: vehicle_point = _visible_vehicle_point(seen_vehicle)
	# Seeing a different survivor must not hide the RV already being pursued.
	# Player association and independently observed vehicle are separate facts.
	if seen_vehicle == null or vehicle_point == Vector3.INF or (is_instance_valid(preferred) and seen_player != preferred):
		best = INF
		var preferred_vehicle: Node3D = _encounter_decision.get("vehicle")
		for candidate in get_tree().get_nodes_in_group(Groups.RV):
			if not candidate is Node3D or not WorldEntities.same_world(self, candidate): continue
			var point := _visible_vehicle_point(candidate)
			if point == Vector3.INF: continue
			if candidate == preferred_vehicle:
				seen_vehicle = candidate
				vehicle_point = point
				break
			var distance := global_position.distance_to(point)
			if distance < best:
				seen_vehicle = candidate
				vehicle_point = point
				best = distance
	var vehicle_visible := is_instance_valid(seen_vehicle) and vehicle_point != Vector3.INF
	_observation = {"player": seen_player, "player_vehicle": player_vehicle, "vehicle": seen_vehicle,
		"sample_time": float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second),
		"player_point": player_point, "vehicle_point": vehicle_point,
		"vehicle_visible": vehicle_visible,
		"roof_visible": _visible_roof(seen_vehicle) if vehicle_visible else false,
		"vehicle_frame": seen_vehicle.global_transform if vehicle_visible else Transform3D.IDENTITY,
		"road_speed": float(seen_vehicle.road_speed()) if vehicle_visible and seen_vehicle.has_method("road_speed") else 0.0}
	if seen_player is CharacterBody3D and vehicle_visible and player_vehicle == seen_vehicle:
		# Sample motion only with actual survivor sight. Player.velocity holds
		# locomotion relative to its carrier; platform transport is separate.
		var motion: Vector3 = Vector3.ZERO if is_instance_valid(seen_player.get("seated_in")) else seen_player.velocity
		_observation.player_motion_local = seen_vehicle.global_basis.inverse() * motion

func _vehicle_is_observed(vehicle: Node3D) -> bool:
	return is_instance_valid(vehicle) and _observation.get("vehicle") == vehicle and _observation.get("vehicle_visible", false)

func _update_encounter(delta: float) -> void:
	var previous := _encounter_decision
	var locked := not _action_context.is_empty()
	_encounter_decision = _encounter.update(_observation, delta, settings, locked)
	var context := _action_context if locked else _encounter_decision
	for key in ["player", "vehicle"]:
		var body: Node3D = context.get(key) if is_instance_valid(context.get(key)) else null
		if body != null and (not body.is_inside_tree() or not WorldEntities.same_world(self, body)):
			reset_after_restore()
			return
	if not locked and _decision_generation != int(_encounter_decision.get("generation", 0)):
		_decision_generation = int(_encounter_decision.get("generation", 0))
		var changed_route: bool = previous.get("mode") != _encounter_decision.get("mode") or previous.get("vehicle") != _encounter_decision.get("vehicle")
		var changed_survivor: bool = is_instance_valid(previous.get("player")) and previous.get("player") != _encounter_decision.get("player")
		# Revealing the same RV's survivor must retain the reached side/stance.
		# Coverage/contact geometry decides whether that roof plan is obsolete.
		if changed_route or changed_survivor:
			_parked_attack.reset()
			_parked_plan.clear()
			_follow_plan.clear()
			_parked_approach_memory.clear()
			_parked_approach_remaining = 0.0
			_parked_facing_waypoint = Vector3.INF
			_parked_recovery_point = Vector3.INF
			_parked_recovery_context.clear()
			_reset_parked_progress()
	target_player = context.get("player") if is_instance_valid(context.get("player")) else null
	target_vehicle = context.get("vehicle") if is_instance_valid(context.get("vehicle")) else null
	_visible_target = bool(_encounter_decision.get("player_visible", false)) or bool(_encounter_decision.get("vehicle_visible", false))
	if _encounter_decision.get("intent", "none") == "none": _visible_target = false
	if _encounter_decision.has("point"): last_seen_position = _encounter_decision.point

func _visible_roof(vehicle: Node3D) -> bool:
	var frame := vehicle.global_transform
	for entry in _parked_attack._roof_bounds(vehicle, frame):
		var box: AABB = entry.box
		var point := box.get_center()
		point.y = box.end.y
		if can_see(entry.panel, frame * point): return true
	return false

func encounter_debug_text() -> String:
	var survivor := str(_encounter_decision.get("player")) if is_instance_valid(_encounter_decision.get("player")) else "none"
	var vehicle := str(_encounter_decision.get("vehicle")) if is_instance_valid(_encounter_decision.get("vehicle")) else "none"
	return "Target %s / RV %s\nMode %s | Intent %s | Action %s\n%s" % [survivor, vehicle,
		_encounter_decision.get("mode", "none"), _encounter_decision.get("intent", "none"),
		_action_context.get("kind", "none"), _encounter_decision.get("reason", "no observation")]

func can_see_player(player: Node3D) -> bool:
	if not is_instance_valid(player) or not WorldEntities.same_world(self, player) or player.get("is_player_dead") == true: return false
	# Visible head/shoulders count even when a console hides the chest.
	# Each posed point still needs the actual speaker cone and an unobstructed ray.
	for proxy in _seated_contact_proxies(player):
		if can_see(player, proxy.center): return true
	return false

func can_see(target: Node3D, point: Vector3) -> bool:
	var origin := _focus_position()
	var direction := point - origin
	if direction.length() > settings.sight_range: return false
	var forward := -global_basis.z
	if visual != null and visual.get("available") == true:
		forward = visual.bone_world("socket_focus").basis.y.normalized()
	# Height alone must not take a nearby ground target out of the cone.
	if forward.slide(Vector3.UP).normalized().dot(direction.slide(Vector3.UP).normalized()) < cos(deg_to_rad(settings.sight_half_angle_degrees)): return false
	var query := PhysicsRayQueryParameters3D.create(origin, point, collision_mask, [get_rid()])
	# A turned speaker can overlap a wall beyond the body's capsule. Do not
	# let an origin inside that solid skip it and reveal targets behind it.
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or _belongs_to(hit.collider, target) or (RVConnection.is_rv(target) and RVConnection.resolve(hit.collider) == target)

func _visible_vehicle_point(vehicle: Node3D) -> Vector3:
	# A long vehicle can remain visible ahead while its closest panel is
	# beside or behind the speaker. Test actual surfaces across its shell.
	var origin := _focus_position()
	var point := Vector3.INF
	var distance := INF
	for child in vehicle.find_children("*", "CollisionShape3D", true, false):
		var shape := child as CollisionShape3D
		if shape.disabled or shape.shape == null: continue
		var owner: Node = shape.get_parent()
		while owner != null and not owner is CollisionObject3D: owner = owner.get_parent()
		if owner != vehicle and not owner is RVStructurePanel: continue
		if owner is RVStructurePanel and owner.is_destroyed: continue
		var box: AABB = _vehicle_follow._shape_box(shape.shape)
		var surface: Vector3 = shape.to_global(shape.to_local(origin).clamp(box.position, box.end))
		var gap := origin.distance_squared_to(surface)
		if gap < distance and can_see(vehicle, surface):
			point = surface
			distance = gap
	return point

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
	if not _vehicle_is_observed(target_vehicle) or not WorldEntities.same_world(self, target_vehicle): return Vector3.ZERO
	_follow_plan = _vehicle_follow.update(self, target_vehicle, delta)
	if _follow_plan.is_empty(): return Vector3.ZERO
	var vehicle_speed := ClimbMath.point_velocity(target_vehicle, target_vehicle.global_position).slide(Vector3.UP).length()
	if vehicle_speed <= .25 and global_position.slide(Vector3.UP).distance_to(_follow_plan.standoff_point.slide(Vector3.UP)) <= .15:
		# At a parked vehicle's slot, face the target rather than an arrival
		# point a few centimetres behind us. Otherwise tiny corrections turn
		# the giant away from a visible, reachable vehicle indefinitely.
		if phase == Phase.CHASE:
			var direction: Vector3 = (_follow_plan.surface_point - global_position).slide(Vector3.UP).normalized()
			rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), deg_to_rad(settings.near_turn_degrees) * delta)
		return Vector3.ZERO
	var route_direction: Vector3 = (_follow_plan.navigation_point - global_position).slide(Vector3.UP).normalized()
	var target_direction: Vector3 = (_follow_plan.surface_point - global_position).slide(Vector3.UP).normalized()
	if route_direction.dot(target_direction) < -.5:
		# After sudden braking the slot can be behind us. Back away along the
		# navigation path while watching the RV, instead of turning out of sight.
		return _navigate(_follow_plan.navigation_point, float(_follow_plan.speed), delta, .1, _follow_plan.surface_point)
	return _navigate(_follow_plan.navigation_point, float(_follow_plan.speed), delta, .1)

func _follow_parked_vehicle(delta: float) -> Vector3:
	_follow_plan.clear()
	if _parked_plan.is_empty(): return Vector3.ZERO
	if _parked_plan.action == "grab":
		target_player = _parked_plan.occupant
		_begin_grab()
		return Vector3.ZERO
	if _parked_plan.action == "smash":
		_begin_smash("roof")
		return Vector3.ZERO
	return _follow_parked_approach(_parked_plan, delta)

func _follow_parked_approach(plan: Dictionary, delta: float) -> Vector3:
	if plan.get("rolling_grab", false) or plan.get("turn_in_place", false):
		# Reach is an observed physical envelope while an unbraked RV drifts.
		# Complete body facing before starting a real hand sweep. A turn-only
		# memory contains a fixed observed point and cannot authorize an attack.
		# Do not route its stationary waypoint out of the inflated shell margin.
		var direction := (Vector3(plan.surface_point) - global_position).slide(Vector3.UP).normalized()
		rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), deg_to_rad(settings.near_turn_degrees) * delta)
		return Vector3.ZERO
	var waypoint: Vector3 = plan.navigation_point
	if plan.has("route_frame"):
		# Continue around all observed corners even if the player is occluded
		# from the first corner. Geometry here is a value snapshot, not an RV.
		var frame: Transform3D = plan.route_frame
		var local_actor := (frame.affine_inverse() * global_position).slide(Vector3.UP)
		var local_goal := (frame.affine_inverse() * Vector3(plan.standoff_point)).slide(Vector3.UP)
		waypoint = frame * _parked_attack._route_point(local_actor, local_goal, plan.route_shell)
		waypoint.y = global_position.y
	var gap := global_position.slide(Vector3.UP).distance_to(waypoint.slide(Vector3.UP))
	var arrival := float(plan.get("arrival_radius", .015))
	var release := float(plan.get("release_radius", .045))
	var can_settle := true
	var must_leave_stance := false
	var braking_arrival := arrival
	if plan.has("route_frame") and plan.has("body_margin"):
		var frame: Transform3D = plan.route_frame
		var shell: AABB = plan.route_shell
		var local_actor := frame.affine_inverse() * global_position
		var local_goal := frame.affine_inverse() * waypoint
		var side_clearance := maxf(local_actor.x - shell.end.x, shell.position.x - local_actor.x)
		var longitudinal := absf(local_actor.z - local_goal.z)
		braking_arrival = minf(arrival, float(plan.get("arrival_longitudinal", arrival)))
		can_settle = side_clearance >= ParkedAttack.GRAB_CLEARANCE - .05 and longitudinal <= float(plan.get("arrival_longitudinal", arrival))
		must_leave_stance = longitudinal > float(plan.get("release_longitudinal", release))
	# Only the committed stance owns arrival. The visible contact may move
	# within reach without sending the feet back into navigation every tick.
	if _parked_facing_waypoint != Vector3.INF and (gap > release or _parked_facing_waypoint.distance_to(waypoint) > release or must_leave_stance):
		_parked_facing_waypoint = Vector3.INF
	if gap <= arrival and can_settle: _parked_facing_waypoint = waypoint
	if _parked_facing_waypoint != Vector3.INF:
		var direction: Vector3 = (Vector3(plan.get("facing_point", plan.surface_point)) - global_position).slide(Vector3.UP).normalized()
		rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), deg_to_rad(settings.near_turn_degrees) * delta)
		return Vector3.ZERO
	# Walk toward the next corner/stance with the authored forward gait. Only
	# face the remembered attack point after arriving, instead of crab-walking.
	# Keep a visible step through the last approach, then brake inside the
	# arrival band rather than spending seconds creeping toward it.
	var approach_speed := minf(settings.patrol_speed, maxf(.3, gap * 3.0))
	var stopping_speed := sqrt(2.0 * settings.braking * maxf(0.0, gap - braking_arrival * .8))
	_parked_move_goal = waypoint
	return _navigate(waypoint, minf(approach_speed, stopping_speed), delta, .005)

func _reset_parked_progress() -> void:
	_parked_progress_goal = Vector3.INF
	_parked_progress_distance = INF
	_parked_progress_angle = INF
	_parked_stall_seconds = 0.0

func _update_parked_progress(delta: float) -> void:
	# Turning toward a route is real progress, and waiting in an attack stance
	# is intentional. Only a requested approach with neither gets recovered.
	if phase not in [Phase.CHASE, Phase.SEARCH] or _parked_move_goal == Vector3.INF:
		_reset_parked_progress()
		return
	var direction := (_parked_move_goal - global_position).slide(Vector3.UP)
	var distance := direction.length()
	var angle := absf((-global_basis.z).signed_angle_to(direction.normalized(), Vector3.UP))
	if _parked_progress_goal == Vector3.INF or _parked_progress_goal.distance_to(_parked_move_goal) > .25 \
		or distance < _parked_progress_distance - .04 or angle < _parked_progress_angle - deg_to_rad(5.0):
		_parked_progress_goal = _parked_move_goal
		_parked_progress_distance = distance
		_parked_progress_angle = angle
		_parked_stall_seconds = 0.0
		return
	_parked_stall_seconds += delta
	if _parked_stall_seconds < 1.5: return
	var plan := _parked_plan if not _parked_plan.is_empty() else _parked_approach_memory
	var outward := -global_basis.z
	if plan.has("route_frame"):
		var frame: Transform3D = plan.route_frame
		var local_actor := frame.affine_inverse() * global_position
		outward = frame.basis.x * (1.0 if local_actor.x >= 0.0 else -1.0)
	# A short forward-walk escape uses the last observed geometry. It never
	# teleports, disables collision, or learns a hidden occupant's position.
	var escape := global_position + outward * .9
	if giant_navigation_map.is_valid() and NavigationServer3D.map_get_iteration_id(giant_navigation_map) > 0:
		var reachable := NavigationServer3D.map_get_closest_point(giant_navigation_map, escape)
		if reachable.slide(Vector3.UP).distance_to(escape.slide(Vector3.UP)) <= .5:
			_parked_recovery_point = reachable
			_parked_recovery_seconds = 4.0
			_parked_recovery_context = {
				"vehicle_id": _parked_approach_memory.get("vehicle_id", 0),
				"occupant_id": _parked_approach_memory.get("occupant_id", 0),
			}
	_parked_attack.invalidate_approach()
	_parked_plan.clear()
	_parked_approach_memory.clear()
	_parked_approach_remaining = 0.0
	_parked_facing_waypoint = Vector3.INF
	_parked_recoveries += 1
	_reset_parked_progress()

func _parked_body_margin() -> float:
	if not _parked_plan.is_empty():
		return float(_parked_plan.get("body_margin", 1.1 if _parked_plan.get("roof") == null else VehicleFollow.BODY_MARGIN))
	if not _parked_approach_memory.is_empty() and _parked_approach_remaining > 0.0:
		return float(_parked_approach_memory.get("body_margin", VehicleFollow.BODY_MARGIN))
	return VehicleFollow.BODY_MARGIN

func _attack_surface() -> Vector3:
	if not _action_context.is_empty():
		if _action_context.kind == "roof":
			if _vehicle_is_observed(target_vehicle) and _action_context.has("local_point"):
				return target_vehicle.to_global(_action_context.local_point)
			return _action_context.point
		if _action_context.kind == "vehicle_assault" and _vehicle_is_observed(target_vehicle):
			if not _follow_plan.is_empty(): return _follow_plan.surface_point
			if _action_context.has("local_point"): return target_vehicle.to_global(_action_context.local_point)
		return _action_context.point
	return _strike_point

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

func _navigate_visible_player(point: Vector3, delta: float) -> Vector3:
	return _navigate_around_vehicles(point, 12.0, delta)

func _navigate_around_vehicles(point: Vector3, speed: float, delta: float) -> Vector3:
	# The streamed terrain map does not bake a live RV into its polygons.
	# A walking route through its live shell must go around observed geometry,
	# independently of encounter ownership, including a suppressed parked RV.
	var waypoint := point
	var nearest := INF
	_patrol_route = {}
	for candidate in get_tree().get_nodes_in_group(Groups.RV):
		if not candidate is Node3D or not WorldEntities.same_world(self, candidate): continue
		var geometry := VehicleFollow.new()
		var frame: Transform3D
		var shell: AABB
		var visible := _visible_vehicle_point(candidate) != Vector3.INF
		if visible:
			geometry._refresh_shapes(candidate)
			var right: Vector3 = candidate.global_basis.x.slide(Vector3.UP).normalized()
			if right.length_squared() < .5: continue
			frame = Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)), candidate.global_position)
			shell = geometry._footprint(frame, true)
		elif phase == Phase.PATROL and _patrol_obstacle.get("vehicle_id") == candidate.get_instance_id():
			# Retain observed collision geometry through an exterior corner turn.
			# This cannot reacquire the suppressed RV or read a hidden occupant.
			frame = _patrol_obstacle.frame
			shell = _patrol_obstacle.shell
		else: continue
		if shell.size.x <= 0.0 or shell.size.z <= 0.0: continue
		if visible and phase == Phase.PATROL and _patrol_obstacle.get("vehicle_id") == candidate.get_instance_id():
			# Keep the last observed pose even when the RV has moved clear.
			_patrol_obstacle = {"vehicle_id": candidate.get_instance_id(), "frame": frame, "shell": shell}
		var from := (frame.affine_inverse() * global_position).slide(Vector3.UP)
		var goal := (frame.affine_inverse() * point).slide(Vector3.UP)
		var blocked := shell.grow(ParkedAttack.ROUTE_CLEARANCE)
		blocked.position.y = -1.0
		blocked.size.y = 2.0
		if blocked.has_point(goal):
			# A ground survivor beside the far wall is not an RV occupant.
			# Stop outside the body radius on that survivor's side, so the
			# inflated route goal cannot itself be inside the blocked shell.
			var edge := geometry._nearest_footprint(goal, shell)
			if float(edge.clearance) <= 0.0 and phase != Phase.PATROL: continue
			if phase == Phase.PATROL:
				# Skip a patrol destination occupied by a vehicle; it can never
				# satisfy arrival and must not pin this waypoint forever.
				_patrol_index += 1
				return Vector3.ZERO
			goal = Vector3(edge.point) + (goal - Vector3(edge.point)).normalized() * (ParkedAttack.ROUTE_CLEARANCE + .05)
		if blocked.intersects_segment(from, goal) == null: continue
		var route: Vector3 = frame * _parked_attack._route_point(from, goal, shell)
		var distance := global_position.distance_squared_to(frame.origin)
		if distance < nearest:
			nearest = distance
			waypoint = route
			waypoint.y = global_position.y
			if phase == Phase.PATROL:
				_patrol_obstacle = {"vehicle_id": candidate.get_instance_id(), "frame": frame, "shell": shell}
				_patrol_route = _patrol_obstacle.duplicate(true)
	return _navigate(waypoint, speed, delta, .2 if nearest < INF else 1.5)

func _navigate(point: Vector3, speed: float, delta: float, arrival_distance := 1.5, facing_point := Vector3.INF) -> Vector3:
	if not giant_navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(giant_navigation_map) <= 0 or nav_agent == null: return Vector3.ZERO
	nav_agent.target_desired_distance = arrival_distance
	var refresh_distance := .001 if not _parked_plan.is_empty() or not _parked_approach_memory.is_empty() else 1.0
	if nav_agent.target_position.distance_to(point) > refresh_distance or phase_elapsed < delta * 1.5: nav_agent.target_position = point
	var next := nav_agent.get_next_path_position()
	var direction := (next - global_position).slide(Vector3.UP).normalized()
	if direction.length_squared() < 0.1: return Vector3.ZERO
	var facing_direction := direction if facing_point == Vector3.INF else (facing_point - global_position).slide(Vector3.UP).normalized()
	var desired_angle := atan2(-facing_direction.x, -facing_direction.z)
	var turning := settings.fast_turn_degrees if velocity.slide(Vector3.UP).length() > 7.0 else settings.near_turn_degrees
	var previous_angle := rotation.y
	rotation.y = rotate_toward(rotation.y, desired_angle, deg_to_rad(turning) * delta)
	# Turning demand reduces the target speed even after the body has aligned
	# with a curved path. Tiny steering corrections retain straight-line pace.
	var yaw_rate := absf(rad_to_deg(angle_difference(previous_angle, rotation.y))) / maxf(delta, .000001)
	var turn_weight := smoothstep(5.0, settings.fast_turn_degrees, yaw_rate)
	var corner_speed := minf(speed, settings.chase_speed) * lerpf(1.0, settings.turn_speed_ratio, turn_weight)
	var alignment := maxf(0.0, (-global_basis.z).dot(direction))
	if phase == Phase.CHASE and not _parked_approach_memory.is_empty():
		# Walk a slow forward arc through corners. The former .8 alignment
		# gate stopped a quarter turn for over half a second. Retain the strict
		# alignment only near the centimetre stance, where a wide arc can orbit.
		var waypoint_gap := global_position.slide(Vector3.UP).distance_to(point.slide(Vector3.UP))
		var steering_error := absf(angle_difference(rotation.y, desired_angle))
		if waypoint_gap > .4 and alignment > 0.0:
			alignment = maxf(.25, alignment)
		# A remaining yaw must fit in the remaining distance before advancing
		# past the stance; braking/swept motion still owns actual displacement.
		var turn_radius_speed := waypoint_gap * deg_to_rad(turning) * .5 / maxf(.15, steering_error)
		corner_speed = minf(corner_speed, turn_radius_speed)
	if facing_point != Vector3.INF:
		# Existing moving-vehicle retreat: permit forward/backward motion while
		# watching the vehicle, but suppress a route perpendicular to the body.
		return direction * corner_speed * absf((-global_basis.z).dot(direction))
	return -global_basis.z * corner_speed * alignment

func _move_swept(desired: Vector3, delta: float) -> void:
	var current := velocity.slide(Vector3.UP)
	var target := desired.slide(Vector3.UP).limit_length(settings.chase_speed)
	var rate := settings.braking if target.length_squared() < current.length_squared() else settings.acceleration
	if target.length_squared() < current.length_squared() and is_instance_valid(target_vehicle) and _visible_target and phase in [Phase.CHASE, Phase.SMASH, Phase.RECOVER] and _parked_approach_memory.is_empty():
		rate = minf(rate, VehicleFollow.FOLLOW_BRAKING)
	# Yaw steers locomotion; acceleration/braking controls speed, rather than
	# spending that budget slowly dragging sideways velocity behind the body.
	# An opposite travel request still brakes through zero before reversing.
	var axis := target.normalized() if target.length_squared() > .000001 else -global_basis.z
	var signed_speed := current.length() * (-1.0 if current.dot(axis) < 0.0 else 1.0)
	var next_speed := move_toward(signed_speed, target.length(), rate * delta)
	if signed_speed < 0.0 and target.length_squared() > .000001:
		# Finish braking before the next step accelerates in reverse.
		next_speed = move_toward(signed_speed, 0.0, settings.braking * delta)
	var horizontal := (axis * next_speed).limit_length(settings.chase_speed)
	if _vehicle_is_observed(target_vehicle):
		var body_margin := _parked_body_margin()
		horizontal = _vehicle_follow.constrain_velocity(self, target_vehicle, horizontal, delta, body_margin).limit_length(settings.chase_speed)
	elif _parked_approach_remaining > 0.0 and _parked_approach_memory.has("route_frame"):
		horizontal = _vehicle_follow.constrain_observed_velocity(self, _parked_approach_memory.route_frame, _parked_approach_memory.route_shell, horizontal, delta, _parked_body_margin()).limit_length(settings.chase_speed)
	elif phase == Phase.PATROL and not _patrol_route.is_empty():
		horizontal = _vehicle_follow.constrain_observed_velocity(self, _patrol_route.frame, _patrol_route.shell, horizontal, delta, 1.1).limit_length(settings.chase_speed)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor(): velocity.y -= gravity * delta
	else: velocity.y = minf(velocity.y, 0.0)
	contact_approach_velocity = velocity
	contact_sample_frame = Engine.get_physics_frames()
	# CharacterBody motion uses a continuous shape sweep at the chase speed cap.
	move_and_slide()
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		var rv := RVConnection.resolve(hit.get_collider())
		if rv != null: receive_vehicle_body_contact(rv, hit.get_normal(), hit.get_position())

func _begin_smash(kind := "vehicle_assault") -> void:
	_moving_smash = velocity.slide(Vector3.UP).length() > .25 or (is_instance_valid(target_vehicle) and ClimbMath.point_velocity(target_vehicle, target_vehicle.global_position).slide(Vector3.UP).length() > .25)
	if kind == "roof": _moving_smash = false
	var point: Vector3 = _parked_plan.get("surface_point", _strike_point) if kind == "roof" else _follow_plan.get("surface_point", _vehicle_surface(target_vehicle) if is_instance_valid(target_vehicle) else _strike_point)
	_action_context = {"kind": kind, "player": target_player, "vehicle": target_vehicle, "point": point, "moving": _moving_smash}
	if kind == "roof": _action_context.roof = _parked_plan.get("roof")
	if is_instance_valid(target_vehicle): _action_context.local_point = target_vehicle.to_local(point)
	_smash_entry_pose = _capture_pose()
	_set_phase(Phase.SMASH)
	_strike_locked = false
	_strike_resolved = false
	_strike_obstruction_pose.clear()
	_smash_cleared_rids.clear()
	_smash_damaged_item_rids.clear()
	_smash_cleared_items.clear()
	_strike_contact_collider = null
	_strike_point = _attack_surface()
	_sample("smash", settings.smash_windup)
	_strike_correction = _strike_point - _bone_position("socket_strike_R")
	_sample("smash", 0.0)
	if _moving_smash: _blend_from_pose(_smash_entry_pose, 0.0)
	_previous_hands["strike"] = _bone_position("socket_strike_R")

func _advance_smash(delta: float = 0.0) -> void:
	if not _strike_obstruction_pose.is_empty():
		# Every first collider stops the real hand path, including the chassis.
		# Once touched, the hand rides that physical surface until impact settles.
		# Aim remains fixed before contact; this is not a new target selection.
		if _moving_smash and _is_smash_vehicle_contact(_strike_contact_collider):
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
	if not _strike_locked:
		var observed := _vehicle_is_observed(target_vehicle)
		if observed: _strike_point = _attack_surface()
		if phase_elapsed >= settings.smash_windup - settings.smash_lock_seconds:
			_strike_locked = true
			if _moving_smash and observed:
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
	if reach_weight > 0.0:
		_adapt_smash_crouch(wrist + _strike_correction * reach_weight, _strike_correction.y * reach_weight, reach_weight)
	_correct_hand("R", wrist + _strike_correction * reach_weight - _bone_position("hand.R"))
	var current := _bone_position("socket_strike_R")
	var previous: Vector3 = _previous_hands.get("strike", current)
	var path_hit := _clear_smash_equipment_path(previous, current, 0.34)
	if not path_hit.is_empty():
		var safe := maxf(0.0, float(path_hit.get("safe_fraction", 0.0)) - .002)
		_correct_hand("R", previous.lerp(current, safe) - current)
		_strike_obstruction_pose = _capture_pose()
		_strike_stopped_socket = _bone_position("socket_strike_R")
		_strike_contact_collider = path_hit.get("collider")
		_strike_contact_probe = path_hit.get("point", current) + path_hit.get("normal", Vector3.ZERO) * .338
		if _is_smash_vehicle_contact(_strike_contact_collider):
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
			var hit := _smash_sweep(current, current, 0.34)
			if not hit.is_empty(): resolve_smash_hit(hit.get("collider"))
		_set_phase(Phase.RECOVER)

func _resolve_stopped_smash() -> void:
	if _strike_resolved: return
	if _is_smash_damage_target(_strike_contact_collider):
		var hit := _smash_sweep(_strike_contact_probe, _strike_contact_probe, .34)
		if hit.get("collider") == _strike_contact_collider:
			resolve_smash_hit(_strike_contact_collider)
			return
	_strike_resolved = true

func resolve_smash_hit(collider: Node) -> bool:
	if _strike_resolved: return false
	_strike_resolved = true
	if not _is_smash_damage_target(collider): return false
	if collider is RVStructurePanel:
		var previous_health: float = collider.current_health
		collider.take_damage(settings.smash_wall_damage)
		if collider.current_health < previous_health and _action_context.get("kind") == "roof" \
			and _action_context.get("roof") == collider and _vehicle_is_observed(target_vehicle):
			_encounter.record_roof_damage(target_vehicle, settings)
	elif collider.is_in_group(Groups.PLAYER):
		collider.take_damage(settings.smash_player_damage)
	else:
		if _action_context.get("kind", "vehicle_assault") != "vehicle_assault": return false
		collider.take_damage(settings.smash_chassis_damage)
	attack_landed.emit(collider, "slender_speaker_smash")
	return true

func _is_smash_vehicle_contact(collider: Node) -> bool:
	return is_instance_valid(collider) and (collider is RVStructurePanel or (collider is Chassis and collider == target_vehicle))

func _smash_sweep(from: Vector3, to: Vector3, radius: float) -> Dictionary:
	return _player_contact_sweep(from, to, radius, _smash_cleared_rids)

func _player_contact_sweep(from: Vector3, to: Vector3, radius: float, excluded: Array[RID] = []) -> Dictionary:
	var hit := sweep_hand(from, to, radius, excluded)
	var first: float = float(hit.get("safe_fraction", 0.0)) if not hit.is_empty() else INF
	# Seat mode disables the locomotion capsule. The visible posed survivor
	# still occupies space, ordered against the same shell/furniture/world hit.
	# Body contact has no occupied-seat exception and never reaches through a block.
	for candidate in get_tree().get_nodes_in_group(Groups.PLAYER):
		if not candidate is Node3D or not _is_smash_damage_target(candidate): continue
		if not is_instance_valid(candidate.get("seated_in")): continue
		for proxy in _seated_contact_proxies(candidate):
			var entry := _sphere_entry(from, to, proxy.center, radius + proxy.radius)
			if entry > 1.0 or entry >= first: continue
			first = entry
			var center: Vector3 = from.lerp(to, entry)
			var normal: Vector3 = (center - Vector3(proxy.center)).normalized()
			hit = {"collider": candidate, "safe_fraction": entry,
				"point": center - normal * radius, "normal": normal}
	return hit

func _clear_smash_equipment_path(from: Vector3, to: Vector3, radius: float) -> Dictionary:
	# Damage each contacted item once per swing. Surviving equipment remains
	# solid; destruction opens the same path for this swing to continue.
	# Keep shell/player first-contact ordering and the one-panel strike rule.
	for attempt in 16:
		var hit := _smash_sweep(from, to, radius)
		var item := hit.get("collider") as Item
		if not is_instance_valid(item) or phase != Phase.SMASH: return hit
		# Releasing an occupied seat is owned by the validated player hit or
		# execution transition, not collateral removal during a roof swing.
		if is_instance_valid(item.get("current_driver")): return hit
		var rid := item.get_rid()
		if rid in _smash_damaged_item_rids: return hit
		_smash_damaged_item_rids.append(rid)
		var path := String(item.get_path())
		if not item.damage_from_giant_smash(settings.smash_equipment_damage): return hit
		_smash_cleared_rids.append(item.get_rid())
		_smash_cleared_items.append(path)
	return _smash_sweep(from, to, radius)

func _is_smash_damage_target(collider: Node) -> bool:
	if not is_instance_valid(collider) or not WorldEntities.same_world(self, collider): return false
	if collider.is_in_group(Groups.PLAYER):
		return collider.get("is_player_dead") != true and collider.has_method("take_damage")
	if not _is_smash_vehicle_contact(collider): return false
	if collider is RVStructurePanel: return not collider.is_destroyed
	return true

func _begin_grab() -> void:
	if not is_instance_valid(target_player): return
	_action_context = {"kind": "grab", "player": target_player, "vehicle": target_vehicle, "point": _player_contact(target_player), "moving": false}
	_action_context.climbing = is_instance_valid(target_player.get("active_climb_rv"))
	_action_context.crawling = target_player.has_method("is_crawling") and target_player.is_crawling()
	_set_phase(Phase.GRAB)
	_grab_locked = false
	_grab_touched = false
	_grab_hands_touched.clear()
	_grab_safe_hands.clear()
	_grab_capture_sweep.clear()
	_previous_palms.clear()
	_grab_cleared_rids.clear()
	_grab_cleared_obstacles.clear()
	_grab_blocked_bones.clear()
	_grab_capture_pose.clear()
	_grab_lift_wrists.clear()
	_grab_blocked = false
	_grab_blocking_hits.clear()
	_grab_contact = _player_contact(target_player)
	_grab_tracking_origin = _grab_contact
	_grab_hand_contact = _grab_contact
	if _action_context.crawling:
		_grab_hand_contact.y = maxf(_grab_contact.y, global_position.y + 0.75)
	_sample("grab", settings.grab_windup)
	_grab_authored_contact = _bone_position("socket_grip_R")
	_grab_correction = _grab_hand_contact - _grab_authored_contact
	_grab_end_wrists = {"R": _bone_position("hand.R") + _grab_correction, "L": _bone_position("hand.L") + _grab_correction}
	_sample("grab", 0.0)
	for side in ["R", "L"]:
		for bone in _hand_contact_bones(side): _previous_hands[bone] = _bone_position(bone)
		_previous_palms[side] = _grab_palm_position(side)
		_remember_grab_hand(side)

func _advance_grab(delta: float = 1.0 / 60.0) -> void:
	if phase != Phase.GRAB: return
	if not _player_can_be_executed():
		_set_phase(Phase.RECOVER)
		return
	_pose_grab_reach(delta)
	# Pose both arms first, then test their actual motion. Either hand can
	# acquire the survivor immediately; windup lock only fixes the aim.
	var contacts: Dictionary = {}
	var contact_probes: Dictionary = {}
	_grab_blocked_bones.clear()
	for side in ["R", "L"]:
		_limit_grab_hand_step(side, delta)
		var palm := _grab_palm_position(side)
		var previous_palm: Vector3 = _previous_palms.get(side, palm)
		var palm_hit := _clear_grab_palm_path(previous_palm, palm, .24)
		var palm_blocked := not palm_hit.is_empty() and not _belongs_to(palm_hit.get("collider"), target_player)
		var first_contact := INF
		if not palm_hit.is_empty() and not palm_blocked:
			first_contact = float(palm_hit.get("safe_fraction", 0.0))
			contact_probes[side] = {"from": previous_palm, "to": palm, "radius": .24, "fraction": first_contact, "bone": "palm." + side}
		var proposed: Dictionary = {}
		for bone in _hand_contact_bones(side):
			var current := _bone_position(bone)
			var previous: Vector3 = _previous_hands.get(bone, current)
			proposed[bone] = current
			if _hand_hits_player(previous, current, .13, side, bone) and not palm_blocked:
				# Fingers may brush through a frame, but cannot acquire someone
				# behind an intact surface that still separates them from the palm.
				var contact_point := previous.lerp(current, _grab_last_fraction)
				if not _grab_sweep(palm, contact_point, .04, [target_player.get_rid()]).is_empty(): continue
				if _grab_last_fraction < first_contact:
					contact_probes[side] = {"from": previous, "to": current, "radius": .13, "fraction": _grab_last_fraction, "bone": bone}
				first_contact = minf(first_contact, _grab_last_fraction)
		if first_contact < INF: contacts[side] = first_contact
		elif palm_blocked:
			_grab_blocked_bones[side] = true
			# Keep the last legal sweep origins. Advancing origins into a wall
			# would authorize contact on its far side on the following tick.
			_restore_grab_hand(side)
		else:
			for bone in proposed: _previous_hands[bone] = proposed[bone]
			_previous_palms[side] = palm
			_remember_grab_hand(side)
	# Only palms clear scenery. Fingers independently contribute real contact,
	# without freezing the entire hand because a fingertip brushes a fixture.
	if not contacts.is_empty():
		var side: String = "L" if float(contacts.get("L", INF)) < float(contacts.get("R", INF)) else "R"
		_grab_touched = true
		_grab_hands_touched[side] = true
		_grab_capture_sweep = contact_probes[side]
		_start_execution()
		return
	if phase_elapsed >= settings.grab_windup: _finish_grab()

func _grab_palm_position(side: String) -> Vector3:
	var knuckles := Vector3.ZERO
	for finger in ["index", "middle", "ring", "little"]:
		knuckles += _bone_position("finger_%s_01.%s" % [finger, side])
	return _bone_position("hand." + side).lerp(knuckles / 4.0, .5)

func _clear_grab_palm_path(from: Vector3, to: Vector3, radius: float) -> Dictionary:
	# Resolve actual palm contacts in order, not an area attack. Never clear
	# objects behind a survivor or erase chassis/terrain collision wholesale.
	for attempt in 16:
		var hit := _grab_sweep(from, to, radius)
		if phase != Phase.GRAB: return hit
		if is_instance_valid(target_player) and is_instance_valid(target_player.get("seated_in")):
			var entry := INF
			for proxy in _seated_contact_proxies(): entry = minf(entry, _sphere_entry(from, to, proxy.center, radius + proxy.radius))
			if entry <= 1.0 and entry < float(hit.get("safe_fraction", 0.0) if not hit.is_empty() else INF):
				return {"collider": target_player, "safe_fraction": entry}
		if hit.is_empty(): return hit
		var collider: Node = hit.get("collider")
		if not is_instance_valid(collider) or _belongs_to(collider, target_player): return hit
		var path := String(collider.get_path())
		var cleared := false
		if collider is RVStructurePanel:
			collider.take_damage(collider.current_health)
			cleared = collider.is_destroyed
		# Equipment remains a physical obstacle during a grab. Its direct
		# demolition belongs to a smash, not to a reaching hand.
		if not cleared: return hit
		_grab_cleared_rids.append(collider.get_rid())
		_grab_cleared_obstacles.append({"node": path, "kind": "panel"})
	return _grab_sweep(from, to, radius)

func _remember_grab_hand(side: String) -> void:
	if visual == null or not visual.available: return
	var skeleton: Skeleton3D = visual.skeleton
	var fingers: Dictionary = {}
	for bone in _hand_contact_bones(side):
		if bone == "hand." + side: continue
		var index := skeleton.find_bone(bone)
		fingers[index] = Transform3D(Basis(skeleton.get_bone_pose_rotation(index)), skeleton.get_bone_pose_position(index))
	_grab_safe_hands[side] = {"wrist": visual.bone_world("hand." + side), "fingers": fingers}

func _limit_grab_hand_step(side: String, delta: float) -> void:
	if not _grab_safe_hands.has(side) or visual == null or not visual.available: return
	var saved: Dictionary = _grab_safe_hands[side]
	var previous: Transform3D = saved.wrist
	var desired: Transform3D = visual.bone_world("hand." + side)
	var distance := previous.origin.distance_to(desired.origin)
	var angle := previous.basis.get_rotation_quaternion().angle_to(desired.basis.get_rotation_quaternion())
	var fraction := minf(1.0, minf(18.0 * delta / maxf(distance, .0001), deg_to_rad(600.0) * delta / maxf(angle, .0001)))
	if fraction >= 1.0: return
	# After a brush clears, rejoin the authored pose over real swept steps,
	# not a large chord that skips the intervening hand trajectory.
	var skeleton: Skeleton3D = visual.skeleton
	var wrist := previous.interpolate_with(desired, fraction)
	if not ArmIK.reach(skeleton, side, wrist.origin): return
	ArmIK._set_global(skeleton, skeleton.find_bone("hand." + side), skeleton.global_transform.affine_inverse() * wrist)
	for index in saved.fingers:
		var before: Transform3D = saved.fingers[index]
		skeleton.set_bone_pose_position(index, before.origin.lerp(skeleton.get_bone_pose_position(index), fraction))
		skeleton.set_bone_pose_rotation(index, before.basis.get_rotation_quaternion().slerp(skeleton.get_bone_pose_rotation(index), fraction))
	skeleton.force_update_all_bone_transforms()

func _restore_grab_hand(side: String) -> void:
	if not _grab_safe_hands.has(side) or visual == null or not visual.available: return
	var skeleton: Skeleton3D = visual.skeleton
	var saved: Dictionary = _grab_safe_hands[side]
	var wrist: Transform3D = saved.wrist
	# Reach from the live shoulder, preserving segment lengths. Do not pull
	# the whole torso or the other hand backward when one hand meets a frame.
	if not ArmIK.reach(skeleton, side, wrist.origin): return
	ArmIK._set_global(skeleton, skeleton.find_bone("hand." + side), skeleton.global_transform.affine_inverse() * wrist)
	for index in saved.fingers:
		var pose: Transform3D = saved.fingers[index]
		skeleton.set_bone_pose_position(index, pose.origin)
		skeleton.set_bone_pose_rotation(index, pose.basis.get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

func _pose_grab_reach(delta: float = 1.0 / 60.0) -> void:
	# This samples the shared indoor/outdoor reach without ownership side effects.
	if not _grab_locked:
		# Track only genuinely visible movement, with a finite reach adjustment.
		# A fleeing or occluded survivor must be able to evade the committed grab.
		if phase_elapsed < settings.grab_windup - 0.25 and can_see_player(target_player):
			_action_context.climbing = is_instance_valid(target_player.get("active_climb_rv"))
			_action_context.crawling = target_player.has_method("is_crawling") and target_player.is_crawling()
			var observed := _player_contact(target_player)
			_grab_contact = _grab_tracking_origin + (observed - _grab_tracking_origin).limit_length(.75)
			_grab_hand_contact = _grab_contact
			if _action_context.crawling:
				_grab_hand_contact.y = maxf(_grab_contact.y, global_position.y + 0.75)
			var corrected := _grab_correction.move_toward(_grab_hand_contact - _grab_authored_contact, 2.0 * maxf(delta, 0.0))
			for side in _grab_end_wrists: _grab_end_wrists[side] += corrected - _grab_correction
			_grab_correction = corrected
		if phase_elapsed >= settings.grab_windup - 0.25:
			_grab_locked = true
	_sample("grab", minf(phase_elapsed, settings.grab_windup))
	var weight := smoothstep(0.0, settings.grab_windup, phase_elapsed)
	var horizontal_weight := smoothstep(0.0, settings.grab_windup * .8, phase_elapsed)
	# Reach the target's height before the shared downward close. This applies
	# equally to an elevated outdoor survivor and a seated one; no wrist turn
	# or obstacle-dependent detour changes the authored palm/finger motion.
	var height_weight := smoothstep(0.0, settings.grab_windup * .25, phase_elapsed) if _grab_correction.y > 0.0 else weight
	var wrists := {"R": _bone_position("hand.R"), "L": _bone_position("hand.L")}
	var desired_wrists: Dictionary = {}
	for side in ["R", "L"]:
		var desired: Vector3 = wrists[side] + _grab_correction * weight
		desired += (_grab_correction * (horizontal_weight - weight)).slide(Vector3.UP)
		desired.y += _grab_correction.y * (height_weight - weight)
		var forward := -global_basis.z
		var end_distance: float = (_grab_end_wrists[side] - global_position).dot(forward)
		var outside_distance := lerpf(0.34, -0.05, smoothstep(0.0, settings.grab_windup * 0.3, phase_elapsed))
		var reach_distance := lerpf(outside_distance, end_distance, smoothstep(settings.grab_windup * 0.85, settings.grab_windup, phase_elapsed))
		if _action_context.get("climbing", false):
			desired += forward * (reach_distance - (desired - global_position).dot(forward))
		desired.y += minf(0.8, absf(_grab_correction.y) * 0.5) * pow(sin(PI * clampf(phase_elapsed / settings.grab_windup, 0.0, 1.0)), 2.0)
		if _action_context.get("crawling", false):
			var lowest: float = wrists[side].y
			for bone in _hand_contact_bones(side): lowest = minf(lowest, _bone_position(bone).y)
			desired.y += maxf(0.0, global_position.y + .14 - (desired.y + lowest - wrists[side].y))
		desired_wrists[side] = desired
	_adapt_grab_crouch(desired_wrists, _grab_correction.y * weight)
	for side in ["R", "L"]:
		var desired: Vector3 = desired_wrists[side]
		_correct_hand(side, desired - _bone_position("hand." + side))

func _finish_grab() -> void:
	# No remembered contact or target proximity may turn a missed reach into a grab.
	if not _grab_blocked_bones.is_empty() and not _parked_approach_memory.is_empty():
		# A blocked attempt must not loop the identical stance/hand path forever.
		# Replan only after recovery and a fresh observation of the occupant.
		_parked_attack.invalidate_approach()
		_parked_plan.clear()
		_parked_approach_memory.clear()
		_parked_approach_remaining = 0.0
		_parked_facing_waypoint = Vector3.INF
	_set_phase(Phase.RECOVER)

func _hand_contact_bones(side: String) -> Array[String]:
	var result: Array[String] = ["hand." + side]
	for finger in ["index", "middle", "ring", "little", "thumb"]:
		for section in [1, 2, 3]: result.append("finger_%s_%02d.%s" % [finger, section, side])
	return result

func _hand_currently_touches_player(side: String) -> bool:
	# Earlier contact during the locked reach cannot capture an evading player.
	# Check both final hands again at the exact ownership transition.
	for bone in _hand_contact_bones(side):
		var point := _bone_position(bone)
		var hit := _grab_sweep(point, point, .13)
		if not hit.is_empty() and _belongs_to(hit.get("collider"), target_player): return true
		if is_instance_valid(target_player.get("seated_in")) and _seated_point_touches_player(point, .13):
			# Seated torso shape is disabled; the same actual posed proxy used by
			# the approach sweep supplies its contact volume. Shell clearance is
			# still independently required before acquiring ownership.
			return true
	return false

func _grab_sweep(from: Vector3, to: Vector3, radius: float, extra_exclude: Array[RID] = []) -> Dictionary:
	# The occupied seat assembly may overlap the hands during this grab.
	# Ignore that body and already cleared objects while deferred frees settle.
	var excluded := extra_exclude.duplicate()
	excluded.append_array(_grab_cleared_rids)
	var seat: Node = target_player.get("seated_in") if is_instance_valid(target_player) else null
	if seat is CollisionObject3D: excluded.append(seat.get_rid())
	return sweep_hand(from, to, radius, excluded)

func _hand_hits_player(from: Vector3, to: Vector3, radius: float, side := "", bone := "") -> bool:
	var hit := _grab_sweep(from, to, radius)
	_grab_last_fraction = float(hit.get("safe_fraction", 0.0)) if not hit.is_empty() else INF
	# A seated body has no active physics RID shape. Put its posed torso proxy
	# into the same first-contact ordering, rather than checking it only after
	# the inactive player capsule. The nearer shell still wins this comparison.
	if is_instance_valid(target_player.get("seated_in")):
		var entry := INF
		for proxy in _seated_contact_proxies(): entry = minf(entry, _sphere_entry(from, to, proxy.center, radius + proxy.radius))
		var blocking: float = float(hit.get("safe_fraction", 0.0)) if not hit.is_empty() else INF
		if entry <= 1.0 and entry < blocking:
			_grab_last_fraction = entry
			return true
	if not hit.is_empty():
		if _belongs_to(hit.get("collider"), target_player): return true
		_grab_blocked = true
		if _grab_blocking_hits.size() < 6:
			_grab_blocking_hits.append({"time": phase_elapsed, "node": String(hit.collider.get_path()) if hit.get("collider") != null else "", "bone": bone, "from": from, "to": to})
		return false
	return false

func _seated_contact_proxies(player: Node3D = null) -> Array[Dictionary]:
	if not is_instance_valid(player): player = target_player
	if not is_instance_valid(player): return []
	var result: Array[Dictionary] = [{"center": _player_contact(player), "radius": .22}]
	var model := player.get_node_or_null("Visuals")
	if model == null or not model.has_method("bite_contact"): return result
	var body: RefCounted = player.get("body_state")
	for part in [&"head", &"left_arm", &"right_arm"]:
		if body != null and not body.has_part(part): continue
		var pose: Transform3D = model.bite_contact(part)
		result.append({"center": pose.origin, "radius": .14 if part == &"head" else .12})
	return result

func _seated_point_touches_player(point: Vector3, radius: float) -> bool:
	for proxy in _seated_contact_proxies():
		if point.distance_to(proxy.center) <= radius + proxy.radius: return true
	return false

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
	_execution_capture_position = execution_anchor.global_position
	_execution_socket_offset = execution_anchor.global_position - _bone_position("socket_grip_R")
	execution_focus.global_position = _focus_position()
	if not target_player.begin_execution(self, execution_anchor, execution_focus):
		_set_phase(Phase.RECOVER)
		return false
	_execution_player = target_player
	_execution_resolved = false
	# Carry the actual reached wrists into the shared authored lift.
	_grab_capture_pose = _capture_pose()
	var capture_wrists := {"R": _bone_position("hand.R"), "L": _bone_position("hand.L")}
	_sample("lift", 0.0)
	var lift_wrists := {"R": _bone_position("hand.R"), "L": _bone_position("hand.L")}
	for side in ["R", "L"]: _grab_lift_wrists[side] = capture_wrists[side] - lift_wrists[side] - _grab_correction
	_blend_from_pose(_grab_capture_pose, 0.0)
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
	if phase == Phase.LIFT:
		var lift_weight := 1.0 - smoothstep(0.0, settings.lift_seconds, phase_elapsed)
		for side in ["R", "L"]: wrists[side] += _grab_lift_wrists.get(side, Vector3.ZERO) * lift_weight
	_adapt_grab_crouch({"R": wrists["R"] + correction, "L": wrists["L"] + correction}, correction.y)
	for side in ["R", "L"]: _correct_hand(side, wrists[side] + correction - _bone_position("hand." + side))
	if phase == Phase.LIFT:
		_blend_from_pose(_grab_capture_pose, smoothstep(0.0, .22, phase_elapsed))
	# Both cases retain contact at first, then settle onto the torso grip.
	var socket_offset := _execution_socket_offset * (1.0 - smoothstep(.3, settings.lift_seconds, phase_elapsed)) if phase == Phase.LIFT else Vector3.ZERO
	execution_anchor.global_position = _bone_position("socket_grip_R") + socket_offset
	if phase == Phase.LIFT:
		# First lift along the contact column, then return toward the authored
		# raised grip. Its initial lateral wrist swing otherwise pushes a body
		# resting by a console/door into that solid before it leaves the cabin.
		# Translate both wrists with the grip, retaining the common bent pose;
		# the complete player sweep still checks each part of this trajectory.
		var rise := maxf(0.0, execution_anchor.global_position.y - _execution_capture_position.y)
		var horizontal := (_execution_capture_position - execution_anchor.global_position).slide(Vector3.UP) * (1.0 - smoothstep(2.75, 3.75, rise))
		for side in ["R", "L"]: _correct_hand(side, horizontal)
		execution_anchor.global_position += horizontal
		# Blending a stopped hand back into lift can dip the socket a few mm.
		# Start upward from the real capture height, never into the cabin floor;
		# the complete player shape still checks every subsequent motion.
		execution_anchor.global_position.y = maxf(execution_anchor.global_position.y, _execution_capture_position.y)
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
	reset_after_restore()
	if patrol_music != null: patrol_music.stop()
	if execution_music != null: execution_music.stop()

func _focus_position() -> Vector3:
	return _bone_position("socket_focus") if visual != null and visual.get("available") == true else global_position + Vector3.UP * 13.85

func execution_camera_ready() -> bool:
	return phase in [Phase.HOLD, Phase.CRUSH]

func execution_camera_frame(subject: Node3D) -> Dictionary:
	# Follow the survivor's own facing and chest, independently of the giant.
	var chest: Vector3 = subject.execution_contact_position()
	var behind := subject.global_basis.z.slide(Vector3.UP).normalized()
	if behind.length_squared() < .0001: behind = Vector3.BACK
	var side := Vector3.UP.cross(behind).normalized()
	return {"pivot": chest, "focus": chest,
		"offset": behind * 2.2 + side * 1.2 + Vector3.UP * 1.0}

func _bone_position(name: String) -> Vector3:
	return visual.bone_world(name).origin if visual != null and visual.get("available") == true else global_position + Vector3.UP

func _correct_hand(side: String, offset: Vector3) -> void:
	if visual == null or visual.get("available") != true or offset.length_squared() < 0.000001: return
	ArmIK.reach(visual.skeleton, side, _bone_position("hand." + side) + offset)

func _adapt_smash_crouch(world_wrist: Vector3, height_correction: float, weight := 1.0) -> void:
	if visual == null or visual.get("available") != true: return
	# A low deck requires room for both the vertical and horizontal reach.
	# Correcting only the target height can leave IK beyond the arm's length,
	# which legitimately refuses the solve and leaves the fist short of the RV.
	var shoulder := _bone_position("upper_arm.R")
	var elbow := _bone_position("forearm.R")
	var wrist := _bone_position("hand.R")
	var reach := shoulder.distance_to(elbow) + elbow.distance_to(wrist) - .04
	var horizontal := (world_wrist - shoulder).slide(Vector3.UP).length()
	var vertical_room := sqrt(maxf(0.0, reach * reach - horizontal * horizontal))
	var reach_drop := maxf(0.0, shoulder.y - world_wrist.y - vertical_room) * weight
	_adapt_crouch(-maxf(maxf(0.0, -height_correction), reach_drop), 2.5)

func _adapt_grab_crouch(world_wrists: Dictionary, height_correction: float) -> void:
	if visual == null or visual.get("available") != true: return
	var drop := maxf(0.0, -height_correction)
	for side in ["R", "L"]:
		var shoulder := _bone_position("upper_arm." + side)
		var elbow := _bone_position("forearm." + side)
		var wrist := _bone_position("hand." + side)
		var target: Vector3 = world_wrists[side]
		var reach := shoulder.distance_to(elbow) + elbow.distance_to(wrist) - .04
		var horizontal := (target - shoulder).slide(Vector3.UP).length()
		var vertical_room := sqrt(maxf(0.0, reach * reach - horizontal * horizontal))
		drop = maxf(drop, shoulder.y - target.y - vertical_room)
	_adapt_crouch(-drop)

func _adapt_crouch(height_correction: float, maximum_drop := 1.1) -> void:
	if height_correction >= 0.0 or visual == null or visual.get("available") != true: return
	var s: Skeleton3D = visual.skeleton
	var index := s.find_bone("pelvis")
	if index < 0: return
	var feet := {"R": _bone_position("foot.R"), "L": _bone_position("foot.L")}
	var pelvis := s.get_bone_global_pose(index)
	pelvis.origin += s.global_basis.inverse() * Vector3.UP * maxf(-maximum_drop, height_correction)
	ArmIK._set_global(s, index, pelvis)
	for side in ["R", "L"]: ArmIK.reach(s, side, feet[side], true)

func _sample(clip: String, time: float) -> void:
	if visual != null and visual.get("available") == true:
		# IK can adjust joint origins that have rotation-only tracks.
		# Each authored sample starts from rest so that deformation cannot leak
		# into later frames, clips, or another survivor's grab.
		visual.skeleton.reset_bone_poses()
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

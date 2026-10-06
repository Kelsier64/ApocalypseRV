extends Node
## Presentation of controller-relative velocity. No controller root motion.
const CLIPS = preload("res://assets/models/player_animations_v021/player_animations_v021.glb")
const INJURY_CLIPS = preload("res://assets/models/player_dismemberment/player_injury_animations.glb")
const AUTHORED_CLIMB_SPEED := 2.6
const LADDER_TRANSITION_POSE_SPEED := 0.6
static var library: AnimationLibrary
static var injury_library: AnimationLibrary
var actor: CharacterBody3D
var animation: AnimationPlayer
var current_clip := ""
var suspended := false
var air_time := 0.0
var last_vertical_speed := 0.0
var landing_remaining := 0.0
var climb_rv: Node3D
var climb_carrier_basis := Basis.IDENTITY
var climb_local_position := Vector3.ZERO
var climb_normal := Vector3.ZERO
var climb_exit_remaining := 0.0
var landing_animation_started := false
var manual_top_departure := false
var climb_pose_offset := Vector3.ZERO
var climb_pose_target := Vector3.ZERO
var skeleton: Skeleton3D
var root_bone := -1
var applied_root_offset := Vector3.ZERO
var view_camera: Camera3D
var camera_rest_position := Vector3.ZERO
var was_crawling := false
var crawl_eye := Vector3(0, .58, -.48)
var driving := preload("res://player/player_driving_visual.gd").new()

func _ready() -> void:
	process_physics_priority = 1 # Observe Player after movement, before pose modifiers.
	actor = get_parent().get_parent() as CharacterBody3D
	animation = get_parent().model.get_node("AnimationPlayer")
	skeleton = get_parent().skeleton
	root_bone = skeleton.find_bone("root")
	view_camera = actor.get_node("Camera3D")
	camera_rest_position = view_camera.position
	if library == null:
		library = AnimationLibrary.new()
		var source := CLIPS.instantiate()
		var imported: AnimationPlayer = source.get_node("AnimationPlayer")
		for clip in imported.get_animation_list():
			var resource: Animation = imported.get_animation(clip).duplicate()
			resource.loop_mode = Animation.LOOP_NONE if clip.begins_with("jump_") or clip == "climb_exit" else Animation.LOOP_LINEAR
			library.add_animation(clip, resource)
		source.free()
	animation.add_animation_library("locomotion", library)
	if injury_library == null: injury_library = _injury_library()
	animation.add_animation_library("injury", injury_library)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.active = true
	_select("idle")
	animation.advance(0)
	set_physics_process(actor != null)

func _physics_process(delta: float) -> void:
	if actor.is_player_dead:
		suspend()
		return
	var carry := get_parent().get_node("Carry")
	carry.clear_pose()
	if actor.seated_in != null:
		suspend()
		current_clip = "drive"
		view_camera.position = camera_rest_position
		driving.update(actor, skeleton, carry, delta)
		return
	driving.clear(skeleton)
	if actor.is_grabbed():
		suspend()
		return
	if suspended:
		current_clip = ""
		suspended = false
	if actor.is_crawling():
		_update_crawl(delta)
		return
	was_crawling = false
	if actor.locomotion_state == actor.LocomotionState.CLIMBING:
		_update_climb(delta)
		return
	if is_instance_valid(climb_rv) or landing_animation_started or manual_top_departure:
		# The controller confirms the completed landing. Recovery already plays
		# during the bounded step, so completing it must not restart the clip.
		if actor.ladder_landed and not landing_animation_started and not manual_top_departure:
			climb_exit_remaining = animation.get_animation("locomotion/climb_exit").length
			_select("climb_exit", .08)
		elif not actor.ladder_landed or manual_top_departure:
			climb_exit_remaining = 0.0
		landing_animation_started = false
		manual_top_departure = false
		climb_rv = null
	climb_pose_target = Vector3.ZERO
	if climb_exit_remaining > 0.0 and (actor.is_on_floor() or (actor.velocity.y <= 0 and actor.velocity.y > -1.0)):
		if actor.in_ui_mode: return
		climb_exit_remaining = maxf(0.0, climb_exit_remaining - delta)
		_advance(delta, 1.0, delta, LADDER_TRANSITION_POSE_SPEED)
		return
	if not actor.is_on_floor():
		climb_exit_remaining = 0.0
		# The controller freezes airborne motion in UI mode. Manual playback
		# freezes alongside it without consuming the landing transition.
		if actor.in_ui_mode: return
		air_time += delta
		last_vertical_speed = actor.velocity.y
		landing_remaining = 0.0
		_select("jump_rise" if actor.velocity.y > .2 else "jump_fall", .08)
		_advance(delta)
		return
	if air_time > .1 and last_vertical_speed < -1.0:
		landing_remaining = animation.get_animation("locomotion/jump_land").length
		_select("jump_land", .06)
	air_time = 0.0
	last_vertical_speed = 0.0
	if landing_remaining > 0.0:
		landing_remaining = maxf(0.0, landing_remaining - delta)
		_advance(delta)
		return
	var local := actor.global_basis.orthonormalized().inverse() * actor.velocity
	# UI mode returns before controller movement and can retain its last velocity.
	var speed := 0.0 if actor.in_ui_mode else Vector2(local.x, local.z).length()
	var clip := "idle"
	if speed > .12:
		var direction := "forward" if local.z < 0 else "back"
		if absf(local.x) > absf(local.z): direction = "right" if local.x > 0 else "left"
		clip = ("run_" if speed > 6.0 else "jog_") + direction
	_select(clip)
	_advance(delta)

func _update_climb(delta: float) -> void:
	var carrier: Node3D = actor.active_climb_rv
	if not is_instance_valid(carrier): return
	var local_position := carrier.to_local(actor.global_position)
	var relative_velocity := Vector3.ZERO
	if climb_rv == carrier and delta > 0.0:
		relative_velocity = carrier.global_basis * (local_position - climb_local_position) / delta
	# Preserve the existing approach distance during a carrier turn. This
	# rotation follows the RV without pulling the eye closer while input rests.
	if not actor.in_ui_mode:
		var carrier_basis := carrier.global_basis.orthonormalized()
		if climb_rv == carrier:
			climb_pose_offset = carrier_basis * climb_carrier_basis.inverse() * climb_pose_offset
		climb_carrier_basis = carrier_basis
	climb_rv = carrier
	climb_local_position = local_position
	climb_normal = actor.active_wall_normal
	air_time = 0.0
	last_vertical_speed = 0.0
	landing_remaining = 0.0
	if actor.in_ui_mode: return
	var probe: RayCast3D = actor.climb_wall_probe
	if is_instance_valid(actor.active_climb_ladder):
		var ladder: RVLadder = actor.active_climb_ladder
		var distance := (skeleton.global_position - ladder.global_position).dot(ladder.global_basis.z.normalized())
		climb_pose_target = -actor.active_wall_normal * clampf(distance - .365, -.12, .15)
	elif probe.is_colliding():
		var normal: Vector3 = actor.active_wall_normal
		var distance := (skeleton.global_position - probe.get_collision_point()).dot(normal)
		# Pose-space approach only. The original controller can catch the wall
		# from farther away than the authored palms (0.365 m from the root).
		climb_pose_target = -normal * clampf(distance - .365, -.12, .5)
	var transition: int = actor.ladder_transition
	if transition == actor.LadderTransition.ENTRY:
		landing_animation_started = false
		manual_top_departure = false
		climb_exit_remaining = 0.0
		_select("climb_hold", .08)
		var advancing := _transition_input_pressed()
		_advance(delta if advancing else 0.0, 1.0, delta if advancing else 0.0, LADDER_TRANSITION_POSE_SPEED)
		return
	if transition == actor.LadderTransition.TOP:
		landing_animation_started = false
		climb_exit_remaining = 0.0
		if actor.ladder_top_input_ready and relative_velocity.slide(carrier.global_basis.y.normalized()).length() > .08:
			manual_top_departure = true
		if manual_top_departure:
			_update_top_walk(relative_velocity, delta)
		else:
			_select("climb_hold", .08)
			_advance(delta, 1.0, delta, LADDER_TRANSITION_POSE_SPEED)
		return
	if transition == actor.LadderTransition.LANDING:
		climb_pose_target = Vector3.ZERO
		if actor.ladder_landing_at_top:
			# Reaching real support only settles vertically. The authored exit
			# leans forward, so top walking uses ordinary poses throughout.
			manual_top_departure = true
			landing_animation_started = false
			climb_exit_remaining = 0.0
			_update_top_walk(relative_velocity, delta)
			return
		if not landing_animation_started:
			landing_animation_started = true
			climb_exit_remaining = animation.get_animation("locomotion/climb_exit").length
			_select("climb_exit", .08)
		if _transition_input_pressed():
			climb_exit_remaining = maxf(0.0, climb_exit_remaining - delta)
			_advance(delta, 1.0, delta, LADDER_TRANSITION_POSE_SPEED)
		else:
			_advance(0.0, 1.0, 0.0, LADDER_TRANSITION_POSE_SPEED)
		return
	landing_animation_started = false
	manual_top_departure = false
	climb_exit_remaining = 0.0
	var up := carrier.global_basis.y.normalized()
	var tangent := up.cross(actor.active_wall_normal).normalized()
	var vertical := relative_velocity.dot(up)
	var horizontal := relative_velocity.dot(tangent)
	var clip := "climb_hold"
	var rate := 1.0
	if absf(vertical) > .08:
		clip = "climb_up"
		rate = clampf(absf(vertical) / AUTHORED_CLIMB_SPEED, 0.0, 1.5)
	elif absf(horizontal) > .08:
		clip = "climb_right" if horizontal > 0 else "climb_left"
		rate = clampf(absf(horizontal) / actor.CLIMB_SIDE_SPEED, 0.0, 1.5)
	_select(clip, .08)
	# Keep the approach gentle after a short entry too; changing phases must
	# not accelerate a partly completed eye/body blend back to the old rate.
	var pose_speed := LADDER_TRANSITION_POSE_SPEED if is_instance_valid(actor.active_climb_ladder) else 3.0
	_advance(delta * rate, -1.0 if vertical < -.08 else 1.0, delta, pose_speed)

func _update_top_walk(relative_velocity: Vector3, delta: float) -> void:
	climb_pose_target = Vector3.ZERO
	var local := actor.global_basis.orthonormalized().inverse() * relative_velocity
	var clip := "idle"
	if Vector2(local.x, local.z).length() > .12:
		var direction := "forward" if local.z < 0 else "back"
		if absf(local.x) > absf(local.z): direction = "right" if local.x > 0 else "left"
		clip = "jog_" + direction
	_select(clip, .12)
	var advancing: bool = not actor.is_gameplay_input_blocked()
	_advance(delta if advancing else 0.0, 1.0, delta if advancing else 0.0, LADDER_TRANSITION_POSE_SPEED)

func _transition_input_pressed() -> bool:
	if actor.is_gameplay_input_blocked(): return false
	var forward := Input.is_action_pressed("move_forward")
	var backward := Input.is_action_pressed("move_back")
	if forward == backward: return false
	return forward if actor.ladder_transition_direction > 0 else backward

func _advance(delta: float, playback_direction: float = 1.0, pose_delta: float = -1.0, pose_speed: float = 3.0) -> void:
	_clear_pose_offset()
	animation.advance(delta * playback_direction)
	# Animation and procedural pose clocks both pause on released transition
	# controls; carrier rotation is handled independently in _update_climb.
	var blend_delta := delta if pose_delta < 0.0 else pose_delta
	climb_pose_offset = climb_pose_offset.move_toward(climb_pose_target, blend_delta * pose_speed)
	# Animation resets this track each sample; never accumulate into a bind pose.
	applied_root_offset = skeleton.global_basis.inverse() * climb_pose_offset
	skeleton.set_bone_pose_position(root_bone, skeleton.get_bone_pose_position(root_bone) + applied_root_offset)
	# Move the eye by the same world-space approach as the visible body. Keep
	# mouse pitch/yaw independent, and unwind both together after detaching.
	view_camera.position = camera_rest_position + actor.global_basis.inverse() * climb_pose_offset

func _clear_pose_offset() -> void:
	# Never let the transition blend capture last frame's procedural offset.
	skeleton.set_bone_pose_position(root_bone, skeleton.get_bone_pose_position(root_bone) - applied_root_offset)
	applied_root_offset = Vector3.ZERO

func _select(clip: String, blend: float = .16) -> void:
	if current_clip == clip: return
	_clear_pose_offset()
	animation.play("locomotion/" + clip, blend if not current_clip.is_empty() else 0.0)
	current_clip = clip

func _update_crawl(delta: float) -> void:
	climb_rv = null
	climb_exit_remaining = 0
	landing_animation_started = false
	manual_top_departure = false
	climb_pose_target = Vector3.ZERO
	climb_pose_offset = Vector3.ZERO
	air_time = 0
	landing_remaining = 0
	var local: Vector3 = actor.global_basis.inverse() * actor.velocity
	var speed := 0.0 if actor.in_ui_mode else Vector2(local.x, local.z).length()
	var clip := "prone_idle"
	if speed > .06 and actor.usable_arms() > 0:
		if actor.usable_arms() == 1: clip = "crawl_onearm_L" if actor.body_state.has_part(&"left_arm") else "crawl_onearm_R"
		elif not actor.body_state.has_part(&"left_leg") and not actor.body_state.has_part(&"right_leg"): clip = "crawl_no_legs"
		else: clip = "crawl_missing_right_leg" if actor.body_state.has_part(&"left_leg") else "crawl_missing_left_leg"
	var name := "injury/" + clip
	if current_clip != name:
		_clear_pose_offset()
		animation.play(name, .45 if not was_crawling else .18)
		current_clip = name
	was_crawling = true
	if not actor.in_ui_mode:
		# Authored palms pull back 34 cm during 67% of each cycle. Match the
		# controller's travel while planted, including the slower one-arm drag.
		var rate := 1.0 if clip == "prone_idle" else clampf(speed * animation.get_animation(name).length * .67 / .34, .0, 2.2)
		animation.advance(delta * rate)
	view_camera.position = view_camera.position.move_toward(crawl_eye, delta * 2.8)

func _injury_library() -> AnimationLibrary:
	var result := AnimationLibrary.new()
	var source := INJURY_CLIPS.instantiate()
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	var clips := source.get_node("AnimationPlayer") as AnimationPlayer
	for name in clips.get_animation_list():
		if name == "RESET": continue
		var imported := clips.get_animation(name)
		var converted := Animation.new()
		converted.length = imported.length
		converted.loop_mode = Animation.LOOP_LINEAR
		var channels: Array[Dictionary] = []
		for bone in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(bone)
			var donor_bone := source_skeleton.find_bone(bone_name)
			if donor_bone < 0: continue
			var path := NodePath("PLAYER_Rig/Skeleton3D:" + bone_name)
			var p := imported.find_track(path, Animation.TYPE_POSITION_3D)
			var r := imported.find_track(path, Animation.TYPE_ROTATION_3D)
			var s := imported.find_track(path, Animation.TYPE_SCALE_3D)
			var out_p := converted.add_track(Animation.TYPE_POSITION_3D)
			var out_r := converted.add_track(Animation.TYPE_ROTATION_3D)
			var out_s := converted.add_track(Animation.TYPE_SCALE_3D)
			for track in [out_p, out_r, out_s]: converted.track_set_path(track, path)
			channels.append({"bone": bone, "donor": donor_bone, "p": p, "r": r, "s": s, "out_p": out_p, "out_r": out_r, "out_s": out_s})
		for frame in ceili(imported.length * 60) + 1:
			var t := minf(float(frame) / 60, imported.length)
			var donor_locals: Dictionary = {}
			for channel in channels:
				# glTF omits constant channels. Their values remain the donor's
				# local rest transform, including the length of each limb segment.
				var rest := source_skeleton.get_bone_rest(channel.donor)
				var position := imported.position_track_interpolate(channel.p, t) if channel.p >= 0 else rest.origin
				var rotation := imported.rotation_track_interpolate(channel.r, t) if channel.r >= 0 else rest.basis.get_rotation_quaternion()
				var scale := imported.scale_track_interpolate(channel.s, t) if channel.s >= 0 else rest.basis.get_scale()
				donor_locals[channel.donor] = Transform3D(Basis(rotation).scaled(scale), position)
			# This import helper is outside the SceneTree. Evaluate parent chains
			# directly rather than depending on deferred Skeleton3D pose caches.
			var donor_globals: Dictionary = {}
			for bone in source_skeleton.get_bone_count():
				var parent := source_skeleton.get_bone_parent(bone)
				donor_globals[bone] = donor_globals.get(parent, Transform3D.IDENTITY) * donor_locals.get(bone, source_skeleton.get_bone_rest(bone))
			var world_poses: Dictionary = {}
			for channel in channels:
				# Blender's glTF import can realign bone axes. Retarget deformation
				# relative to GLOBAL rest, not raw local rotations: the latter folds
				# wrists/elbows even when the bone names and joint positions match.
				world_poses[channel.bone] = donor_globals[channel.donor] * source_skeleton.get_bone_global_rest(channel.donor).affine_inverse() * skeleton.get_bone_global_rest(channel.bone)
			for channel in channels:
				var parent := skeleton.get_bone_parent(channel.bone)
				var parent_pose: Transform3D = world_poses.get(parent, Transform3D.IDENTITY)
				# Godot animation tracks store the complete parent-relative bone
				# transform, not an additive offset from that bone's rest matrix.
				var pose: Transform3D = parent_pose.affine_inverse() * world_poses[channel.bone]
				converted.position_track_insert_key(channel.out_p, t, pose.origin)
				converted.rotation_track_insert_key(channel.out_r, t, pose.basis.orthonormalized().get_rotation_quaternion())
				converted.scale_track_insert_key(channel.out_s, t, pose.basis.get_scale())
		for track in converted.get_track_count():
			converted.track_set_key_value(track, converted.track_get_key_count(track) - 1, converted.track_get_key_value(track, 0))
		result.add_animation(name, converted)
	source.free()
	return result

func suspend() -> void:
	if suspended: return
	animation.pause() # Preserve the visible pose for the physics handoff.
	suspended = true
	air_time = 0.0
	last_vertical_speed = 0.0
	landing_remaining = 0.0
	climb_rv = null
	climb_exit_remaining = 0.0
	landing_animation_started = false
	manual_top_departure = false
	climb_pose_target = Vector3.ZERO
	climb_pose_offset = Vector3.ZERO # Keep the currently evaluated skeleton for death.
	applied_root_offset = Vector3.ZERO

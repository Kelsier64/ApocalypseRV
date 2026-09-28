extends Node
## Presentation of controller-relative velocity. No controller root motion.
const CLIPS = preload("res://assets/models/player_animations_v021/player_animations_v021.glb")
static var library: AnimationLibrary
var actor: CharacterBody3D
var animation: AnimationPlayer
var current_clip := ""
var suspended := false
var air_time := 0.0
var last_vertical_speed := 0.0
var landing_remaining := 0.0
var climb_rv: Node3D
var climb_local_position := Vector3.ZERO
var climb_normal := Vector3.ZERO
var climb_exit_remaining := 0.0
var climb_pose_offset := Vector3.ZERO
var climb_pose_target := Vector3.ZERO
var skeleton: Skeleton3D
var root_bone := -1
var applied_root_offset := Vector3.ZERO
var view_camera: Camera3D
var camera_rest_position := Vector3.ZERO

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
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.active = true
	_select("idle")
	animation.advance(0)
	set_physics_process(actor != null)

func _physics_process(delta: float) -> void:
	if actor.is_player_dead:
		suspend()
		return
	# Seat is currently hidden; grabbed poses remain separate future work.
	if actor.seated_in != null or actor.is_grabbed():
		if actor.seated_in != null and not actor.is_grabbed():
			view_camera.position = camera_rest_position
		suspend()
		return
	if suspended:
		current_clip = ""
		suspended = false
	if actor.locomotion_state == actor.LocomotionState.CLIMBING:
		_update_climb(delta)
		return
	if is_instance_valid(climb_rv):
		# Roof transfer moves inward by a capsule diameter; its floor/support
		# flags can arrive one frame later. A manual detach has no inward step.
		var transfer := actor.global_position - climb_rv.to_global(climb_local_position)
		if (actor.is_on_floor() and actor.rv_support.rv == climb_rv) or transfer.dot(-climb_normal) > .6:
			climb_exit_remaining = animation.get_animation("locomotion/climb_exit").length
			_select("climb_exit", .08)
		climb_rv = null
	climb_pose_target = Vector3.ZERO
	if climb_exit_remaining > 0.0 and (actor.is_on_floor() or (actor.velocity.y <= 0 and actor.velocity.y > -1.0)):
		if actor.in_ui_mode: return
		climb_exit_remaining = maxf(0.0, climb_exit_remaining - delta)
		_advance(delta)
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
	climb_rv = carrier
	climb_local_position = local_position
	climb_normal = actor.active_wall_normal
	air_time = 0.0
	last_vertical_speed = 0.0
	landing_remaining = 0.0
	climb_exit_remaining = 0.0
	if actor.in_ui_mode: return
	var probe: RayCast3D = actor.climb_wall_probe
	if probe.is_colliding():
		var normal: Vector3 = actor.active_wall_normal
		var distance := (skeleton.global_position - probe.get_collision_point()).dot(normal)
		# Pose-space approach only. The original controller can catch the wall
		# from farther away than the authored palms (0.365 m from the root).
		climb_pose_target = -normal * clampf(distance - .365, -.12, .5)
	var up := carrier.global_basis.y.normalized()
	var tangent := up.cross(actor.active_wall_normal).normalized()
	var vertical := relative_velocity.dot(up)
	var horizontal := relative_velocity.dot(tangent)
	var clip := "climb_hold"
	var rate := 1.0
	if vertical > .08:
		clip = "climb_up"
		rate = clampf(vertical / actor.CLIMB_VERTICAL_SPEED, 0.0, 1.5)
	elif absf(horizontal) > .08:
		clip = "climb_right" if horizontal > 0 else "climb_left"
		rate = clampf(absf(horizontal) / actor.CLIMB_SIDE_SPEED, 0.0, 1.5)
	_select(clip, .08)
	_advance(delta * rate)

func _advance(delta: float) -> void:
	_clear_pose_offset()
	animation.advance(delta)
	climb_pose_offset = climb_pose_offset.move_toward(climb_pose_target, delta * 3.0)
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

func suspend() -> void:
	if suspended: return
	animation.pause() # Preserve the visible pose for the physics handoff.
	suspended = true
	air_time = 0.0
	last_vertical_speed = 0.0
	landing_remaining = 0.0
	climb_rv = null
	climb_exit_remaining = 0.0
	climb_pose_target = Vector3.ZERO
	climb_pose_offset = Vector3.ZERO # Keep the currently evaluated skeleton for death.
	applied_root_offset = Vector3.ZERO

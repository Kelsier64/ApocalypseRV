extends CharacterBody3D
class_name Monster

const CLIMB_WALL_MIN_DOT = 0.0
const CLIMB_WALL_MAX_DOT = 0.85
const CLIMB_MIN_HIT_Y = 0.1
const CLIMB_MAX_HIT_Y = 1.4
const CLIMB_EXIT_MAX_UP_VELOCITY = 0.1
const CLIMB_VERTICAL_SPEED = 1
const CLIMB_SIDE_SPEED = 1.2
const CLIMB_WALL_STICK_SPEED = 0.0
const CLIMB_CONTACT_GRACE_TIME = 0.28
const CLIMB_CONTACT_GRACE_DISTANCE = 0.4
const CLIMB_CONTACT_GRACE_MAX_TIME = 0.9
const CLIMB_CONTACT_FALLBACK_HEIGHT = 0.7
const CLIMB_CONTACT_FALLBACK_RAY_LENGTH = 0.85
const CLIMB_START_CEILING_CHECK_DISTANCE = 0.6
const CLIMB_MAX_RV_ANGULAR_SPEED = 2.4
const CLIMB_MAX_FRAME_DELTA = 1.5
const CLIMB_REENTER_COOLDOWN = 0.2
const CLIMB_WALL_ALIGN_OFFSET = 0.22
const CLIMB_WALL_MAX_OUTWARD_CORRECTION = 0.08
const CLIMB_EXIT_TRANSFER_TIME = 0.22
const CLIMB_EXIT_TRANSFER_SPEED = 2.8
const CLIMB_DESCENT_MIN_HEIGHT_GAP = 0.8
const CLIMB_DESCENT_HINT_WEIGHT = 0.75
const CLIMB_POST_SEPARATION_NAV_BLOCK_TIME = 0.45
const CLIMB_DEBUG_LOG_ABORTS = false

@export var monster_name: String = "Unknown Creature"
@export var max_health: float = 100.0
@export var move_speed: float = 3.0
@export var contact_damage: float = 10.0

@export_group("AI")
@export var detection_range: float = 25.0
@export var attack_range: float = 2.0
@export var attack_max_vertical_gap: float = 1.1
@export var attack_cooldown: float = 1.5
@export var lose_interest_range: float = 40.0

@export_group("Navigation")
@export var nav_path_desired_distance: float = 0.6
@export var nav_target_desired_distance: float = 1.2
@export var nav_repath_interval: float = 0.25
@export var nav_repath_distance_epsilon: float = 0.75
@export var wander_min_distance: float = 3.0
@export var wander_max_distance: float = 8.0

@export_group("Anti-Stuck")
@export var move_progress_threshold: float = 0.05
@export var stuck_time_threshold: float = 1.0
@export var stuck_recovery_cooldown: float = 0.8
@export var stuck_fallback_duration: float = 0.5

@export_group("Elevation Assist")
@export var elevation_assist_min_gap: float = 0.2
@export var elevation_assist_max_gap: float = 2.4
@export var elevation_assist_up_speed: float = 3.8
@export var elevation_assist_planar_scale: float = 0.65
@export var elevation_assist_cooldown: float = 0.7
@export var stuck_recovery_hop_speed: float = 4.4
@export var stuck_recovery_side_push: float = 1.7
@export var stuck_recovery_forward_scale: float = 0.7

@export_group("Vehicle Damage")
@export var vehicle_damage_min_speed: float = 3.0
@export var vehicle_damage_min_approach_speed: float = 2.2
@export var vehicle_damage_min_approach_dot: float = 0.35

@export_group("Loot")
@export var loot_drops: Dictionary = {} # e.g. {"Metal Parts": Vector2(1, 3)}
@export var loot_scene: String = "res://props/scrap.tscn"

@export_group("Debug")
@export var debug_climb_messages: bool = false
@export var debug_navigation_messages: bool = false
@export var debug_climb_message_interval: float = 0.35

var current_health: float
var is_dead: bool = false

# AI State
enum State { WANDER, CHASE, ATTACK }
var ai_state: State = State.WANDER
var target_player: Node3D = null

enum LocomotionState { NORMAL, CLIMBING }
var locomotion_state: LocomotionState = LocomotionState.NORMAL
var active_climb_rv: Node3D = null
var previous_climb_rv_transform: Transform3D = Transform3D.IDENTITY
var active_wall_normal: Vector3 = Vector3.ZERO
var climb_contact_grace_remaining: float = 0.0
var climb_reenter_cooldown_remaining: float = 0.0
var last_climb_wall_normal: Vector3 = Vector3.ZERO
var last_climb_separation_state: String = "unknown"
var post_separation_nav_block_remaining: float = 0.0
var post_climb_transfer_direction: Vector3 = Vector3.ZERO
var post_climb_transfer_time_remaining: float = 0.0
var debug_last_ceiling_hit_distance: float = INF
var debug_last_ceiling_hit_position: Vector3 = Vector3.ZERO
var debug_last_ceiling_hit_source: String = ""
var debug_last_ceiling_hit_node: String = ""
var debug_climb_last_log_time_by_tag: Dictionary = {}

# Wandering
var wander_direction: Vector3 = Vector3.ZERO
var wander_target_position: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var idle_timer: float = 0.0
var is_idle: bool = false

# Organic movement
var sway_phase: float = 0.0
var stagger_amount: float = 0.0

# Attack
var attack_timer: float = 0.0

# Navigation + anti-stuck
var nav_agent: NavigationAgent3D = null
var nav_target_position: Vector3 = Vector3.ZERO
var nav_has_target: bool = false
var nav_repath_timer: float = 0.0
var fallback_steer_timer: float = 0.0
var stuck_timer: float = 0.0
var stuck_cooldown_timer: float = 0.0
var elevation_assist_cooldown_timer: float = 0.0
var last_flat_position: Vector3 = Vector3.ZERO
var has_last_flat_position: bool = false

var body_collision_shape: CollisionShape3D = null
var climb_wall_probe: RayCast3D = null
var climb_upward_probe: RayCast3D = null

var gravity: float = 20.0

func _ready():
	current_health = max_health
	add_to_group("monsters")
	
	# Randomize initial sway so all zombies don't sync
	sway_phase = randf_range(0, TAU)
	stagger_amount = randf_range(0.3, 0.7)
	
	# Connect the HitBox Area3D for vehicle detection
	var hitbox = get_node_or_null("HitBox")
	if hitbox and hitbox is Area3D:
		hitbox.body_entered.connect(_on_hitbox_body_entered)

	nav_agent = _resolve_navigation_agent()
	if nav_agent:
		nav_agent.path_desired_distance = nav_path_desired_distance
		nav_agent.target_desired_distance = nav_target_desired_distance

	body_collision_shape = get_node_or_null("CollisionShape")
	climb_wall_probe = get_node_or_null("ClimbWallProbe")
	climb_upward_probe = get_node_or_null("ClimbUpwardProbe")
	if climb_upward_probe:
		climb_upward_probe.enabled = true
		climb_upward_probe.collision_mask = 0xFFFFFFFF
		climb_upward_probe.collide_with_bodies = true
		climb_upward_probe.collide_with_areas = true
		climb_upward_probe.exclude_parent = true

	last_flat_position = _flat_position(global_position)
	has_last_flat_position = true
	
	_pick_new_wander_direction()

func _physics_process(delta: float):
	if is_dead: return
	_sync_body_collision_to_locomotion()
	
	if locomotion_state == LocomotionState.NORMAL:
		# Gravity
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
	
	# Update sway for organic movement
	sway_phase += delta * 3.0
	
	# Attack cooldown
	if attack_timer > 0.0:
		attack_timer -= delta
	if nav_repath_timer > 0.0:
		nav_repath_timer -= delta
	if stuck_cooldown_timer > 0.0:
		stuck_cooldown_timer -= delta
	if fallback_steer_timer > 0.0:
		fallback_steer_timer -= delta
	if elevation_assist_cooldown_timer > 0.0:
		elevation_assist_cooldown_timer -= delta
	if climb_reenter_cooldown_remaining > 0.0:
		climb_reenter_cooldown_remaining = maxf(0.0, climb_reenter_cooldown_remaining - delta)
	if post_separation_nav_block_remaining > 0.0:
		post_separation_nav_block_remaining = maxf(0.0, post_separation_nav_block_remaining - delta)
	if post_climb_transfer_time_remaining > 0.0:
		post_climb_transfer_time_remaining = maxf(0.0, post_climb_transfer_time_remaining - delta)
	
	# Find player if we don't have one
	if not target_player or not is_instance_valid(target_player):
		target_player = _find_nearest_player()

	var moving_intent := false

	match locomotion_state:
		LocomotionState.NORMAL:
			# AI State Machine
			match ai_state:
				State.WANDER:
					moving_intent = _process_wander(delta)
					# Check if player is close enough to chase
					if target_player and global_position.distance_to(target_player.global_position) < detection_range:
						ai_state = State.CHASE
					
				State.CHASE:
					moving_intent = _process_chase(delta)
					if locomotion_state == LocomotionState.NORMAL:
						if target_player:
							var dist = global_position.distance_to(target_player.global_position)
							var has_attack_los := _has_attack_line_of_sight_to_target(target_player)
							if _can_attack_target_position(target_player.global_position, has_attack_los):
								ai_state = State.ATTACK
							elif dist > lose_interest_range:
								ai_state = State.WANDER
								_pick_new_wander_direction()
						else:
							ai_state = State.WANDER
							_pick_new_wander_direction()
					
				State.ATTACK:
					_process_attack(delta)
					moving_intent = false
					if target_player:
						var dist = global_position.distance_to(target_player.global_position)
						var has_attack_los := _has_attack_line_of_sight_to_target(target_player)
						if not _can_attack_target_position(target_player.global_position, has_attack_los) or dist > attack_range * 1.5:
							ai_state = State.CHASE
					else:
						ai_state = State.WANDER

			_update_stuck_watchdog(delta, moving_intent)

		LocomotionState.CLIMBING:
			moving_intent = true
			_apply_rv_delta_compensation()
			var climb_destination := global_position
			if target_player and is_instance_valid(target_player):
				climb_destination = target_player.global_position
			_process_climbing(delta, climb_destination)
	
	# Apply organic body sway (slight rotation wobble)
	var body_mesh = get_node_or_null("BodyMesh")
	if body_mesh:
		body_mesh.rotation.z = sin(sway_phase) * 0.08 * stagger_amount
		body_mesh.rotation.x = cos(sway_phase * 0.7) * 0.04 * stagger_amount
	
	if locomotion_state == LocomotionState.NORMAL:
		move_and_slide()

# --- WANDERING ---
func _process_wander(delta: float) -> bool:
	if is_idle:
		idle_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if idle_timer <= 0.0:
			is_idle = false
			_pick_new_wander_direction()
		return false
	
	wander_timer -= delta
	if wander_timer <= 0.0:
		# Sometimes stop and idle
		if randf() < 0.4:
			is_idle = true
			idle_timer = randf_range(1.0, 3.0)
			return false
		_pick_new_wander_direction()

	if global_position.distance_to(wander_target_position) < 1.5:
		_pick_new_wander_direction()
	
	# Slow shambling speed when wandering
	var wander_speed = move_speed * 0.4
	var move_dir = _get_navigation_direction(wander_target_position)
	if move_dir.length_squared() <= 0.0001:
		move_dir = wander_direction
	
	# Add slight stagger to the path
	var stagger = Vector3(sin(sway_phase * 1.3), 0, cos(sway_phase * 0.9)) * stagger_amount * 0.5
	var combined = move_dir + stagger
	if combined.length_squared() <= 0.0001:
		combined = move_dir
	combined = combined.normalized()
	velocity.x = combined.x * wander_speed
	velocity.z = combined.z * wander_speed
	
	_face_movement_direction()
	return true

# --- CHASING ---
func _process_chase(_delta: float) -> bool:
	if not target_player or not is_instance_valid(target_player):
		return false

	var destination = target_player.global_position
	if _try_start_climb(destination):
		return true

	var on_rv_surface := _is_on_rv_surface()
	var can_nav := _can_use_navigation() and fallback_steer_timer <= 0.0
	var vertical_gap := absf(destination.y - global_position.y)
	var nav_active = _should_use_navigation_for_chase(can_nav, on_rv_surface, vertical_gap, post_separation_nav_block_remaining)
	var dir := _resolve_chase_direction(destination, on_rv_surface, nav_active)
	_debug_nav_log(
		"chase_state",
		"nav_active=%s on_rv=%s can_nav=%s vgap=%.2f nav_block=%.2f dir=%s dist=%.2f sep=%s" % [
			str(nav_active),
			str(on_rv_surface),
			str(can_nav),
			vertical_gap,
			post_separation_nav_block_remaining,
			_debug_v3(dir),
			global_position.distance_to(destination),
			last_climb_separation_state
		]
	)
	if dir.length_squared() <= 0.0001:
		_debug_climb_log(
			"chase_stall",
			"side=%s on_rv=%s y_gap=%.2f last_wall=%s transfer_t=%.2f" % [
				_debug_climb_side_label(active_climb_rv, last_climb_wall_normal),
				str(on_rv_surface),
				global_position.y - destination.y,
				_debug_v3(last_climb_wall_normal),
				post_climb_transfer_time_remaining
			]
		)
		_debug_nav_log(
			"chase_stall",
			"on_rv=%s y_gap=%.2f sep=%s" % [
				str(on_rv_surface),
				global_position.y - destination.y,
				last_climb_separation_state
			],
			true
		)
		velocity.x = 0.0
		velocity.z = 0.0
		return false
	
	# Stagger while chasing (not a perfectly straight line)
	var stagger_strength = 0.05 if nav_active else 0.22
	var stagger = Vector3(sin(sway_phase * 2.0), 0, cos(sway_phase * 1.5)) * stagger_amount * stagger_strength
	var combined = (dir + stagger).normalized()

	velocity.x = combined.x * move_speed
	velocity.z = combined.z * move_speed

	if _should_apply_elevation_assist(destination):
		var assisted_velocity = _build_elevation_assist_velocity(Vector3(velocity.x, 0.0, velocity.z))
		velocity.x = assisted_velocity.x
		velocity.y = maxf(velocity.y, assisted_velocity.y)
		velocity.z = assisted_velocity.z
		elevation_assist_cooldown_timer = elevation_assist_cooldown
	
	_face_movement_direction()
	return true

func _resolve_chase_direction(destination: Vector3, on_rv_surface: bool, nav_active: bool) -> Vector3:
	var origin := global_position if is_inside_tree() else position
	var dir := Vector3.ZERO
	if nav_active:
		dir = _get_navigation_direction(destination)
	else:
		dir = _compute_fallback_direction(origin, destination)

	if dir.length_squared() <= 0.0001:
		dir = _get_descent_hint_direction(destination)

	if dir.length_squared() <= 0.0001 and post_climb_transfer_time_remaining > 0.0:
		dir = post_climb_transfer_direction

	if post_climb_transfer_time_remaining > 0.0 and post_climb_transfer_direction.length_squared() > 0.0001:
		var blend := clampf(post_climb_transfer_time_remaining / CLIMB_EXIT_TRANSFER_TIME, 0.0, 1.0)
		if dir.length_squared() <= 0.0001:
			dir = post_climb_transfer_direction
		else:
			dir = (dir + post_climb_transfer_direction * blend).normalized()

	if dir.length_squared() <= 0.0001:
		dir = _compute_fallback_direction(origin, destination)

	if on_rv_surface and dir.length_squared() <= 0.0001:
		return _get_descent_hint_direction(destination)

	return dir

func _should_disable_body_collision_for_locomotion(state: int) -> bool:
	return state == LocomotionState.CLIMBING

func _sync_body_collision_to_locomotion() -> void:
	if body_collision_shape == null:
		return
	body_collision_shape.disabled = _should_disable_body_collision_for_locomotion(int(locomotion_state))

func _is_rv_wall_normal(hit_normal: Vector3, rv_up: Vector3 = Vector3.UP) -> bool:
	var n := hit_normal.normalized()
	var up := rv_up.normalized()
	var d := absf(n.dot(up))
	return d >= CLIMB_WALL_MIN_DOT and d <= CLIMB_WALL_MAX_DOT

func _is_valid_climb_hit_height(local_hit_y: float) -> bool:
	return local_hit_y >= CLIMB_MIN_HIT_Y and local_hit_y <= CLIMB_MAX_HIT_Y

func _compute_rv_position_delta(prev_rv_transform: Transform3D, next_rv_transform: Transform3D) -> Vector3:
	return next_rv_transform.origin - prev_rv_transform.origin

func _sanitize_velocity_after_climb(v: Vector3) -> Vector3:
	var out := v
	if out.y > CLIMB_EXIT_MAX_UP_VELOCITY:
		out.y = 0.0
	return out

func _debug_v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _debug_node_name(node: Node) -> String:
	if node == null:
		return "null"
	return "%s:%s" % [node.name, node.get_class()]

func _debug_climb_side_label(rv: Node3D, wall_normal: Vector3) -> String:
	if rv == null:
		return "rv_unknown"
	var local_normal := rv.global_transform.basis.inverse() * wall_normal.normalized()
	if absf(local_normal.x) >= absf(local_normal.z):
		return "rv_right" if local_normal.x >= 0.0 else "rv_left"
	return "rv_back" if local_normal.z >= 0.0 else "rv_front"

func _debug_climb_log(tag: String, message: String, force: bool = false) -> void:
	if not debug_climb_messages:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	if not force:
		var last: float = float(debug_climb_last_log_time_by_tag.get(tag, -INF))
		if now - last < maxf(0.01, debug_climb_message_interval):
			return
	debug_climb_last_log_time_by_tag[tag] = now
	print("[CLIMB_DEBUG][monster][", monster_name, "][", tag, "] ", message)

func _debug_nav_log(tag: String, message: String, force: bool = false) -> void:
	if not debug_navigation_messages:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var key := "nav:%s" % tag
	if not force:
		var last: float = float(debug_climb_last_log_time_by_tag.get(key, -INF))
		if now - last < maxf(0.01, debug_climb_message_interval):
			return
	debug_climb_last_log_time_by_tag[key] = now
	print("[NAV_DEBUG][monster][", monster_name, "][", tag, "] ", message)

func _build_climb_motion(rv_up: Vector3, wall_normal: Vector3, vertical_input: float, horizontal_input: float, delta: float) -> Vector3:
	var wall_tangent := rv_up.cross(wall_normal).normalized()
	if wall_tangent.length_squared() < 0.001:
		wall_tangent = transform.basis.x.normalized()

	var motion := (rv_up * vertical_input * CLIMB_VERTICAL_SPEED)
	motion += wall_tangent * horizontal_input * CLIMB_SIDE_SPEED
	motion += (-wall_normal) * CLIMB_WALL_STICK_SPEED
	var inward_mag := motion.dot(-wall_normal)
	if inward_mag > 0.0:
		motion += wall_normal * inward_mag
	motion *= delta
	if motion.length() > CLIMB_MAX_FRAME_DELTA:
		motion = motion.normalized() * CLIMB_MAX_FRAME_DELTA
	return motion

func _compute_climb_contact_grace_time(vertical_speed: float) -> float:
	var safe_speed := maxf(vertical_speed, 0.01)
	var distance_based_time := CLIMB_CONTACT_GRACE_DISTANCE / safe_speed
	return clampf(maxf(CLIMB_CONTACT_GRACE_TIME, distance_based_time), CLIMB_CONTACT_GRACE_TIME, CLIMB_CONTACT_GRACE_MAX_TIME)

func _get_climb_contact_grace_time() -> float:
	return _compute_climb_contact_grace_time(CLIMB_VERTICAL_SPEED)

func _get_climb_separation_state(has_wall_contact: bool, grace_remaining: float) -> String:
	if has_wall_contact:
		return "attached"
	if grace_remaining > 0.0:
		return "detaching"
	return "separated"

func _clamp_upward_climb_distance(rv_up: Vector3, desired_upward_distance: float) -> float:
	debug_last_ceiling_hit_distance = INF
	debug_last_ceiling_hit_position = Vector3.ZERO
	debug_last_ceiling_hit_source = ""
	debug_last_ceiling_hit_node = ""

	if desired_upward_distance <= 0.0:
		return 0.0

	var from := global_position + rv_up * 0.2
	var to := from + rv_up * (desired_upward_distance + 0.8)
	var min_hit_distance := INF

	if climb_upward_probe != null:
		var local_from := to_local(from)
		var local_to := to_local(to)
		climb_upward_probe.position = local_from
		climb_upward_probe.target_position = local_to - local_from
		climb_upward_probe.force_raycast_update()
		if climb_upward_probe.is_colliding():
			var probe_hit_position: Vector3 = climb_upward_probe.get_collision_point()
			var probe_hit_distance := from.distance_to(probe_hit_position)
			if probe_hit_distance < min_hit_distance:
				min_hit_distance = probe_hit_distance
				debug_last_ceiling_hit_distance = probe_hit_distance
				debug_last_ceiling_hit_position = probe_hit_position
				debug_last_ceiling_hit_source = "upward_probe"
				debug_last_ceiling_hit_node = _debug_node_name(climb_upward_probe.get_collider() as Node)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid()])
	query.hit_from_inside = true
	var hit := space_state.intersect_ray(query)
	if hit:
		var hit_position: Vector3 = hit.get("position", from) as Vector3
		var hit_distance := from.distance_to(hit_position)
		if hit_distance < min_hit_distance:
			min_hit_distance = hit_distance
			debug_last_ceiling_hit_distance = hit_distance
			debug_last_ceiling_hit_position = hit_position
			debug_last_ceiling_hit_source = "intersect_ray"
			debug_last_ceiling_hit_node = _debug_node_name(hit.get("collider", null) as Node)

	if min_hit_distance == INF:
		return desired_upward_distance

	var safe_distance := maxf(0.0, min_hit_distance - 0.05)
	return minf(desired_upward_distance, safe_distance)

func _move_with_climb_collision(step: Vector3) -> KinematicCollision3D:
	if step.length_squared() <= 0.0000001:
		return null
	return move_and_collide(step)

func _apply_wall_outward_alignment(rv_up: Vector3) -> void:
	if climb_wall_probe == null or not climb_wall_probe.is_colliding() or active_climb_rv == null:
		return

	var hit_node := climb_wall_probe.get_collider() as Node
	if _find_rv_ancestor(hit_node) != active_climb_rv:
		return

	var wall_normal: Vector3 = climb_wall_probe.get_collision_normal().normalized()
	if _is_rv_wall_normal(wall_normal, rv_up):
		active_wall_normal = wall_normal

	var desired_probe_position: Vector3 = climb_wall_probe.get_collision_point() + wall_normal * CLIMB_WALL_ALIGN_OFFSET
	var correction: Vector3 = desired_probe_position - climb_wall_probe.global_position
	var normal_mag: float = correction.dot(wall_normal)
	if absf(normal_mag) <= 0.0001:
		return
	var alignment_step: Vector3 = wall_normal * clampf(normal_mag, -CLIMB_WALL_MAX_OUTWARD_CORRECTION, CLIMB_WALL_MAX_OUTWARD_CORRECTION)
	_move_with_climb_collision(alignment_step)

func _align_to_climb_wall(rv_up: Vector3) -> void:
	if active_wall_normal.length_squared() < 0.001:
		return
	var desired_forward := -active_wall_normal
	desired_forward = (desired_forward - rv_up * desired_forward.dot(rv_up)).normalized()
	if desired_forward.length_squared() < 0.001:
		return
	var desired_transform := global_transform.looking_at(global_position + desired_forward, rv_up)
	global_transform = global_transform.interpolate_with(desired_transform, 0.35)

func _find_rv_ancestor(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current is Node3D and current.is_in_group("rv"):
			return current as Node3D
		current = current.get_parent()
	return null

func _try_start_climb(_destination: Vector3) -> bool:
	if locomotion_state != LocomotionState.NORMAL:
		return false
	if climb_reenter_cooldown_remaining > 0.0:
		_debug_climb_log("start_cooldown", "blocked by reenter cooldown: %.2f" % climb_reenter_cooldown_remaining)
		return false
	if climb_wall_probe == null or not climb_wall_probe.is_colliding():
		_debug_climb_log("start_probe_miss", "wall probe has no hit")
		return false

	var hit_node := climb_wall_probe.get_collider() as Node
	var rv := _find_rv_ancestor(hit_node)
	if rv == null:
		return false

	var hit_normal: Vector3 = climb_wall_probe.get_collision_normal()
	var hit_point: Vector3 = climb_wall_probe.get_collision_point()
	var local_hit_y: float = to_local(hit_point).y
	var rv_up: Vector3 = rv.global_transform.basis.y.normalized()
	var start_allowed_upward := _clamp_upward_climb_distance(rv_up, CLIMB_START_CEILING_CHECK_DISTANCE)
	if start_allowed_upward < CLIMB_START_CEILING_CHECK_DISTANCE:
		var blocked_side := _debug_climb_side_label(rv, hit_normal)
		_debug_climb_log(
			"start_ceiling_block",
			"side=%s allowed=%.2f wanted=%.2f hit_dist=%.2f src=%s hit_node=%s hit_pos=%s wall_n=%s" % [
				blocked_side,
				start_allowed_upward,
				CLIMB_START_CEILING_CHECK_DISTANCE,
				debug_last_ceiling_hit_distance,
				debug_last_ceiling_hit_source,
				debug_last_ceiling_hit_node,
				_debug_v3(debug_last_ceiling_hit_position),
				_debug_v3(hit_normal.normalized())
			]
		)
		return false
	var wall_normal_ok := _is_rv_wall_normal(hit_normal, rv_up)
	var hit_height_ok := _is_valid_climb_hit_height(local_hit_y)
	if not wall_normal_ok or not hit_height_ok:
		_debug_climb_log(
			"start_gate_reject",
			"side=%s wall_ok=%s hit_y=%.2f range=[%.2f, %.2f] wall_dot_up=%.2f" % [
				_debug_climb_side_label(rv, hit_normal),
				str(wall_normal_ok),
				local_hit_y,
				CLIMB_MIN_HIT_Y,
				CLIMB_MAX_HIT_Y,
				absf(hit_normal.normalized().dot(rv_up))
			]
		)
		return false

	locomotion_state = LocomotionState.CLIMBING
	active_climb_rv = rv
	previous_climb_rv_transform = rv.global_transform
	active_wall_normal = hit_normal.normalized()
	climb_contact_grace_remaining = _get_climb_contact_grace_time()
	last_climb_separation_state = "attached"
	post_separation_nav_block_remaining = 0.0
	velocity = Vector3.ZERO
	_debug_climb_log(
		"start_ok",
		"entered climbing side=%s wall_n=%s hit_y=%.2f" % [
			_debug_climb_side_label(rv, hit_normal),
			_debug_v3(active_wall_normal),
			local_hit_y
		],
		true
	)
	return true

func _apply_rv_delta_compensation() -> void:
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		return
	var next_transform := active_climb_rv.global_transform
	var delta_pos := _compute_rv_position_delta(previous_climb_rv_transform, next_transform)
	if delta_pos.length() > CLIMB_MAX_FRAME_DELTA:
		delta_pos = delta_pos.normalized() * CLIMB_MAX_FRAME_DELTA
	var collision := _move_with_climb_collision(delta_pos)
	if collision and _find_rv_ancestor(collision.get_collider()) == active_climb_rv:
		active_wall_normal = collision.get_normal().normalized()
	previous_climb_rv_transform = next_transform

func _get_fallback_wall_contact_normal(rv_up: Vector3) -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		return Vector3.ZERO
	if active_wall_normal.length_squared() <= 0.0001:
		return Vector3.ZERO

	var toward_wall := -active_wall_normal
	toward_wall.y = 0.0
	if toward_wall.length_squared() <= 0.0001:
		return Vector3.ZERO
	toward_wall = toward_wall.normalized()

	var from := global_position + rv_up * CLIMB_CONTACT_FALLBACK_HEIGHT
	var to := from + toward_wall * CLIMB_CONTACT_FALLBACK_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit:
		return Vector3.ZERO

	var hit_node := hit.get("collider", null) as Node
	if _find_rv_ancestor(hit_node) != active_climb_rv:
		return Vector3.ZERO

	var hit_normal := hit.get("normal", Vector3.ZERO) as Vector3
	if hit_normal.length_squared() <= 0.0001:
		return Vector3.ZERO
	hit_normal = hit_normal.normalized()
	if not _is_rv_wall_normal(hit_normal, rv_up):
		return Vector3.ZERO
	return hit_normal

func _process_climbing(delta: float, destination: Vector3) -> void:
	if active_climb_rv == null or not is_instance_valid(active_climb_rv):
		_abort_climb("rv invalid")
		return

	if active_climb_rv is RigidBody3D:
		if (active_climb_rv as RigidBody3D).angular_velocity.length() > CLIMB_MAX_RV_ANGULAR_SPEED:
			_abort_climb("rv angular speed too high")
			return

	var rv_up := active_climb_rv.global_transform.basis.y.normalized()
	_align_to_climb_wall(rv_up)
	_apply_wall_outward_alignment(rv_up)
	var has_valid_wall_contact := false
	var pending_abort_lost_contact := false
	var contact_source := "none"

	if climb_wall_probe and climb_wall_probe.is_colliding():
		var wall_node := climb_wall_probe.get_collider() as Node
		if _find_rv_ancestor(wall_node) == active_climb_rv:
			var hit_normal: Vector3 = climb_wall_probe.get_collision_normal().normalized()
			has_valid_wall_contact = true
			active_wall_normal = hit_normal
			contact_source = "probe"

	if not has_valid_wall_contact:
		var fallback_wall_normal := _get_fallback_wall_contact_normal(rv_up)
		if fallback_wall_normal.length_squared() > 0.0001:
			has_valid_wall_contact = true
			active_wall_normal = fallback_wall_normal
			contact_source = "fallback"
			_debug_climb_log(
				"contact_fallback",
				"side=%s wall_n=%s" % [
					_debug_climb_side_label(active_climb_rv, active_wall_normal),
					_debug_v3(active_wall_normal)
				]
			)

	if has_valid_wall_contact:
		climb_contact_grace_remaining = _get_climb_contact_grace_time()
	else:
		climb_contact_grace_remaining -= delta
		if climb_contact_grace_remaining <= 0.0:
			pending_abort_lost_contact = true

	var separation_state := _get_climb_separation_state(has_valid_wall_contact, climb_contact_grace_remaining)
	var separation_changed := separation_state != last_climb_separation_state
	last_climb_separation_state = separation_state
	_debug_nav_log(
		"separation_state",
		"state=%s source=%s grace=%.2f side=%s wall_n=%s" % [
			separation_state,
			contact_source,
			maxf(climb_contact_grace_remaining, 0.0),
			_debug_climb_side_label(active_climb_rv, active_wall_normal),
			_debug_v3(active_wall_normal)
		],
		separation_changed or pending_abort_lost_contact
	)

	var vertical_input := 1.0

	if vertical_input > 0.0:
		var desired_upward_distance := vertical_input * CLIMB_VERTICAL_SPEED * delta
		var allowed_upward_distance := _clamp_upward_climb_distance(rv_up, desired_upward_distance)
		if allowed_upward_distance < desired_upward_distance:
			_debug_climb_log(
				"climb_ceiling_block",
				"side=%s wanted=%.3f allowed=%.3f hit_dist=%.3f src=%s hit_node=%s hit_pos=%s" % [
					_debug_climb_side_label(active_climb_rv, active_wall_normal),
					desired_upward_distance,
					allowed_upward_distance,
					debug_last_ceiling_hit_distance,
					debug_last_ceiling_hit_source,
					debug_last_ceiling_hit_node,
					_debug_v3(debug_last_ceiling_hit_position)
				],
				true
			)
			_abort_climb("ceiling detected")
			return
		else:
			vertical_input *= allowed_upward_distance / desired_upward_distance

	var horizontal_input := 0.0
	var wall_tangent := rv_up.cross(active_wall_normal).normalized()
	if wall_tangent.length_squared() > 0.001:
		var desired_to_target := destination - global_position
		desired_to_target = (desired_to_target - rv_up * desired_to_target.dot(rv_up)).normalized()
		if desired_to_target.length_squared() > 0.001:
			horizontal_input = clampf(desired_to_target.dot(wall_tangent), -1.0, 1.0)

	var motion := _build_climb_motion(rv_up, active_wall_normal, vertical_input, horizontal_input, delta)
	var collision := _move_with_climb_collision(motion)
	if collision and _find_rv_ancestor(collision.get_collider()) == active_climb_rv:
		active_wall_normal = collision.get_normal().normalized()
	_align_to_climb_wall(rv_up)
	velocity = Vector3.ZERO

	if pending_abort_lost_contact:
		_abort_climb("lost wall contact")

func _abort_climb(reason: String = "") -> void:
	if CLIMB_DEBUG_LOG_ABORTS and not reason.is_empty():
		print("Monster climb aborted: ", reason)
	if debug_climb_messages and not reason.is_empty():
		_debug_climb_log(
			"abort",
			"reason=%s side=%s pos=%s wall_n=%s" % [
				reason,
				_debug_climb_side_label(active_climb_rv, active_wall_normal),
				_debug_v3(global_position),
				_debug_v3(active_wall_normal)
			],
			true
		)
	_exit_climb_to_normal(reason)

func _exit_climb_to_normal(reason: String = "") -> void:
	var exit_wall_normal := active_wall_normal
	locomotion_state = LocomotionState.NORMAL
	active_climb_rv = null
	previous_climb_rv_transform = Transform3D.IDENTITY
	climb_contact_grace_remaining = 0.0
	climb_reenter_cooldown_remaining = CLIMB_REENTER_COOLDOWN
	last_climb_wall_normal = exit_wall_normal
	last_climb_separation_state = "separated"
	active_wall_normal = Vector3.ZERO
	_reset_navigation_state()
	velocity = _sanitize_velocity_after_climb(velocity)

	if reason == "lost wall contact":
		post_separation_nav_block_remaining = CLIMB_POST_SEPARATION_NAV_BLOCK_TIME
		var inward := -exit_wall_normal
		inward.y = 0.0
		if inward.length_squared() > 0.0001:
			post_climb_transfer_direction = inward.normalized()
			post_climb_transfer_time_remaining = CLIMB_EXIT_TRANSFER_TIME
			var transfer_speed := maxf(move_speed, CLIMB_EXIT_TRANSFER_SPEED)
			velocity.x = post_climb_transfer_direction.x * transfer_speed
			velocity.z = post_climb_transfer_direction.z * transfer_speed
	else:
		post_separation_nav_block_remaining = 0.0
		post_climb_transfer_direction = Vector3.ZERO
		post_climb_transfer_time_remaining = 0.0

# --- ATTACKING ---
func _process_attack(delta: float):
	if not target_player or not is_instance_valid(target_player): return
	
	# Slow down when attacking
	velocity.x = 0.0
	velocity.z = 0.0
	
	# Face the player
	var look_pos = target_player.global_position
	look_pos.y = global_position.y
	if look_pos.distance_to(global_position) > 0.01:
		look_at(look_pos, Vector3.UP)
	
	# Deal damage on cooldown
	if attack_timer <= 0.0:
		if target_player.has_method("take_damage"):
			target_player.take_damage(contact_damage)
			print(">>> ", monster_name, " attacks player for ", contact_damage, " damage!")
		attack_timer = attack_cooldown

func _pick_new_wander_direction():
	var angle = randf_range(0, TAU)
	wander_direction = Vector3(cos(angle), 0, sin(angle))
	wander_timer = randf_range(2.0, 5.0)
	var wander_distance = randf_range(wander_min_distance, wander_max_distance)
	wander_target_position = global_position + wander_direction * wander_distance
	_nav_set_target(wander_target_position, true)

func _face_movement_direction():
	var flat_vel = Vector3(velocity.x, 0, velocity.z)
	if flat_vel.length_squared() > 0.1:
		var look_target = global_position + flat_vel
		if look_target.distance_to(global_position) > 0.01:
			# Smooth rotation instead of snapping
			var target_transform = global_transform.looking_at(look_target, Vector3.UP)
			global_transform = global_transform.interpolate_with(target_transform, 0.1)

func _find_nearest_player() -> Node3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var nearest = null
	var nearest_dist = INF
	for p in players:
		var d = global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest

func _resolve_navigation_agent() -> NavigationAgent3D:
	var found = get_node_or_null("NavigationAgent3D")
	if found and found is NavigationAgent3D:
		return found as NavigationAgent3D
	return null

func _flat_position(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

func _can_use_navigation() -> bool:
	if nav_agent == null:
		return false
	var nav_map = nav_agent.get_navigation_map()
	if nav_map == RID():
		return false
	return NavigationServer3D.map_get_iteration_id(nav_map) > 0

func _compute_fallback_direction(origin: Vector3, destination: Vector3) -> Vector3:
	var direction = destination - origin
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return Vector3.ZERO
	return direction.normalized()

func _should_use_navigation_for_chase(can_nav: bool, on_rv_surface: bool, vertical_gap: float, post_separation_block_remaining: float) -> bool:
	if not can_nav:
		return false
	if on_rv_surface:
		return false
	if post_separation_block_remaining > 0.0:
		return false
	if last_climb_separation_state != "attached" and vertical_gap >= CLIMB_DESCENT_MIN_HEIGHT_GAP:
		return false
	return true

func _can_attack_target_position(target_position: Vector3, has_line_of_sight: bool = true) -> bool:
	if not has_line_of_sight:
		return false
	var origin := global_position if is_inside_tree() else position
	var offset := target_position - origin
	var vertical_gap := absf(offset.y)
	if vertical_gap > attack_max_vertical_gap:
		return false
	offset.y = 0.0
	return offset.length() <= attack_range

func _has_attack_line_of_sight_to_target(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not is_inside_tree():
		return true

	var from := global_position + Vector3.UP * 1.0
	var to := target.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit:
		return true

	var collider := hit.get("collider", null) as Node
	if collider == null:
		return false
	if collider == target:
		return true
	if target.is_ancestor_of(collider):
		return true
	if collider.is_ancestor_of(target):
		return true
	return false

func _get_descent_hint_direction(destination: Vector3) -> Vector3:
	var origin := global_position if is_inside_tree() else position
	var fallback_direction := _compute_fallback_direction(origin, destination)
	if origin.y - destination.y < CLIMB_DESCENT_MIN_HEIGHT_GAP:
		return fallback_direction

	var hint := last_climb_wall_normal
	hint.y = 0.0
	if hint.length_squared() <= 0.0001:
		return fallback_direction
	hint = hint.normalized()

	if fallback_direction.length_squared() <= 0.0001:
		return hint

	var blend := hint * CLIMB_DESCENT_HINT_WEIGHT + fallback_direction * (1.0 - CLIMB_DESCENT_HINT_WEIGHT)
	if blend.length_squared() <= 0.0001:
		return hint
	return blend.normalized()

func _is_on_rv_surface() -> bool:
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.3
	var to := from + Vector3.DOWN * 2.6
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [self.get_rid()])
	var hit := space_state.intersect_ray(query)
	if not hit:
		return false
	var hit_node := hit.collider as Node
	return _find_rv_ancestor(hit_node) != null

func _reset_navigation_state() -> void:
	nav_has_target = false
	nav_repath_timer = 0.0
	if nav_agent:
		nav_agent.target_position = global_position

func _nav_set_target(destination: Vector3, force: bool = false) -> void:
	if nav_agent == null:
		return
	if not force and nav_has_target and nav_repath_timer > 0.0:
		var delta = destination - nav_target_position
		delta.y = 0.0
		if delta.length() < nav_repath_distance_epsilon:
			return

	nav_target_position = destination
	nav_has_target = true
	nav_repath_timer = nav_repath_interval
	nav_agent.target_position = destination

func _get_navigation_direction(destination: Vector3) -> Vector3:
	var fallback_direction = _compute_fallback_direction(global_position, destination)
	if fallback_steer_timer > 0.0:
		return fallback_direction
	if not _can_use_navigation():
		return fallback_direction

	_nav_set_target(destination)
	var next_path_pos = nav_agent.get_next_path_position()
	var nav_direction = _compute_fallback_direction(global_position, next_path_pos)
	if nav_direction.length_squared() <= 0.0001:
		return fallback_direction
	return nav_direction

func _is_progress_too_small(progress: float, threshold: float) -> bool:
	return progress < threshold

func _get_frame_progress_threshold(delta: float) -> float:
	var frame_delta = maxf(delta, 0.0001)
	return maxf(move_progress_threshold * frame_delta, 0.0005)

func _is_elevation_gap_climbable(gap: float) -> bool:
	return gap >= elevation_assist_min_gap and gap <= elevation_assist_max_gap

func _build_elevation_assist_velocity(planar_velocity: Vector3) -> Vector3:
	var assisted = planar_velocity * elevation_assist_planar_scale
	assisted.y = elevation_assist_up_speed
	return assisted

func _build_stuck_recovery_velocity(planar_dir: Vector3, side_sign: float) -> Vector3:
	var dir = planar_dir
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()

	var side = dir.cross(Vector3.UP)
	if side.length_squared() <= 0.0001:
		side = Vector3.RIGHT
	else:
		side = side.normalized()

	var recovery = dir * (move_speed * stuck_recovery_forward_scale)
	recovery += side * side_sign * stuck_recovery_side_push
	recovery.y = stuck_recovery_hop_speed
	return recovery

func _compute_vehicle_approach_speed(vehicle_velocity: Vector3, impact_direction: Vector3) -> float:
	var flat_velocity = vehicle_velocity
	flat_velocity.y = 0.0
	if flat_velocity.length_squared() <= 0.0001:
		return 0.0

	var flat_impact = impact_direction
	flat_impact.y = 0.0
	if flat_impact.length_squared() <= 0.0001:
		return 0.0

	return flat_velocity.dot(flat_impact.normalized())

func _should_apply_vehicle_damage(vehicle_velocity: Vector3, impact_direction: Vector3) -> bool:
	var flat_velocity = vehicle_velocity
	flat_velocity.y = 0.0
	var speed = flat_velocity.length()
	if speed < vehicle_damage_min_speed:
		return false

	var approach_speed = _compute_vehicle_approach_speed(vehicle_velocity, impact_direction)
	if approach_speed < vehicle_damage_min_approach_speed:
		return false

	var approach_dot = approach_speed / maxf(speed, 0.0001)
	return approach_dot >= vehicle_damage_min_approach_dot

func _should_apply_elevation_assist(destination: Vector3) -> bool:
	if elevation_assist_cooldown_timer > 0.0:
		return false
	if not is_on_floor():
		return false
	if not is_on_wall():
		return false
	var height_gap = destination.y - global_position.y
	return _is_elevation_gap_climbable(height_gap)

func _can_trigger_stuck_recovery() -> bool:
	return stuck_cooldown_timer <= 0.0

func _update_stuck_watchdog(delta: float, moving_intent: bool) -> void:
	var current_flat = _flat_position(global_position)
	if not has_last_flat_position:
		last_flat_position = current_flat
		has_last_flat_position = true
		return

	var progress = current_flat.distance_to(last_flat_position)
	last_flat_position = current_flat

	if not moving_intent:
		stuck_timer = 0.0
		return

	var frame_progress_threshold = _get_frame_progress_threshold(delta)
	if _is_progress_too_small(progress, frame_progress_threshold):
		stuck_timer += delta
		if stuck_timer >= stuck_time_threshold and _can_trigger_stuck_recovery():
			_trigger_stuck_recovery()
	else:
		stuck_timer = 0.0

func _trigger_stuck_recovery() -> void:
	stuck_timer = 0.0
	stuck_cooldown_timer = stuck_recovery_cooldown
	fallback_steer_timer = stuck_fallback_duration
	nav_repath_timer = 0.0

	var recovery_destination = global_position + Vector3.FORWARD
	if target_player and is_instance_valid(target_player):
		recovery_destination = target_player.global_position
	elif ai_state == State.WANDER:
		recovery_destination = wander_target_position

	var recovery_dir = _compute_fallback_direction(global_position, recovery_destination)
	var side_sign = 1.0 if randf() > 0.5 else -1.0
	var recovery_velocity = _build_stuck_recovery_velocity(recovery_dir, side_sign)
	velocity.x = recovery_velocity.x
	velocity.z = recovery_velocity.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, recovery_velocity.y)

	if target_player and is_instance_valid(target_player):
		_nav_set_target(target_player.global_position, true)
	elif ai_state == State.WANDER:
		_pick_new_wander_direction()

# --- DAMAGE SYSTEM ---
func take_damage(amount: float):
	if is_dead: return
	
	current_health -= amount
	print(monster_name, " took ", amount, " damage! HP: ", current_health, "/", max_health)
	
	# Visual feedback: flash white briefly
	var mesh = get_node_or_null("BodyMesh")
	if mesh and mesh.material_override:
		var orig_color = mesh.material_override.albedo_color
		var tween = create_tween()
		mesh.material_override.albedo_color = Color.WHITE
		tween.tween_property(mesh.material_override, "albedo_color", orig_color, 0.15)
	
	if current_health <= 0.0:
		die()

func die():
	if is_dead: return
	is_dead = true
	
	print(">>> ", monster_name, " KILLED! Spawning loot...")
	
	# Spawn loot prop at death location
	_spawn_loot()
	
	# Death animation: shrink and disappear (uniform scale to avoid Jolt errors)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tween.tween_callback(queue_free)

func _spawn_loot():
	if loot_drops.is_empty(): return
	
	var scene = load(loot_scene)
	if not scene: return
	
	var item = scene.instantiate()
	
	# Override the prop's scrap_yields with the monster's loot table
	if item.has_method("set") and item.get("scrap_yields") != null:
		var rolled_yields = {}
		for mat_name in loot_drops:
			var range_vec = loot_drops[mat_name]
			var min_qty = int(range_vec.x)
			var max_qty = int(range_vec.y)
			var amount = randi_range(min_qty, max_qty)
			if amount > 0:
				rolled_yields[mat_name] = Vector2(amount, amount)
		
		item.set("scrap_yields", rolled_yields)
	
	# Spawn into the world
	var world = get_tree().current_scene
	if world:
		world.add_child(item)
		item.global_position = global_position + Vector3(0, 1.0, 0)
		if item is RigidBody3D:
			item.apply_central_impulse(Vector3(randf_range(-2, 2), 5.0, randf_range(-2, 2)))

# --- VEHICLE COLLISION ---
func _on_hitbox_body_entered(body: Node3D):
	if is_dead: return
	
	if body is VehicleBody3D:
		var knockback_dir = (global_position - body.global_position).normalized()
		if not _should_apply_vehicle_damage(body.linear_velocity, knockback_dir):
			return

		var approach_speed = _compute_vehicle_approach_speed(body.linear_velocity, knockback_dir)
		var damage_amount = approach_speed * 5.0

		print(">>> ", monster_name, " HIT BY VEHICLE. Approach speed: ", approach_speed, " m/s. Damage: ", damage_amount)
		take_damage(damage_amount)

		# Apply knockback away from the vehicle
		velocity = knockback_dir * approach_speed * 2.0 + Vector3(0, 5.0, 0)

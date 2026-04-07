extends CharacterBody3D
class_name Monster

@export var monster_name: String = "Unknown Creature"
@export var max_health: float = 100.0
@export var move_speed: float = 3.0
@export var contact_damage: float = 10.0

@export_group("AI")
@export var detection_range: float = 25.0
@export var attack_range: float = 2.0
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

var current_health: float
var is_dead: bool = false

# AI State
enum State { WANDER, CHASE, ATTACK }
var ai_state: State = State.WANDER
var target_player: Node3D = null

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

	last_flat_position = _flat_position(global_position)
	has_last_flat_position = true
	
	_pick_new_wander_direction()

func _physics_process(delta: float):
	if is_dead: return
	
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
	
	# Find player if we don't have one
	if not target_player or not is_instance_valid(target_player):
		target_player = _find_nearest_player()

	var moving_intent := false
	
	# AI State Machine
	match ai_state:
		State.WANDER:
			moving_intent = _process_wander(delta)
			# Check if player is close enough to chase
			if target_player and global_position.distance_to(target_player.global_position) < detection_range:
				ai_state = State.CHASE
				
		State.CHASE:
			moving_intent = _process_chase(delta)
			if target_player:
				var dist = global_position.distance_to(target_player.global_position)
				if dist < attack_range:
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
				if dist > attack_range * 1.5:
					ai_state = State.CHASE
			else:
				ai_state = State.WANDER

	_update_stuck_watchdog(delta, moving_intent)
	
	# Apply organic body sway (slight rotation wobble)
	var body_mesh = get_node_or_null("BodyMesh")
	if body_mesh:
		body_mesh.rotation.z = sin(sway_phase) * 0.08 * stagger_amount
		body_mesh.rotation.x = cos(sway_phase * 0.7) * 0.04 * stagger_amount
	
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
	var nav_active = _can_use_navigation() and fallback_steer_timer <= 0.0
	var dir = _get_navigation_direction(destination)
	if dir.length_squared() <= 0.0001:
		dir = _compute_fallback_direction(global_position, destination)
	if dir.length_squared() <= 0.0001:
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

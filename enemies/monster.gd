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
var wander_timer: float = 0.0
var idle_timer: float = 0.0
var is_idle: bool = false

# Organic movement
var sway_phase: float = 0.0
var stagger_amount: float = 0.0

# Attack
var attack_timer: float = 0.0

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
	
	# Find player if we don't have one
	if not target_player or not is_instance_valid(target_player):
		target_player = _find_nearest_player()
	
	# AI State Machine
	match ai_state:
		State.WANDER:
			_process_wander(delta)
			# Check if player is close enough to chase
			if target_player and global_position.distance_to(target_player.global_position) < detection_range:
				ai_state = State.CHASE
				
		State.CHASE:
			_process_chase(delta)
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
			if target_player:
				var dist = global_position.distance_to(target_player.global_position)
				if dist > attack_range * 1.5:
					ai_state = State.CHASE
			else:
				ai_state = State.WANDER
	
	# Apply organic body sway (slight rotation wobble)
	var body_mesh = get_node_or_null("BodyMesh")
	if body_mesh:
		body_mesh.rotation.z = sin(sway_phase) * 0.08 * stagger_amount
		body_mesh.rotation.x = cos(sway_phase * 0.7) * 0.04 * stagger_amount
	
	move_and_slide()

# --- WANDERING ---
func _process_wander(delta: float):
	if is_idle:
		idle_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if idle_timer <= 0.0:
			is_idle = false
			_pick_new_wander_direction()
		return
	
	wander_timer -= delta
	if wander_timer <= 0.0:
		# Sometimes stop and idle
		if randf() < 0.4:
			is_idle = true
			idle_timer = randf_range(1.0, 3.0)
			return
		_pick_new_wander_direction()
	
	# Slow shambling speed when wandering
	var wander_speed = move_speed * 0.4
	velocity.x = wander_direction.x * wander_speed
	velocity.z = wander_direction.z * wander_speed
	
	# Add slight stagger to the path
	var stagger = Vector3(sin(sway_phase * 1.3), 0, cos(sway_phase * 0.9)) * stagger_amount * 0.5
	velocity.x += stagger.x
	velocity.z += stagger.z
	
	_face_movement_direction()

# --- CHASING ---
func _process_chase(delta: float):
	if not target_player or not is_instance_valid(target_player): return
	
	var dir = (target_player.global_position - global_position)
	dir.y = 0
	dir = dir.normalized()
	
	# Stagger while chasing (not a perfectly straight line)
	var stagger = Vector3(sin(sway_phase * 2.0), 0, cos(sway_phase * 1.5)) * stagger_amount * 0.3
	
	velocity.x = (dir.x + stagger.x) * move_speed
	velocity.z = (dir.z + stagger.z) * move_speed
	
	_face_movement_direction()

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
		# Fallback: find by class
		for node in get_tree().get_nodes_in_group(""):
			pass
		return null
	var nearest = null
	var nearest_dist = INF
	for p in players:
		var d = global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest

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
		var speed = body.linear_velocity.length()
		var damage_amount = speed * 5.0
		
		print(">>> ", monster_name, " HIT BY VEHICLE at speed ", speed, " m/s! Damage: ", damage_amount)
		take_damage(damage_amount)
		
		# Apply knockback away from the vehicle
		var knockback_dir = (global_position - body.global_position).normalized()
		velocity = knockback_dir * speed * 2.0 + Vector3(0, 5.0, 0)

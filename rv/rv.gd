extends VehicleBody3D
class_name RV

@export var max_engine_force: float = 20000.0 # Massive starting torque for 3.5 tons!
@export var max_speed: float = 35.0 # Max speed in m/s (~126 km/h)
@export var max_braking_force: float = 300.0 # Heavy brakes
@export var max_steering: float = 0.6 
@export var is_player_driving: bool = false

# Artificially lower the center of mass so the tall RV doesn't flip easily
@export var center_of_mass_offset: Vector3 = Vector3(0, -0.8, 0)

# --- LOCAL STORAGE & POWER SYSTEMS ---
signal inventory_changed(item_name: String, new_amount: int)

var inventory: Dictionary = {
	"Metal Parts": 0,
	"Unrefined Fuel": 0,
	"Unknown Material": 0
}

var current_fuel: float = 100.0
var max_fuel: float = 100.0
var current_power: float = 100.0
var max_power: float = 100.0
# -----------------------------------

func _ready():
	# Godot 4 VehicleBody3D center of mass can be adjusted via mass properties, 
	# but setting it dynamically here ensures it's always applied safely.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	
	add_to_group("rv")

# --- INVENTORY MANAGEMENT ---
func add_item(item_name: String, amount: int):
	if not inventory.has(item_name):
		inventory[item_name] = 0
		
	inventory[item_name] += amount
	inventory_changed.emit(item_name, inventory[item_name])
	
	print("RV_Storage: Added ", amount, "x ", item_name, " (Total: ", inventory[item_name], ")")

func has_materials(costs: Dictionary) -> bool:
	for item_name in costs:
		if get_item_count(item_name) < costs[item_name]:
			return false
	return true
	
func deduct_materials(costs: Dictionary) -> bool:
	if not has_materials(costs): return false
	
	for item_name in costs:
		inventory[item_name] -= costs[item_name]
		inventory_changed.emit(item_name, inventory[item_name])
	return true

func get_item_count(item_name: String) -> int:
	return inventory.get(item_name, 0)
	
func get_all_items() -> Dictionary:
	return inventory.duplicate()
# -----------------------------------

func set_driving_state(state: bool):
	is_player_driving = state

func _physics_process(delta):
	var throttle = 0.0
	var braking = 0.0
	var steer_left = 0.0
	var steer_right = 0.0
	
	# 1. Input Collection
	if is_player_driving:
		if Input.is_physical_key_pressed(KEY_W): throttle = 1.0
		if Input.is_physical_key_pressed(KEY_S): braking = 1.0
		if Input.is_physical_key_pressed(KEY_A): steer_left = 1.0
		if Input.is_physical_key_pressed(KEY_D): steer_right = 1.0
		if Input.is_physical_key_pressed(KEY_SPACE): braking = 1.0 # Handbrake
		
	# Remote Control / Testing (Arrow Keys)
	if Input.is_physical_key_pressed(KEY_UP): throttle = 1.0
	if Input.is_physical_key_pressed(KEY_DOWN): braking = 1.0
	if Input.is_physical_key_pressed(KEY_LEFT): steer_left = 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT): steer_right = 1.0
	
	var has_input = throttle > 0.0 or braking > 0.0 or steer_left > 0.0 or steer_right > 0.0

	if not is_player_driving and not has_input:
		brake = max_braking_force * 2.0 # Parking brake
		engine_force = 0.0
		steering = 0.0
		return
		
	# Physics calculations
	var fwd_speed = abs(linear_velocity.dot(transform.basis.z))
	
	# 2. Dynamic Steering (Less steering at high speeds to prevent rolling)
	var speed_factor = clamp(fwd_speed / max_speed, 0.0, 1.0)
	var dynamic_max_steer = lerp(max_steering, max_steering * 0.3, speed_factor)
	var target_steering = (steer_left - steer_right) * dynamic_max_steer
	steering = lerp(steering, target_steering, 5.0 * delta)
	
	# 3. Torque Curve (High power at slow speeds for hills, zero power at top speed)
	if throttle > 0.0:
		var torque_multiplier = 1.0 - speed_factor
		# If we are reversing, limit throttle severely to avoid crazy backward speeds
		if linear_velocity.dot(transform.basis.z) > 1.0: 
			torque_multiplier *= 0.3
			
		engine_force = throttle * max_engine_force * max(0.1, torque_multiplier)
		brake = 0.0
		
	elif braking > 0.0:
		# Braking or Reversing
		var moving_forward = linear_velocity.dot(transform.basis.z) < -0.1
		
		if moving_forward:
			# Apply brakes
			engine_force = 0.0
			brake = braking * max_braking_force
		else:
			# Reverse (with much less power than forward)
			brake = 0.0
			engine_force = braking * max_engine_force * 0.3
	else:
		# Engine braking / rolling
		engine_force = 0.0
		brake = 2.0

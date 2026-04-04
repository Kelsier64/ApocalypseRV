extends VehicleBody3D
class_name Chassis

@export var max_engine_force: float = 5000.0
@export var max_speed: float = 35.0
@export var max_braking_force: float = 300.0
@export var max_steering: float = 0.6
@export var is_player_driving: bool = false
@export var center_of_mass_offset: Vector3 = Vector3(0, -0.8, 0)

# --- WHEEL SLOT SYSTEM ---
# Godot VehicleBody3D convention: -Z = forward, +X = left
const WHEEL_SLOTS: Array[Dictionary] = [
	{"name": "Wheel_FL", "position": Vector3(1.5, -0.5, -3.75), "steering": true, "traction": false},
	{"name": "Wheel_FR", "position": Vector3(-1.5, -0.5, -3.75), "steering": true, "traction": false},
	{"name": "Wheel_RL", "position": Vector3(1.5, -0.5, 3.0), "steering": false, "traction": true},
	{"name": "Wheel_RR", "position": Vector3(-1.5, -0.5, 3.0), "steering": false, "traction": true},
]
const WHEEL_HITBOX_SCRIPT: String = "res://rv/wheel_hitbox.gd"
const WHEEL_PROP_SCENE: String = "res://props/wheel.tscn"
const EMPTY_GAS_CAN_SCENE: String = "res://props/gas_can_empty.tscn"
const EMPTY_GAS_CAN_ITEM_NAME: String = "Gasoline Can (Empty)"
const WHEEL_RADIUS: float = 0.7
const WHEEL_WIDTH: float = 0.5

@export var pre_install_wheels: bool = true

var installed_wheels: Array = [null, null, null, null]

# --- INVENTORY & POWER ---
signal inventory_changed(item_name: String, new_amount: int)
signal fuel_changed(current: float, max_value: float)
signal power_changed(current: float, max_value: float)

var inventory: Dictionary = {
	"Metal Parts": 0,
	"Unrefined Fuel": 0,
	"Unknown Material": 0
}

var current_fuel: float = 100.0
var max_fuel: float = 100.0
var current_power: float = 100.0
var max_power: float = 100.0

@export var fuel_idle_burn_per_second: float = 0.04
@export var fuel_drive_burn_per_second: float = 0.9
@export var power_charge_per_second_driving: float = 0.8
@export var power_parked_drain_per_second: float = 0.15
@export var fuel_per_gas_can: float = 30.0

@export_group("Durability")
@export var max_chassis_health: float = 450.0
var current_chassis_health: float = 450.0
var chassis_destroyed: bool = false

func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	add_to_group("rv")
	add_to_group("chassis")
	add_to_group("monster_damageable")
	current_fuel = clampf(current_fuel, 0.0, max_fuel)
	current_power = clampf(current_power, 0.0, max_power)
	current_chassis_health = clampf(current_chassis_health, 0.0, max_chassis_health)
	fuel_changed.emit(current_fuel, max_fuel)
	power_changed.emit(current_power, max_power)
	if pre_install_wheels:
		for i in range(WHEEL_SLOTS.size()):
			_create_wheel_at(i)

func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	if chassis_destroyed:
		return

	current_chassis_health = maxf(current_chassis_health - amount, 0.0)
	print("Chassis took ", amount, " damage. HP: ", current_chassis_health, "/", max_chassis_health)

	if current_chassis_health <= 0.0:
		chassis_destroyed = true
		is_player_driving = false
		engine_force = 0.0
		brake = max_braking_force
		print("Chassis destroyed!")

func refuel_from_player(player: Node3D) -> void:
	if not player or not player.has_method("get_active_item_name"):
		return

	if player.get_active_item_name() != "Gasoline Can":
		print("Chassis: Need a Gasoline Can to refuel.")
		return

	if current_fuel >= max_fuel - 0.01:
		print("Chassis: Fuel tank is already full.")
		return

	var added := add_fuel(fuel_per_gas_can)
	if added <= 0.0:
		return

	if player.has_method("consume_active_item"):
		player.consume_active_item()
	if player.has_method("add_item"):
		player.add_item(EMPTY_GAS_CAN_ITEM_NAME, false, EMPTY_GAS_CAN_SCENE)
	print("Chassis: Refueled +", snappedf(added, 0.01), " fuel.")

# --- INVENTORY MANAGEMENT ---
func add_item(item_name: String, amount: int) -> void:
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

# --- DRIVING ---
func set_driving_state(state: bool) -> void:
	is_player_driving = state

func consume_fuel(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if current_fuel + 0.0001 < amount:
		return false
	_set_fuel(current_fuel - amount)
	return true

func add_fuel(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := current_fuel
	_set_fuel(current_fuel + amount)
	return current_fuel - before

func consume_power(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if current_power + 0.0001 < amount:
		return false
	_set_power(current_power - amount)
	return true

func add_power(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := current_power
	_set_power(current_power + amount)
	return current_power - before

func has_usable_power(required: float = 0.01) -> bool:
	return current_power >= maxf(required, 0.0)

func step_energy_system(drive_input: float, braking_input: float, steering_input: float, delta: float) -> bool:
	if delta <= 0.0:
		return true

	_run_generators(delta)

	var drive_intensity := clampf(drive_input, 0.0, 1.0)
	var wants_drive_force := drive_intensity > 0.0

	if not wants_drive_force:
		if not consume_power(power_parked_drain_per_second * delta):
			_set_power(0.0)
		return true

	var fuel_needed := (fuel_idle_burn_per_second + fuel_drive_burn_per_second * drive_intensity) * delta

	if current_fuel + 0.0001 < fuel_needed:
		return false

	consume_fuel(fuel_needed)
	add_power(power_charge_per_second_driving * drive_intensity * delta)
	return true

func _set_fuel(value: float) -> void:
	var next := clampf(value, 0.0, max_fuel)
	if absf(next - current_fuel) <= 0.0001:
		return
	current_fuel = next
	fuel_changed.emit(current_fuel, max_fuel)

func _set_power(value: float) -> void:
	var next := clampf(value, 0.0, max_power)
	if absf(next - current_power) <= 0.0001:
		return
	current_power = next
	power_changed.emit(current_power, max_power)

func _run_generators(delta: float) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return

	for generator in tree.get_nodes_in_group("rv_power_generators"):
		if not is_instance_valid(generator):
			continue
		if not generator.has_method("get_connected_rv"):
			continue
		if generator.get_connected_rv() != self:
			continue
		if generator.has_method("generate_power"):
			generator.generate_power(self, delta)

func _physics_process(delta: float) -> void:
	var throttle: float = 0.0
	var braking_input: float = 0.0
	var steer_left: float = 0.0
	var steer_right: float = 0.0

	if is_player_driving:
		if Input.is_physical_key_pressed(KEY_W): throttle = 1.0
		if Input.is_physical_key_pressed(KEY_S): braking_input = 1.0
		if Input.is_physical_key_pressed(KEY_A): steer_left = 1.0
		if Input.is_physical_key_pressed(KEY_D): steer_right = 1.0
		if Input.is_physical_key_pressed(KEY_SPACE): braking_input = 1.0

	# Remote Control / Testing (Arrow Keys)
	if Input.is_physical_key_pressed(KEY_UP): throttle = 1.0
	if Input.is_physical_key_pressed(KEY_DOWN): braking_input = 1.0
	if Input.is_physical_key_pressed(KEY_LEFT): steer_left = 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT): steer_right = 1.0

	var has_input := throttle > 0.0 or braking_input > 0.0 or steer_left > 0.0 or steer_right > 0.0

	if not is_player_driving and not has_input:
		step_energy_system(0.0, 0.0, 0.0, delta)
		brake = max_braking_force * 2.0
		engine_force = 0.0
		steering = 0.0
		return

	# Forward direction: -Z (Godot convention)
	var forward_dir: Vector3 = -transform.basis.z
	var fwd_speed: float = absf(linear_velocity.dot(forward_dir))

	var speed_factor := clampf(fwd_speed / max_speed, 0.0, 1.0)
	var dynamic_max_steer := lerpf(max_steering, max_steering * 0.3, speed_factor)
	var target_steering := (steer_left - steer_right) * dynamic_max_steer
	steering = lerpf(steering, target_steering, 5.0 * delta)
	var moving_forward := linear_velocity.dot(forward_dir) > 0.1
	var reverse_drive_intent := braking_input > 0.0 and not moving_forward
	var drive_intensity := throttle
	if reverse_drive_intent:
		drive_intensity = maxf(drive_intensity, braking_input)

	var can_apply_drive_force := step_energy_system(drive_intensity, braking_input, absf(steer_left - steer_right), delta)

	if throttle > 0.0:
		if not can_apply_drive_force:
			engine_force = 0.0
			brake = 2.0
			return
		var torque_multiplier := 1.0 - speed_factor
		# Reduce torque when moving backward while accelerating forward
		if linear_velocity.dot(forward_dir) < -1.0:
			torque_multiplier *= 0.3
		engine_force = -throttle * max_engine_force * max(0.1, torque_multiplier)
		brake = 0.0
	elif braking_input > 0.0:
		if moving_forward:
			engine_force = 0.0
			brake = braking_input * max_braking_force
		else:
			if not can_apply_drive_force:
				engine_force = 0.0
				brake = 2.0
				return
			brake = 0.0
			engine_force = braking_input * max_engine_force * 0.3
	else:
		engine_force = 0.0
		brake = 2.0

# --- WHEEL MANAGEMENT ---
func install_wheel() -> bool:
	for i in range(installed_wheels.size()):
		if installed_wheels[i] == null:
			_create_wheel_at(i)
			return true
	return false

func remove_wheel(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= installed_wheels.size():
		return
	var wheel: VehicleWheel3D = installed_wheels[slot_index]
	if wheel == null:
		return
	installed_wheels[slot_index] = null
	wheel.queue_free()

func get_installed_wheel_count() -> int:
	var count: int = 0
	for w in installed_wheels:
		if w != null:
			count += 1
	return count

func _create_wheel_at(slot_index: int) -> void:
	if installed_wheels[slot_index] != null:
		return

	var slot: Dictionary = WHEEL_SLOTS[slot_index]

	var wheel := VehicleWheel3D.new()
	wheel.name = slot["name"]
	wheel.position = slot["position"]
	wheel.use_as_traction = slot["traction"]
	wheel.use_as_steering = slot["steering"]
	wheel.wheel_friction_slip = 3.5
	wheel.suspension_travel = 0.5
	wheel.suspension_stiffness = 40.0
	wheel.suspension_max_force = 15000.0
	wheel.damping_compression = 0.88
	wheel.damping_relaxation = 0.95
	wheel.wheel_radius = WHEEL_RADIUS

	# Visual mesh
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WheelMesh"
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.height = WHEEL_WIDTH
	cyl_mesh.top_radius = WHEEL_RADIUS
	cyl_mesh.bottom_radius = WHEEL_RADIUS
	mesh_instance.mesh = cyl_mesh
	mesh_instance.transform = Transform3D(
		Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)),
		Vector3.ZERO
	)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15, 1)
	mesh_instance.set_surface_override_material(0, mat)
	wheel.add_child(mesh_instance)

	# Hitbox for player removal interaction
	# Layer 2 = interaction-only, not seen by chassis physics (mask=1)
	var hitbox := StaticBody3D.new()
	hitbox.name = "WheelHitbox"
	hitbox.collision_layer = 2
	hitbox.collision_mask = 0
	hitbox.set_script(load(WHEEL_HITBOX_SCRIPT))
	hitbox.slot_index = slot_index
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = WHEEL_RADIUS + 0.1
	col_shape.shape = sphere
	hitbox.add_child(col_shape)
	wheel.add_child(hitbox)

	add_child(wheel)
	installed_wheels[slot_index] = wheel

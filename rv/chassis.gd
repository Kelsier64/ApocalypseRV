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
const WHEEL_RADIUS: float = 0.7
const WHEEL_WIDTH: float = 0.5

@export var pre_install_wheels: bool = true

var installed_wheels: Array = [null, null, null, null]

# --- INVENTORY & POWER ---
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

func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	add_to_group("rv")
	add_to_group("chassis")
	if pre_install_wheels:
		for i in range(WHEEL_SLOTS.size()):
			_create_wheel_at(i)

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

	if throttle > 0.0:
		var torque_multiplier := 1.0 - speed_factor
		# Reduce torque when moving backward while accelerating forward
		if linear_velocity.dot(forward_dir) < -1.0:
			torque_multiplier *= 0.3
		engine_force = -throttle * max_engine_force * max(0.1, torque_multiplier)
		brake = 0.0
	elif braking_input > 0.0:
		var moving_forward := linear_velocity.dot(forward_dir) > 0.1
		if moving_forward:
			engine_force = 0.0
			brake = braking_input * max_braking_force
		else:
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

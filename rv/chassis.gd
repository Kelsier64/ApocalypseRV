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
const EMPTY_GAS_CAN_ITEM_NAME: String = ItemNames.GAS_CAN_EMPTY
const WHEEL_RADIUS: float = 0.7
const WHEEL_WIDTH: float = 0.5

@export var wheel_wear_per_meter: float = 0.002
@export var pre_install_wheels: bool = true

var installed_wheels: Array = [null, null, null, null]
var wheel_health: Array[float] = [100.0, 100.0, 100.0, 100.0]
var wheel_ids: Array[String] = [InstanceIds.create(), InstanceIds.create(), InstanceIds.create(), InstanceIds.create()]

# --- INVENTORY & POWER ---
signal inventory_changed(item_name: String, new_amount: int)
signal fuel_changed(current: float, max_value: float)
signal power_changed(current: float, max_value: float)

var storage := MaterialStorage.new()
var inventory: Dictionary:
	get: return storage.items
	set(value): storage.items = value.duplicate(true)

var persistent_id: String = InstanceIds.create()
var energy := VehicleEnergy.new(self)
@export var material_capacity: int = 300
@export var item_capacity: int = 24
@export var max_fuel: float = 100.0
@export var current_fuel: float = 100.0
var stored_items: Array[Dictionary] = []

var current_power: float:
	get: return energy.battery.charge if energy.battery else 0.0
	set(value):
		if energy.battery: energy.battery.charge = clampf(value, 0.0, energy.battery.capacity)
var max_power: float:
	get: return energy.battery.capacity if energy.battery else 0.0
	set(value):
		if energy.battery: energy.battery.capacity = maxf(value, 0.0)
var handbrake: bool = true
var gear: int = 1
var base_mass: float = 3000.0
var control_override: Dictionary = {}
@export var allow_test_controls: bool = false

@export var fuel_idle_burn_per_second: float = 0.04
@export var fuel_drive_burn_per_second: float = 0.9
@export var power_parked_drain_per_second: float = 0.15
@export var fuel_per_gas_can: float = 30.0

@export_group("Durability")
@export var max_chassis_health: float = 450.0
var current_chassis_health: float = 450.0
var chassis_destroyed: bool = false
signal equipment_changed
var equipment_registry: Array[Node] = []

func register_equipment(equipment: Node) -> void:
	if not equipment_registry.has(equipment):
		equipment_registry.append(equipment)
		equipment_changed.emit()

func unregister_equipment(equipment: Node) -> void:
	equipment_registry.erase(equipment)
	equipment_changed.emit()

func get_equipment() -> Array[Node]:
	var result: Array[Node] = []
	for equipment in equipment_registry:
		if is_instance_valid(equipment) and not equipment.is_queued_for_deletion() and is_ancestor_of(equipment):
			result.append(equipment)
	return result

func _ready() -> void:
	base_mass = mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	add_to_group(Groups.RV)
	add_to_group(Groups.CHASSIS)
	add_to_group(Groups.MONSTER_DAMAGEABLE)
	for child in find_children("*", "Equipment", true, false):
		register_equipment(child)
	current_fuel = clampf(current_fuel, 0.0, max_fuel)
	current_power = clampf(current_power, 0.0, max_power)
	current_chassis_health = clampf(current_chassis_health, 0.0, max_chassis_health)
	fuel_changed.emit(current_fuel, max_fuel)
	power_changed.emit(current_power, max_power)
	for slot_index in range(WHEEL_SLOTS.size()):
		_create_wheel_socket(slot_index)
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
		energy.engine_running = false
		is_player_driving = false
		engine_force = 0.0
		brake = max_braking_force
		print("Chassis destroyed!")

# --- INVENTORY MANAGEMENT ---
func update_storage_capacity() -> void:
	storage.capacity = maxi(0, material_capacity)

func add_item(item_name: String, amount: int) -> bool:
	return deposit_materials({item_name: amount})

func deposit_materials(amounts: Dictionary, refund: bool = false) -> bool:
	update_storage_capacity()
	if not storage.deposit(amounts, refund):
		return false
	for key in amounts:
		inventory_changed.emit(key, storage.items[key])
	return true

func has_materials(costs: Dictionary) -> bool:
	return storage.has_materials(costs)

func deduct_materials(costs: Dictionary) -> bool:
	if not storage.deduct(costs):
		return false
	for key in costs:
		inventory_changed.emit(key, storage.items[key])
	return true

func get_item_count(item_name: String) -> int:
	return int(storage.items.get(item_name, 0))

func get_all_items() -> Dictionary:
	return storage.items.duplicate()

func get_battery_socket() -> BatterySocket:
	# One connected battery per vehicle; no fallback battery lives in the chassis.
	for device in get_equipment():
		if device is BatterySocket and device.can_operate() and device.installed_battery:
			return device
	for device in get_equipment():
		if device is BatterySocket and device.can_operate():
			return device
	return null

func store_player_item(player: Node3D, index: int) -> bool:
	if stored_items.size() >= item_capacity or index < 0 or index >= player.inventory.items.size():
		return false
	var item: Dictionary = player.inventory.items[index]
	if item.get("state", {}).has("materials"): return false
	stored_items.append(item.duplicate(true))
	player.inventory.items.remove_at(index)
	player.inventory.active_slot = mini(player.inventory.active_slot, maxi(0, player.inventory.items.size() - 1))
	player.refresh_inventory()
	return true

func take_stored_item(player: Node3D, index: int) -> bool:
	if index < 0 or index >= stored_items.size(): return false
	var item: Dictionary = stored_items[index]
	if not player.add_item(item.name, item.is_large, item.scene_path, item.state): return false
	stored_items.remove_at(index)
	player.refresh_inventory()
	return true

# --- DRIVING ---
func set_driving_state(state: bool) -> void:
	is_player_driving = state and not chassis_destroyed

func consume_fuel(amount: float) -> bool:
	if amount < 0.0 or not is_finite(amount) or current_fuel + 0.000001 < amount:
		return false
	current_fuel -= amount
	fuel_changed.emit(current_fuel, max_fuel)
	return true

func add_fuel(amount: float) -> float:
	if amount <= 0.0 or not is_finite(amount):
		return 0.0
	var accepted := minf(amount, maxf(0.0, max_fuel - current_fuel))
	current_fuel += accepted
	fuel_changed.emit(current_fuel, max_fuel)
	return accepted

func consume_power(amount: float) -> bool:
	var result := energy.consume_power(amount)
	if result: power_changed.emit(current_power, max_power)
	return result

func add_power(amount: float) -> float:
	var added := energy.add_power(amount)
	if added > 0.0: power_changed.emit(current_power, max_power)
	return added

func has_usable_power(required: float = 0.01) -> bool:
	return current_power >= maxf(required, 0.0)

func step_energy_system(drive_input: float, _braking_input: float, _steering_input: float, delta: float) -> bool:
	var result := energy.step(self, drive_input, delta)
	fuel_changed.emit(current_fuel, max_fuel)
	power_changed.emit(current_power, max_power)
	return result

func set_engine_running(running: bool) -> bool:
	if running and (chassis_destroyed or current_fuel <= 0.0):
		return false
	energy.engine_running = running
	return true

func exchange_battery(player: Node3D, socket: BatterySocket = null) -> bool:
	if socket == null: socket = get_battery_socket()
	if socket == null or socket.get_connected_rv() != self or not socket.can_operate() or socket.has_other_battery() or linear_velocity.length() > 0.5 or player.get_active_item_name() != ItemNames.BATTERY:
		return false
	var active: Dictionary = player.inventory.active_item()
	if not active.get("state", {}).has("battery"):
		return false
	var next := BatteryState.new(active.state.battery)
	var old := socket.installed_battery
	if old:
		player.inventory.items[player.inventory.active_slot] = {"name": ItemNames.BATTERY, "is_large": false,
			"scene_path": "res://props/battery.tscn", "state": {"id": old.id, "battery": old.snapshot()}}
	else:
		player.inventory.consume_active()
	socket.installed_battery = next
	player.refresh_inventory()
	power_changed.emit(current_power, max_power)
	return true

func remove_battery_to_player(player: Node3D, socket: BatterySocket = null) -> bool:
	if socket == null: socket = get_battery_socket()
	if socket == null or socket.get_connected_rv() != self or not socket.can_operate() or linear_velocity.length() > 0.5 or socket.installed_battery == null:
		return false
	var old := socket.installed_battery
	if not player.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"id": old.id, "battery": old.snapshot()}):
		return false
	socket.installed_battery = null
	power_changed.emit(0.0, 0.0)
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

func _physics_process(delta: float) -> void:
	update_load()
	for index in range(4):
		var wheel: VehicleWheel3D = installed_wheels[index]
		if wheel and wheel.is_in_contact():
			wheel_health[index] = maxf(0.0, wheel_health[index] - linear_velocity.length() * delta * wheel_wear_per_meter)
			_update_wheel_condition(index)
	var throttle := 0.0
	var braking_input := 0.0
	var turn := 0.0
	if is_player_driving and not chassis_destroyed:
		throttle = Input.get_action_strength("move_forward")
		braking_input = Input.get_action_strength("move_back")
		turn = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	if allow_test_controls and not control_override.is_empty():
		throttle = control_override.get("throttle", 0.0)
		braking_input = control_override.get("brake", 0.0)
		turn = control_override.get("steering", 0.0)
	var drive := throttle if gear != 0 and not handbrake and not chassis_destroyed else 0.0
	var can_drive := step_energy_system(drive, braking_input, absf(turn), delta)
	var forward := -global_transform.basis.z
	var speed_factor := clampf(absf(linear_velocity.dot(forward)) / max_speed, 0.0, 1.0)
	var gear_limit: float = [8.0, 16.0, 25.0, max_speed][clampi(gear - 1, 0, 3)]
	var torque := maxf(0.1, 1.0 - absf(linear_velocity.dot(forward)) / gear_limit)
	steering = lerpf(steering, turn * lerpf(max_steering, max_steering * 0.3, speed_factor), minf(5.0 * delta, 1.0))
	engine_force = 0.0
	brake = max_braking_force if handbrake or chassis_destroyed else braking_input * max_braking_force
	if can_drive and drive > 0.0 and braking_input == 0.0:
		engine_force = -drive * max_engine_force * torque * (1.0 if gear > 0 else -0.3)
	if not is_player_driving and control_override.is_empty():
		engine_force = 0.0

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

	var wheel_visual: Node3D = preload("res://rv/visuals/wheel.tscn").instantiate()
	wheel_visual.name = "WheelMesh"
	# The visual scene uses a 0.5 m radius; retain the existing wheel physics.
	wheel_visual.scale = Vector3(WHEEL_WIDTH / 0.4, WHEEL_RADIUS / 0.5, WHEEL_RADIUS / 0.5)
	wheel.add_child(wheel_visual)


	add_child(wheel)
	installed_wheels[slot_index] = wheel

func needs_repair() -> bool:
	return current_chassis_health < max_chassis_health

func repair_health(amount: float) -> void:
	current_chassis_health = minf(max_chassis_health, current_chassis_health + maxf(amount, 0.0))
	chassis_destroyed = current_chassis_health <= 0.0

func _create_wheel_socket(slot_index: int) -> void:
	var hitbox := StaticBody3D.new()
	hitbox.name = "WheelSocket%d" % slot_index
	hitbox.position = WHEEL_SLOTS[slot_index].position
	hitbox.collision_layer = 2
	hitbox.collision_mask = 0
	hitbox.set_script(load(WHEEL_HITBOX_SCRIPT))
	hitbox.slot_index = slot_index
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = WHEEL_RADIUS + 0.1
	shape.shape = sphere
	hitbox.add_child(shape)
	add_child(hitbox)

func install_wheel_from_player(player: Node3D, slot: int = -1) -> bool:
	if linear_velocity.length() > 0.5 or energy.engine_running or player.get_active_item_name() != ItemNames.WHEEL:
		return false
	if slot < 0:
		slot = installed_wheels.find(null)
	if slot < 0 or slot >= 4 or installed_wheels[slot] != null:
		return false
	var state: Dictionary = player.inventory.active_item().get("state", {})
	wheel_health[slot] = clampf(float(state.get("condition", 100.0)), 0.0, 100.0)
	wheel_ids[slot] = state.get("id", InstanceIds.create())
	_create_wheel_at(slot)
	_update_wheel_condition(slot)
	player.consume_active_item()
	return true

func remove_wheel_to_world(slot: int) -> bool:
	if slot < 0 or slot >= 4 or installed_wheels[slot] == null or linear_velocity.length() > 0.5 or energy.engine_running:
		return false
	var scene := load(WHEEL_PROP_SCENE) as PackedScene
	var container := WorldEntities.get_container(self)
	if scene == null or container == null:
		return false
	var prop := scene.instantiate() as Prop
	prop.restore_item_state({"id": wheel_ids[slot], "condition": wheel_health[slot]})
	var outward: Vector3 = global_basis.x * signf(WHEEL_SLOTS[slot].position.x)
	var output: Vector3 = to_global(WHEEL_SLOTS[slot].position) + outward * 1.1 + Vector3.UP
	container.add_child(prop)
	prop.global_position = output
	prop.linear_velocity = ClimbMath.point_velocity(self, output) + outward
	remove_wheel(slot)
	return true

func _update_wheel_condition(slot: int) -> void:
	var wheel: VehicleWheel3D = installed_wheels[slot]
	if wheel:
		wheel.wheel_friction_slip = lerpf(0.7, 3.5, wheel_health[slot] / 100.0)
		wheel.use_as_traction = WHEEL_SLOTS[slot].traction and wheel_health[slot] > 0.0

func update_load() -> void:
	var total := base_mass
	var weighted := center_of_mass_offset * base_mass
	for device in get_equipment():
		if not device.is_being_placed and not device.is_destroyed:
			total += device.mass
			weighted += to_local(device.global_position) * device.mass
		if device is BatterySocket and device.installed_battery:
			total += device.installed_battery.weight
			weighted += to_local(device.global_position) * device.installed_battery.weight
	if not is_equal_approx(mass, total): mass = total
	var next_center := weighted / total
	if not center_of_mass.is_equal_approx(next_center): center_of_mass = next_center

func set_gear(next: int) -> bool:
	next = clampi(next, -1, 4)
	if next < 0 and linear_velocity.length() > 0.5:
		return false
	if gear < 0 and next > 0 and linear_velocity.length() > 0.5:
		return false
	gear = next
	return true

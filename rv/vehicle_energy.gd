extends RefCounted
class_name VehicleEnergy
## Authoritative storage. Chassis compatibility properties delegate here.

var _vehicle: WeakRef
var battery: BatteryState:
	get:
		var rv: Node = _vehicle.get_ref() if _vehicle else null
		var socket: BatterySocket = rv.get_battery_socket() if rv else null
		return socket.installed_battery if socket else null
	set(value):
		var rv: Node = _vehicle.get_ref() if _vehicle else null
		var socket: BatterySocket = rv.get_battery_socket() if rv else null
		if socket: socket.installed_battery = value

func _init(vehicle: Node) -> void:
	_vehicle = weakref(vehicle)

var engine_running: bool = false
var generated_rate: float = 0.0
var load_rate: float = 0.0
var _consumed: float = 0.0

func consume_power(amount: float) -> bool:
	if amount < 0.0 or not is_finite(amount):
		return false
	if amount == 0.0:
		return true
	if battery == null or battery.charge + 0.000001 < amount:
		return false
	battery.charge = maxf(0.0, battery.charge - amount)
	_consumed += amount
	return true

func add_power(amount: float) -> float:
	if battery == null or amount <= 0.0 or not is_finite(amount):
		return 0.0
	var accepted := minf(amount, battery.capacity - battery.charge)
	battery.charge += accepted
	return accepted

func step(rv: Node, drive_intensity: float, delta: float) -> bool:
	if delta <= 0.0:
		return engine_running
	generated_rate = 0.0
	_consumed = 0.0
	if rv.chassis_destroyed:
		engine_running = false
	if engine_running:
		var required: float = (rv.fuel_idle_burn_per_second + rv.fuel_drive_burn_per_second * clampf(drive_intensity, 0.0, 1.0)) * delta
		if not rv.consume_fuel(required):
			rv.consume_fuel(rv.current_fuel)
			engine_running = false
	# Stable per-vehicle order: charging, standby, then registered work by ID.
	var equipment: Array[Node] = rv.get_equipment()
	equipment.sort_custom(func(a: Node, b: Node) -> bool: return a.persistent_id < b.persistent_id)
	if engine_running:
		for device in equipment:
			if device.can_operate() and device.has_method("generate_power"):
				var before: float = rv.current_power
				device.generate_power(rv, delta)
				generated_rate += (rv.current_power - before) / delta
	var standby: float = rv.power_parked_drain_per_second * delta
	if not consume_power(standby) and battery:
		_consumed += battery.charge
		battery.charge = 0.0
	for device in equipment:
		if is_instance_valid(device) and device.can_operate() and device.has_method("step_work"):
			device.step_work(delta)
	load_rate = _consumed / delta
	return engine_running

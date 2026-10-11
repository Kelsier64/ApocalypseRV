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
var charging_enabled: bool = true
var charging: bool = false
var fuel_reserve: float = 5.0
var recharge_below: float = 0.8
var fuel_consumption_per_second: float = 0.6
var power_generation_per_second: float = 1.8
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

func charging_snapshot() -> Dictionary:
	return {"enabled": charging_enabled, "charging": charging, "fuel_reserve": fuel_reserve, "recharge_below": recharge_below}

func restore_charging(data: Dictionary) -> void:
	charging_enabled = data.get("enabled", true)
	charging = data.get("charging", false) and charging_enabled
	fuel_reserve = data.get("fuel_reserve", 5.0)
	recharge_below = data.get("recharge_below", 0.8)
	generated_rate = 0.0
	load_rate = 0.0

func charging_status() -> String:
	var rv: Node = _vehicle.get_ref()
	if not charging_enabled: return "RV 充電已關閉"
	if not engine_running: return "引擎未運轉"
	if battery == null: return "未安裝可用電池"
	if rv.current_fuel <= fuel_reserve: return "已達保留油量；引擎仍消耗運轉燃油"
	if battery.charge >= battery.capacity - 0.001: return "電池已充滿"
	if not charging: return "等待充電門檻"
	return "RV 充電中：最高 +%.1f 電量／秒" % power_generation_per_second

func _charge(rv: Node, delta: float) -> void:
	if not charging_enabled or not engine_running or battery == null:
		charging = false
		return
	if battery.charge >= battery.capacity - 0.001:
		charging = false
	if battery.charge <= battery.capacity * recharge_below:
		charging = true
	if not charging: return
	var full_power := power_generation_per_second * delta
	var full_fuel := fuel_consumption_per_second * delta
	if full_power <= 0.0 or full_fuel <= 0.0: return
	var available_fuel: float = maxf(rv.current_fuel - fuel_reserve, 0.0)
	var generated := minf(battery.capacity - battery.charge, full_power * clampf(available_fuel / full_fuel, 0.0, 1.0))
	if generated <= 0.0: return
	if rv.consume_fuel(full_fuel * generated / full_power):
		generated_rate = add_power(generated) / delta

func step(rv: Node, drive_intensity: float, delta: float) -> bool:
	if delta <= 0.0:
		return engine_running
	generated_rate = 0.0
	_consumed = 0.0
	if not rv.has_working_engine():
		engine_running = false
	if engine_running:
		var required: float = (rv.fuel_idle_burn_per_second + rv.fuel_drive_burn_per_second * clampf(drive_intensity, 0.0, 1.0)) * rv.get_engine().definition().fuel_multiplier * delta
		if not rv.consume_fuel(required):
			rv.consume_fuel(rv.current_fuel)
			engine_running = false
	# Built-in charging, standby, then registered work by stable per-vehicle ID.
	_charge(rv, delta)
	var equipment: Array[Node] = rv.get_equipment()
	equipment.sort_custom(func(a: Node, b: Node) -> bool: return a.persistent_id < b.persistent_id)
	var standby: float = rv.power_parked_drain_per_second * delta
	if not consume_power(standby) and battery:
		_consumed += battery.charge
		battery.charge = 0.0
	for device in equipment:
		if is_instance_valid(device) and device.can_operate() and device.has_method("step_work"):
			device.step_work(delta)
	var lights: float = (0.12 if rv.headlights_requested else 0.0) + (0.04 if rv.handbrake or rv.brake_input > 0.0 else 0.0) + (0.04 if rv.gear < 0 else 0.0)
	rv.lamps_powered = battery != null and battery.charge > 0.0 and consume_power(lights * delta)
	var strips := 0
	var benches := 0
	for device in equipment:
		if not device.can_operate(): continue
		if device is CabinLightStrip: strips += 1
		if device is CraftingStation: benches += 1
	var available := {"cabin": strips > 0, "work": benches > 0, "service": rv.engine_bay.hatch_open}
	var draws := {"cabin": rv.cabin_light_draw * strips, "work": rv.work_light_draw * benches, "service": rv.service_light_draw}
	for kind in rv.interior_requested:
		rv.interior_powered[kind] = rv.interior_requested[kind] and available[kind] and battery != null and battery.charge > 0.0 and consume_power(draws[kind] * delta)
	load_rate = _consumed / delta
	return engine_running

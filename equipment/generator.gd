extends Equipment

@export var fuel_consumption_per_second: float = 0.6
@export var power_generation_per_second: float = 1.8

@export var fuel_reserve: float = 5.0
@export_range(0.0, 1.0) var recharge_below: float = 0.8
var charging: bool = false

func _ready() -> void:
	super._ready()
	add_to_group(Groups.RV_POWER_GENERATORS)

func generate_power(rv: Node, delta: float) -> void:
	if not is_instance_valid(rv) or not can_operate() or not rv.energy.engine_running or delta <= 0.0:
		return
	if rv == null:
		return
	if not rv.has_method("consume_fuel") or not rv.has_method("add_power"):
		return
	if not ("current_power" in rv and "max_power" in rv and "current_fuel" in rv):
		return

	var current_power: float = float(rv.current_power)
	var max_power: float = float(rv.max_power)
	var current_fuel: float = maxf(float(rv.current_fuel) - fuel_reserve, 0.0)
	if max_power <= 0.0:
		return
	if current_power >= max_power - 0.001:
		charging = false
	if current_power <= max_power * recharge_below:
		charging = true
	if not charging:
		return

	var missing_power: float = max_power - current_power
	if missing_power <= 0.001:
		return

	var full_step_power := power_generation_per_second * delta
	var full_step_fuel := fuel_consumption_per_second * delta
	if full_step_power <= 0.0 or full_step_fuel <= 0.0:
		return

	var fuel_limited_power: float = full_step_power * clampf(current_fuel / full_step_fuel, 0.0, 1.0)
	var generated_power: float = minf(missing_power, fuel_limited_power)
	if generated_power <= 0.0:
		return

	var fuel_needed := full_step_fuel * (generated_power / full_step_power)
	if rv.consume_fuel(fuel_needed):
		rv.add_power(generated_power)

func get_status() -> String:
	var rv := get_connected_rv()
	if not can_operate(): return "Disabled or unmounted"
	if not rv.energy.engine_running: return "Engine off"
	if rv.energy.battery == null: return "No battery installed"
	if rv.current_fuel <= fuel_reserve: return "Fuel reserve reached; engine still burns idle fuel"
	if not charging: return "Waiting for charge threshold"
	return "Charging: up to +%.1f power/s" % power_generation_per_second

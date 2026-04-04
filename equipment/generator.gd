extends Equipment

@export var fuel_consumption_per_second: float = 0.6
@export var power_generation_per_second: float = 1.8

func _ready() -> void:
	super._ready()
	add_to_group("rv_power_generators")

func generate_power(rv: Node, delta: float) -> void:
	if delta <= 0.0:
		return
	if rv == null:
		return
	if not rv.has_method("consume_fuel") or not rv.has_method("add_power"):
		return
	if not ("current_power" in rv and "max_power" in rv and "current_fuel" in rv):
		return

	var current_power: float = float(rv.current_power)
	var max_power: float = float(rv.max_power)
	var current_fuel: float = float(rv.current_fuel)

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

extends RefCounted
class_name VehicleStatus
const IDS := ["engine", "fuel", "battery", "door", "brake", "tire", "ramp", "headlight"]
static func read(rv: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var engine: EngineState = rv.get_engine()
	var bad_engine := engine == null or engine.health <= 0.0
	rows.append({"id": "engine", "label": "Engine", "level": 3 if bad_engine else (2 if engine.health < engine.definition().max_health * 0.3 else 0), "message": rv.engine_start_reason() if bad_engine else "Engine durability low: stop and use an Engine Repair Kit"})
	rows.append({"id": "fuel", "label": "Fuel", "level": 0 if rv.unlimited_fuel else (3 if not rv.has_usable_fuel() else (2 if rv.current_fuel < rv.max_fuel * 0.15 else 0)), "message": "Fuel low: refill through the fuel inlet"})
	var electrical_fault: bool = not rv.has_usable_power(0.000001)
	rows.append({"id": "battery", "label": "Battery", "level": 3 if electrical_fault else (2 if not rv.unlimited_power and rv.current_power < rv.max_power * 0.2 else 0), "message": "Battery missing or empty: replace it or start the engine to charge" if electrical_fault else "Battery charge low"})
	var open_door: bool = rv.engine_bay.hatch_open or not rv.engine_bay.get_node("Hatch").stable()
	for device in rv.get_structures():
		if not device.is_destroyed and device.has_method("restore_angles"):
			for value in device.angles:
				if absf(value) > 0.02: open_door = true
	rows.append({"id": "door", "label": "Doors", "level": 3 if open_door else 0, "message": "Door or engine service hatch is open"})
	rows.append({"id": "brake", "label": "Parking brake", "level": 3 if rv.handbrake else 0, "message": "Parking brake applied"})
	var minimum := 100.0
	for hp in rv.wheel_health: minimum = minf(minimum, hp)
	rows.append({"id": "tire", "label": "Tires", "level": 3 if rv.get_installed_wheel_count() < 4 or minimum <= 0.0 else (2 if minimum < 30.0 else 0), "message": rv.tire_warning()})
	rows.append({"id": "ramp", "label": "Ramp", "level": 2 if rv.drive_blocked() else 0, "message": "Stow the ramp to drive. The engine can still charge the battery at idle."})
	rows.append({"id": "headlight", "label": "Headlights", "level": 1 if rv.headlights_requested and rv.lamps_powered else 0, "message": "Headlights on"})
	return rows
static func messages(rv: Node) -> String:
	var result := PackedStringArray()
	for row in read(rv):
		if row.level >= 2: result.append(row.message)
	return " · ".join(result)

extends RefCounted
class_name VehicleStatus
const IDS := ["engine", "fuel", "battery", "door", "brake", "tire", "ramp", "headlight"]
static func color(level: int) -> Color:
	return [Color(0.16, 0.22, 0.22), Color(0.35, 1.0, 0.65), Color(1.0, 0.68, 0.12), Color(1.0, 0.16, 0.1)][clampi(level, 0, 3)]
static func read(rv: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var engine: EngineState = rv.get_engine()
	var bad_engine := engine == null or engine.health <= 0.0
	rows.append({"id": "engine", "label": "引擎", "level": 3 if bad_engine else (2 if engine.health < engine.definition().max_health * 0.3 else 0), "message": rv.engine_start_reason() if bad_engine else "引擎低耐久：停穩後使用專用維修包"})
	rows.append({"id": "fuel", "label": "燃油", "level": 0 if rv.unlimited_fuel else (3 if not rv.has_usable_fuel() else (2 if rv.current_fuel < rv.max_fuel * 0.15 else 0)), "message": "燃油不足，請使用加油孔補充"})
	var electrical_fault: bool = not rv.has_usable_power(0.000001)
	rows.append({"id": "battery", "label": "充電", "level": 3 if electrical_fault else (2 if not rv.unlimited_power and rv.current_power < rv.max_power * 0.2 else 0), "message": "電池缺失／耗盡，請更換電池或發動引擎充電" if electrical_fault else "電池電量低"})
	var open_door: bool = rv.engine_bay.hatch_open or not rv.engine_bay.get_node("Hatch").stable()
	for device in rv.get_structures():
		if not device.is_destroyed and device.has_method("restore_angles"):
			for value in device.angles:
				if absf(value) > 0.02: open_door = true
	rows.append({"id": "door", "label": "車門", "level": 3 if open_door else 0, "message": "車門或引擎維修蓋未關"})
	rows.append({"id": "brake", "label": "手煞車", "level": 3 if rv.handbrake else 0, "message": "手煞車已拉起"})
	var minimum := 100.0
	for hp in rv.wheel_health: minimum = minf(minimum, hp)
	rows.append({"id": "tire", "label": "輪胎", "level": 3 if rv.get_installed_wheel_count() < 4 or minimum <= 0.0 else (2 if minimum < 30.0 else 0), "message": rv.tire_warning()})
	rows.append({"id": "ramp", "label": "坡板", "level": 2 if rv.drive_blocked() else 0, "message": "坡板未收妥，禁止驅動；仍可怠速發電"})
	rows.append({"id": "headlight", "label": "頭燈", "level": 1 if rv.headlights_requested and rv.lamps_powered else 0, "message": "頭燈已開啟"})
	return rows
static func messages(rv: Node) -> String:
	var result := PackedStringArray()
	for row in read(rv):
		if row.level >= 2: result.append(row.message)
	return " · ".join(result)

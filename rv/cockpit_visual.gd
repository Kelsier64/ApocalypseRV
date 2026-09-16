extends Node3D
## Presentation only; every instrument reads the chassis owned by this seat.
var warning_lamps: Dictionary = {}
func _ready() -> void:
	for i in range(VehicleStatus.IDS.size()):
		var id: String = VehicleStatus.IDS[i]
		var lamp := Sprite3D.new()
		lamp.texture = load("res://assets/rv_status/" + id + ".svg")
		lamp.pixel_size = 0.0009
		lamp.position = Vector3(-0.46 + i * 0.13, 1.36, -0.94)
		lamp.shaded = false
		add_child(lamp)
		warning_lamps[id] = lamp

@onready var seat: Equipment = get_parent()
@onready var steering_wheel: Node3D = $SteeringTilt/SteeringWheel
@onready var gear_lever: Node3D = $GearLever
@onready var parking_lever: Node3D = $ParkingLever

func _process(delta: float) -> void:
	var rv: Chassis = seat.get_connected_rv() as Chassis
	var connected := rv != null and seat.can_operate()
	var speed := rv.linear_velocity.length() * 3.6 if connected else 0.0
	var fuel := rv.current_fuel / maxf(rv.max_fuel, 1.0) if connected else 0.0
	var charge := rv.current_power / maxf(rv.max_power, 1.0) if connected else 0.0
	var gear := rv.gear if connected else 0
	var parked := rv.handbrake if connected else true
	var running := connected and rv.energy.engine_running
	var steer := -rv.steering * 3.5 if connected else 0.0
	steering_wheel.rotation.y = lerp_angle(steering_wheel.rotation.y, steer, minf(delta * 12.0, 1.0))
	gear_lever.rotation.x = lerp_angle(gear_lever.rotation.x, -0.28 if gear < 0 else (0.0 if gear == 0 else 0.23), minf(delta * 12.0, 1.0))
	gear_lever.rotation.z = lerp_angle(gear_lever.rotation.z, float(gear - 2) * 0.08 if gear > 0 else 0.0, minf(delta * 12.0, 1.0))
	parking_lever.rotation.x = lerp_angle(parking_lever.rotation.x, 0.55 if parked else 0.0, minf(delta * 12.0, 1.0))
	$SpeedNeedle.rotation.z = deg_to_rad(130.0 - clampf(speed / 140.0, 0.0, 1.0) * 260.0)
	$FuelNeedle.rotation.z = deg_to_rad(130.0 - clampf(fuel, 0.0, 1.0) * 260.0)
	$BatteryNeedle.rotation.z = deg_to_rad(130.0 - clampf(charge, 0.0, 1.0) * 260.0)
	$Readout.text = "%03.0f  %s" % [speed, "R" if gear < 0 else ("N" if gear == 0 else str(gear))]
	$EngineStatus.text = ("ENGINE ON" if running else "ENGINE OFF") if connected else "OFFLINE"
	$EngineStatus.modulate = Color(0.3, 1.0, 0.6) if running else Color(0.95, 0.55, 0.2)
	$BrakeStatus.text = "PARK" if parked else ""
	$BatteryLabel.text = "NO BAT" if connected and rv.energy.battery == null else "BATT"

	if connected:
		for row in VehicleStatus.read(rv): warning_lamps[row.id].modulate = VehicleStatus.color(row.level) if rv.current_power > 0 else VehicleStatus.color(0)
	else:
		for lamp in warning_lamps.values(): lamp.modulate = VehicleStatus.color(0)

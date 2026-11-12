extends Node3D
## Presentation only; every instrument reads the chassis owned by this seat.
const MAX_STEERING_ANGLE := 1.25 # Match the existing driving hand travel.
@onready var seat: Item = get_parent()
@onready var steering_wheel: Node3D = $SteeringTilt/SteeringWheel
@onready var gear_lever: Node3D = $GearLever
@onready var parking_lever: Node3D = $ParkingLever

func _process(delta: float) -> void:
	var rv: Chassis = seat.get_connected_rv() as Chassis
	var connected := rv != null and seat.can_operate()
	var gear := rv.gear if connected else 0
	var parked := rv.handbrake if connected else true
	# Tilted local +Y points toward the driver: positive rotation is left.
	var steer := clampf(rv.steering * 3.5, -MAX_STEERING_ANGLE, MAX_STEERING_ANGLE) if connected else 0.0
	steering_wheel.rotation.y = lerp_angle(steering_wheel.rotation.y, steer, minf(delta * 12.0, 1.0))
	gear_lever.rotation.x = lerp_angle(gear_lever.rotation.x, -0.28 if gear < 0 else (0.0 if gear == 0 else 0.23), minf(delta * 12.0, 1.0))
	gear_lever.rotation.z = lerp_angle(gear_lever.rotation.z, float(gear - 2) * 0.08 if gear > 0 else 0.0, minf(delta * 12.0, 1.0))
	parking_lever.rotation.x = lerp_angle(parking_lever.rotation.x, 0.55 if parked else 0.0, minf(delta * 12.0, 1.0))
	$InstrumentCluster.update_instruments(rv if connected else null, delta)

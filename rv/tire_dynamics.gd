extends RefCounted
class_name TireDynamics
## A flat is condition == 0, shared with the existing wheel item/save/repair state.
const NAMES := ["Front left", "Front right", "Rear left", "Rear right"]

static func visual_scale(radius: float, width: float) -> Vector3:
	# Shared visual is authored with its axle along X, radius 0.5 m and width 0.4 m.
	return Vector3(width / 0.4, radius / 0.5, radius / 0.5)

static func update_condition(rv: Chassis, slot: int) -> void:
	var wheel: VehicleWheel3D = rv.installed_wheels[slot]
	var flat: bool = rv.wheel_health[slot] <= 0.0
	# A collapsed tire can limp on its rim; it is different from a missing wheel.
	var radius := rv.WHEEL_RADIUS * (rv.handling_profile.flat_radius_scale if flat else 1.0)
	if not is_equal_approx(wheel.wheel_radius, radius):
		wheel.wheel_radius = radius
		var mesh := wheel.get_node("WheelMesh") as Node3D
		mesh.scale = visual_scale(radius, rv.WHEEL_WIDTH * (1.15 if flat else 1.0))

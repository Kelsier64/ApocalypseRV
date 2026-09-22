extends RefCounted
class_name TireDynamics
## A flat is condition == 0, shared with the existing wheel item/save/repair state.
const NAMES := ["左前", "右前", "左後", "右後"]
const FLAT_GRIP := 0.5
const FLAT_DRIVE := 0.35
const FLAT_STEERING := 0.55
const ROLLING_DECELERATION := 0.38 # m/s² per flat, at normal road speed

static func update_condition(rv: Chassis, slot: int) -> void:
	var wheel: VehicleWheel3D = rv.installed_wheels[slot]
	var flat: bool = rv.wheel_health[slot] <= 0.0
	wheel.wheel_friction_slip = FLAT_GRIP if flat else lerpf(0.7, 3.5, rv.wheel_health[slot] / 100.0)
	# A collapsed tire can limp on its rim; it is different from a missing wheel.
	wheel.use_as_traction = rv.WHEEL_SLOTS[slot].traction
	var radius := rv.WHEEL_RADIUS * (0.8 if flat else 1.0)
	if not is_equal_approx(wheel.wheel_radius, radius):
		wheel.wheel_radius = radius
		var mesh := wheel.get_node("WheelMesh") as Node3D
		mesh.scale = Vector3(rv.WHEEL_WIDTH / 0.4 * (1.15 if flat else 1.0), radius / 0.5, radius / 0.5)

static func step(rv: Chassis) -> void:
	var pull := 0.0
	for slot in range(4):
		if rv.installed_wheels[slot] != null and rv.wheel_health[slot] <= 0.0 and rv.installed_wheels[slot].is_in_contact():
			# Collapsed sidewalls deflect the effective wheel alignment. Rear
			# damage has less steering influence but still loads the steering rack.
			pull -= signf(rv.WHEEL_SLOTS[slot].position.x) * (0.065 if slot < 2 else 0.04)
	pull *= clampf(absf(rv.linear_velocity.dot(rv.global_basis.z)) / 4.0, 0.0, 1.0)
	for slot in range(4):
		var wheel: VehicleWheel3D = rv.installed_wheels[slot]
		if wheel == null: continue
		var flat: bool = rv.wheel_health[slot] <= 0.0
		# Body setters run first; each wheel then receives its own condition.
		if rv.WHEEL_SLOTS[slot].steering:
			wheel.steering = rv.steering * (FLAT_STEERING if flat else 1.0) + pull
		if rv.WHEEL_SLOTS[slot].traction:
			wheel.engine_force = rv.engine_force * (FLAT_DRIVE if flat else 1.0)
		if not flat or not wheel.is_in_contact(): continue
		var point := wheel.get_contact_point()
		var offset := point - rv.global_position
		var velocity := ClimbMath.point_velocity(rv, point)
		var forward := -rv.global_basis.z
		var speed := velocity.dot(forward)
		# Smoothly vanishes at rest and reverses in reverse gear. Applying at
		# the contact patch creates side-dependent yaw without scripted rotation.
		var drag := -forward * clampf(speed / 2.0, -1.0, 1.0) * rv.mass * ROLLING_DECELERATION
		rv.apply_force(drag, offset)

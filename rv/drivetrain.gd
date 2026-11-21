class_name RVDrivetrain
extends RefCounted

var spin := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var slip_speed := 0.0

static func ratio(profile: RVHandlingProfile, gear: int) -> float:
	if gear == 0: return 0.0
	return profile.gear_ratios[absi(gear) - 1]

func shaft_rpm(vehicle: Chassis) -> float:
	var wheel_rate := absf((spin[2] + spin[3]) * 0.5)
	var final_drive := Chassis.ENGINE_REDLINE_RPM * TAU * vehicle.WHEEL_RADIUS / (60.0 * vehicle.max_speed)
	return wheel_rate * ratio(vehicle.handling_profile, vehicle.gear) * final_drive * 60.0 / TAU

func drive_force(vehicle: Chassis, pedal: float) -> float:
	var engine := vehicle.get_engine()
	var spec := engine.definition()
	var health := minf(1.0, engine.health / (spec.max_health * Chassis.ENGINE_SPEED_WEAR_THRESHOLD))
	var speed_scale := lerpf(Chassis.MIN_ENGINE_SPEED_SCALE, 1.0, health)
	var rpm := shaft_rpm(vehicle)
	# At launch the clutch supplies torque at idle. The shaft still sets the rev limiter.
	var normalized := rpm / (Chassis.ENGINE_REDLINE_RPM * speed_scale)
	var torque := lerpf(0.85, 1.0, smoothstep(0.0, 0.38, rpm / Chassis.ENGINE_REDLINE_RPM)) * (1.0 - smoothstep(0.32, 1.15, normalized))
	if pedal <= 0.0: return 0.0
	var gear_scale := ratio(vehicle.handling_profile, vehicle.gear) / ratio(vehicle.handling_profile, 1)
	var force := pedal * vehicle.max_engine_force * spec.force_multiplier * torque * gear_scale
	return -force if vehicle.gear > 0 else force * vehicle.handling_profile.reverse_torque_scale

func step(vehicle: Chassis, field: WorldField, delta: float, parking: bool, engaged: bool) -> void:
	var profile := vehicle.handling_profile
	var loads := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var travel := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	slip_speed = 0.0
	for i in loads.size():
		var wheel: VehicleWheel3D = vehicle.installed_wheels[i]
		if wheel == null:
			spin[i] = 0.0
			continue
		if not wheel.is_in_contact(): continue
		var point := wheel.get_contact_point()
		var up := vehicle.global_basis.y
		var normal := wheel.get_contact_normal()
		var hard_point := vehicle.to_global(vehicle.WHEEL_SLOTS[i].position)
		var ray := wheel.wheel_rest_length + wheel.wheel_radius
		var ray_distance := (hard_point + up * wheel.wheel_radius - point).dot(up)
		var length := clampf(ray_distance * ray / (ray + wheel.wheel_radius) - wheel.wheel_radius, wheel.wheel_rest_length - wheel.suspension_travel, wheel.wheel_rest_length + wheel.suspension_travel)
		travel[i] = wheel.wheel_rest_length - length
		var incoming: Vector3 = vehicle.suspension_incoming_velocity(point)
		var normal_projection := maxf(0.1, up.dot(normal))
		var speed := incoming.dot(normal) / normal_projection
		var damping := wheel.damping_compression if speed < 0.0 else wheel.damping_relaxation
		loads[i] = clampf(vehicle.mass * (wheel.suspension_stiffness * travel[i] / normal_projection - damping * speed), 0.0, wheel.suspension_max_force)
	for left in [0, 2]:
		var right: int = left + 1
		if loads[left] <= 0.0 or loads[right] <= 0.0: continue
		var bar := clampf((travel[left] - travel[right]) * profile.anti_roll_stiffness, -loads[left], loads[right])
		apply_support(vehicle, vehicle.installed_wheels[left], bar)
		apply_support(vehicle, vehicle.installed_wheels[right], -bar)
		loads[left] += bar
		loads[right] -= bar
	var rear_pair: bool = vehicle.installed_wheels[2] != null and vehicle.installed_wheels[3] != null
	var drive_torque := -vehicle.engine_force * vehicle.WHEEL_RADIUS
	# A missing axle end leaves an open differential without useful reaction torque.
	if not rear_pair: drive_torque = 0.0
	var engine_drag := profile.engine_braking_force * vehicle.WHEEL_RADIUS if engaged and rear_pair else 0.0
	var pull := 0.0
	for i in loads.size():
		if loads[i] > 0.0 and vehicle.wheel_health[i] <= 0.0:
			pull -= signf(vehicle.WHEEL_SLOTS[i].position.x) * profile.flat_alignment * (1.0 if i < 2 else 0.6)
	pull *= clampf(vehicle.linear_velocity.length() / 4.0, 0.0, 1.0)
	for i in loads.size():
		var wheel: VehicleWheel3D = vehicle.installed_wheels[i]
		if wheel == null: continue
		var flat: bool = vehicle.wheel_health[i] <= 0.0
		if i < 2: wheel.steering = vehicle.steering * (profile.flat_steering_scale if flat else 1.0) + pull
		var service_bias := profile.front_brake_bias if i < 2 else 1.0 - profile.front_brake_bias
		var brake_force := vehicle.max_braking_force * 60.0 * vehicle.brake_input * service_bias * 2.0
		if parking and i >= 2: brake_force += vehicle.parking_braking_force * 60.0
		var torque := drive_torque if i >= 2 else 0.0
		var drag := engine_drag * (1.0 - vehicle.throttle_input) if i >= 2 else 0.0
		var stop_torque := brake_force * wheel.wheel_radius + drag
		var inertia := profile.wheel_inertia
		var free_spin := move_toward(spin[i] + torque * delta / inertia, 0.0, stop_torque * delta / inertia)
		if loads[i] > 0.0:
			var extra := maxf(0.0, travel[i] - profile.bump_stop_compression) * profile.bump_stop_stiffness
			apply_support(vehicle, wheel, extra)
			var reaction := apply_tire(vehicle, field, i, wheel, loads[i] + extra, free_spin, stop_torque, delta)
			free_spin -= reaction * wheel.wheel_radius * delta / inertia
			# Brake torque left after stopping the free wheel also resists contact spin-up.
			var unused_brake := maxf(0.0, stop_torque * delta / inertia - absf(spin[i] + torque * delta / inertia))
			free_spin = move_toward(free_spin, 0.0, unused_brake)
		spin[i] = clampf(free_spin, -profile.wheel_spin_limit, profile.wheel_spin_limit)

func apply_tire(vehicle: Chassis, field: WorldField, index: int, wheel: VehicleWheel3D, load: float, free_spin: float, stop_torque: float, delta: float) -> float:
	var profile := vehicle.handling_profile
	var point := wheel.get_contact_point()
	var normal := wheel.get_contact_normal()
	var ground := wheel.get_contact_body()
	var centre := vehicle.to_global(vehicle.center_of_mass)
	var relative := vehicle.linear_velocity + vehicle.angular_velocity.cross(point - centre)
	if ground is RigidBody3D: relative -= ClimbMath.point_velocity(ground, point)
	var forward := (-vehicle.global_basis.z).rotated(vehicle.global_basis.y, wheel.steering).slide(normal).normalized()
	var lateral := forward.cross(normal)
	var radius := wheel.wheel_radius
	var along := relative.dot(forward)
	var across := relative.dot(lateral)
	var reference_speed := maxf(1.5, absf(along))
	var slip := Vector2((free_spin * radius - along) / reference_speed, -atan2(across, reference_speed))
	var surface := RVTireModel.surface_grip(profile, field, point)
	var condition := vehicle.wheel_health[index]
	var grip := RVTireModel.grip_limit(profile, load, vehicle.mass * 9.8 * 0.25, surface, condition)
	var force := RVTireModel.force(profile, slip, grip)
	var stop_response := profile.wheel_inertia / (radius * radius * maxf(delta, 0.001))
	var brake_headroom := maxf(0.0, stop_torque - absf(spin[index]) * profile.wheel_inertia / delta) / radius if is_zero_approx(free_spin) else 0.0
	force.x = signf(force.x) * minf(absf(force.x), absf(free_spin * radius - along) * stop_response + brake_headroom)
	force.y = signf(force.y) * minf(absf(force.y), absf(across) * vehicle.mass * 0.18 / delta)
	var rolling_drag := profile.flat_rolling_drag if condition <= 0.0 else (profile.rolling_drag if surface >= profile.asphalt_grip else profile.loose_surface_drag)
	var rolling := -load * rolling_drag * clampf(along / 2.0, -1.0, 1.0)
	var tread_force := (force + Vector2(rolling, 0.0)).limit_length(grip)
	vehicle.apply_force(forward * tread_force.x + lateral * tread_force.y, point - vehicle.global_position)
	# Audio measures the wheel speed retained from the previous contact solve.
	# The free-spin prediction includes this step's torque before the tire reacts.
	var longitudinal_slip_speed := spin[index] * radius - along
	if absf(longitudinal_slip_speed) > profile.longitudinal_peak_slip * reference_speed or absf(slip.y) > profile.lateral_peak_angle:
		slip_speed = maxf(slip_speed, Vector2(longitudinal_slip_speed, across).length())
	return force.x

static func apply_support(vehicle: Chassis, wheel: VehicleWheel3D, load: float) -> void:
	vehicle.apply_force(wheel.get_contact_normal() * load, wheel.get_contact_point() - vehicle.global_position)

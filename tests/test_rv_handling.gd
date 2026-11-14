extends SceneTree

const Fixture := preload("res://tests/support/rv_handling_fixture.gd")
const PROFILE := preload("res://rv/handling_profile.tres")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	var peak := PROFILE.lateral_peak_angle
	check(RVTireModel.grip_curve(0.0, peak, PROFILE.sliding_grip_fraction) < RVTireModel.grip_curve(peak, peak, PROFILE.sliding_grip_fraction), "Slip angle builds lateral force")
	check(RVTireModel.grip_curve(peak * 3.0, peak, PROFILE.sliding_grip_fraction) < RVTireModel.grip_curve(peak, peak, PROFILE.sliding_grip_fraction), "Side force falls beyond peak slip")
	var combined := RVTireModel.force(PROFILE, Vector2(PROFILE.longitudinal_peak_slip, peak), 1.0)
	check(is_equal_approx(combined.length(), 1.0) and combined.y < 1.0, "Braking and steering share the grip limit")
	var field := WorldField.new(42)
	var frame := field.road_frame(100.0)
	var asphalt := RVTireModel.surface_grip(PROFILE, field, frame.origin)
	var dirt := RVTireModel.surface_grip(PROFILE, field, frame.origin + frame.basis.x * 35.0)
	check(asphalt > dirt, "The world road query gives asphalt more grip than dirt")
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	Fixture.ground(world)
	var vehicle := Fixture.vehicle(world, Vector3.UP * 1.4)
	vehicle.allow_test_controls = true
	for i in 120: await physics_frame
	vehicle.set_handbrake(false)
	vehicle.set_gear(3)
	vehicle.set_engine_running(true)
	vehicle.linear_velocity = -vehicle.global_basis.z * 19.0
	for i in 4: vehicle.drivetrain.spin[i] = 19.0 / vehicle.WHEEL_RADIUS
	vehicle.control_override = {"steering": 1.0, "throttle": 0.65}
	var roll := 0.0
	var slip := 0.0
	var overturned := false
	for i in 240:
		await physics_frame
		roll = maxf(roll, absf(vehicle.global_basis.x.y))
		slip = maxf(slip, vehicle.drivetrain.slip_speed)
		overturned = overturned or vehicle.rollover_state() != Chassis.Rollover.UPRIGHT
	print("ASPHALT roll=", roll, " slip=", slip, " speed=", vehicle.road_speed())
	check(roll > 0.01 and slip > 0.0 and not overturned, "Flat asphalt full steering slides with body roll before overturning")
	world.free()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var slope := 1.1
	Fixture.ground(world, slope)
	var slope_vehicle := Fixture.vehicle(world, Vector3.UP * 2.2, slope)
	var min_upright := 1.0
	for i in 150:
		await physics_frame
		min_upright = minf(min_upright, slope_vehicle.global_basis.y.y)
	print("SLOPE up=", min_upright)
	check(min_upright <= PROFILE.rollover_side_up_dot, "A steep cross-slope can roll the RV onto its side")
	world.free()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	Fixture.ground(world)
	var curb := StaticBody3D.new()
	var curb_shape := CollisionShape3D.new()
	var barrier := BoxShape3D.new()
	barrier.size = Vector3(0.7, 0.75, 30.0)
	curb_shape.shape = barrier
	curb.add_child(curb_shape)
	curb.position = Vector3(-4.3, 0.37, 0.0)
	world.add_child(curb)
	var trip := Fixture.vehicle(world, Vector3.UP * 1.4)
	for i in 110: await physics_frame
	trip.handbrake = false
	trip.set_gear(0)
	trip.linear_velocity = Vector3(-18.0, 0.0, -7.0)
	var curb_up := 1.0
	for i in 150:
		await physics_frame
		curb_up = minf(curb_up, trip.global_basis.y.y)
	print("CURB up=", curb_up, " tires=", trip.wheel_health)
	check(curb_up <= PROFILE.rollover_side_up_dot, "A strong sideways curb impact can trip the RV")
	check(trip.wheel_health[1] < trip.wheel_health[0] or trip.wheel_health[3] < trip.wheel_health[2], "Tires on the impacted side suffer more damage")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: shared tire grip, surface handling and rollover")
	quit(1 if not failures.is_empty() else 0)

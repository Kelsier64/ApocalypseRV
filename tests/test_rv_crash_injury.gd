extends SceneTree

const Fixture := preload("res://tests/support/rv_handling_fixture.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := Fixture.ground(world)
	var vehicle := Fixture.vehicle(world, Vector3.UP * 1.3)
	vehicle.freeze = true
	var profile := vehicle.handling_profile
	var player := Fixture.player(world, Vector3(5.0, 1.0, 0.0))
	await physics_frame
	var below := profile.crash_injury_speed - 0.1
	check(not player.apply_crash_hit(vehicle, 1, below, Vector3.ZERO, false), "Low impulses cause no injury")
	var heavy := RVCrashDamage.injury(profile, profile.crash_stun_speed, false)
	var belted := RVCrashDamage.injury(profile, profile.crash_stun_speed, true)
	check(heavy.stun > 0.0 and is_equal_approx(belted.damage / heavy.damage, profile.crash_seated_damage_scale), "Heavy crashes stun and seating reduces injury")
	player.rv_support.rv = vehicle
	check(player.apply_crash_hit(vehicle, 2, profile.crash_stun_speed, Vector3.LEFT * 9.0, false), "Heavy standing crash applies")
	check(player.rv_support.rv == null and player.released_carrier_velocity.is_equal_approx(Vector3.LEFT * 9.0), "The occupant is released with the prior world momentum")
	check(player._crash_stun_remaining > 0.0, "Heavy injury triggers stun feedback")
	player.damage_cooldown = 0.0
	check(not player.apply_crash_hit(vehicle, 2, profile.crash_lethal_speed, Vector3.ZERO, false), "Repeated contacts use the same injury episode")
	var wounded := Fixture.player(world, Vector3(6.0, 0.1, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	wounded.apply_crash_hit(vehicle, 3, profile.crash_lethal_speed * 1.25, Vector3.ZERO, false, rng)
	var remaining := 0
	for part: StringName in [&"left_arm", &"right_arm", &"left_leg", &"right_leg"]:
		if wounded.body_state.has_part(part): remaining += 1
	check(remaining == 3 and wounded.body_state.has_part(&"head") and wounded.is_player_dead, "A severe collision can kill and remove at most one limb")
	for i in 5: await physics_frame
	player.queue_free()
	wounded.queue_free()
	await process_frame
	var driver := Fixture.player(world, Vector3(5.0, 0.1, 0.0))
	var seat := vehicle.get_node("DriverSeat")
	var wall := ground.duplicate() as StaticBody3D
	wall.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -19.0))
	world.add_child(wall)
	for i in 60: await physics_frame
	vehicle.freeze = false
	seat.interact_hold(driver)
	for i in 90: await physics_frame
	vehicle.handbrake = false
	vehicle.linear_velocity = Vector3.FORWARD * (profile.crash_stun_speed + 4.0)
	for i in 100: await physics_frame
	check(driver.current_player_health < driver.max_player_health and driver.current_player_health > 0.0 and driver._crash_event > 0, "The seated player receives one injury from a real wall impact")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: crash thresholds, momentum, deduplication, seeded severing and seated wall impact")
	quit(1 if not failures.is_empty() else 0)

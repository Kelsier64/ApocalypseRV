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
	var injury = player.injury_effects
	player.take_damage(player.max_player_health * injury.BLACKOUT_THRESHOLD * 0.4)
	check(injury._focus_peak > 0.0 and injury._black_start < 0.0 and injury._ring_start < 0.0, "Light direct damage triggers defocus without blackout or ringing")
	player.current_player_health = player.max_player_health
	player.damage_cooldown = 0.0
	injury.reset()
	var below := profile.crash_injury_speed - 0.1
	check(not player.apply_crash_hit(vehicle, 1, below, Vector3.ZERO, false), "Low impulses cause no injury")
	var heavy_speed := lerpf(profile.crash_injury_speed, profile.crash_lethal_speed, 0.4)
	var heavy := RVCrashDamage.injury(profile, heavy_speed, false)
	var belted := RVCrashDamage.injury(profile, heavy_speed, true)
	check(is_equal_approx(belted.damage / heavy.damage, profile.crash_seated_damage_scale), "Seating reduces injury")
	player.rv_support.rv = vehicle
	check(player.apply_crash_hit(vehicle, 2, heavy_speed, Vector3.LEFT * 9.0, false), "Heavy standing crash applies")
	check(player.rv_support.rv == null and player.released_carrier_velocity.is_equal_approx(Vector3.LEFT * 9.0), "The occupant is released with the prior world momentum")
	var original_blackout: float = injury._black_end
	var original_focus: float = injury._focus_peak
	check(original_blackout > 0.0, "Heavy injury triggers blackout")
	player.damage_cooldown = 0.0
	check(not player.apply_crash_hit(vehicle, 2, profile.crash_lethal_speed, Vector3.ZERO, false), "Repeated contacts use the same injury episode")
	check(player.apply_explosion_hit(player.current_player_health * 0.75), "An accepted blast arrives during crash recovery")
	check(injury._black_end == original_blackout and injury._focus_peak > original_focus and injury._ring_end > injury._focus_end, "Accepted follow-up blast deepens defocus and extends audio without restarting blackout")
	check(injury.stride_scale() > 0.0, "Severe injury preserves movement")
	var wounded := Fixture.player(world, Vector3(6.0, 0.1, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	wounded.apply_crash_hit(vehicle, 3, profile.crash_lethal_speed * 1.25, Vector3.ZERO, false, rng)
	var remaining := 0
	for part: StringName in [&"left_arm", &"right_arm", &"left_leg", &"right_leg"]:
		if wounded.body_state.has_part(part): remaining += 1
	check(remaining == 3 and wounded.body_state.has_part(&"head") and wounded.is_player_dead, "A severe collision can kill and remove at most one limb")
	check(not wounded.injury_effects.is_processing(), "Death clears any transient injury presentation")
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
	vehicle.linear_velocity = Vector3.FORWARD * lerpf(profile.crash_sever_speed, profile.crash_lethal_speed, 0.5)
	var jolt_before_blackout := false
	var blackout_before_damage := false
	var backward_rebound := false
	for i in 100:
		await physics_frame
		var black: float = driver.injury_effects._black_at(driver.injury_effects._age)
		if seat._impact_age < seat.IMPACT_SECONDS and seat._impact_direction.z < -0.5:
			var offset: float = seat.seat_camera.position.z - seat._camera_rest_position.z
			jolt_before_blackout = jolt_before_blackout or (offset < -0.001 and black == 0.0)
			backward_rebound = backward_rebound or offset > 0.001
		blackout_before_damage = blackout_before_damage or (black == 1.0 and driver.current_player_health == driver.max_player_health)
	check(jolt_before_blackout and blackout_before_damage, "Real wall contact shows the forward jolt and then black before damage settles")
	check(not backward_rebound, "Cabin camera returns to rest on the impact side")
	check(driver.current_player_health < driver.max_player_health and driver.current_player_health > 0.0 and driver._crash_event > 0, "The seated player receives one injury from a real wall impact")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: crash thresholds, momentum, deduplication, seeded severing and seated wall impact")
	quit(1 if not failures.is_empty() else 0)

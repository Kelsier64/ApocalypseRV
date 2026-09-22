extends SceneTree
## Production wheels; initial configuration only, no scripted vehicle motion.
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	var results := {}
	var configs := [{"id": "standard"}, {"id": "reinforced", "engine": "upgraded"}, {"id": "equipment", "load": 600.0}, {"id": "worn", "wear": 20.0}, {"id": "missing", "missing": 0}, {"id": "failed", "failed": true}, {"id": "slope", "slope": 5.0}, {"id": "turn", "turn": 0.7}, {"id": "reverse", "gear": -1}, {"id": "fast_turn", "turn": 0.7, "gear": 4, "initial_speed": 20.0}]
	for i in range(1, 6):
		var uphill: Dictionary = configs[i].duplicate()
		uphill.id += "_slope"
		uphill.slope = 5.0
		configs.append(uphill)
	for config in configs:
		var world := Node3D.new()
		root.add_child(world)
		current_scene = world
		var ground := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(400, 0.2, 400)
		collider.shape = box
		ground.add_child(collider)
		ground.position.y = -0.1
		ground.rotation.x = deg_to_rad(config.get("slope", 0.0))
		world.add_child(ground)
		var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
		shell.position.y = 1.8
		world.add_child(shell)
		var rv: Chassis = shell.get_node("Chassis")
		rv.allow_test_controls = true
		if config.has("engine"): rv.engine_bay.installed_engine = EngineState.new({"model": config.engine})
		if config.has("load"):
			# Explicit test ballast on an actual installed equipment item.
			rv.get_node("ItemBox").mass += config.load
		if config.has("wear"):
			for i in range(4): rv.wheel_health[i] = config.wear
		if config.has("missing"): rv.remove_wheel(config.missing)
		if config.has("failed"): rv.get_engine().health = 0.0
		for i in range(120): await physics_frame
		var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
		player.position = Vector3(30, 1, 30)
		world.add_child(player)
		player.set_physics_process(false)
		var seat: Equipment = rv.get_node("DriverSeat")
		seat.interact_hold(player)
		check(seat.current_driver == player, "%s allows driver entry" % config.id)
		var parked := rv.global_position
		for i in range(60): await physics_frame
		var parking_drift := Vector2(rv.global_position.x - parked.x, rv.global_position.z - parked.z).length()
		check(parking_drift < 0.15, "%s parking holds" % config.id)
		rv.set_engine_running(true)
		rv.set_gear(config.get("gear", 1))
		rv.handbrake = false
		var start := rv.global_position
		var forward := -rv.global_basis.z
		if config.has("initial_speed"): rv.linear_velocity = forward * config.initial_speed
		var peak := 0.0
		var seconds_to_three := -1.0
		rv.control_override = {"throttle": 1.0, "steering": config.get("turn", 0.0)}
		for i in range(360):
			await physics_frame
			peak = maxf(peak, Vector2(rv.linear_velocity.x, rv.linear_velocity.z).length())
			if seconds_to_three < 0.0 and peak >= 3.0: seconds_to_three = i / 60.0
			if i == 2: check(rv.throttle_input > 0.0 and rv.throttle_input < 0.5, "Throttle builds progressively")
		var travelled := rv.global_position - start
		var yaw := absf(rv.global_basis.z.signed_angle_to(-forward, Vector3.UP))
		rv.control_override = {"brake": 1.0}
		for i in range(180): await physics_frame
		check(rv.linear_velocity.length() < 0.3, "%s brakes stop vehicle" % config.id)
		check(absf(rv.steering) < 0.01, "%s steering recentres" % config.id)
		check(rv.global_basis.y.dot(Vector3.UP) > 0.65, "%s stays upright" % config.id)
		if config.has("failed"):
			check(not rv.energy.engine_running and rv.engine_force == 0.0, "Failed engine cannot provide propulsion")
			if not config.has("slope"): check(peak < 0.2, "Failed engine stays stationary on level ground")
		elif config.id == "reverse": check(travelled.dot(forward) < -2.0, "Reverse moves backwards")
		elif not (config.has("missing") and config.has("slope")):
			check(travelled.length() > 2.0, "%s can move under wheel power" % config.id)
		if config.id == "turn": check(yaw > 0.2, "Low speed steering changes heading")
		print("HANDLING %s distance=%.3f peak=%.3f to3=%.3f yaw=%.3f radius=%.3f hold=%.3f" % [config.id, travelled.length(), peak, seconds_to_three, yaw, travelled.length() / maxf(yaw, 0.001), parking_drift])
		results[config.id] = {"distance": travelled.length(), "peak": peak, "to3": seconds_to_three, "radius": travelled.length() / maxf(yaw, 0.001)}
		if config.id == "standard":
			# Low-speed docking and reversing out use only production controls.
			var dock_start := rv.global_position
			var dock_target := dock_start + forward * 14.0
			rv.handbrake = false
			rv.set_gear(1)
			for i in range(1200):
				var remaining := (dock_target - rv.global_position).dot(forward)
				var speed := maxf(0.0, rv.linear_velocity.dot(forward))
				var stopping := speed * speed / 5.0 + speed * 0.35 + 0.2
				rv.control_override = {"brake": 1.0} if remaining <= stopping else {"throttle": 0.3}
				await physics_frame
				if remaining < 0.5 and speed < 0.1: break
			var dock_error := absf((dock_target - rv.global_position).dot(forward))
			check(dock_error < 0.7 and rv.road_speed() < 0.2, "Wheel controls stop inside marked parking bay")
			rv.set_handbrake(true)
			var parked_at := rv.global_position
			for i in range(120): await physics_frame
			check(Vector2(rv.global_position.x - parked_at.x, rv.global_position.z - parked_at.z).length() < 0.15, "Parking bay hold is stable")
			rv.set_gear(-1)
			rv.set_handbrake(false)
			for i in range(1200):
				var remaining := (rv.global_position - dock_start).dot(forward)
				var speed := maxf(0.0, -rv.linear_velocity.dot(forward))
				var stopping := speed * speed / 5.0 + speed * 0.35 + 0.2
				rv.control_override = {"brake": 1.0} if remaining <= stopping else {"throttle": 0.55}
				await physics_frame
				if remaining < 0.5 and speed < 0.1: break
			var return_error := absf((rv.global_position - dock_start).dot(forward))
			check(return_error < 0.7 and rv.road_speed() < 0.2, "Reverse returns from bay to road without repositioning body")
			print("PARKING dock_error=%.3f return_error=%.3f" % [dock_error, return_error])
		seat.exit_seat()
		check(player.seated_in == null and rv.handbrake, "%s allows supported exit even with degraded vehicle condition" % config.id)
		world.queue_free()
		await process_frame
		await process_frame
	# Wheel traction and added equipment do not promise 10% more distance in
	# this fixed window. Verify the upgrade accelerates sooner and travels farther.
	# The exact 1.25 force multiplier is covered by test_rv_engine.
	check(results.reinforced.to3 > 0 and results.reinforced.to3 < results.standard.to3 and results.reinforced.distance > results.standard.distance and results.reinforced.peak > results.standard.peak, "Reinforced engine retains stronger acceleration")
	check(results.equipment.distance < results.standard.distance, "Installed equipment mass reduces acceleration")
	check(results.fast_turn.radius > results.turn.radius * 3.0, "High speed steering uses a wider, stable turn")
	for failure in failures: push_error("FAIL: " + failure)
	if failures.is_empty(): print("PASS: wheel-driven handling, condition, load, slope, reverse and steering return")
	quit(0 if failures.is_empty() else 1)

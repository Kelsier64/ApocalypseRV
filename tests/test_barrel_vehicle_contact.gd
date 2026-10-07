extends SceneTree
## Production vehicle physics must ignite a mimic without generic impact billing.
var failures: Array[String] = []

class ContactBarrel extends BarrelMan:
	var explosions := 0
	var contacted_vehicle: Node3D
	var full_explosion := false
	var result := {"explosions": 0, "contacted_vehicle": null}
	func _refresh_barrel_target() -> void: pass
	func _resolve_explosion(_origin: Vector3, vehicle_ref: WeakRef) -> void:
		explosions += 1
		contacted_vehicle = vehicle_ref.get_ref() if vehicle_ref != null else null
		result.explosions = explosions
		result.contacted_vehicle = contacted_vehicle
		if full_explosion: super._resolve_explosion(_origin, vehicle_ref)
		else: body_collision_shape.disabled = true

func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	await scenario(Vector3.FORWARD, 0.7, "slow front")
	await scenario(Vector3.FORWARD, 12.0, "fast front")
	await scenario(Vector3.BACK, 6.0, "reverse rear")
	await scenario(Vector3.RIGHT, 6.0, "side")
	await scenario(Vector3.FORWARD, 12.0, "full explosion front", true)
	if failures.is_empty(): print("PASS: actual low/high speed, rear and side barrel contacts with no duplicate engine billing")
	quit(0 if failures.is_empty() else 1)

func scenario(direction: Vector3, speed: float, label: String, full_explosion := false) -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(100, 0.2, 100)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.1
	ground.add_child(floor_collision)
	world.add_child(ground)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.allow_test_controls = true
	rv.handbrake = false
	rv.control_override = {"throttle": 0.0}
	for index in 90: await physics_frame
	rv.set_physics_process(false)
	rv.brake = 0.0
	var events: Array[Dictionary] = []
	rv.vehicle_impact.connect(func(kind: String, _loss: float, damage: float) -> void: events.append({"kind": kind, "damage": damage}))
	var barrel := ContactBarrel.new()
	# These scenarios isolate genuine low/high-speed physical contact.
	barrel.settings.proximity_trigger_radius = 0.0
	barrel.full_explosion = full_explosion
	var result := barrel.result
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape"
	barrel.add_child(collision)
	barrel.position = direction * 14
	world.add_child(barrel)
	var surface := barrel._vehicle_surface(rv)
	barrel.position = Vector3(surface.x, 0, surface.z) + direction * (BarrelMan.BARREL_RADIUS + 0.6)
	await physics_frame
	var start_health := rv.get_engine().health
	rv.linear_velocity = direction * speed
	var speed_after := 0.0
	for index in 180:
		await physics_frame
		if result.explosions > 0 and speed_after <= 0.0: speed_after = rv.linear_velocity.dot(direction)
	check(result.explosions == 1 and result.contacted_vehicle == rv, "%s production vehicle hits disguise and ignites once" % label)
	check(not events.any(func(event: Dictionary) -> bool: return event.kind == "monster"), "%s yielded mimic does not charge generic monster collision damage" % label)
	if full_explosion:
		var subsequent_impacts := 0.0
		for event in events: subsequent_impacts += event.damage
		check(is_equal_approx(start_health - rv.get_engine().health - subsequent_impacts, 60.0), "%s true-contact blast pays exactly one 60 HP engine hit before subsequent wreck-ground impacts" % label)
		check(not is_instance_valid(barrel), "%s full explosion removes source actor" % label)
	else: check(rv.get_engine().health >= start_health - 0.01, "%s contact pays no engine damage before explosion resolver" % label)
	if speed >= 6.0: check(speed_after > speed * 0.5, "%s RV retains travel after barrel yields" % label)
	print("BARREL_CONTACT label=%s speed=%.1f detonations=%d speed_after=%.2f engine_delta=%.3f events=%s" % [label, speed, result.explosions, speed_after, start_health - rv.get_engine().health, events])
	world.queue_free()
	await process_frame
	await physics_frame

extends SceneTree

var failures: Array[String] = []

class ContactMonster extends Monster:
	var accepted_contacts := 0
	var rv_overlap_events := 0
	var duplicate_health := 0.0
	var impact_velocity := Vector3.ZERO
	var impact_normal := Vector3.ZERO
	var impact_approach := 0.0
	var health_before := 0.0
	var health_after := 0.0
	var rv_speed_before := 0.0
	var probe_contacts := false

	func _physics_process(delta: float) -> void:
		if vehicle_impact_cooldown > 0.0:
			velocity.y -= gravity * delta
			move_and_slide()
		elif probe_contacts:
			climb_wall_probe.force_raycast_update()
			_try_start_climb(global_position)

	func _on_hitbox_body_entered(body: Node3D) -> void:
		if _find_rv_ancestor(body) != null: rv_overlap_events += 1
		super._on_hitbox_body_entered(body)

	func _apply_vehicle_contact(rv: Node3D, normal: Vector3, point: Vector3) -> bool:
		var before := current_health
		var incoming: Vector3 = rv.vehicle_impact_point_velocity(point) if rv.has_method("vehicle_impact_point_velocity") else ClimbMath.point_velocity(rv, point)
		var approach := maxf(0.0, (incoming - _contact_world_velocity()).dot(normal))
		var result := super._apply_vehicle_contact(rv, normal, point)
		if current_health < before:
			accepted_contacts += 1
			health_before = before
			health_after = current_health
			impact_velocity = velocity
			impact_normal = normal
			impact_approach = approach
			rv_speed_before = incoming.length()
			# Multiple real collider/Area notifications in one frame must share cooldown.
			super._apply_vehicle_contact(rv, normal, point)
			duplicate_health = current_health
		return result

func _init() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func monster_at(world: Node3D, point: Vector3) -> ContactMonster:
	var monster := ContactMonster.new()
	monster.max_health = 200.0
	monster.position = point
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2.0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape"
	collision.shape = capsule
	collision.position.y = 1.0
	monster.add_child(collision)
	var area := Area3D.new()
	area.name = "HitBox"
	area.collision_layer = 0
	area.monitorable = false
	var hit_shape := CollisionShape3D.new()
	hit_shape.shape = capsule
	hit_shape.position.y = 1.0
	area.add_child(hit_shape)
	monster.add_child(area)
	var probe := RayCast3D.new()
	probe.name = "ClimbWallProbe"
	probe.position.y = 1.05
	probe.target_position = Vector3.BACK
	probe.enabled = true
	monster.add_child(probe)
	world.add_child(monster)
	monster.set_physics_process(false)
	return monster

func run() -> void:
	await collision_scenario(false)
	await collision_scenario(true)
	await collision_scenario(false, true)
	if failures.is_empty(): print("PASS: actual monster vehicle contact, queued RV damage, duplicate cooldown and boarding guards")
	quit(0 if failures.is_empty() else 1)

func collision_scenario(probe_contacts: bool, lethal: bool = false) -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	ground_shape.shape = box
	ground.add_child(ground_shape)
	world.add_child(ground)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	world.add_child(shell)
	var rv := shell.get_node("Chassis") as Chassis
	for i in range(90): await physics_frame
	rv.set_physics_process(false)
	rv.brake = 0.0
	var monster := monster_at(world, Vector3(0, 0.1, -13))
	if lethal:
		monster.max_health = 20.0
		monster.current_health = 20.0
	monster.probe_contacts = probe_contacts
	monster.set_physics_process(true)
	var nearby := monster_at(world, Vector3(8, 0.1, -13))
	var climber := monster_at(world, Vector3(0, 0.1, -13))
	climber.locomotion_state = Monster.LocomotionState.CLIMBING
	climber.get_node("CollisionShape").disabled = true
	var supported := monster_at(world, rv.global_position + Vector3(0, 2.2, -2))
	supported.rv_support.rv = rv
	supported.get_node("CollisionShape").disabled = true
	await physics_frame
	var initial_health := rv.get_engine().health
	var impacts: Array[Dictionary] = []
	rv.connect("vehicle_impact", func(kind: String, speed_loss: float, damage: float) -> void:
		if kind == "monster": impacts.append({"loss": speed_loss, "damage": damage}))
	rv.linear_velocity = Vector3.FORWARD * 12.0
	var consumed_health := -1.0
	var consumed_speed := -1.0
	for i in range(110):
		await physics_frame
		if monster.accepted_contacts > 0 and rv.get_engine().health < initial_health and consumed_health < 0.0:
			consumed_health = rv.get_engine().health
			consumed_speed = rv.linear_velocity.dot(Vector3.FORWARD)
		if lethal and consumed_health > 0.0:
			for j in range(3): await physics_frame
			break
	print("MONSTER_IMPACT probe=%s lethal=%s accepted=%s hp=%.3f->%.3f rv_hp=%.3f->%.3f rv_speed=%.3f->%.3f knockback=%s normal=%s events=%s" % [probe_contacts, lethal, monster.accepted_contacts, monster.health_before, monster.health_after, initial_health, consumed_health, monster.rv_speed_before, consumed_speed, monster.impact_velocity, monster.impact_normal, impacts])
	check(monster.accepted_contacts == 1, "Actual frontal monster contact is accepted once")
	check(monster.health_after < monster.health_before, "Vehicle contact preserves monster damage")
	check(monster.is_dead == lethal, "Lethal vehicle contact resolves monster death while preserving queued RV impact")
	var expected_knockback := monster.impact_normal * minf(monster.impact_approach * 1.5, 18.0) + Vector3.UP * 3.0
	check(monster.impact_velocity.is_equal_approx(expected_knockback), "Vehicle contact preserves outward knockback and adds the existing upward kick")
	check(monster.impact_velocity.dot(Vector3.FORWARD) > 3.0 and monster.impact_velocity.y > 0.0, "Actual frontal collision knocks monster forward and upward")
	check(monster.duplicate_health == monster.health_after, "Same-frame duplicate contact does not repeat monster damage")
	check(impacts.size() == 1, "Duplicate body, probe and Area contacts produce only one RV monster impact")
	if impacts.size() == 1:
		check(impacts[0].loss > 0.1 and impacts[0].loss < 1.0, "Monster impact reports a small actual loss of speed")
		check(is_equal_approx(initial_health - rv.get_engine().health, impacts[0].damage), "RV health loss matches one consumed impact")
	check(consumed_health > initial_health - 3.0 and consumed_health < initial_health, "Monster collision costs only a tiny amount of RV engine health")
	check(consumed_speed > 6.0 and consumed_speed < monster.rv_speed_before, "Monster contact slightly reduces RV speed while retaining travel")
	check(rv.get_engine().health == consumed_health, "Queued monster impact damages RV only once")
	if not lethal: check(rv.global_position.z < -14.0, "RV continues past struck monster")
	check(nearby.current_health == nearby.max_health and nearby.accepted_contacts == 0, "Standing beside passing RV is not an impact")
	check(climber.current_health == climber.max_health and climber.accepted_contacts == 0, "Climbing monster is not charged as a vehicle collision")
	check(climber.rv_overlap_events > 0, "Climbing guard is exercised by real RV overlap")
	check(supported.current_health == supported.max_health and supported.accepted_contacts == 0, "Monster supported by RV is not charged as a vehicle collision")
	check(supported.rv_overlap_events > 0, "Roof support guard is exercised by real RV overlap")
	world.queue_free()
	await process_frame
	await physics_frame

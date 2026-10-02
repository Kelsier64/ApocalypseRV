extends SceneTree
## Actual production Raker/Jolt handoff, directional hit, floor and recovery.
var failures: Array[String] = []
var world: Node3D
var modified_poses: Array[Transform3D] = []

class ImpactVehicle extends RigidBody3D:
	var queued := 0
	func vehicle_impact_point_velocity(_point: Vector3) -> Vector3: return linear_velocity
	func queue_monster_impact(_monster: Monster, _normal: Vector3, _point: Vector3, _speed: float) -> void: queued += 1

func _init() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error("FAIL: " + message)

func step(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func spawn_at(point: Vector3) -> Raker:
	var actor: Raker = load("res://enemies/raker.tscn").instantiate()
	actor.position = point
	actor.loot_drops = {}
	actor.detection_range = 0.0
	actor.move_speed = 0.0
	world.add_child(actor)
	return actor

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	world.add_child(ground)
	var rv := ImpactVehicle.new()
	rv.freeze = true
	world.add_child(rv)
	var actor := spawn_at(Vector3(0,-.25,0))
	await step(5)
	rv.linear_velocity = Vector3(0,0,-10)
	var accepted := actor._apply_vehicle_contact(rv, Vector3.FORWARD, actor.global_position + Vector3.UP)
	check(accepted and actor.ragdoll.pending and not actor.is_dead, "Strong nonlethal contact requests ragdoll")
	var health := actor.current_health
	actor._apply_vehicle_contact(rv, Vector3.FORWARD, actor.global_position + Vector3.UP)
	check(actor.current_health == health and rv.queued == 1, "Duplicate contact does not retrigger damage/effects")
	await step(2)
	check(actor.ragdoll.active and actor.body_collision_shape.disabled, "Physical bones replace control capsule")
	check(not actor.get_node("BodyMesh").animation_player.is_playing(), "Animation stops overwriting physical pose")
	check(actor.ragdoll.bodies.size() == 15, "Fifteen mapped major physical bones")
	var pelvis: PhysicalBone3D = actor.ragdoll.bodies["pelvis"]
	actor.ragdoll.simulator.modification_processed.connect(func():
		modified_poses.clear()
		for bone in actor.ragdoll.skeleton.get_bone_count(): modified_poses.append(actor.ragdoll.skeleton.get_bone_global_pose(bone)))
	check(pelvis.linear_velocity.z < -8 and pelvis.linear_velocity.y > 1, "Momentum survives lethal-order handoff and launches forward/up")
	var start := pelvis.global_position
	var max_gap := 0.0
	var max_speed := 0.0
	for frame in 420:
		await step(1)
		if not actor.ragdoll.active: continue
		for body: PhysicalBone3D in actor.ragdoll.bodies.values():
			check(body.global_transform.is_finite(), "Every physical body remains finite")
			check(body.global_basis.get_scale().distance_to(Vector3.ONE) < .01, "Scaled visual model produces scale-one rigid bodies")
			check(body.global_position.y > -.2, "Bodies do not fall through ground")
			max_speed = maxf(max_speed, body.linear_velocity.length())
			if modified_poses.size() == 54:
				var visible: Transform3D = actor.ragdoll.skeleton.global_transform * modified_poses[body.get_bone_id()] * body.body_offset
				check(visible.origin.distance_to(body.global_position) < .02, "Rendered bone pose follows physics")
		for link: Dictionary in actor.ragdoll.links:
			max_gap = maxf(max_gap, (link.child.global_transform * link.child.joint_offset).origin.distance_to((link.parent.global_transform * link.parent_frame).origin))
	print("RAKER_PHYSICS max_gap=",max_gap," max_speed=",max_speed," position=",actor.global_position," active=",actor.ragdoll.active)
	check(max_gap < .20 and max_speed < 35, "Joints remain connected without explosive velocities")
	check(actor.global_position.z < start.z-2, "Ragdoll travels in impact direction")
	check(not actor.ragdoll.is_busy() and not actor.body_collision_shape.disabled, "Settled survivor safely gets up")
	check(actor.current_health == health and not actor.is_dead, "Knockdown preserves health and life")
	# Fatal impact is still exactly one RV notification; corpses keep physics.
	rv.linear_velocity = Vector3(12,0,0)
	actor.current_health = 10
	actor.vehicle_impact_cooldown = 0
	actor._apply_vehicle_contact(rv, Vector3.RIGHT, actor.global_position+Vector3.UP)
	await step(3)
	check(actor.is_dead and actor.ragdoll.active, "Fatal impact uses ragdoll")
	check(actor.ragdoll.bodies["pelvis"].linear_velocity.x > 8, "Death receives final vehicle kick, not stale pre-damage velocity")
	check(WorldActorSnapshot.capture(actor).is_empty(), "Dead ragdoll is not saved as a living monster")
	actor.death_remaining = .1
	await step(15)
	check(not is_instance_valid(actor), "Corpse timer removes every physical body with actor")
	# Save/load a living physical pose without embedding a standing capsule.
	actor = spawn_at(Vector3(15, -.25, 0))
	await step(4)
	actor.ragdoll.request(Vector3.ZERO)
	await step(65)
	var saved := WorldActorSnapshot.capture(actor)
	var before: Vector3 = actor.ragdoll.bodies["pelvis"].global_position
	check(saved.has("ragdoll") and WorldActorSnapshot.validation_error(saved, "actor").is_empty(), "Living knockdown snapshot validates")
	actor.free()
	actor = WorldActorSnapshot.restore(saved, world)
	await step(2)
	check(actor.ragdoll.active and actor.ragdoll.bodies["pelvis"].global_position.distance_to(before) < .3, "Saved physical pose resumes at actual fallen position")
	var ceiling := StaticBody3D.new()
	var ceiling_collision := CollisionShape3D.new()
	var ceiling_box := BoxShape3D.new()
	ceiling_box.size = Vector3(10,.15,10)
	ceiling_collision.shape = ceiling_box
	ceiling.add_child(ceiling_collision)
	ceiling.position = Vector3(before.x,1.6,before.z)
	world.add_child(ceiling)
	await step(240)
	check(actor.ragdoll.active, "Blocked standing volume keeps survivor down without ceiling teleport")
	ceiling.queue_free()
	await step(300)
	check(not actor.ragdoll.is_busy(), "Restored survivor can recover")
	actor.free()
	actor = spawn_at(Vector3(-15,-.25,0))
	await step(4)
	rv.linear_velocity = Vector3.FORWARD * 3.5
	actor.locomotion_state = Monster.LocomotionState.CLIMBING
	check(not actor._apply_vehicle_contact(rv, Vector3.FORWARD, actor.global_position), "Climbing Raker contact is not an impact")
	actor.locomotion_state = Monster.LocomotionState.NORMAL
	actor.rv_support.rv = rv
	check(not actor._apply_vehicle_contact(rv, Vector3.FORWARD, actor.global_position), "Roof-supported Raker contact is not an impact")
	actor.rv_support.clear()
	var low_start := actor.global_position
	actor._apply_vehicle_contact(rv, Vector3.FORWARD, actor.global_position+Vector3.UP)
	await step(20)
	check(not actor.ragdoll.is_busy() and actor.global_position.z < low_start.z-1.0, "Light impact preserves knockback over AI movement without ragdoll")
	actor.set_physics_process(false)
	actor.velocity = Vector3(1,7,2)
	actor.released_carrier_velocity = Vector3(3,2,4)
	actor.die()
	check(actor.ragdoll.launch_velocity.is_equal_approx(Vector3(4,7,6)), "Death does not duplicate released carrier vertical velocity")
	world.queue_free()
	await step(2)
	for scenario in 4: await actual_vehicle_contact(scenario)
	if failures.is_empty(): print("PASS: Raker vehicle knockdown, ragdoll, physics stability, recovery, death and snapshots")
	quit(0 if failures.is_empty() else 1)

func actual_vehicle_contact(scenario: int) -> void:
	load("res://tests/raker_impact_playground.gd").selected = scenario
	var stage: Node3D = load("res://tests/raker_impact_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	while not stage.ready_to_drive: await step(1)
	stage.start()
	var max_forward := 0.0
	var max_up := 0.0
	var max_gap := 0.0
	for i in 960:
		await step(1)
		var actor: Raker = stage.monster
		if stage.impact_seen and stage.since_impact < .1:
			check(actor.is_dead == (scenario == 1), "Initial real impact has the scenario's lethal/nonlethal result")
		if not actor.ragdoll.active: continue
		var pelvis: PhysicalBone3D = actor.ragdoll.bodies["pelvis"]
		max_forward = maxf(max_forward, -pelvis.linear_velocity.z)
		max_up = maxf(max_up, pelvis.linear_velocity.y)
		for link: Dictionary in actor.ragdoll.links:
			max_gap = maxf(max_gap,(link.child.global_transform*link.child.joint_offset).origin.distance_to((link.parent.global_transform*link.parent_frame).origin))
	print("RAKER_REAL_RV case=",scenario," hit=",stage.impact_seen," max_forward=",max_forward," max_up=",max_up," gap=",max_gap," busy=",stage.monster.ragdoll.is_busy()," root=",stage.monster.global_position," rv=",stage.rv.global_position)
	check(stage.impact_seen, "Wheel-driven production RV actually hits production Raker")
	if scenario != 3: check(max_forward > 7 and max_up > 1, "Actual RV contact launches the physical body forward and upward")
	check(max_gap < .25, "Actual RV contact preserves joint connections")
	if scenario == 1: check(stage.monster.is_dead and stage.monster.ragdoll.active, "Actual fatal RV impact keeps corpse physics")
	else: check(not stage.monster.ragdoll.is_busy(), "Actual wheel-driven nonlethal hit ends with survivor recovery")
	stage.queue_free()
	await step(2)

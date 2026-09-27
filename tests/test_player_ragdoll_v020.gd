extends SceneTree
## Actual Jolt simulation, sampled at 120 Hz; independent of production Player.
const STAGE = preload("res://tests/player_ragdoll_v020/playground.tscn")
const OUTPUT := "res://docs/validation/player-v020-ragdoll/physics_audit.json"
var failures: Array[String] = []
var results: Array = []

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)

func steps(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	var original_hz := Engine.physics_ticks_per_second
	var original_world := root.world_3d
	var original_settings: Dictionary = {}
	for prop in ProjectSettings.get_property_list():
		if String(prop.name).begins_with("physics/jolt_physics_3d/"):
			original_settings[prop.name] = ProjectSettings.get_setting(prop.name)
	var stage: Node3D = STAGE.instantiate()
	root.add_child(stage)
	stage.set_physics_process(false)
	var actor: CharacterBody3D = stage.actor
	await steps(4)
	for key: String in original_settings:
		check(ProjectSettings.get_setting(key) == original_settings[key], "Global Jolt settings restored after isolated space creation")
	check(actor.bodies.size() == 14, "14 simple physical bodies")
	check(actor.skeleton.get_bone_count() == 41, "Imported 41-bone hierarchy retained")
	var total_mass := 0.0
	for body: PhysicalBone3D in actor.bodies.values():
		total_mass += body.mass
		check(body.get_bone_id() >= 0, "Every physical body maps to an imported bone")
		check(body.get_child(0).shape is CapsuleShape3D or body.get_child(0).shape is BoxShape3D, "Only primitive convex shapes")
	for link: Dictionary in actor.links:
		check(link.parent in link.child.get_collision_exceptions(), "Adjacent physical bodies cannot collide")
	var config: Array = actor.configuration()
	for index in stage.CASES.size():
		stage.reset_case(index)
		await steps(4)
		if index == 8:
			actor.animate = true
			actor.set_physics_process(true)
			await steps(12)
		if index == 2:
			actor.move_request = Vector3.RIGHT
			actor.set_physics_process(true)
			await steps(36)
		var start_pelvis: Vector3 = actor.bodies["pelvis"].global_position
		var root_before := actor.global_transform
		stage.start_case()
		check(actor.controller_shape.disabled and actor.simulator.is_simulating_physics(), "Ragdoll owns motion and disables character capsule")
		var metrics := {"case": stage.CASES[index], "max_joint_gap_m": 0.0, "max_speed_m_s": 0.0, "min_collider_y_m": INF, "max_skin_binding_error_m": 0.0, "max_scale_error": 0.0, "late_speed_m_s": 0.0, "late_angular_speed_rad_s": 0.0, "hinges": {}, "max_cone_excess_deg": 0.0, "max_twist_excess_deg": 0.0, "late_twist_excess_deg": 0.0, "max_hinge_excess_deg": 0.0, "max_terrain_penetration_m": 0.0, "terrain_contacts": {}}
		# The body spans three stair treads and takes longer to settle there.
		var sample_count := 1440 if index == 7 else 960
		metrics.samples = sample_count
		for frame in sample_count:
			await steps(1)
			for bone_name: String in actor.bodies:
				var body: PhysicalBone3D = actor.bodies[bone_name]
				check(body.global_transform.is_finite(), stage.CASES[index] + " finite transforms")
				metrics.max_speed_m_s = maxf(metrics.max_speed_m_s, body.linear_velocity.length())
				metrics.max_scale_error = maxf(metrics.max_scale_error, body.global_basis.get_scale().distance_to(Vector3.ONE))
				metrics.min_collider_y_m = minf(metrics.min_collider_y_m, shape_min_y(body))
				if frame % 4 == 0:
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = body.get_child(0).shape
					query.transform = body.global_transform
					query.collision_mask = 1
					var contacts := stage.get_world_3d().direct_space_state.collide_shape(query, 8)
					for contact in range(0, contacts.size(), 2):
						metrics.max_terrain_penetration_m = maxf(metrics.max_terrain_penetration_m, contacts[contact].distance_to(contacts[contact + 1]))
					for hit in stage.get_world_3d().direct_space_state.intersect_shape(query, 8):
						metrics.terrain_contacts[String(hit.collider.name)] = true
				if frame >= sample_count - 240:
					if body.linear_velocity.length() > metrics.late_speed_m_s:
						metrics.late_peak_bone = bone_name
					metrics.late_speed_m_s = maxf(metrics.late_speed_m_s, body.linear_velocity.length())
					metrics.late_angular_speed_rad_s = maxf(metrics.late_angular_speed_rad_s, body.angular_velocity.length())
				if actor.modified_poses.size() == 41:
					var skin_pose: Transform3D = actor.skeleton.global_transform * actor.modified_poses[body.get_bone_id()]
					var physical_pose := body.global_transform * body.body_offset.affine_inverse()
					metrics.max_skin_binding_error_m = maxf(metrics.max_skin_binding_error_m, skin_pose.origin.distance_to(physical_pose.origin))
			for link: Dictionary in actor.links:
				var parent: Transform3D = link.parent.global_transform * link.parent_frame
				var child: Transform3D = link.child.global_transform * link.child.joint_offset
				metrics.max_joint_gap_m = maxf(metrics.max_joint_gap_m, parent.origin.distance_to(child.origin))
				var relative := parent.basis.orthonormalized().inverse() * child.basis.orthonormalized()
				var joint: PhysicalBone3D = link.child
				if joint.joint_type == PhysicalBone3D.JOINT_TYPE_HINGE:
					var angle := -rad_to_deg(atan2(relative.x.y, relative.x.x))
					var key: String = joint.get("bone_name")
					if not metrics.hinges.has(key):
						metrics.hinges[key] = [angle, angle]
					metrics.hinges[key][0] = minf(metrics.hinges[key][0], angle)
					metrics.hinges[key][1] = maxf(metrics.hinges[key][1], angle)
					metrics.max_hinge_excess_deg = maxf(metrics.max_hinge_excess_deg, maxf(joint.get("joint_constraints/angular_limit_lower") - angle, angle - joint.get("joint_constraints/angular_limit_upper")))
				elif joint.joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
					var swing := rad_to_deg(acos(clampf(relative.x.x, -1, 1)))
					var q := relative.get_rotation_quaternion()
					var twist := absf(rad_to_deg(wrapf(2.0 * atan2(q.x, q.w), -PI, PI)))
					if twist - float(joint.get("joint_constraints/twist_span")) > metrics.max_twist_excess_deg:
						metrics.twist_peak_bone = joint.get("bone_name")
						metrics.twist_peak_frame = frame
					metrics.max_twist_excess_deg = maxf(metrics.max_twist_excess_deg, twist - float(joint.get("joint_constraints/twist_span")))
					if frame >= sample_count - 240:
						metrics.late_twist_excess_deg = maxf(metrics.late_twist_excess_deg, twist - float(joint.get("joint_constraints/twist_span")))
					if swing - float(joint.get("joint_constraints/swing_span")) > metrics.max_cone_excess_deg:
						metrics.cone_peak_bone = joint.get("bone_name")
						metrics.cone_peak_frame = frame
					metrics.max_cone_excess_deg = maxf(metrics.max_cone_excess_deg, swing - float(joint.get("joint_constraints/swing_span")))
		var end_pelvis: Vector3 = actor.bodies["pelvis"].global_position
		check(actor.global_transform.is_equal_approx(root_before), "Character movement does not compete with physics")
		if index == 6:
			check(metrics.terrain_contacts.has("Slope20deg"), "Slope test contacts the inclined surface")
		if index == 7:
			check(metrics.terrain_contacts.keys().filter(func(key): return key.begins_with("Step")).size() >= 2, "Stair test contacts multiple actual stair treads")
		if index == 0:
			# A small 3 N.s impulse must wake a settled body and remain stable.
			actor.bodies["spine_02"].apply_central_impulse(Vector3(3, 0, 0))
			var response := 0.0
			for frame in 240:
				await steps(1)
				response = maxf(response, actor.bodies["spine_02"].linear_velocity.length())
			metrics.small_impulse_peak_speed_m_s = response
			check(response > 0.01 and response < 2.0, "Settled ragdoll responds to a small external impulse")
		metrics.pelvis_drop_m = start_pelvis.y - end_pelvis.y
		metrics.final_pelvis = [end_pelvis.x, end_pelvis.y, end_pelvis.z]
		metrics.recovered = stage.recover_control()
		await steps(60)
		var recover_start := actor.global_position
		actor.move_request = Vector3.RIGHT
		await steps(60)
		actor.move_request = Vector3.ZERO
		metrics.control_distance_m = actor.global_position.distance_to(recover_start)
		metrics.physics_stopped = not actor.simulator.is_simulating_physics()
		metrics.control_capsule_enabled = not actor.controller_shape.disabled
		actor.animate = true
		var pose_before: Quaternion = actor.skeleton.get_bone_pose_rotation(actor.skeleton.find_bone("upper_arm_L"))
		await steps(40)
		var pose_after: Quaternion = actor.skeleton.get_bone_pose_rotation(actor.skeleton.find_bone("upper_arm_L"))
		metrics.animation_resumed = pose_before.angle_to(pose_after) > 0.05
		actor.animate = false
		check(metrics.max_joint_gap_m < 0.025, metrics.case + " joints stay connected")
		check(metrics.max_speed_m_s < 12.0, metrics.case + " no explosive velocities")
		check(metrics.min_collider_y_m > -0.03, metrics.case + " no floor tunnelling")
		check(metrics.max_terrain_penetration_m < 0.03, metrics.case + " limited contact overlap on actual terrain")
		check(metrics.max_skin_binding_error_m < 0.002, metrics.case + " skin follows physical bones")
		check(metrics.max_scale_error < 0.0002, metrics.case + " no physical stretching")
		check(metrics.late_speed_m_s < 0.10 and metrics.late_angular_speed_rad_s < 0.8, metrics.case + " settles without persistent jitter")
		check(metrics.max_hinge_excess_deg < 6.0 and metrics.max_cone_excess_deg < 6.0 and metrics.max_twist_excess_deg < 6.0, metrics.case + " anatomical joint limits hold")
		check(metrics.late_twist_excess_deg < 1.0, metrics.case + " no persistent twist beyond limits")
		check(metrics.recovered and metrics.physics_stopped and metrics.control_capsule_enabled and metrics.control_distance_m > 0.35 and metrics.animation_resumed, metrics.case + " recovery restores movement and TEST animation")
		results.append(metrics)
		print("RAGDOLL_CASE ", JSON.stringify(metrics))
	var report := {"godot": Engine.get_version_info().string, "physics": ProjectSettings.get_setting("physics/3d/physics_engine"), "display_server": DisplayServer.get_name(), "physics_hz": Engine.physics_ticks_per_second, "test_world_settings": stage.JOLT_TEST_SETTINGS, "mass_kg": total_mass, "configuration": config, "cases": results, "failures": failures}
	stage.free()
	check(Engine.physics_ticks_per_second == original_hz and root.world_3d == original_world, "Test simulation context restored on scene exit")
	FileAccess.open(OUTPUT, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	if failures.is_empty():
		print("PASS: player v020 ragdoll simulation and recovery")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func shape_min_y(body: PhysicalBone3D) -> float:
	var shape: Shape3D = body.get_child(0).shape
	var basis := body.global_basis
	if shape is BoxShape3D:
		var half: Vector3 = shape.size * 0.5
		return body.global_position.y - absf(basis.x.y) * half.x - absf(basis.y.y) * half.y - absf(basis.z.y) * half.z
	return body.global_position.y - absf(basis.y.y) * (shape.height * 0.5 - shape.radius) - shape.radius

extends SceneTree
const GrabRules = preload("res://core/raker_grab_rules.gd")
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var actor: Raker = load("res://enemies/raker.tscn").instantiate()
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(actor)
	world.add_child(player)
	actor.set_physics_process(false)
	player.set_physics_process(false)
	actor.target_player = player
	var visual := actor.get_node("BodyMesh")
	visual.set_process(false)
	var sk: Skeleton3D = visual.skeleton
	var modifier: SkeletonModifier3D = visual.pose_modifier
	modifier.active = false
	visual.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for variant in ["stand", "low", "seat"]:
		actor.set_crouched(variant != "stand")
		actor.position = Vector3(0, -.23, 0)
		player.position = Vector3(0, .02, -.8)
		# These authored solver fixtures use the legacy camera anchor in full.
		# The live scenarios below exercise the production full-body eye offset.
		player.camera.position = Vector3(0, 1.4146 if variant == "stand" else 1.05, 0)
		visual.animation_player.play("game/grab_" + variant + "_bite", 0)
		visual.animation_player.seek(.20 * actor.grab.BITE_SPEED, true)
		visual.animation_player.advance(0)
		var positions: Array[Vector3] = []
		for i in sk.get_bone_count(): positions.append(sk.get_bone_pose_position(i))
		actor.grab.victim = player
		actor.grab.phase = actor.grab.Phase.BITE
		actor.grab.elapsed = .20
		var before: float = (sk.global_transform * modifier.mouth_position(sk)).distance_to(player.camera.global_position)
		modifier._process_modification_with_delta(1.0 / 60)
		var after: float = (sk.global_transform * modifier.mouth_position(sk)).distance_to(player.camera.global_position)
		var face: Vector3 = actor.global_basis.inverse() * modifier.face_direction(sk)
		var elevation := asin(clampf(face.y,-1,1))
		check(elevation >= deg_to_rad(-25 if actor.crouched else -65)-.001 and elevation <= deg_to_rad(40 if actor.crouched else 30)+.001,"Evaluated bite face respects pitch limits: "+variant)
		check(absf(atan2(face.x,-face.z)) <= PI/2+.001,"Evaluated bite face respects yaw limits: "+variant)
		print("BITE_REACH ", variant, " before=",before," after=",after)
		check(after < .10 and after < before, "Mouth reaches player before damage: " + variant)
		for i in sk.get_bone_count(): check(positions[i].distance_to(sk.get_bone_pose_position(i)) < .00001,"No bone stretch/root translation")
		check(player.position == Vector3(0,.02,-.8),"Bite does not teleport victim")
	actor.grab.victim = null
	actor.grab.phase = actor.grab.Phase.NONE
	var original_near: float = player.camera.near
	player.begin_grab(actor,10)
	check(player.camera.near <= .01201, "Close bite face is not cut by the near plane")
	var rest_position: Vector3 = player.camera.position
	var anchor: Vector3 = player.camera.global_position
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2,2,.02)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = anchor + (actor.global_position-anchor).slide(Vector3.UP).normalized() * .15
	await physics_frame
	actor.grab.phase = actor.grab.Phase.BITE
	actor.grab.elapsed = .20
	modifier.world_positions["mouth"] = sk.to_local(anchor + Vector3.FORWARD * .4)
	player.grab_control._update_bite_pull()
	var toward_wall := (wall.global_position - anchor).slide(Vector3.UP).normalized()
	check((player.camera.global_position - anchor).dot(toward_wall) < .065,"Head sweep stops before the wall plane while allowing downward pull")
	var head_query := PhysicsShapeQueryParameters3D.new()
	var head_shape := SphereShape3D.new()
	head_shape.radius = .09
	head_query.shape = head_shape
	head_query.transform.origin = player.camera.global_position
	head_query.exclude = [player.get_rid(), actor.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_shape(head_query).is_empty(), "Pulled camera sphere does not overlap the wall")
	player.grab_control.end("test_wall")
	check(player.grab_control.recovery_camera == null,"Interrupted approach cannot start a post-contact arm turn")
	check(player.camera.position == rest_position,"Interrupted pull restores camera position")
	check(is_equal_approx(player.camera.near, original_near), "Interrupted grab restores the camera near plane")
	actor.grab.phase = actor.grab.Phase.NONE
	player.grab_control.bite_impact()
	player.grab_control._process(.3)
	check(player.grab_control.impact.color.a == 0,"Crush flash clears after release/death")
	world.free()
	var playground: Node3D = load("res://tests/raker_vehicle_playground.tscn").instantiate()
	root.add_child(playground)
	current_scene = playground
	for i in 75: await physics_frame
	for mode in [0,1,2]:
		playground.setup_grab(mode)
		var reached := false
		var held_view := Quaternion.IDENTITY
		var view_locked := false
		for i in 1200:
			await physics_frame
			var grab: Node = playground.player.grab_control
			if grab.active() and grab.camera_elapsed >= .2:
				var current: Quaternion = grab.camera.basis.get_rotation_quaternion()
				if not view_locked:
					held_view = current
					view_locked = true
				check(current.angle_to(held_view) < .001, "View stays fixed through hold and bite: %d" % mode)
			if playground.monster.grab.phase == playground.monster.grab.Phase.BITE and playground.monster.grab.elapsed >= .18:
				await process_frame
				var view: Camera3D = playground.player.seated_in.seat_camera if mode == 2 else playground.player.camera
				var mouth: Vector3 = playground.monster.get_node("BodyMesh").bone_world_position("mouth")
				var distance := mouth.distance_to(view.global_position)
				var face_center: Vector3 = playground.monster.grab_face_position()
				var face_axis: Vector3 = playground.monster.get_node("BodyMesh").bone_world_position("face_forward")-face_center
				var alignment := face_axis.normalized().dot((view.global_position-face_center).normalized())
				print("LIVE_FACE_ALIGNMENT ",mode," dot=",alignment)
				var mouth_in_view := (-view.global_basis.z).dot((mouth-view.global_position).normalized())
				print("LIVE_MOUTH_IN_VIEW ",mode," dot=",mouth_in_view)
				check(mouth_in_view > cos(deg_to_rad(view.fov * .4)),"Mouth stays inside the fixed view with a screen-edge margin: %d" % mode)
				print("LIVE_BITE_REACH ",mode," distance=",distance," mouth=",mouth," face=",view.global_position)
				check(distance < .10,"Live mouth contacts player in every scenario: %d" % mode)
				var rest: Vector3 = playground.player.grab_control.camera_rest_position
				check(view.position.distance_to(rest) <= .251,"Head pull stays within 25 cm")
				playground.monster.grab.cancel("test_release")
				check(view.position.distance_to(rest) < .00001,"Camera returns to body/seat anchor on release")
				reached = true
				break
		check(reached,"Bite stays valid until contact: %d" % mode)
		check(view_locked,"Captured view settled before bite: %d" % mode)
		if not reached: print("BITE_FAILED gate=",playground.monster.grab.contact_failure)
	# Arm contact has its own visible target, while the controller keeps its yaw.
	# Exercise the rendered modifier cache: reading raw bone poses here would
	# follow the unmodified mouth and teleport the detached arm out of the POV.
	for mode in [0, 1]:
		playground.player.body_state.reset()
		playground.player._apply_body_capabilities()
		playground.setup_grab(mode)
		var saw_arm_contact := false
		var opening_face_samples := 0
		var late_face_samples := 0
		var held_arm_view := Quaternion.IDENTITY
		for i in 1200:
			await physics_frame
			if playground.player.is_grabbed():
				var grab: Node = playground.player.grab_control
				grab.presses = GrabRules.minimum_wounded_presses(grab.required)
				if grab.camera_elapsed >= .3:
					if opening_face_samples == 0: held_arm_view = grab.camera.quaternion
					opening_face_samples += 1
					check(grab.camera.quaternion.angle_to(held_arm_view) < .001, "Face view stays fixed until actual bite contact: %d" % mode)
					check(grab.recovery_camera == null, "No delayed arm turn is scheduled before contact: %d" % mode)
					if playground.monster.grab.phase == playground.monster.grab.Phase.HOLD:
						if grab.remaining < .35: late_face_samples += 1
						check(grab.camera.position.distance_to(grab.camera_rest_position) < .0001, "Hold has no premature shoulder lean: %d" % mode)
						var face_direction: Vector3 = (playground.monster.grab_face_position() - grab.camera.global_position).normalized()
						check((-grab.camera.global_basis.z).dot(face_direction) > cos(deg_to_rad(20)), "Monster face remains central during the struggle: %d" % mode)
			if playground.monster.grab.phase == playground.monster.grab.Phase.BITE and playground.monster.grab.elapsed >= .19:
				await process_frame
				var view: Camera3D = playground.player.camera
				var mouth: Vector3 = playground.monster.get_node("BodyMesh").bone_world_position("mouth")
				var wound: Vector3 = playground.player.get_node("Visuals").bite_contact(&"left_arm").origin
				print("ARM_BITE_REACH ", mode, " distance=", mouth.distance_to(wound))
				check(mouth.distance_to(wound) < .12, "Rendered arm bite reaches the shoulder: %d" % mode)
				check(view.quaternion.angle_to(held_arm_view) < .001, "Bite approach still has no premature head turn: %d" % mode)
				saw_arm_contact = true
				break
		check(saw_arm_contact, "Arm bite reaches contact in ground/cabin: %d" % mode)
		check(opening_face_samples > 20, "Opening face view was sampled before the arm bite: %d" % mode)
		check(late_face_samples > 10, "Last 0.35 seconds of hold were sampled without turning: %d" % mode)
		if not saw_arm_contact: continue
		while playground.player.is_grabbed(): await physics_frame
		var limb: Node3D = get_nodes_in_group("player_detached_parts").back()
		for i in 11: await physics_frame
		var limb_anchor: Vector3 = limb.skeleton.to_global(limb.skeleton.get_bone_global_pose(limb.anchor_bone).origin)
		var rendered_mouth: Vector3 = playground.monster.get_node("BodyMesh").bone_world_position("mouth")
		print("HELD_ARM_MOUTH_ERROR ", mode, " distance=", limb_anchor.distance_to(rendered_mouth))
		check(limb.held > 0 and limb_anchor.distance_to(rendered_mouth) < .12, "Detached arm follows the evaluated mouth during recoil: %d" % mode)
		var released_view: Camera3D = playground.player.camera
		check(released_view.quaternion.angle_to(held_arm_view) > .5, "Camera turns toward the arm after contact: %d" % mode)
		check(not released_view.is_position_behind(rendered_mouth) and root.get_visible_rect().has_point(released_view.unproject_position(rendered_mouth)), "Post-contact turn reveals the mouth holding the torn arm: %d" % mode)
		playground.monster.grab.cancel("arm_test_complete")
	# Let the audio server retire playback before the accelerated test exits.
	playground.process_mode = Node.PROCESS_MODE_DISABLED
	for sound in playground.find_children("*", "AudioStreamPlayer3D", true, false): sound.stop()
	await process_frame
	playground.queue_free()
	for i in 4: await physics_frame
	for i in 4: await process_frame
	if failures.is_empty(): print("PASS: Bite reaches face, fixed bone lengths/root, flash cleanup")
	else:
		for note in failures: push_error(note)
	quit(0 if failures.is_empty() else 1)

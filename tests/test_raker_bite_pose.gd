extends SceneTree
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
		player.camera.position.y = 1.4146 if variant == "stand" else 1.05
		visual.animation_player.play("game/grab_" + variant + "_bite", 0)
		visual.animation_player.seek(.36, true)
		visual.animation_player.advance(0)
		var positions: Array[Vector3] = []
		for i in sk.get_bone_count(): positions.append(sk.get_bone_pose_position(i))
		actor.grab.victim = player
		actor.grab.phase = actor.grab.Phase.BITE
		actor.grab.elapsed = .36
		var before: float = (sk.global_transform * modifier.mouth_position(sk)).distance_to(player.camera.global_position)
		modifier._process_modification_with_delta(1.0 / 60)
		var after: float = (sk.global_transform * modifier.mouth_position(sk)).distance_to(player.camera.global_position)
		print("BITE_REACH ", variant, " before=",before," after=",after)
		check(after < .20 and after < before, "Mouth reaches face: " + variant)
		for i in sk.get_bone_count(): check(positions[i].distance_to(sk.get_bone_pose_position(i)) < .00001,"No bone stretch/root translation")
		check(player.position == Vector3(0,.02,-.8),"Bite does not teleport victim")
	actor.grab.victim = null
	actor.grab.phase = actor.grab.Phase.NONE
	player.begin_grab(actor,10)
	var rest_position: Vector3 = player.camera.position
	var anchor: Vector3 = player.camera.global_position
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2,2,.02)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = anchor + Vector3.FORWARD * .15
	await physics_frame
	actor.grab.phase = actor.grab.Phase.BITE
	actor.grab.elapsed = .32
	modifier.world_positions["mouth"] = sk.to_local(anchor + Vector3.FORWARD * .4)
	player.grab_control._update_bite_pull()
	check(player.camera.position.distance_to(rest_position) < .065,"Head sweep stops before a wall")
	player.grab_control.end("test_wall")
	check(player.camera.position == rest_position,"Interrupted pull restores camera position")
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
		for i in 1200:
			await physics_frame
			if playground.monster.grab.phase == playground.monster.grab.Phase.BITE and playground.monster.grab.elapsed >= .32:
				await process_frame
				var view: Camera3D = playground.player.seated_in.seat_camera if mode == 2 else playground.player.camera
				var mouth: Vector3 = playground.monster.get_node("BodyMesh").bone_world_position("mouth")
				var distance := mouth.distance_to(view.global_position)
				print("LIVE_BITE_REACH ",mode," distance=",distance," mouth=",mouth," face=",view.global_position)
				check(distance < .22,"Live moving scenario reaches face: %d" % mode)
				var rest: Vector3 = playground.player.grab_control.camera_rest_position
				check(view.position.distance_to(rest) <= .281,"Head pull stays within 28 cm")
				playground.monster.grab.cancel("test_release")
				check(view.position.distance_to(rest) < .00001,"Camera returns to body/seat anchor on release")
				reached = true
				break
		check(reached,"Bite stays valid until contact: %d" % mode)
		if not reached: print("BITE_FAILED gate=",playground.monster.grab.contact_failure)
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

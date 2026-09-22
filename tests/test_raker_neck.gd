extends SceneTree
const Modifier = preload("res://enemies/raker_pose_modifier.gd")
func _init() -> void: run.call_deferred()
func run() -> void:
	var failures: Array[String] = []
	for fps in [30,60,144]:
		var pose := Modifier.new()
		for direction in [Vector3.FORWARD,Vector3.LEFT,Vector3.RIGHT,Vector3.BACK,Vector3.UP,Vector3.DOWN]:
			for i in fps*2: pose.step_angles(direction,1.0/fps)
			if absf(pose.yaw)>PI/2+.0001 or pose.pitch>deg_to_rad(30)+.0001 or pose.pitch<deg_to_rad(-25)-.0001: failures.append("Bounds at %d FPS" % fps)
		pose.step_angles(Vector3(.001,0,1),1)
		var side: float = signf(pose.yaw)
		for i in fps:
			pose.step_angles(Vector3(.001 if i%2==0 else -.001,0,1),1.0/fps)
			if signf(pose.yaw)!=side: failures.append("Rear seam flips")
		for i in fps: pose.step_angles(Vector3.ZERO,1.0/fps,false)
		if absf(pose.yaw)+absf(pose.pitch)>.0001: failures.append("Return to baseline")
		for crouch in [false, true]:
			for i in fps * 2: pose.step_angles(Vector3.UP, 1.0 / fps, true, crouch)
			if absf(pose.pitch - deg_to_rad(40 if crouch else 30)) > .0001: failures.append("Posture upward cap")
		pose.step_angles(Vector3.UP, 1.0 / fps, true, false)
		if pose.pitch > deg_to_rad(30) + .0001: failures.append("Standing cap applies immediately after crouch")
		pose.free()
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var actor: Raker = load("res://enemies/raker.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	var target := Node3D.new()
	world.add_child(target)
	target.position = Vector3(-10,1.7,0)
	actor.target_player = target
	var visual := actor.get_node("BodyMesh")
	visual.set_process(false)
	visual.animation_player.play("game/idle")
	visual.animation_player.advance(0)
	visual.animation_player.pause()
	var sk: Skeleton3D = visual.skeleton
	var original: Array[Vector3] = []
	for name in Modifier.BONES: original.append(sk.get_bone_pose_position(sk.find_bone(name)))
	for i in 90: await process_frame
	var first: Array[Quaternion] = []
	for name in Modifier.BONES: first.append(sk.get_bone_pose_rotation(sk.find_bone(name)))
	for i in 90: await process_frame
	for i in Modifier.BONES.size():
		var bone := sk.find_bone(Modifier.BONES[i])
		if sk.get_bone_pose_position(bone).distance_to(original[i])>.00001: failures.append("Neck must not stretch")
		if first[i].angle_to(sk.get_bone_pose_rotation(bone))>.002: failures.append("Post-animation rotation must not accumulate")
	world.free()
	if failures.is_empty(): print("PASS: Neck bounds, rear seam and tick rates")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

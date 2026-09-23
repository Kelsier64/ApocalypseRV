extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var actor: Raker = load('res://enemies/raker.tscn').instantiate()
	var player: CharacterBody3D = load('res://player/player.tscn').instantiate()
	world.add_child(actor)
	world.add_child(player)
	actor.set_physics_process(false)
	player.set_physics_process(false)
	actor.position.y = -.25
	actor.target_player = player
	var visual := actor.get_node('BodyMesh')
	visual.set_process(false)
	var sk: Skeleton3D = visual.skeleton
	var modifier: SkeletonModifier3D = visual.pose_modifier
	modifier.active = false
	visual.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for height in [1.16,1.43,1.70]:
		for clip in ['grab_stand_reach','grab_stand_hold','grab_stand_bite']:
			for turn in [-.5,0,.5]:
				actor.rotation.y = turn
				player.position = actor.global_basis*Vector3(0,0,-.8)
				player.camera.position.y = height
				sk.reset_bone_poses()
				visual.animation_player.play('game/'+clip,0)
				visual.animation_player.seek(.32,true)
				visual.animation_player.advance(0)
				actor.grab.victim = player
				actor.grab.phase = actor.grab.Phase.BITE if clip.ends_with('bite') else (actor.grab.Phase.REACH if clip.ends_with('reach') else actor.grab.Phase.HOLD)
				actor.grab.elapsed = .6 if clip.ends_with("reach") else .32
				modifier.tracking_weight = 1
				var positions: Array[Vector3] = []
				for i in sk.get_bone_count(): positions.append(sk.get_bone_pose_position(i))
				var spine: Array[Quaternion] = []
				for name in ['spine_01','spine_02','spine_03']: spine.append(sk.get_bone_pose_rotation(sk.find_bone(name)))
				modifier._process_modification_with_delta(1)
				var toward: Vector3 = (player.camera.global_position-sk.to_global(modifier.face_position(sk))).normalized()
				var alignment: float = modifier.face_direction(sk).dot(toward)
				check(alignment > .985,'Face points at visible player: %s height %.2f turn %.1f dot %.4f' % [clip,height,turn,alignment])
				print('ATTACK_AIM ',clip,' height=',height,' turn=',turn,' dot=',alignment)
				for i in 3: check(spine[i].angle_to(sk.get_bone_pose_rotation(sk.find_bone('spine_0'+str(i+1)))) < .001,'Standing grab must not add a torso bow')
				# Independent anatomical landmarks: do not reuse the solver's palm
				# frame/sign, which previously let backwards hands pass this test.
				for side in [-1,1]:
					var suffix := '_R' if side > 0 else '_L'
					var hand := sk.to_global(sk.get_bone_global_pose(sk.find_bone('hand'+suffix)).origin)
					var finger := sk.to_global(sk.get_bone_global_pose(sk.find_bone('middle_01'+suffix)).origin)
					var thumb := sk.to_global(sk.get_bone_global_pose(sk.find_bone('thumb_01'+suffix)).origin)
					check((finger-hand).normalized().dot(-actor.global_basis.z) > .8,'Fingers reach beyond wrist toward player, not monster')
					check((thumb-hand).dot(actor.global_basis.x*float(-side)) > .025,'Both thumbs point inward toward neck')
					var distal := (sk.global_basis*sk.get_bone_global_pose(sk.find_bone('middle_02'+suffix)).basis.y).normalized()
					check(distal.dot(Vector3.DOWN) > .9,'Fingertips bend down over chest')
				for i in sk.get_bone_count(): check(sk.get_bone_pose_position(i).distance_to(positions[i]) < .00001,'Rotations preserve joints/root')
	actor.grab.victim = null
	world.free()
	if failures.is_empty(): print('PASS: Standing neck-only eye contact, unchanged spine, anatomical hands and fixed joints')
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

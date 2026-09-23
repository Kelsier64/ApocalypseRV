extends SceneTree
## Independent anatomical landmarks catch backwards joints even when thumbs pass.
var failures: Array[String] = []
var checked := 0
func _init() -> void: run.call_deferred()

func verify(sk: Skeleton3D, label: String) -> void:
	for side in [-1,1]:
		var suffix := '_L' if side < 0 else '_R'
		var wrist := sk.get_bone_global_pose(sk.find_bone('hand'+suffix)).origin
		var middle := sk.get_bone_global_pose(sk.find_bone('middle_01'+suffix)).origin
		var thumb := sk.get_bone_global_pose(sk.find_bone('thumb_01'+suffix)).origin
		var forward := (middle-wrist).normalized()
		var lateral := (thumb-middle).slide(forward).normalized()
		var palm := forward.cross(lateral)*float(-side)
		for finger in ['index','middle','ring','pinky']:
			var base := sk.get_bone_global_pose(sk.find_bone(finger+'_01'+suffix))
			var joint := sk.get_bone_global_pose(sk.find_bone(finger+'_02'+suffix))
			var proximal := (joint.origin-base.origin).normalized()
			var distal := joint.basis.y.normalized()
			var inward := palm.slide(proximal).normalized()
			var mcp := rad_to_deg(atan2(proximal.dot(palm),proximal.dot(forward)))
			var pip := rad_to_deg(atan2(distal.dot(inward),distal.dot(proximal)))
			var tip_bone := sk.find_bone(finger+'_03'+suffix)
			if tip_bone < 0:
				failures.append('Rebuilt hand needs a third phalanx: '+finger+suffix)
				continue
			var tip := sk.get_bone_global_pose(tip_bone).basis.y.normalized()
			var dip := rad_to_deg(atan2(tip.dot(palm.slide(distal).normalized()),tip.dot(distal)))
			checked += 1
			var bind_pose := label == 'REST'
			if mcp < (-.5 if bind_pose else 2.0) or pip < (-.5 if bind_pose else 10.0) or pip > 71.0 or dip < (-.5 if bind_pose else 5.0) or dip > 50:
				failures.append('%s %s%s MCP %.2f PIP %.2f DIP %.2f' % [label,finger,suffix,mcp,pip,dip])

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var actor: Raker = load('res://enemies/raker.tscn').instantiate()
	var player = load('res://player/player.tscn').instantiate()
	world.add_child(actor)
	world.add_child(player)
	actor.set_physics_process(false)
	player.set_physics_process(false)
	player.position = Vector3(0,0,-.9)
	actor.target_player = player
	var visual := actor.get_node('BodyMesh')
	visual.set_process(false)
	visual.pose_modifier.active = false
	var sk: Skeleton3D = visual.skeleton
	var anim: AnimationPlayer = visual.animation_player
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	sk.reset_bone_poses()
	verify(sk,'REST')
	var clips := 0
	for clip in anim.get_animation_list():
		if not clip.begins_with('game/'): continue
		clips += 1
		anim.play(clip,0)
		for sample in range(17):
			anim.seek(anim.current_animation_length*sample/16.0,true)
			anim.advance(0)
			verify(sk,clip+' sample '+str(sample))
	for variant in ['stand','low','seat']:
		actor.crouched = variant != 'stand'
		player.camera.position.y = 1.7 if variant == 'stand' else 1.1
		for phase in ['reach','hold','bite']:
			anim.play('game/grab_'+variant+'_'+phase,0)
			for sample in range(13):
				var seconds := anim.current_animation_length*sample/12.0
				anim.seek(seconds,true)
				anim.advance(0)
				actor.grab.victim = player
				actor.grab.phase = actor.grab.Phase.REACH if phase == 'reach' else (actor.grab.Phase.HOLD if phase == 'hold' else actor.grab.Phase.BITE)
				actor.grab.elapsed = seconds
				visual.pose_modifier._process_modification_with_delta(.1)
				verify(sk,'runtime '+variant+' '+phase+' '+str(sample))
	actor.grab.victim = null
	world.free()
	if clips != 41: failures.append('Expected all 41 clips, got '+str(clips))
	if failures.is_empty(): print('PASS: REST, 41 source clips and 9 runtime grip phases bend toward palms; ',checked,' finger samples')
	else:
		for failure in failures.slice(0,16): push_error(failure)
		push_error(str(failures.size())+' finger flexion failures')
	quit(0 if failures.is_empty() else 1)

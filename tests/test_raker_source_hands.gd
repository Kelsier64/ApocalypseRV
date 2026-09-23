extends SceneTree
## Verify the imported Blender animation itself, with runtime pose fixes OFF.
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func run() -> void:
	var actor: Raker = load('res://enemies/raker.tscn').instantiate()
	root.add_child(actor)
	actor.set_physics_process(false)
	var visual := actor.get_node('BodyMesh')
	visual.set_process(false)
	visual.pose_modifier.active = false
	var sk: Skeleton3D = visual.skeleton
	var anim: AnimationPlayer = visual.animation_player
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in ['idle','walk','chase','sprint','crouch_idle','crouch_walk','grab_stand_hold','grab_low_hold','grab_seat_hold']:
		anim.play('game/'+clip,0)
		for sample in range(9):
			anim.seek(anim.current_animation_length*sample/8.0,true)
			anim.advance(0)
			for side in [-1,1]:
				var suffix := '_L' if side < 0 else '_R'
				var wrist := sk.to_global(sk.get_bone_global_pose(sk.find_bone('hand'+suffix)).origin)
				var middle := sk.to_global(sk.get_bone_global_pose(sk.find_bone('middle_01'+suffix)).origin)
				var thumb := sk.to_global(sk.get_bone_global_pose(sk.find_bone('thumb_01'+suffix)).origin)
				var fingers := (middle-wrist).normalized()
				var lateral := (thumb-middle).slide(fingers).normalized()
				var palm := fingers.cross(lateral)*float(-side)
				var note := '%s frame %d side %d' % [clip,sample,side]
				if clip.begins_with('grab_'):
					check(lateral.dot(actor.global_basis.x*float(-side))>.98,'Grab thumb toward neck: '+note)
					check(fingers.dot(-actor.global_basis.z)>.8 and palm.dot(Vector3.DOWN)>.8,'Grab palm down and fingers forward: '+note)
				else:
					check(lateral.dot(-actor.global_basis.z)>.7,'Source thumb must face FORWARD: '+note)
					check(palm.dot(actor.global_basis.x*float(-side))>.8,'Source palm must face INWARD: '+note)
	actor.free()
	if failures.is_empty(): print('PASS: Blender source thumbs forward/palms inward in six gaits; anatomical grip in three variants, runtime modifier disabled')
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

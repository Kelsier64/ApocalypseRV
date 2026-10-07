extends SceneTree
## Evaluate exported skin, attachment, clip timing and independent instances.
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok and note not in failures: failures.append(note); push_error("FAIL: " + note)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var actor: BarrelMan = load("res://enemies/barrel_man.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	var visual = actor.get_node("BodyMesh")
	visual.set_physics_process(false)
	visual.ground_modifier.active = false
	var sk: Skeleton3D = visual.skeleton
	var ap: AnimationPlayer = visual.animation_player
	check(sk.get_bone_count() == 11, "Eleven anatomical and attachment bones are exported")
	var names := ["disguised","rise","idle","run","sprint","turn_left","turn_right","retract","fall","land"]
	check(ap.get_animation_library("game").get_animation_list().size() == names.size(), "Ten authored clips, no unrelated Blender scene")
	var surfaces: Array[Dictionary] = []
	var triangles := 0
	for node in visual.meshes:
		var mesh := node as MeshInstance3D
		if mesh.skin == null: continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bone_indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			check(bone_indices.size() == positions.size()*4 and weights.size() == positions.size()*4, "Four bounded skin influences per vertex")
			for vertex in positions.size():
				var sum := 0.0
				for influence in range(4): sum += weights[vertex*4+influence]
				check(absf(sum-1.0) < .001, "Skin weights sum to one")
			surfaces.append({"mesh":mesh,"positions":positions,"bones":bone_indices,"weights":weights})
	check(triangles < 45000, "Legs and detailed nails stay below 45k triangles")
	var metrics: Array = []
	for name in names:
		var animation := ap.get_animation("game/"+name)
		check(animation != null, "Clip exists: "+name)
		var looping: bool = name in visual.LOOPS
		check(animation.loop_mode == (Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE), "Clip loop policy: "+name)
		for track in animation.get_track_count():
			var path := str(animation.track_get_path(track))
			check(path.contains("Skeleton3D:"), "Only bones are animated; gameplay root stays fixed")
			if looping and animation.track_get_key_count(track)>1:
				var first: Variant = animation.track_get_key_value(track,0)
				var last: Variant = animation.track_get_key_value(track,animation.track_get_key_count(track)-1)
				check(first.is_equal_approx(last), "Loop endpoints agree: "+name)
		var minimum := INF
		var maximum := -INF
		var hidden_radius := 0.0
		var shell_radius := 0.0
		var frames := ceili(animation.length*60)
		for frame in range(frames+1):
			ap.play("game/"+name,0)
			ap.seek(animation.length*float(frame)/maxi(1,frames),true)
			ap.advance(0)
			sk.force_update_all_bone_transforms()
			var barrel_inverse := sk.get_bone_global_pose(visual.barrel_bone).affine_inverse()
			var barrel_rest := sk.get_bone_global_rest(visual.barrel_bone).basis
			for data in surfaces:
				var binds: Array[Transform3D] = []
				var mesh: MeshInstance3D = data.mesh
				for bind in mesh.skin.get_bind_count():
					var bone := sk.find_bone(mesh.skin.get_bind_name(bind))
					check(bone >= 0, "Named skin bone resolves")
					binds.append(sk.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind))
				for vertex in data.positions.size():
					var point := Vector3.ZERO
					for influence in range(4): point += (binds[data.bones[vertex*4+influence]]*data.positions[vertex])*data.weights[vertex*4+influence]
					minimum = minf(minimum,point.y)
					maximum = maxf(maximum,point.y)
					if name == "disguised": hidden_radius = maxf(hidden_radius,Vector2(point.x,point.z).length())
					var in_barrel: Vector3 = barrel_rest * (barrel_inverse * point)
					if in_barrel.y > -.49: shell_radius = maxf(shell_radius,Vector2(in_barrel.x,in_barrel.z).length())
		check(minimum >= -.025, "No substantial floor penetration: "+name)
		check(maximum < 1.20, "Skin stays inside the humanoid lower-body envelope: "+name)
		check(shell_radius < .32959, "Legs do not emerge through barrel walls: "+name)
		if name == "disguised":
			check(hidden_radius < .31 and minimum >= 0.0 and maximum < 1.0, "Disguised legs including toenails fully fit inside barrel")
		metrics.append({"clip":name,"frames":frames+1,"min_y":minimum,"max_y":maximum,"hidden_radius":hidden_radius,"shell_radius":shell_radius})
	visual._play("idle",0)
	ap.seek(0,true)
	ap.advance(0)
	check(visual.get_blast_origin().distance_to(Vector3(0,1.4,0))<.01, "Standing explosion follows actual shared barrel anchor")
	var second: BarrelMan = load("res://enemies/barrel_man.tscn").instantiate()
	world.add_child(second)
	second.set_physics_process(false)
	second.get_node("BodyMesh").set_physics_process(false)
	check(second.get_node("BodyMesh").animation_player != ap, "Instances have independent playback")
	check(second.get_node("BodyMesh").flash_material != visual.flash_material, "Damage flashes do not modify another monster")
	# Grounding must preserve authored push-off height, not snap every ankle to
	# its standing height and drive the rolled toes through the floor.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20,.2,20)
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	floor_body.position.y = -.1
	second.position.x = 5
	actor.position.y = .001
	actor.phase = BarrelMan.Phase.CHASE
	await physics_frame
	actor.velocity = Vector3(0,-1,0)
	actor.move_and_slide()
	check(actor.is_on_floor(), "Grounding fixture contacts the actual flat floor")
	ap.play("game/run",0)
	ap.seek(.12,true)
	ap.advance(0)
	var foot_bone := sk.find_bone("foot_R")
	var before := sk.get_bone_global_pose(foot_bone).origin
	check(before.y > .15, "Push-off fixture has an intentionally lifted ankle")
	visual.ground_modifier._process_modification_with_delta(1.0/60.0)
	var after := sk.get_bone_global_pose(foot_bone).origin
	check(before.distance_to(after) < .005, "Flat-ground correction preserves authored heel/toe push-off")
	print("BARREL_ASSET_METRICS "+JSON.stringify({"triangles":triangles,"clips":metrics}))
	var out := FileAccess.open("res://.godot/barrel-asset-audit.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"triangles":triangles,"clips":metrics,"failures":failures},"\t"))
	out.close()
	world.queue_free()
	await process_frame
	await physics_frame
	if failures.is_empty(): print("PASS: barrel imported skin, hidden legs, all 60Hz animation poses and shared barrel anchor")
	quit(0 if failures.is_empty() else 1)

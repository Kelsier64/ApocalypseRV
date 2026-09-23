extends SceneTree
var failures: Array[String] = []
var world: Node3D
var actor: Raker
var player: CharacterBody3D
class TargetDummy:
	extends Node3D
	func take_damage(_amount: float) -> void: pass

func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func step(count: int) -> void:
	for i in count:
		await physics_frame
		if is_instance_valid(actor): actor._physics_process(1.0/60.0)
func box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = position
	return body
func reset_combat() -> void:
	actor.strike_elapsed = -1
	actor.strike_target = {}
	actor.attack_timer = 0
	actor.reaction_remaining = 0
	actor.position = Vector3(0,-.25,0)
	actor.rotation = Vector3.ZERO
	actor.velocity = Vector3.ZERO
	player.position = Vector3(0,-.25,-1.05)
	player.current_player_health = 1000
	player.damage_cooldown = 0
	# Climbing targets intentionally retain the original sweep contract.
	player.locomotion_state = player.LocomotionState.CLIMBING
func request_attack() -> void:
	actor._execute_attack_on_target(actor._build_combat_target(player,"player"))

func _run() -> void:
	world=Node3D.new()
	root.add_child(world)
	current_scene=world
	box(Vector3(0,-.1,0),Vector3(100,.2,100))
	player=load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	actor=load("res://enemies/raker.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.target_player=player
	actor.loot_drops={}
	reset_combat()
	var model: Node3D=actor.get_node("BodyMesh/Model")
	var skeleton: Skeleton3D=model.find_child("Skeleton3D",true,false)
	var mesh: MeshInstance3D=model.find_child("Raker_Mesh",true,false)
	check(skeleton.get_bone_count()==54,"54 deform bones including jaw and eight new distal finger joints imported")
	check(absf(mesh.get_aabb().size.y-2.18)<.001 and model.scale==Vector3.ONE,"Full 2.18 m source imported without shrinking")
	check(absf(actor.body_collision_shape.shape.height-2.18)<.001,"Standing collider is 2.18 m")
	check(not mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].is_empty(),"v007 UV survives export")
	var rebuilt_skin := false
	var rebuilt_nails := false
	for surface in mesh.mesh.get_surface_count():
		var skin := mesh.get_active_material(surface) as StandardMaterial3D
		check(skin != null,"Every imported surface has its material")
		if skin == null: continue
		if skin.resource_name == "Raker018_OralCavity":
			check(skin.albedo_color.get_luminance() < .2,"Rebuilt oral cavity retains its dark lining")
		elif skin.resource_name == "Raker021_WornNails":
			rebuilt_nails = true
			check(is_equal_approx(skin.roughness,.78) and skin.albedo_color.is_equal_approx(Color(.18,.165,.125).linear_to_srgb()),"New nail faces retain authored roughness and linear-to-sRGB keratin color")
		else:
			check(skin.albedo_texture != null,"Skin, eyes and internal tooth textures survive production import")
			if skin.resource_name == "Raker021_RebuiltHandSkin":
				rebuilt_skin = skin.albedo_texture != null and skin.albedo_texture.get_width() >= 1024
	check(rebuilt_skin and rebuilt_nails,"New hand UV atlas and sculpted nail surfaces imported")
	var anim: AnimationPlayer=model.get_node("AnimationPlayer")
	anim.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in ["idle","walk","chase","sprint","attack_left","attack_right","crouch_idle","crouch_walk","crouch_attack","climb_loop","hang_idle","attack_door","mantle","roof_settle","attack_down","slip_loop","fall_loop","land","hit_react","death","crouch_hit_react","crouch_land","crouch_death"]:
		check(anim.has_animation("game/"+clip),"Imported animation "+clip)
		anim.play("game/"+clip)
		for i in 20:
			anim.advance(.1)
			check(skeleton.get_bone_pose_position(skeleton.find_bone("root")).length()<.001,"No root drift "+clip)
		if clip in actor.get_node("BodyMesh").LOOPS:
			anim.seek(0,true)
			var starts: Array[Transform3D]=[]
			for bone in skeleton.get_bone_count(): starts.append(skeleton.get_bone_pose(bone))
			anim.seek(anim.current_animation_length-.000001,true)
			for bone in skeleton.get_bone_count():
				check(starts[bone].origin.distance_to(skeleton.get_bone_pose_position(bone))<.001,"Loop position seam "+clip)
				check(absf(starts[bone].basis.get_rotation_quaternion().dot(skeleton.get_bone_pose_rotation(bone)))>.999,"Loop rotation seam "+clip)
	await physics_frame
	for variant in ["stand", "low", "seat"]:
		for phase in {"reach":.6,"hold":1.0,"bite":.65,"release":.35,"escape":.45,"miss":.45}:
			var clip: String = "game/grab_" + variant + "_" + phase
			check(anim.has_animation(clip), "Grab variant imported " + clip)
			var durations := {"reach":.6,"hold":1.0,"bite":.65,"release":.35,"escape":.45,"miss":.45}
			check(absf(anim.get_animation(clip).length - durations[phase]) < .018, "Authored duration " + clip)
			anim.play(clip)
			for i in 20:
				anim.advance(.04)
				check(skeleton.get_bone_pose_position(skeleton.find_bone("root")).length()<.001,"Grab root stays fixed " + clip)
	request_attack()
	check(actor.strike_elapsed==0 and player.current_player_health==1000,"Telegraph begins without instant damage")
	actor._tick_strike(.70)
	check(player.current_player_health==1000,"Windup remains harmless")
	actor._tick_strike(.04)
	check(player.current_player_health==976,"One 24 damage hit at contact")
	actor._tick_strike(.3)
	check(player.current_player_health==976,"No double damage during follow through")
	reset_combat()
	request_attack()
	player.position.x=3
	actor._tick_strike(.8)
	check(player.current_player_health==1000,"Evading range during windup avoids damage")
	reset_combat()
	request_attack()
	player.position=Vector3(0,-.25,1.5)
	actor._tick_strike(.8)
	check(player.current_player_health==1000,"Locked facing allows sidestep behind attacker")
	reset_combat()
	request_attack()
	var wall:=box(Vector3(0,1,-.7),Vector3(4,3,.15))
	await physics_frame
	actor._tick_strike(.8)
	check(player.current_player_health==1000,"New obstruction blocks committed attack")
	wall.free()
	reset_combat()
	request_attack()
	actor.take_damage(10)
	actor._tick_strike(1)
	check(actor.strike_elapsed<0 and player.current_player_health==1000,"Heavy hit interrupts pending attack")
	actor.set_crouched(true)
	actor.take_damage(10)
	check(anim.current_animation=="game/crouch_hit_react","Low hit reaction preserves low posture")
	var ceiling:=box(Vector3(0,1.8,0),Vector3(4,.2,4))
	await physics_frame
	check(not actor.can_stand(),"Low ceiling blocks standing capsule")
	actor._update_posture()
	check(actor.crouched and absf(actor.body_collision_shape.shape.height-1.6)<.001,"Low posture retains actual smaller collider")
	ceiling.free()
	await physics_frame
	actor._update_posture()
	check(not actor.crouched,"Stands when headroom returns")
	var snapshot:=WorldActorSnapshot.capture(actor)
	check(WorldActorSnapshot.validation_error(snapshot,"raker").is_empty(),"New species accepted by save validation")
	var restored: Raker=WorldActorSnapshot.restore(snapshot,world)
	check(restored is Raker and restored.current_health==actor.current_health,"Save restores species and health")
	restored.loot_drops={}
	restored.set_crouched(true)
	restored.take_damage(10000)
	check(restored.get_node("BodyMesh").animation_player.current_animation=="game/crouch_death","Low death never starts from standing pose")
	restored.free()
	reset_combat()
	var disposable:=TargetDummy.new()
	world.add_child(disposable)
	disposable.position=Vector3(0,-.25,-1)
	actor._execute_attack_on_target(actor._build_combat_target(disposable,"player"))
	disposable.free()
	actor._tick_strike(1)
	check(actor.strike_resolved,"Deleted target is discarded safely at contact")
	# Exercise the real production spawn method with actual deterministic plans.
	var chunk:=ChunkGenerator.new()
	world.add_child(chunk)
	chunk.field=WorldField.new(42)
	var container:=WorldEntities.get_container(chunk)
	var existing:=container.get_children()
	var covered_buckets: Array[int]=[]
	var covered_multiple:=false
	for site_index in range(24):
		var expected:=chunk.field.enemy_count(site_index)
		chunk.sites.assign([{"kind":"maintenance","index":site_index,"building":Transform3D.IDENTITY,"frame":Transform3D.IDENTITY,"side":1}])
		chunk._spawn_actors()
		var spawned:=0
		for child in container.get_children():
			if child in existing: continue
			if child is Monster:
				spawned+=1
				check(child is Raker,"Every new outdoor enemy uses Raker at site %d" % site_index)
				check(child.scene_file_path=="res://enemies/raker.tscn","Outdoor spawn uses the production Raker scene")
			child.free()
		check(spawned==expected,"Outdoor replacement preserves the planned enemy count")
		if expected>0 and site_index%3 not in covered_buckets: covered_buckets.append(site_index%3)
		if expected>1: covered_multiple=true
	check(covered_buckets.size()==3 and covered_multiple,"Spawn regression covers all former selection branches and second enemies")
	chunk.free()
	reset_combat()
	player.position=Vector3(0,-.25,-6)
	actor.ai_state=Monster.State.CHASE
	await step(150)
	check(actor.position.z< -2,"New AI actually pursues real player")
	reset_combat()
	request_attack()
	actor.take_damage(10000)
	actor._tick_strike(1)
	check(actor.is_dead and player.current_player_health==1000,"Death cancels pending attack")
	check(actor.get_node("BodyMesh").animation_player.current_animation=="game/death","Death animation replaces shrink")
	await step(130)
	check(not is_instance_valid(actor),"Death cleans up after animation")
	world.free()
	if failures.is_empty(): print("PASS: Raker dimensions, 23 clips, root, combat, posture, pursuit, save and death")
	else:
		for failure in failures: push_error("FAIL: "+failure)
	quit(0 if failures.is_empty() else 1)

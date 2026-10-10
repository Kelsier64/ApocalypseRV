extends SceneTree
## Real imported foot poses, first-contact shielding and ordinary live Player damage.
const PLAYER := preload("res://player/player.tscn")
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var giant: SlenderSpeaker
var landed: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func frames(count := 2) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func box(body: Node3D, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func reset_player(point := Vector3.ZERO) -> void:
	giant.set_physics_process(false)
	if is_instance_valid(player.seated_in): player.seated_in.exit_seat(true)
	player.ragdoll_control.stop()
	player.is_player_dead = false
	player.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0,
		"transform": Transform3D(Basis.IDENTITY, point)})
	player.damage_cooldown = 0.0
	player.set_physics_process(false)
	for child in player.get_node("Visuals").get_children():
		if child.name == "Locomotion": child._physics_process(.7)
	giant.position = Vector3.ZERO
	giant.rotation = Vector3.ZERO
	giant.velocity = Vector3.ZERO
	giant.target_player = null
	giant.target_vehicle = null
	giant.reset_after_restore()
	giant._sample("idle_play", 0.0)
	landed.clear()

func move_foot(side: String, displacement: Vector3) -> void:
	# Alter the imported foot bone, leaving the giant's body capsule stationary.
	# This exercises the same posed geometry as an animated kick or footfall.
	var skeleton: Skeleton3D = giant.visual.skeleton
	var index := skeleton.find_bone("foot." + side)
	var parent := skeleton.get_bone_parent(index)
	var parent_world := skeleton.global_transform * skeleton.get_bone_global_pose(parent)
	skeleton.set_bone_pose_position(index, skeleton.get_bone_pose_position(index) + parent_world.basis.inverse() * displacement)
	skeleton.force_update_all_bone_transforms()

func sole_at(side: String, point: Vector3) -> void:
	var points: Array[Vector3] = giant._foot_contact.samples(giant)[side]
	move_foot(side, point - points[2])

func only_right_foot(point: Vector3) -> void:
	sole_at("L", Vector3(10, 1, 0))
	sole_at("R", point)

func update_contact() -> void:
	giant._foot_contact.update(giant, 1.0 / 60.0)

func check_forward_sweep() -> void:
	reset_player()
	only_right_foot(Vector3(0, 1, -1.4))
	await frames()
	update_contact()
	check(player.current_player_health == 100.0, "Forward kick begins with all actual foot probes outside the player")
	move_foot("R", Vector3(0, 0, 2.8))
	await frames()
	var end: Array[Vector3] = giant._foot_contact.samples(giant)["R"]
	for index in end.size():
		check(giant._player_contact_sweep(end[index], end[index], giant.FootContact.PROBES[index].w).get("collider") != player,
			"Forward kick endpoint probe %d is outside; the hit must come from its swept path" % index)
	update_contact()
	check(player.current_player_health == 60.0 and player.damage_cooldown > 0.0 and landed == ["slender_speaker_foot"], "Real forward foot sweep pays exactly 40 HP through Player and emits one landed event")
	check(not player.is_grabbed() and not player.is_player_dead, "Nonlethal foot contact leaves ordinary player control")

func check_authored_gait() -> void:
	for speed in [4.0, 10.0]:
		reset_player()
		giant.position.z = 6.0
		giant._gait_phase = .5
		giant._gait_blend = 0.0
		giant._locomotion_transition_pose.clear()
		giant._locomotion_transition_elapsed = 1.0
		giant.velocity = Vector3(0, 0, -speed)
		giant._sample("walk", .5 * giant._duration("walk"))
		# The survivor stands in the authored right foot's lane. No bone poses
		# are altered: normal gait blending and CharacterBody movement supply
		# the complete path, including collision against the player's capsule.
		var initial: Array[Vector3] = giant._foot_contact.samples(giant)["R"]
		player.position.x = initial[2].x
		await frames()
		update_contact()
		check(player.current_player_health == 100.0, "Authored gait starts outside foot reach at %.0f m/s" % speed)
		var first_hit := -1
		for tick in 240:
			await physics_frame
			giant._animate_locomotion(1.0 / 60.0, giant.velocity.slide(Vector3.UP).length())
			giant._move_swept(Vector3(0, 0, -speed), 1.0 / 60.0)
			update_contact()
			if player.current_player_health < 100.0:
				first_hit = tick
				break
			await process_frame
		print("FOOT_GAIT speed=", speed, " first_hit=", first_hit, " root=", giant.position,
			" sole=", giant._foot_contact.samples(giant)["R"][2], " hp=", player.current_player_health)
		check(first_hit >= 0 and player.current_player_health == 60.0 and landed == ["slender_speaker_foot"],
			"Authored walk/run gait and real root collision produce actual 40 HP foot contact at %.0f m/s" % speed)

func check_step_and_episodes() -> void:
	reset_player()
	only_right_foot(Vector3(0, 2.8, 0))
	await frames()
	update_contact()
	check(player.current_player_health == 100.0, "Raised sole does not damage before actual contact")
	move_foot("R", Vector3(0, -2.5, 0))
	await frames()
	update_contact()
	check(player.current_player_health == 60.0, "Descending sole crossing the live player causes 40 HP")
	player.damage_cooldown = 0.0
	for tick in 6: update_contact()
	check(player.current_player_health == 60.0 and landed.size() == 1, "A planted overlapping foot cannot repeatedly hurt after player invulnerability clears")
	move_foot("R", Vector3(0, 0, -3))
	await frames()
	update_contact()
	update_contact()
	check(giant._foot_contact._contacts.is_empty(), "Full separation ends the per-foot player contact episode")
	move_foot("R", Vector3(0, 0, 3))
	await frames()
	update_contact()
	check(player.current_player_health == 20.0 and landed.size() == 2, "Separated foot returning to the player can hurt once in its new episode")

func check_both_feet_and_body_only() -> void:
	reset_player()
	sole_at("R", Vector3(.1, .3, 0))
	sole_at("L", Vector3(-.1, .3, 0))
	await frames()
	update_contact()
	check(giant._foot_contact._contacts.size() == 2, "Both imported feet independently register simultaneous player contact")
	check(player.current_player_health == 60.0 and landed.size() == 1, "Simultaneous feet share normal player hurt invulnerability")
	player.damage_cooldown = 0.0
	update_contact()
	check(player.current_player_health == 60.0, "The cooldown-rejected second foot remains in the same contact episode")
	reset_player(Vector3(0, 5, 0))
	await frames()
	update_contact()
	check(player.current_player_health == 100.0, "Torso/body capsule overlap without a real foot contact causes no foot damage")

func check_shielding() -> void:
	for kind in ["world", "panel", "item"]:
		reset_player()
		only_right_foot(Vector3(0, 1, -1.8))
		var blocker: PhysicsBody3D
		if kind == "panel": blocker = RVStructurePanel.new()
		elif kind == "item":
			blocker = Item.new()
			blocker.freeze = true
		else: blocker = StaticBody3D.new()
		blocker.position = Vector3(0, 1, -.65)
		box(blocker, Vector3(3, 3, .12))
		world.add_child(blocker)
		await frames()
		update_contact()
		move_foot("R", Vector3(0, 0, 2.8))
		await frames()
		update_contact()
		check(player.current_player_health == 100.0 and landed.is_empty(), "First physical %s obstruction shields the player from the swept foot" % kind)
		move_foot("R", Vector3(0, 0, -1.0))
		await frames()
		for tick in 4: update_contact()
		check(player.current_player_health == 100.0 and landed.is_empty(), "Later posed foot frames beyond the same %s obstruction cannot bypass its shield" % kind)
		if kind == "panel": check(blocker.current_health == blocker.max_health and not blocker.is_destroyed, "Foot contact preserves intact vehicle panel durability")
		if kind == "item": check(blocker.current_health == blocker.max_health and not blocker.is_destroyed and blocker.collision_layer != 0, "Foot contact preserves Item durability and collision")
		blocker.queue_free()
		await frames()

func check_runtime_and_restore() -> void:
	reset_player()
	# Keep the locomotion capsule clear; only the posed foot reaches the player.
	giant.position.z = 5.0
	only_right_foot(Vector3(0, .3, 0))
	giant._set_phase(SlenderSpeaker.Phase.STAGGER)
	giant.settings.stagger_seconds = 100.0
	giant._sense_remaining = 100.0
	giant.set_physics_process(true)
	await frames()
	giant.set_physics_process(false)
	check(player.current_player_health == 60.0 and landed == ["slender_speaker_foot"], "Normal active physics frames invoke foot contact after the posed rig update")
	reset_player()
	only_right_foot(Vector3(0, 1, -2))
	await frames()
	update_contact()
	giant.position.z += 4
	await frames()
	update_contact()
	check(player.current_player_health == 100.0, "Teleport across the player establishes fresh foot samples without a historical damage chord")
	check(not giant._foot_contact._previous.is_empty(), "Teleport records the new foot location for subsequent motion")
	giant.reset_after_restore()
	check(giant._foot_contact._previous.is_empty() and giant._foot_contact._contacts.is_empty(), "Checkpoint restoration clears both historical foot samples and contact episodes")

func check_lethal_flow() -> void:
	reset_player()
	player.current_player_health = 30.0
	only_right_foot(Vector3(0, .3, 0))
	await frames()
	update_contact()
	check(player.is_player_dead and player.current_player_health == 0.0, "Lethal foot contact reaches ordinary player death")
	await frames()
	check(player.ragdoll_control.active and player.body_collision_shape.disabled, "Existing deferred death contract starts physical ragdoll")
	check(not giant._is_smash_damage_target(player), "Dead player no longer qualifies for foot contact damage")
	player.set_physics_process(true)
	await frames(180)
	check(not player.is_player_dead and not player.ragdoll_control.active and player.current_player_health == 100.0, "Existing death flow restores full player health after lethal foot contact")
	check(not player.body_collision_shape.disabled and not player.is_grabbed(), "Death recovery restores ordinary collision and ownership")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -.1
	box(floor_body, Vector3(80, .2, 80))
	world.add_child(floor_body)
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	giant.attack_landed.connect(func(_target: Node, kind: String): landed.append(kind))
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	await frames()
	check(giant.settings.foot_player_damage == 40.0, "Foot player damage defaults to 40 HP")
	check(giant._foot_contact.samples(giant).size() == 2, "Production imported rig provides both posed foot samples")
	await check_forward_sweep()
	await check_authored_gait()
	await check_step_and_episodes()
	await check_both_feet_and_body_only()
	await check_shielding()
	await check_runtime_and_restore()
	await check_lethal_flow()
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: Slender Speaker foot player")
	else: print("FAIL Slender Speaker foot player: ", failures.size())
	quit(0 if failures.is_empty() else 1)

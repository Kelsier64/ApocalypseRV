extends SceneTree
## Production rig sweep, live Player hurt/death contract, and posed seat proxy.
const PLAYER := preload("res://player/player.tscn")
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var giant: SlenderSpeaker
var landed: Array[Node] = []

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
	if is_instance_valid(player.seated_in): player.seated_in.exit_seat(true)
	player.ragdoll_control.stop()
	player.is_player_dead = false
	player.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0,
		"transform": Transform3D(Basis.IDENTITY, point)})
	player.damage_cooldown = 0.0
	player.set_physics_process(false)
	for child in player.get_node("Visuals").get_children():
		if child.name == "Locomotion": child._physics_process(.7)
	landed.clear()
	giant.target_player = null
	giant.target_vehicle = null
	giant.velocity = Vector3.ZERO
	giant.position = Vector3(0, 0, 4)
	giant.rotation = Vector3.ZERO
	giant._set_phase(SlenderSpeaker.Phase.PATROL)
	giant._sample("idle_play", 0.0)

func smash(dodge_before := false, dodge_after_contact := false, impact_offset := Vector3.ZERO) -> void:
	# A fixed reachable impact point isolates the actual authored attack path
	# from RV target selection. The survivor need not be the selected target.
	giant._strike_point = player.execution_contact_position() + impact_offset
	giant._begin_smash()
	var dodged := false
	for tick in 108:
		giant.phase_elapsed = float(tick + 1) / 60.0
		if not dodged and ((dodge_before and tick == 75) or (dodge_after_contact and giant._strike_contact_collider == player)):
			player.position.x += 4.0
			dodged = true
			await frames()
		giant._advance_smash(1.0 / 60.0)
		if giant.phase == SlenderSpeaker.Phase.RECOVER: break
	check(giant.phase == SlenderSpeaker.Phase.RECOVER, "Animated smash completes into recovery")
	if dodge_after_contact: check(dodged, "Evading fixture first receives an actual swept hand contact")
	print("SMASH_PLAYER before_dodge=", dodge_before, " after_contact_dodge=", dodge_after_contact,
		" hp=", player.current_player_health, " contact=", giant._strike_contact_collider,
		" events=", landed.size(), " socket=", giant._bone_position("socket_strike_R"))

func check_normal_and_evading() -> void:
	reset_player()
	await frames()
	await smash()
	check(giant._strike_contact_collider == player and landed == [player], "Real attacking hand sweep selects the unselected live player as first contact")
	check(is_equal_approx(player.current_player_health, 60.0) and player.damage_cooldown > 0.0, "Impact pays configured 40 HP through normal Player damage API")
	check(not player.is_grabbed() and not player.is_player_dead, "A nonlethal smash leaves normal player control without capture")
	player.damage_cooldown = 0.0
	check(not giant.resolve_smash_hit(player) and player.current_player_health == 60.0 and landed.size() == 1, "One strike cannot damage twice even after hurt cooldown clears")
	reset_player()
	await frames()
	await smash(true)
	check(player.current_player_health == 100.0 and landed.is_empty(), "Moving out of the real sweep before contact avoids smash damage")
	reset_player()
	await frames()
	await smash(false, true)
	check(player.current_player_health == 100.0 and landed.is_empty(), "Earlier contact cannot hurt a player who leaves before settled impact")
	reset_player()
	await frames()
	var idle_hand := giant._bone_position("socket_strike_R")
	player.position = idle_hand - Vector3.UP
	await frames(10)
	check(player.current_player_health == 100.0 and not player.is_grabbed(), "Idle hand proximity produces neither damage nor capture")

func check_shell_block() -> void:
	reset_player()
	var panel := RVStructurePanel.new()
	panel.position = Vector3(0, 2.6, 0)
	box(panel, Vector3(4, .2, 3))
	world.add_child(panel)
	await frames()
	await smash()
	check(giant._strike_contact_collider == panel and panel.current_health == panel.max_health - 60.0 and not panel.is_destroyed and landed == [panel], "First physical shell panel takes 60 damage and consumes the strike")
	check(player.current_player_health == 100.0, "Damaging a shell never spills the same smash through to the player")
	panel.queue_free()
	await frames()

func check_seated() -> void:
	reset_player()
	var seat: Node3D = load("res://equipment/driver_seat.tscn").instantiate()
	world.add_child(seat)
	seat.freeze = true
	seat.set_physics_process(false)
	check(player.enter_seat_mode(seat), "Seat fixture enters production seat mode")
	seat.current_driver = player
	player._physics_process(1.0 / 60.0)
	for child in player.get_node("Visuals").get_children():
		if child.name == "Locomotion": child._physics_process(.7)
	giant.position = Vector3(0, 0, -4)
	giant.rotation.y = PI
	await frames()
	check(player.body_collision_shape.disabled, "Actual seated player locomotion capsule is disabled")
	var chest: Vector3 = player.get_node("Visuals").bite_contact(&"head").origin
	var from := chest + Vector3.UP * 2
	var to := chest - Vector3.UP * 2
	check(giant._smash_sweep(from, to, .34).get("collider") == player, "Posed seated chest enters first-contact ordering before furniture behind it")
	var blocker := StaticBody3D.new()
	blocker.position = chest + Vector3.UP
	box(blocker, Vector3(2, .1, 2))
	world.add_child(blocker)
	await frames()
	check(giant._smash_sweep(from, to, .34).get("collider") == blocker, "Nearer physical shell/world obstruction shields a disabled seated capsule")
	blocker.queue_free()
	await frames()
	await smash()
	check(giant._strike_contact_collider == seat and player.current_player_health == 100.0 and landed.is_empty(), "Actual occupied chair back blocks the torso-directed swing without a smash seat exception")
	# Aim toward the exposed front of the head. Its real posed volume is now
	# first along the authored hand path, above the console and before the back.
	await smash(false, false, Vector3(0, .3, -.4))
	check(player.current_player_health == 60.0 and landed == [player], "Actual animated smash hurts seated posed survivor once through normal damage API")
	check(player.seated_in == seat and not player.is_grabbed(), "Nonlethal smash preserves normal occupied seat ownership")
	seat.exit_seat(true)
	seat.queue_free()
	await frames()

func check_lethal_flow() -> void:
	reset_player()
	player.current_player_health = 30.0
	await frames()
	await smash()
	check(player.is_player_dead and player.current_player_health == 0.0, "Lethal smash reaches ordinary player death immediately")
	await frames()
	check(player.ragdoll_control.active and player.body_collision_shape.disabled, "Existing deferred death contract starts physical ragdoll")
	check(not giant._is_smash_damage_target(player), "Dead player no longer qualifies for smash damage")
	player.set_physics_process(true)
	await frames(180)
	check(not player.is_player_dead and not player.ragdoll_control.active and player.current_player_health == 100.0, "Existing death flow recovers player with full health")
	check(not player.body_collision_shape.disabled and not player.is_grabbed(), "Recovery restores ordinary collision/control without execution ownership")

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
	giant.attack_landed.connect(func(target: Node, _kind: String): landed.append(target))
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	await frames()
	check(giant.settings.smash_player_damage == 40.0, "Smash player damage defaults to 40 HP")
	await check_normal_and_evading()
	await check_shell_block()
	await check_seated()
	await check_lethal_flow()
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: Slender Speaker smash player")
	else: print("FAIL Slender Speaker smash player: ", failures.size())
	quit(0 if failures.is_empty() else 1)

extends SceneTree
const GrabRules = preload("res://core/raker_grab_rules.gd")
const Grab = preload("res://enemies/raker_grab.gd")
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var actor: Raker
func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func key(down: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = down
	event.echo = echo
	player.grab_control._input(event)
func reset() -> void:
	player.ragdoll_control.stop()
	actor.grab.cancel()
	actor.grab.phase = Grab.Phase.NONE
	actor.attack_timer = 0
	actor.strike_elapsed = -1
	actor.strike_target = {}
	actor.reaction_remaining = 0
	player.grab_control.immunity = 0
	player.is_player_dead = false
	player.body_state.reset()
	player._apply_body_capabilities()
	player._sync_body_collision_to_locomotion()
	player.current_player_health = 100
	player.damage_cooldown = .5
	player.position = Vector3(0, .02, -.80)
	actor.position = Vector3(0, -.23, 0)
	actor.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	actor.get_node("BodyMesh").pose_modifier.world_positions.clear()
	key(false)
func capture(count: int, facing: float = 0.0, player_yaw: float = 0.0) -> void:
	reset()
	actor.rotation.y = facing
	player.position = actor.position + Basis(Vector3.UP, facing) * Vector3(0, .25, -.80)
	player.rotation.y = player_yaw
	actor.grab.victim = player
	check(actor.grab.valid_contact(false), "Unobstructed head contact is reachable")
	check(player.begin_grab(actor, count), "Capture succeeds")
	actor.grab._change(Grab.Phase.HOLD)
	actor.grab.had_support = false
	actor.grab.was_seated = false
func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	world.add_child(floor_body)
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	actor = load("res://enemies/raker.tscn").instantiate()
	world.add_child(actor)
	actor.loot_drops = {}
	actor.target_player = player
	actor.set_physics_process(false)
	player.set_physics_process(false)
	actor.get_node("BodyMesh").set_process(false)
	var animation: AnimationPlayer = actor.get_node("BodyMesh").animation_player
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play("game/idle")
	animation.advance(0)
	await physics_frame
	# Every seed draws one immutable count in the approved range.
	var draws: Dictionary = {}
	for seed_value in 100:
		actor.grab.rng.seed = seed_value
		draws[actor.grab.rng.randi_range(6,10)] = true
	check(draws.size()==5,"RNG covers all five struggle counts")
	for required in range(6,11):
		for presses in range(required+1):
			var expected := 0 if presses==required else (1 if presses*5>=required*3 else 2)
			check(Grab.classify(presses,required)==expected,"Integer outcome %d/%d" % [presses,required])
		var threshold := ceili(required * .6)
		check(GrabRules.minimum_wounded_presses(required) == threshold, "Rounded 60 percent boundary %d" % required)
		capture(required)
		check(player.grab_control.required == required and player.grab_control.remaining == 1.0, "Capture preserves count and starts one-second HUD")
		check(player.grab_control.label.text.contains("60%"), "HUD displays the 60 percent threshold")
		check(is_equal_approx(player.grab_control.threshold_mark.position.x, 264.0), "HUD marker is at 60 percent")
		for i in required:
			key(true)
			key(true,true)
			if i < required-1: key(false)
		check(not player.is_grabbed() and player.current_player_health==100,"Immediate harmless escape %d" % required)
		for part: StringName in PlayerBodyState.PARTS:
			check(player.body_state.has_part(part),"Escape preserves %s" % part)
		check(actor.reaction_remaining==1 and player.grab_control.immunity==3,"Stagger and release immunity")
		check(player.grab_control.jump_release_required,"Final press cannot jump")
		key(false)
		check(not player.grab_control.jump_release_required,"Release re-arms jump")
	for count in [0, 5, 11, 99]:
		capture(count)
		check(player.grab_control.required == clampi(count, 6, 10), "Player clamps external capture counts to 6–10")
	# Exercise the actual REACH draw, not just the RNG in isolation.
	for seed_value in 20:
		reset()
		actor.grab.rng.seed = seed_value
		actor.grab.start(player)
		actor.grab.tick(Grab.REACH_DURATION)
		check(player.is_grabbed() and player.grab_control.required >= 6 and player.grab_control.required <= 10, "Production draw stays within unchanged 6–10 range")
		var drawn: int = player.grab_control.required
		actor.grab.tick(.5)
		check(player.grab_control.required == drawn, "Capture count is immutable during the hold")
	# Every integer rounding boundary chooses the same pose and bite outcome.
	for required in range(6, 11):
		var threshold := ceili(required * .6)
		for presses in [threshold - 1, threshold]:
			capture(required)
			player.grab_control.presses = presses
			actor.grab.tick(.7)
			player.grab_control._update_bite_pull(.18)
			check((player.grab_control.arm_grip_weight > 0) == (presses == threshold), "Arm preparation agrees with 60 percent boundary %d/%d" % [presses, required])
			actor.grab.tick(.3)
			check(actor.grab.phase == Grab.Phase.BITE and actor.grab.outcome == (1 if presses == threshold else 2), "Deadline resolves rounded threshold %d/%d" % [presses, required])
	capture(10)
	key(true)
	for i in 20: key(true,true)
	check(player.grab_control.presses==1,"Held/echo Space counts once")
	key(false)
	for i in 5:
		key(true)
		key(false)
	actor.grab.tick(.99)
	check(actor.grab.phase==Grab.Phase.HOLD and player.body_state.has_part(&"left_arm"),"One-second hold completes before biting")
	actor.grab.tick(.01)
	check(actor.grab.phase==Grab.Phase.BITE and actor.grab.outcome==1,"Exactly 60 percent locks wounded result")
	check(actor.grab.bite_part==&"left_arm","Wounded bite locks the left-arm target")
	key(true)
	check(player.grab_control.presses==6,"Deadline rejects new presses")
	check(is_equal_approx(animation.speed_scale, Grab.BITE_SPEED), "Bite animation accelerates with damage timing")
	actor.grab.tick(.20)
	check(player.current_player_health==100 and player.is_grabbed(), "Contact approach does not damage early")
	actor.grab.tick(.021)
	check(player.current_player_health==50,"Bite bypasses ordinary hurt cooldown")
	check(not player.body_state.has_part(&"left_arm") and player.body_state.has_part(&"head") and player.body_state.has_part(&"right_arm"),"Wounded contact severs only the left arm")
	check(player.body_state.has_part(&"left_leg") and player.body_state.has_part(&"right_leg"),"Grab bites never remove legs")
	check(not player.is_grabbed() and not player.grab_control.hud.visible and player.grab_control.camera == null,"Bite contact immediately releases input, camera and HUD")
	check(actor.grab.phase == Grab.Phase.RELEASE and actor.grab.victim == null,"Only monster recovery continues after biting")
	actor.grab.tick(.02)
	check(player.current_player_health==50,"One damage at bite contact")
	actor.grab.tick(.25)
	check(not player.is_grabbed(),"Bite releases control")
	# A temporary shoulder-facing POV must never become movement/body yaw.
	# Exercise different world headings so this cannot pass by resetting to zero.
	for facing in [0.0, .65, -1.1]:
		capture(10, facing, facing + .35)
		var body_yaw: float = player.global_rotation.y
		player.grab_control._process(.2)
		check(absf(angle_difference(player.global_rotation.y, body_yaw)) < .0001,"Capture camera aim preserves body yaw %.2f" % facing)
		player.grab_control.presses = 6
		actor.grab.tick(GrabRules.HOLD_DURATION)
		var face_view: Quaternion = player.camera.quaternion
		actor.grab.tick(.20)
		player.grab_control._update_bite_pull()
		player.grab_control._process(.01)
		check(player.camera.quaternion.angle_to(face_view) < .001,"Arm approach keeps the face view until damage %.2f" % facing)
		actor.grab.tick(Grab.BITE_CONTACT)
		check(player.current_player_health == 50 and not player.is_grabbed(),"Turned POV arm bite survives and releases %.2f" % facing)
		check(not player.grab_control.hud.visible and player.grab_control.camera == null,"Turned POV releases camera and HUD at contact %.2f" % facing)
		check(absf(angle_difference(player.global_rotation.y, body_yaw)) < .0001,"Arm bite release preserves body yaw %.2f" % facing)
		check(player.camera.quaternion.angle_to(face_view) < .001,"Contact schedules the turn without snapping the camera %.2f" % facing)
		player.grab_control._process(.16)
		check(player.camera.quaternion.angle_to(face_view) > .2,"Only post-contact processing turns toward the arm %.2f" % facing)
		player.camera.rotation.x -= .07
		player.rotation.y -= .18
		player.grab_control._process(1.0)
		check(absf(angle_difference(player.global_rotation.y, body_yaw - .18)) < .0001,"Released view recovery preserves mouse yaw %.2f" % facing)
		check(absf(player.camera.rotation.x + .07) < .0001,"Released view recovery preserves mouse pitch %.2f" % facing)
		check(not player.is_grabbed() and player.grab_control.camera == null,"Released view recovery does not reacquire ownership %.2f" % facing)
	for cancel_view in [false, true]:
		capture(10)
		player.grab_control._process(.2)
		player.grab_control.presses = 6
		actor.grab.tick(GrabRules.HOLD_DURATION)
		actor.grab.tick(Grab.BITE_CONTACT)
		player.grab_control._process(.16)
		# Large mouse motion reaches the visible pitch limit while the effect
		# still points down; removing it must not reveal a base above 80 degrees.
		player.camera.rotation.x = deg_to_rad(80)
		if cancel_view: player.grab_control.clear_view_recovery()
		else: player.grab_control._process(1.0)
		check(absf(player.camera.rotation.x) <= deg_to_rad(80) + .0001,"Post-bite view respects pitch limits on completion/cancel %s" % cancel_view)
	capture(10, .4, .75)
	player.grab_control._process(.2)
	player.grab_control.presses = 6
	actor.grab.tick(GrabRules.HOLD_DURATION)
	player.camera.rotation = Vector3(-.5, .9, 0)
	actor.grab.tick(Grab.BITE_CONTACT)
	check(player.current_player_health == 50 and not player.is_grabbed(),"World-transition fixture survives the arm bite")
	var destination := Transform3D(Basis(Vector3.UP, -1.25), Vector3(3, .02, -2))
	player.complete_world_transition(destination)
	player.grab_control._process(1.0)
	check(player.camera.rotation.is_equal_approx(Vector3.ZERO),"Old bite recovery cannot rotate a new world's reset camera")
	check(player.global_transform.is_equal_approx(destination),"Old bite recovery preserves the world-transition body transform")
	capture(10)
	player.body_state.sever(&"left_arm")
	player._apply_body_capabilities()
	player.grab_control.presses = 6
	actor.grab.tick(GrabRules.HOLD_DURATION)
	check(actor.grab.outcome==2 and actor.grab.bite_part==&"head","Missing left arm promotes wounded result to fatal head bite")
	actor.grab.tick(Grab.BITE_CONTACT)
	check(player.is_player_dead and not player.body_state.has_part(&"head"),"Promoted bite severs the head and follows death cleanup")
	capture(6)
	player.grab_control.presses = 6
	actor.grab.tick(GrabRules.HOLD_DURATION)
	check(actor.grab.phase==Grab.Phase.ESCAPE and not player.is_grabbed() and player.current_player_health==100,"Deadline classification of full struggle also escapes harmlessly")
	check(player.body_state.has_part(&"left_arm") and player.body_state.has_part(&"head"),"Deadline escape has no bite target or severance")
	capture(6)
	var second: Raker = load("res://enemies/raker.tscn").instantiate()
	world.add_child(second)
	second.set_physics_process(false)
	check(not player.begin_grab(second,6),"Single captor ownership")
	second.free()
	key(true)
	actor.grab.cancel()
	check(not player.can_be_grabbed(),"Three-second regrab immunity")
	player.grab_control._physics_process(3)
	check(player.can_be_grabbed(),"Immunity expires")
	reset()
	actor.grab.start(player)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,3,.1)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.position = Vector3(0,1,-.4)
	await physics_frame
	actor.grab.tick(.6)
	check(not player.is_grabbed() and actor.grab.phase==Grab.Phase.MISS,"New wall/intact panel blocks capture at windup end")
	wall.free()
	await physics_frame
	for low_health in [false,true]:
		capture(10)
		player.current_player_health = 40 if low_health else 100
		player.grab_control.presses = 6 if low_health else 5
		actor.grab.tick(GrabRules.HOLD_DURATION)
		check(actor.grab.bite_part==(&"left_arm" if low_health else &"head"),"Fatal versus wounded result selects the actual bitten part")
		actor.grab.tick(Grab.BITE_CONTACT)
		check(player.is_player_dead and player.current_player_health==0 and not player.is_grabbed(),"Fatal/sub-50 HP bite follows death cleanup")
		check(player.grab_control.recovery_camera == null,"Fatal bite does not start a survivor arm turn")
		check(player.body_state.has_part(&"head")==low_health,"Only a fatal head result removes the head")
	reset()
	player.body_state.sever(&"left_leg")
	player.body_state.sever(&"right_leg")
	player._apply_body_capabilities()
	player.damage_cooldown = 0
	var crawler_target := {"node": player, "attack_source": "state_attack"}
	check(not player.can_be_grabbed() and actor._can_attack_combat_target(crawler_target),"Crawler remains a valid ordinary claw target")
	actor._execute_attack_on_target(crawler_target)
	check(not actor.grab.busy() and actor.strike_elapsed==0,"Unavailable crawler grab falls back to timed claw strike")
	actor._tick_strike(actor.strike_contact)
	check(player.current_player_health<100 and player.body_state.has_part(&"left_arm"),"Crawler claw contact deals ordinary damage without severing an arm")
	capture(6)
	actor.take_damage(8)
	check(not player.is_grabbed() and actor.grab.phase==Grab.Phase.NONE,"8 damage interrupts")
	capture(6)
	player.complete_world_transition(Transform3D.IDENTITY)
	check(not player.is_grabbed() and not actor.grab.busy(),"World transition clears both owners")
	capture(6)
	actor.grab.had_support = true
	actor.grab.support = null
	actor.grab.tick(.01)
	check(not player.is_grabbed(),"Loss of original shared support cancels")
	capture(6)
	var item_count: int = player.inventory.items.size()
	player.drop_item()
	check(player.inventory.items.size()==item_count and not player.enter_ui_mode(),"Hard control blocks item/UI")
	Input.action_press("move_forward")
	player._process_normal_movement(.016)
	Input.action_release("move_forward")
	check(Vector2(player.velocity.x,player.velocity.z).length()<.01,"WASD is ignored with physics active")
	reset()
	actor.grab.start(player)
	player.position.x = 4
	actor.grab.tick(.6)
	check(actor.grab.phase==Grab.Phase.MISS and not player.is_grabbed(),"Windup rechecks range")
	capture(6)
	actor.free()
	check(not player.is_grabbed() and not player.grab_control.hud.visible,"Removing monster releases HUD/input")
	world.free()
	if failures.is_empty(): print("PASS: Raker grab outcomes, ownership, input and cleanup")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


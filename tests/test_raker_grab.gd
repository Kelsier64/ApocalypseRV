extends SceneTree
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
	actor.grab.cancel()
	actor.grab.phase = Grab.Phase.NONE
	actor.attack_timer = 0
	actor.reaction_remaining = 0
	player.grab_control.immunity = 0
	player.is_player_dead = false
	player.current_player_health = 100
	player.damage_cooldown = .5
	player.position = Vector3(0, .02, -.80)
	actor.position = Vector3(0, -.23, 0)
	actor.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	actor.get_node("BodyMesh").pose_modifier.world_positions.clear()
	key(false)
func capture(count: int) -> void:
	reset()
	actor.grab.victim = player
	check(actor.grab.valid_contact(false), "Unobstructed shoulder contact is reachable")
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
			var expected := 0 if presses==required else (1 if presses*5>=required*4 else 2)
			check(Grab.classify(presses,required)==expected,"Integer outcome %d/%d" % [presses,required])
		capture(required)
		for i in required:
			key(true)
			key(true,true)
			if i < required-1: key(false)
		check(not player.is_grabbed() and player.current_player_health==100,"Immediate harmless escape %d" % required)
		check(actor.reaction_remaining==1 and player.grab_control.immunity==3,"Stagger and release immunity")
		check(player.grab_control.jump_release_required,"Final press cannot jump")
		key(false)
		check(not player.grab_control.jump_release_required,"Release re-arms jump")
	capture(10)
	key(true)
	for i in 20: key(true,true)
	check(player.grab_control.presses==1,"Held/echo Space counts once")
	key(false)
	for i in 7:
		key(true)
		key(false)
	actor.grab.tick(2)
	check(actor.grab.phase==Grab.Phase.BITE and actor.grab.outcome==1,"Exactly 80 percent locks wounded result")
	key(true)
	check(player.grab_control.presses==8,"Deadline rejects new presses")
	actor.grab.tick(.38)
	check(player.current_player_health==50,"Bite bypasses ordinary hurt cooldown")
	actor.grab.tick(.02)
	check(player.current_player_health==50,"One damage at bite contact")
	actor.grab.tick(.25)
	check(not player.is_grabbed(),"Bite releases control")
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
		player.grab_control.presses = 8 if low_health else 7
		actor.grab.tick(2)
		actor.grab.tick(.38)
		check(player.is_player_dead and player.current_player_health==0 and not player.is_grabbed(),"Fatal/sub-50 HP bite follows death cleanup")
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


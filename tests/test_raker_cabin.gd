extends SceneTree
var failures: Array[String]=[]
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var actor: Raker
var trace_tick := 0
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func ticks(count: int) -> void:
	for i in count:
		await physics_frame
		player._physics_process(1.0/60.0)
		actor._physics_process(1.0/60.0)
		trace_tick += 1
		if "--trace" in OS.get_cmdline_user_args() and trace_tick % 60 == 0:
			print("CABIN ",trace_tick," ",rv.to_local(actor.global_position)," climb=",actor.locomotion_state," low=",actor.crouched," route=",actor.boarding.cabin.active," vel=",actor.velocity," target=",actor.current_combat_target.get("target_type")," strike=",actor.strike_elapsed," grab=",actor.grab.phase," gate=",actor.grab.contact_failure)
func spawn(point: Vector3) -> void:
	trace_tick = 0
	if is_instance_valid(actor): actor.free()
	actor=load("res://enemies/raker.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.position=rv.to_global(point)
	actor.rotation.y=PI/2
	actor.target_player=player
	actor.ai_state=Monster.State.CHASE
	actor.boarding.rng.seed=7
	actor.loot_drops={}
	player.current_player_health=10000
	player.damage_cooldown=0
func run() -> void:
	world=Node3D.new()
	root.add_child(world)
	current_scene=world
	var ground:=StaticBody3D.new()
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(60,.2,60)
	collision.shape=shape
	ground.add_child(collision)
	world.add_child(ground)
	ground.position.y=-.1
	var vehicle: Node3D=load("res://rv/new_rv.tscn").instantiate()
	world.add_child(vehicle)
	rv=vehicle.get_node("Chassis")
	rv.freeze=true
	rv.set_physics_process(false)
	rv.position.y=.95
	player=load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.enter_seat_mode(rv.get_node("DriverSeat"))
	await physics_frame
	var door: Equipment=rv.get_node("RightMiddle")
	door.current_health=24
	var roof: Equipment=rv.get_node("Ceiling")
	roof.current_health=10000
	spawn(Vector3(2.65,-.35,0))
	await ticks(1500)
	print("Raker door pursuit ",rv.to_local(actor.global_position)," health ",player.current_player_health," posture ",actor.crouched," shoulder ",actor.to_local(actor.grab_shoulder_position(1))," gate ",actor.grab.contact_failure," clip ",actor.get_node("BodyMesh").animation_player.current_animation)
	check(not is_instance_valid(door),"New species destroys side door")
	check(actor.crouched and actor.boarding.cabin.inside(actor,rv),"2.18 m monster enters cabin in low posture")
	check(player.current_player_health<10000,"Low attack reaches seated driver after door breach")
	roof.current_health=24
	spawn(Vector3(0,2.55,2.8))
	await ticks(1300)
	print("Raker roof pursuit ",rv.to_local(actor.global_position)," health ",player.current_player_health)
	check(not is_instance_valid(roof),"New species breaks supporting roof")
	check(actor.crouched and actor.boarding.mode==MonsterBoarding.Mode.NONE,"Drops into cabin and acquires low locomotion")
	check(player.current_player_health<10000,"Roof breaker pursues driver inside")
	check(rv.get_node("CraftingStation").current_health==rv.get_node("CraftingStation").max_health,"Leaves cabin equipment intact")
	player.seated_in=null
	player.in_ui_mode=true
	player.position=rv.to_global(Vector3(6,-1.2,1.5))
	player.current_player_health=10000
	await ticks(1500)
	print("Raker exit pursuit ",rv.to_local(actor.global_position)," health ",player.current_player_health)
	check(rv.to_local(actor.global_position).x>3.5,"Exits through the real breach")
	check(not actor.crouched,"Returns to full 2.18 m outside")
	check(player.current_player_health<10000,"Resumes ground sweep after exit")
	world.free()
	if failures.is_empty(): print("PASS: Raker side-door breach, roof breach, low cabin pursuit and standing exit")
	else:
		for note in failures: push_error("FAIL: "+note)
	quit(0 if failures.is_empty() else 1)

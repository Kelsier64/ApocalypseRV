extends SceneTree
const GrabRules = preload("res://core/raker_grab_rules.gd")
var failures: Array[String]=[]
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var actor: Raker
var trace_tick := 0
var target_survived := true
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func ticks(count: int) -> void:
	for i in ceili(count * Engine.physics_ticks_per_second / 60.0):
		await physics_frame
		player._physics_process(1.0 / Engine.physics_ticks_per_second)
		actor._physics_process(1.0 / Engine.physics_ticks_per_second)
		# Keep one real wounded bite per breach case, then use normal escapes.
		# A second wounded bite after losing the left arm is fatal at any HP.
		if player.is_grabbed() and player.grab_control.accepting:
			var goal: int = GrabRules.minimum_wounded_presses(player.grab_control.required) if player.body_state.has_part(&"left_arm") else player.grab_control.required
			while player.is_grabbed() and player.grab_control.presses < goal:
				player.submit_struggle()
		# Surviving release restores automatic physics; this fixture advances it
		# explicitly above, so never let a capture add a second update per tick.
		player.set_physics_process(false)
		target_survived = target_survived and not player.is_player_dead
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
	player.body_state.reset()
	player._apply_body_capabilities()
	player.grab_control.immunity=0
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
	var door: RVStructurePanel=rv.get_node("RightMiddle")
	door.current_health=24
	var roof: RVStructurePanel=rv.get_node("RoofRear")
	roof.current_health=10000
	spawn(Vector3(2.65,-.35,0))
	await ticks(1500)
	print("Raker door pursuit ",rv.to_local(actor.global_position)," health ",player.current_player_health," posture ",actor.crouched," shoulder ",actor.to_local(actor.grab_shoulder_position(1))," gate ",actor.grab.contact_failure," clip ",actor.get_node("BodyMesh").animation_player.current_animation)
	check(door.is_destroyed,"New species destroys side door")
	check(actor.crouched and actor.boarding.cabin.inside(actor,rv),"Enlarged monster enters cabin in low posture")
	check(player.current_player_health<10000,"Low attack reaches seated driver after door breach")
	check(target_survived and player.body_state.has_part(&"head") and player.seated_in==rv.get_node("DriverSeat"),"Door pursuit retains a living seated target")
	roof.current_health=24
	spawn(Vector3(0,2.55,2.8))
	await ticks(1300)
	print("Raker roof pursuit ",rv.to_local(actor.global_position)," health ",player.current_player_health)
	check(roof.is_destroyed,"New species breaks supporting roof")
	check(actor.crouched and actor.boarding.mode==MonsterBoarding.Mode.NONE,"Drops into cabin and acquires low locomotion")
	check(player.current_player_health<10000,"Roof breaker pursues driver inside")
	check(target_survived and player.body_state.has_part(&"head") and player.seated_in==rv.get_node("DriverSeat"),"Roof pursuit retains a living seated target")
	check(rv.get_node("CraftingStation").current_health==rv.get_node("CraftingStation").max_health,"Leaves cabin equipment intact")
	player.seated_in=null
	player.in_ui_mode=true
	player.position=rv.to_global(Vector3(6,-1.2,1.5))
	player.current_player_health=10000
	# The fixed chassis deck stays intact when the quarry moves below it;
	# pursuit must leave through the existing side breach.
	await ticks(2400)
	print("Raker exit pursuit ",rv.to_local(actor.global_position)," health ",player.current_player_health)
	check(rv.to_local(actor.global_position).x>3.5,"Exits through the real breach")
	check(not actor.crouched,"Returns to full standing height outside")
	check(player.current_player_health<10000,"Resumes ground sweep after exit")
	check(target_survived,"Cabin and exit pursuit never invoke death or respawn")
	var deck_ray := PhysicsRayQueryParameters3D.create(rv.to_global(Vector3(0, 1, 2.6)), rv.to_global(Vector3(0, -.4, 2.6)), 1)
	var deck_hit := world.get_world_3d().direct_space_state.intersect_ray(deck_ray)
	check(deck_hit.get("collider") == rv and not rv.get_node("DeckCollision").disabled, "Fixed chassis floor survives monster side and roof breaches")
	world.free()
	if failures.is_empty(): print("PASS: Raker side-door breach, roof breach, low cabin pursuit and standing exit")
	else:
		for note in failures: push_error("FAIL: "+note)
	quit(0 if failures.is_empty() else 1)

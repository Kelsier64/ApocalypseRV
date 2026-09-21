extends RefCounted
## Shared by headless behavior verification and visible continuous-input replay.
var interior: MaintenanceInterior
var player: CharacterBody3D
var message: Callable
var failures: Array[String] = []
var steps := 0
var travelled := 0.0

func check(ok: bool, detail: String) -> bool:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)
	return ok

func report(detail: String) -> void:
	print("V2_REPLAY: " + detail)
	if message.is_valid(): message.call(detail)

func frames(count: int) -> void:
	for i in count:
		await interior.get_tree().physics_frame
		steps += 1

func walk(target: Vector3) -> bool:
	for frame in 900:
		var flat := Vector2(player.position.x-target.x,player.position.z-target.z)
		if flat.length() < 0.3:
			Input.action_release("move_forward")
			await frames(8)
			return check(absf(player.position.y-target.y) < 0.8, "Walk arrives at correct level %s actual=%s" % [target,player.position])
		player.look_at(Vector3(target.x,player.position.y,target.z))
		player.camera.rotation = Vector3.ZERO
		var before := player.position
		Input.action_press("move_forward")
		await frames(1)
		travelled += before.distance_to(player.position)
	Input.action_release("move_forward")
	return check(false,"Walking blocked target=%s actual=%s" % [target,player.position])

func press_e(target: Vector3) -> void:
	player.look_at(Vector3(target.x,player.position.y,target.z))
	player.camera.look_at(target)
	await frames(6)
	Input.action_press("interact")
	await frames(8)
	Input.action_release("interact")
	await frames(6)

func run(inside: MaintenanceInterior, actor: CharacterBody3D, callback := Callable()) -> bool:
	interior = inside
	player = actor
	message = callback
	# Controlled locomotion fixture; production population is verified separately.
	for entity in interior.entities.get_children():
		if entity is Monster:
			entity.process_mode = Node.PROCESS_MODE_DISABLED
			entity.collision_layer = 0
	await frames(15)
	var cargo: Prop = preload("res://props/engine_standard.tscn").instantiate()
	interior.entities.add_child(cargo)
	cargo.position = player.position + Vector3(1,0.6,0)
	cargo.freeze = true
	cargo.interact(player)
	await frames(2)
	check(player.inventory.items.any(func(item): return item.is_large),"Large engine occupies inventory during stair traversal")
	report("Carry engine through lower route and climb first stair")
	for target in [Vector3(0,0,0),Vector3(0,0,-13.5),Vector3(0,0,-24),Vector3(0,0,-25.5),Vector3(0,6,-37.5),Vector3(0,6,-39.5),Vector3(0,6,-43)]:
		if not await walk(target): return false
	report("Zombie follows actual ramp from lower landing to upper floor")
	var zombie: Monster = preload("res://enemies/zombie.tscn").instantiate()
	interior.entities.add_child(zombie)
	zombie.position = Vector3(0,0.05,-24)
	zombie.contact_damage = 0
	zombie.detection_range = 50
	player.look_at(Vector3(zombie.position.x,player.position.y,zombie.position.z))
	player.camera.rotation = Vector3.ZERO
	for i in 1500:
		await frames(1)
		if zombie.position.y > 5.4 and zombie.position.z < -38: break
	check(zombie.position.y > 5.4 and zombie.position.z < -38,"Zombie physically climbs stairs: " + str(zombie.position))
	# Check actual floor occlusion before retiring this locomotion fixture.
	zombie.position = Vector3(0,0,-43)
	await frames(2)
	check(not zombie._has_attack_line_of_sight_to_target(player),"Floor blocks attack line of sight between levels")
	zombie.queue_free()
	await frames(2)
	report("Cross upper rooms, descend second stair with cargo")
	for target in [Vector3(0,6,-45),Vector3(9,6,-45),Vector3(18,6,-45),Vector3(27,6,-45),Vector3(27,6,-39.5),Vector3(27,6,-37.5),Vector3(27,0,-25.5),Vector3(27,0,-24),Vector3(27,0,-13.5),Vector3(27,0,0)]:
		if not await walk(target): return false
	check(player.inventory.items.any(func(item): return item.is_large),"Cargo survives both stairs")
	report("Release depot by real E interaction, then open inside-only return hatch")
	if not await walk(Vector3(28,0,-1)): return false
	var before := interior.entities.get_child_count()
	await press_e(interior.depot.global_position + Vector3.UP)
	check(interior.objective_claimed,"Real E opens depot")
	check(interior.entities.get_child_count() == before+3,"Depot releases one engine and two repair kits")
	await press_e(interior.depot.global_position + Vector3.UP)
	check(interior.entities.get_child_count() == before+3,"Depot cannot duplicate reward")
	for target in [Vector3(27,0,0),Vector3(18,0,0),Vector3(9,0,0),Vector3(6,0,0)]:
		if not await walk(target): return false
	await press_e(interior.gate.global_position + Vector3.UP*1.5)
	check(interior.shortcut_open,"Real E opens hatch from inside")
	while interior.rebaking: await frames(1)
	if not await walk(Vector3(0,0,0)): return false
	check(interior.explored.size() >= 10,"Exploration records visited rooms: " + str(interior.explored))
	report("%s / two stairs, large cargo, zombie, depot and return hatch / %.1f m / %.1f s" % ["PASS" if failures.is_empty() else "FAIL",travelled,steps/60.0])
	return failures.is_empty()

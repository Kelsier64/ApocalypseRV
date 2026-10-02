extends SceneTree
## Real production-RV contacts: compare impact severity and episode rearming.
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	var slow := await wall_scenario(6.0)
	var fast := await wall_scenario(12.0)
	check(fast.damage > slow.damage and slow.damage > 0, "Faster real wall impacts lose more engine durability")
	await rapid_wall_scenario()
	var tree := await tree_scenario(false)
	check(tree.damage > 0 and tree.damage < fast.damage * 0.5, "A yielded tree costs less durability than a hard wall at the same entry speed")
	await tree_scenario(true)
	await intact_tree_scenario()
	var mild := await landing_scenario(2.0)
	var heavy := await landing_scenario(8.0, true)
	check(heavy.damage > mild.damage and heavy.damage > 0, "A heavy real landing causes more damage than a mild landing")
	await quiet_driving_scenario()
	await bump_scenario()
	if failures.is_empty(): print("PASS: unified actual RV wall, tree, landing, bump and quiet-driving impact damage")
	quit(0 if failures.is_empty() else 1)

func fixture() -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := box_body(world, Vector3(200, 0.2, 200), Vector3(0, -0.1, 0))
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	var events: Array[Dictionary] = []
	rv.vehicle_impact.connect(func(kind: String, speed_loss: float, damage: float) -> void:
		events.append({"kind": kind, "loss": speed_loss, "damage": damage, "frame": Engine.get_physics_frames()}))
	rv.allow_test_controls = true
	rv.handbrake = false
	rv.gear = 2
	rv.control_override = {"throttle": 0.0}
	for i in range(90): await physics_frame
	check(rv.get_engine().health == 450 and events.is_empty(), "Spawn settling and stationary suspension create no phantom impact damage")
	return {"world": world, "rv": rv, "ground": ground, "events": events}

func box_body(world: Node3D, size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	world.add_child(body)
	return body

func retire(data: Dictionary) -> void:
	data.world.queue_free()
	await process_frame
	await physics_frame

func paid(data: Dictionary, kind: String) -> Array:
	return data.events.filter(func(event: Dictionary) -> bool: return event.kind == kind)

func wall_scenario(speed: float) -> Dictionary:
	var data := await fixture()
	var rv: Chassis = data.rv
	var wall := box_body(data.world, Vector3(30, 6, 0.5), Vector3(0, 3, -20))
	var contacted := false
	rv.linear_velocity = Vector3.FORWARD * speed
	for i in range(240):
		await physics_frame
		if rv.get_colliding_bodies().has(wall): contacted = true
	var health := rv.get_engine().health
	var paid_before: int = data.events.size()
	for i in range(90): await physics_frame
	check(contacted and not paid(data, "body").is_empty(), "Wall damage comes from actual production chassis contact")
	check(rv.get_engine().health == health and data.events.size() == paid_before, "Remaining pressed against one wall does not repeatedly charge impact damage")
	var damage := 450.0 - health
	print("VEHICLE_WALL entry=%.1f damage=%.2f final=%.2f events=%s" % [speed, damage, rv.linear_velocity.length(), data.events])
	await retire(data)
	return {"damage": damage}

func tree_scenario(rapid: bool) -> Dictionary:
	var data := await fixture()
	var rv: Chassis = data.rv
	var chunk := ChunkGenerator.new()
	chunk.field = WorldField.new(42)
	var planned: Array[Dictionary] = [{"point": Vector3(0, 0, -20), "height": 14.0, "width": 3.0, "angle": 0.0}]
	if rapid: planned.append({"point": Vector3(0, 0, -21.3), "height": 14.0, "width": 3.0, "angle": 0.0})
	chunk.field.forest_cache = {0: planned, -1: [] as Array[Dictionary], 1: [] as Array[Dictionary]}
	data.world.add_child(chunk)
	await ForestScenery.build(chunk, false)
	var trunks := chunk.get_node("ForestTrunks") as ForestTrunks
	rv.linear_velocity = Vector3.FORWARD * 12
	for i in range(240): await physics_frame
	var damage := 450.0 - rv.get_engine().health
	var events := paid(data, "tree")
	check(trunks.broken.size() == (2 if rapid else 1) and not events.is_empty(), "Unified damage accompanies actual tree-breaking physics callbacks")
	if rapid:
		check(events.size() >= 2 and events[1].frame - events[0].frame < 15, "A second actual tree contact charges damage promptly without a global cooldown")
	var health := rv.get_engine().health
	for i in range(60): await physics_frame
	check(rv.get_engine().health == health, "Broken tree debris cannot repeatedly charge the original tree episode")
	print("VEHICLE_TREE rapid=%s broken=%d damage=%.2f events=%s" % [rapid, trunks.broken.size(), damage, events])
	await retire(data)
	return {"damage": damage}

func rapid_wall_scenario() -> void:
	var data := await fixture()
	var rv: Chassis = data.rv
	# A movable heavy barricade absorbs a first hit while leaving forward motion
	# for the fixed wall immediately behind it. Neither contact resets RV motion.
	var first := RigidBody3D.new()
	first.mass = 1500
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 3, 0.5)
	collision.shape = shape
	first.add_child(collision)
	first.position = Vector3(1.2, 1.5, -20)
	data.world.add_child(first)
	var second := box_body(data.world, Vector3(3, 6, 0.5), Vector3(-2, 3, -20.8))
	var first_contact := -1
	var second_contact := -1
	rv.linear_velocity = Vector3.FORWARD * 12
	for i in range(240):
		await physics_frame
		if first_contact < 0 and rv.get_colliding_bodies().has(first): first_contact = Engine.get_physics_frames()
		if second_contact < 0 and rv.get_colliding_bodies().has(second): second_contact = Engine.get_physics_frames()
	var events := paid(data, "body")
	check(first_contact >= 0 and second_contact >= first_contact and second_contact - first_contact < 15, "RV physically meets a barricade and a second wall promptly without velocity resets")
	var second_events := events.filter(func(event: Dictionary) -> bool: return second_contact >= 0 and event.frame >= second_contact)
	check(events.size() >= 2 and not second_events.is_empty() and second_events[0].frame - events[0].frame < 15, "Distinct rapid wall contacts charge damage without a global cooldown")
	print("VEHICLE_RAPID_WALL first=%d second=%d health=%.2f position=%s events=%s" % [first_contact, second_contact, rv.get_engine().health, rv.global_position, events])
	await retire(data)

func intact_tree_scenario() -> void:
	var data := await fixture()
	var rv: Chassis = data.rv
	var chunk := ChunkGenerator.new()
	chunk.field = WorldField.new(42)
	var planned: Array[Dictionary] = [{"point": Vector3(0, 0, -10), "height": 14.0, "width": 3.0, "angle": 0.0}]
	chunk.field.forest_cache = {0: planned, -1: [] as Array[Dictionary], 1: [] as Array[Dictionary]}
	data.world.add_child(chunk)
	await ForestScenery.build(chunk, false)
	var trunks := chunk.get_node("ForestTrunks") as ForestTrunks
	var contacted := false
	rv.linear_velocity = Vector3.FORWARD * 2.5
	for i in range(240):
		await physics_frame
		if rv.get_colliding_bodies().has(trunks): contacted = true
	check(contacted and trunks.broken.is_empty(), "A real sub-threshold tree contact leaves the standing tree intact")
	check(rv.linear_velocity.length() < 0.5 and not paid(data, "body").is_empty() and paid(data, "tree").is_empty(), "An intact tree stops a slow RV and charges its actual hard-contact loss")
	print("VEHICLE_INTACT_TREE health=%.2f final=%.2f events=%s" % [rv.get_engine().health, rv.linear_velocity.length(), data.events])
	await retire(data)

func landing_scenario(height: float, repeat_landing := false) -> Dictionary:
	var data := await fixture()
	var rv: Chassis = data.rv
	rv.global_position += Vector3.UP * height
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	for i in range(240): await physics_frame
	var damage := 450.0 - rv.get_engine().health
	var first_events := paid(data, "ground").size()
	if repeat_landing:
		var health := rv.get_engine().health
		rv.global_position += Vector3.UP * height
		rv.linear_velocity = Vector3.ZERO
		rv.angular_velocity = Vector3.ZERO
		for i in range(240): await physics_frame
		check(rv.get_engine().health < health and paid(data, "ground").size() > first_events, "A separated second landing on the same ground rearms ground damage")
	check(rv.global_position.y < 3, "Dropped RV actually returns to its ground fixture")
	print("VEHICLE_LANDING height=%.1f damage=%.2f repeated=%s events=%s" % [height, damage, repeat_landing, data.events])
	await retire(data)
	return {"damage": damage}

func quiet_driving_scenario() -> void:
	var data := await fixture()
	var rv: Chassis = data.rv
	check(rv.set_engine_running(true), "Quiet-driving fixture starts the production engine")
	rv.linear_velocity = Vector3.FORWARD * 8
	for i in range(180):
		rv.control_override = {"throttle": 0.5, "steering": 0.2 if i < 90 else -0.2}
		await physics_frame
	rv.control_override = {"brake": 1.0}
	for i in range(180): await physics_frame
	check(rv.get_engine().health == 450 and data.events.is_empty(), "Normal wheel acceleration, steering, braking and parked jitter cause no phantom damage")
	print("VEHICLE_QUIET health=%.2f final=%.2f events=%s" % [rv.get_engine().health, rv.linear_velocity.length(), data.events])
	await retire(data)

func bump_scenario() -> void:
	var data := await fixture()
	var rv: Chassis = data.rv
	var bump := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([Vector3(-15, 0, -10), Vector3(15, 0, -10), Vector3(-15, 0, -14), Vector3(15, 0, -14), Vector3(-15, 2.5, -14), Vector3(15, 2.5, -14)])
	collision.shape = wedge
	bump.add_child(collision)
	data.world.add_child(bump)
	rv.linear_velocity = Vector3.FORWARD * 12
	var contact_frame := -1
	for i in range(240):
		await physics_frame
		if contact_frame < 0 and rv.get_colliding_bodies().has(bump): contact_frame = Engine.get_physics_frames()
	var bump_events: Array = data.events.filter(func(event: Dictionary) -> bool: return contact_frame >= 0 and event.frame >= contact_frame)
	check(contact_frame >= 0 and not bump_events.is_empty(), "A real raised terrain wedge contact causes collision damage")
	print("VEHICLE_BUMP health=%.2f position=%s events=%s" % [rv.get_engine().health, rv.global_position, data.events])
	await retire(data)

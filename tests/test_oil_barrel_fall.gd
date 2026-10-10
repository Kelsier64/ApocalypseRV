extends SceneTree
## Actual rigid-body landings, ownership resets and midair save/load behavior.
const BARREL := preload("res://props/oil_barrel.tscn")
const EFFECT := preload("res://enemies/barrel_explosion_effect.gd")
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func fixture() -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, .2, 40)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -.1
	world.add_child(ground)
	return {"world": world, "ground": ground}

func barrel_at(world: Node3D, height: float) -> OilBarrel:
	var barrel := BARREL.instantiate() as OilBarrel
	barrel.position.y = .5 + height
	world.add_child(barrel)
	return barrel

func run() -> void:
	await drop_case(1.9, false)
	await drop_case(2.1, true)
	await drop_case(4.0, true)
	await restored_fall()
	await reset_and_release()
	await wall_contact()
	check(not ItemState.valid_service("res://props/scrap.tscn", {"fall_height": 1.0}), "Fall state belongs only to ordinary barrels")
	for value in [-1.0, INF, NAN, "2"]:
		check(not ItemState.valid_service("res://props/oil_barrel.tscn", {"fall_height": value}), "Invalid saved fall height is rejected")
	if failures.is_empty(): print("PASS: ordinary barrel short/long falls, landing-only ignition, state restore, release and side contact")
	quit(0 if failures.is_empty() else 1)

func drop_case(height: float, explodes: bool) -> void:
	var data := fixture()
	var effects: Array[int] = []
	var observer := func(node: Node) -> void:
		if node.get_script() == EFFECT: effects.append(node.get_instance_id())
	node_added.connect(observer)
	var barrel := barrel_at(data.world, height)
	await steps(10)
	check(is_instance_valid(barrel) and effects.is_empty(), "%.1fm drop cannot explode while still airborne" % height)
	await steps(170)
	check(effects.size() == (1 if explodes else 0), "%.1fm drop emits expected single landing blast" % height)
	check(not is_instance_valid(barrel) if explodes else is_instance_valid(barrel) and not barrel.is_destroyed, "%.1fm landing has expected barrel survival" % height)
	if not explodes:
		check(not WorldActorSnapshot.capture(barrel).is_empty(), "Short-drop survivor remains a saveable Item")
	node_added.disconnect(observer)
	data.world.queue_free()
	await steps(2)

func restored_fall() -> void:
	var data := fixture()
	var barrel := barrel_at(data.world, 2.5)
	for frame in 60:
		await steps(1)
		if is_instance_valid(barrel) and barrel.global_position.y < 1.6: break
	check(is_instance_valid(barrel), "Midair source has not landed")
	var saved := WorldActorSnapshot.capture(barrel)
	check(WorldActorSnapshot.validation_error(saved, "fall").is_empty() and saved.state.service.get("fall_height", 0.0) > 1.0, "Midair Item snapshot retains valid fall distance")
	barrel.begin_world_transfer()
	barrel.free()
	barrel = WorldActorSnapshot.restore(saved, data.world) as OilBarrel
	await steps(100)
	check(not is_instance_valid(barrel), "Reload near ground preserves the full 2.5m drop and explodes on landing")
	data.world.queue_free()
	await steps(2)

func reset_and_release() -> void:
	var data := fixture()
	var barrel := barrel_at(data.world, 2.5)
	barrel.confirm_placement(barrel.global_transform, data.ground, data.ground)
	await steps(30)
	check(is_instance_valid(barrel) and barrel.is_fixed, "Fixed elevated cargo does not count as falling")
	barrel.detach_from_support()
	await steps(120)
	check(not is_instance_valid(barrel), "Support release starts a fresh fall and detonates after landing")
	barrel = barrel_at(data.world, 4.0)
	await steps(30)
	# Transfer to a low position simulates pickup/placement/world relocation.
	barrel.begin_world_transfer()
	barrel.global_position.y = 1.0
	barrel.linear_velocity = Vector3.ZERO
	barrel.end_world_transfer()
	await steps(120)
	check(is_instance_valid(barrel) and not barrel.is_destroyed, "World relocation clears previous airborne height")
	data.world.queue_free()
	await steps(2)

func wall_contact() -> void:
	var data := fixture()
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.2, 8, 8)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(.7, 4, 0)
	data.world.add_child(wall)
	var barrel := barrel_at(data.world, 4.0)
	barrel.linear_velocity = Vector3.RIGHT * 3.0
	var touched: Array[Node] = []
	barrel.body_entered.connect(func(body: Node) -> void: touched.append(body))
	await steps(15)
	check(touched.has(wall) and is_instance_valid(barrel) and not barrel.is_destroyed, "Actual airborne wall contact neither ignites nor ends the fall")
	await steps(165)
	check(not is_instance_valid(barrel), "Wall scrape preserves long-drop distance until ground landing")
	data.world.queue_free()
	await steps(2)

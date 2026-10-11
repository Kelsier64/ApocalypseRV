extends SceneTree
## Actual enemy damage dispatch, opaque collision and isolated interior physics.
const PISTOL := "res://props/pistol.tscn"
var failures: Array[String] = []
var world: Node3D
var actor: CharacterBody3D

func _init() -> void: run.call_deferred()

func check(value: bool, note: String) -> void:
	if not value: failures.append(note)

func steps(count := 2) -> void:
	for index in count:
		await physics_frame
		await process_frame

func player_in(parent: Node3D) -> CharacterBody3D:
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	parent.add_child(player)
	player.set_physics_process(false)
	player.weapon.set_physics_process(false)
	player.camera.get_node("InteractRay").set_physics_process(false)
	check(player.add_item("Pistol", false, PISTOL), "Fixture grants canonical pistol")
	return player

func target_in(parent: Node3D, path: String, at: Vector3) -> Monster:
	var target: Monster = load(path).instantiate()
	target.position = at
	parent.add_child(target)
	target.set_physics_process(false)
	return target

func wall_in(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	wall.position = at
	parent.add_child(wall)
	return wall

func fire_at(player: CharacterBody3D, point: Vector3) -> bool:
	player.camera.look_at(point)
	player.weapon.advance(0.31)
	return player.weapon.try_fire()

func run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	actor = player_in(world)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await steps()
	var raker := target_in(world, "res://enemies/raker.tscn", Vector3(0, 0, -9))
	await steps()
	var original: float = raker.current_health
	check(fire_at(actor, raker.global_position + Vector3.UP * 1.5), "Unobstructed shot is accepted")
	check(is_equal_approx(raker.current_health, original - 25.0), "Real Raker receives exactly 25 damage")
	for index in 5:
		check(fire_at(actor, raker.global_position + Vector3.UP * 1.5), "Next Raker shot is accepted")
	check(raker.is_dead, "Six normal rounds kill the production 140-HP Raker")
	raker.free()
	await steps()

	var barrel := target_in(world, "res://enemies/barrel_man.tscn", Vector3(0, 0, -12)) as BarrelMan
	await steps()
	original = barrel.current_health
	check(fire_at(actor, barrel.global_position + Vector3.UP * 0.5), "Disguised barrel shot is accepted")
	check(is_equal_approx(barrel.current_health, original - 25.0) and barrel.phase == BarrelMan.Phase.RISING, "Real barrel takes damage and breaks disguise")
	check(fire_at(actor, barrel.global_position + Vector3.UP * 0.5), "Second barrel shot is accepted")
	check(fire_at(actor, barrel.global_position + Vector3.UP * 0.5), "Lethal barrel shot is accepted")
	check(barrel.is_dead and barrel.phase == BarrelMan.Phase.DETONATED, "Lethal pistol damage keeps barrel detonation semantics")
	await steps()
	if is_instance_valid(barrel): barrel.free()
	await steps()

	# New full magazine for each independent obstruction case.
	actor.inventory.items[0].state.pistol.loaded_rounds = 12
	actor.refresh_inventory()
	var giant := target_in(world, "res://enemies/slender_speaker/slender_speaker.tscn", Vector3(0, 0, -18))
	await steps()
	original = giant.current_health
	check(fire_at(actor, giant.global_position + Vector3.UP * 7.5), "Giant collision accepts the shot")
	check(giant.current_health == original and not giant.is_dead, "Pistol preserves Slender Speaker invincibility")
	giant.free()
	await steps()
	raker = target_in(world, "res://enemies/raker.tscn", Vector3(0, 0, -12))
	await steps()
	original = raker.current_health
	var wall := wall_in(world, Vector3(0, 1.5, -4), Vector3(4, 4, 0.2))
	await steps()
	check(fire_at(actor, raker.global_position + Vector3.UP * 1.5), "Wall shot consumes a round")
	check(raker.current_health == original, "Opaque wall prevents damage to monster behind it")
	wall.free()
	await steps()

	var rv: Chassis = load("res://rv/chassis.tscn").instantiate()
	# Its production solid floor crosses this lane at camera height.
	rv.position = Vector3(0, actor.camera.global_position.y - 0.4, -7)
	rv.freeze = true
	world.add_child(rv)
	rv.set_physics_process(false)
	await steps()
	var engine: EngineState = rv.get_engine()
	var rv_health: float = engine.health if engine != null else 0.0
	check(fire_at(actor, raker.global_position + Vector3.UP * 1.5), "RV obstruction shot consumes a round")
	check(raker.current_health == original and (engine == null or engine.health == rv_health), "RV collision blocks bullets without taking monster-only bullet damage")
	rv.free()
	await steps()
	var item: Item = load("res://props/scrap.tscn").instantiate()
	item.position = Vector3(0, 1.5, -4)
	item.scale = Vector3(8, 8, 3)
	item.freeze = true
	world.add_child(item)
	await steps()
	var item_health: float = item.current_health
	check(fire_at(actor, raker.global_position + Vector3.UP * 1.5), "Item obstruction shot consumes a round")
	check(raker.current_health == original and item.current_health == item_health, "Item blocks shot and retains its immunity")
	item.free()
	await steps()

	actor.camera.look_at(raker.global_position + Vector3.UP * 1.5)
	var muzzle: Vector3 = actor.held_item_node.muzzle_position()
	var camera_point: Vector3 = actor.camera.global_position
	wall = wall_in(world, camera_point.lerp(muzzle, 0.5), Vector3(4, 4, 0.025))
	await steps()
	check(fire_at(actor, raker.global_position + Vector3.UP * 1.5), "Close-wall shot still consumes its round")
	check(raker.current_health == original, "Muzzle extending past close wall cannot bypass camera-to-muzzle clearance")
	wall.free()
	await steps()
	check(fire_at(actor, raker.global_position + Vector3.UP * 1.5), "Removing blocker permits the next shot")
	check(is_equal_approx(raker.current_health, original - 25.0), "Removing blocker restores actual monster damage")
	raker.free()
	await steps()
	var close_target := target_in(world, "res://enemies/raker.tscn", Vector3(0, 0, -0.65))
	actor.camera.look_at(close_target.global_position + Vector3.UP * 1.5)
	await steps()
	var close_query := PhysicsRayQueryParameters3D.create(actor.camera.global_position, actor.held_item_node.muzzle_position())
	close_query.exclude = [actor.get_rid()]
	close_query.collide_with_areas = false
	close_query.hit_from_inside = true
	var close_hit := actor.get_world_3d().direct_space_state.intersect_ray(close_query)
	check(close_hit.get("collider") == close_target, "Pointblank fixture places a real Monster between camera and muzzle")
	check(fire_at(actor, close_target.global_position + Vector3.UP * 1.5), "Pointblank shot is accepted")
	check(is_equal_approx(close_target.current_health, close_target.max_health - 25.0), "Monster before muzzle receives first-contact damage")
	close_target.free()
	await steps()

	# Matching coordinates belong to different physics spaces, as in POI interiors.
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(320, 240)
	root.add_child(viewport)
	var interior := Node3D.new()
	interior.set_meta("entity_domain", true)
	viewport.add_child(interior)
	var interior_player := player_in(interior)
	var interior_target := target_in(interior, "res://enemies/raker.tscn", Vector3(0, 0, -9))
	var exterior_target := target_in(world, "res://enemies/raker.tscn", Vector3(0, 0, -9))
	wall = wall_in(world, Vector3(0, 1.5, -3), Vector3(4, 4, 0.2))
	await steps(4)
	check(interior_player.get_world_3d() != actor.get_world_3d(), "Interior fixture owns a different World3D")
	check(fire_at(interior_player, interior_target.global_position + Vector3.UP * 1.5), "Interior shot is accepted")
	check(is_equal_approx(interior_target.current_health, interior_target.max_health - 25.0), "Exterior wall cannot obstruct shot in own interior World3D")
	check(exterior_target.current_health == exterior_target.max_health, "Interior shot cannot damage exterior actor at identical coordinates")
	viewport.free()
	world.free()
	if failures.is_empty():
		print("PASS: pistol real enemy damage, obstruction, close-wall clearance and World3D isolation")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

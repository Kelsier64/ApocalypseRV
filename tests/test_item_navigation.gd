extends SceneTree
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

func barrier(world: Node3D, position: Vector3, size: Vector3) -> Item:
	var item := Item.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position.y = size.y * 0.5
	item.add_child(collider)
	world.add_child(item)
	item.confirm_placement(Transform3D(Basis.IDENTITY, position), world)
	return item

func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 0.2, 40)
	collider.shape = shape
	floor.add_child(collider)
	world.add_child(floor)
	floor.position.y = -0.1
	var actor: Monster = load("res://enemies/raker.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.position = Vector3(-4, -0.25, 0)
	actor.stagger_amount = 0.0
	actor.move_speed = 3.0
	var goal := Vector3(4, -0.25, 0)
	await physics_frame
	var straight: Vector3 = actor.item_detour.direction(actor, goal, Vector3.RIGHT)
	check(straight.is_equal_approx(Vector3.RIGHT) and not actor.item_detour.active, "Open world uses the original navigation direction")
	var first := barrier(world, Vector3.ZERO, Vector3(1.5, 3.5, 2.5))
	var second := barrier(world, Vector3(2, 0, 0.8), Vector3(1.0, 3.5, 2.5))
	await physics_frame
	var detour: Vector3 = actor.item_detour.direction(actor, goal, Vector3.RIGHT)
	check(actor.item_detour.active and absf(detour.z) > 0.1, "Newly fixed Items create a side detour without rebaking navigation")
	actor._process_chase(1.0 / 60.0, goal)
	check(actor.item_detour.active, "Production chase adopts the Item detour before completing its turn")
	var went_around := false
	for frame in range(260):
		await physics_frame
		actor._process_chase(1.0 / 60.0, goal)
		actor.move_and_slide()
		went_around = went_around or absf(actor.position.z) > 1.4
		if actor.position.distance_to(goal) < 0.35: break
	check(went_around and actor.position.distance_to(goal) < 0.5, "Real monster collision walks around multiple fixed Items to the target")
	actor.position = Vector3(-4, -0.25, 0)
	first.queue_free()
	second.queue_free()
	await physics_frame
	straight = actor.item_detour.direction(actor, goal, Vector3.RIGHT)
	check(straight.is_equal_approx(Vector3.RIGHT) and not actor.item_detour.active, "Removing Items immediately restores the direct route")
	var enclosing := barrier(world, Vector3.ZERO, Vector3(2, 3.5, 2))
	barrier(world, Vector3(-4, 0, -1.1), Vector3(4, 3.5, 0.4))
	barrier(world, Vector3(-4, 0, 1.1), Vector3(4, 3.5, 0.4))
	barrier(world, Vector3(-6, 0, 0), Vector3(0.4, 3.5, 2.6))
	await physics_frame
	actor.item_detour._next_refresh = 0
	var blocked: Vector3 = actor.item_detour.direction(actor, goal, Vector3.RIGHT)
	check(actor.item_detour.active and blocked.is_zero_approx(), "Closed Item barrier produces no path instead of tunneling")
	actor._process_chase(1.0 / 60.0, goal)
	check(Vector2(actor.velocity.x, actor.velocity.z).is_zero_approx(), "Production chase waits when cargo completely blocks its route")
	check(actor.test_move(actor.global_transform, Vector3(8, 0, 0)), "Closed barrier retains physical collision")
	check(not enclosing.is_in_group(Groups.MONSTER_DAMAGEABLE), "Detour barriers remain immune to monster attacks")
	# Endpoints have ground, but the clear space between them is a void.
	collider.disabled = true
	for x in [-3.5, 3.5]:
		var ledge := StaticBody3D.new()
		var ledge_collider := CollisionShape3D.new()
		var ledge_shape := BoxShape3D.new()
		ledge_shape.size = Vector3(3, 0.2, 2)
		ledge_collider.shape = ledge_shape
		ledge.add_child(ledge_collider)
		world.add_child(ledge)
		ledge.position = Vector3(x, -0.1, 10)
	await physics_frame
	var gap_start := Vector3(-4, -0.25, 10)
	var gap_end := Vector3(4, -0.25, 10)
	check(actor.item_detour._supported(actor, gap_start) and actor.item_detour._supported(actor, gap_end), "Gap test has supported route endpoints")
	check(actor.item_detour._clear(actor, gap_start, gap_end) and not actor.item_detour._walkable_edge(actor, gap_start, gap_end), "Detour rejects unsupported ground between clear endpoints")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: dynamic Item placement, detours, removal and closed barriers")
	quit(0 if failures.is_empty() else 1)

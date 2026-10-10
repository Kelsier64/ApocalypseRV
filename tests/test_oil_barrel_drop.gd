extends SceneTree
## G release uses real player inventory, RV geometry, contacts and gravity.
const PLAYER := preload("res://player/player.tscn")
const RV := preload("res://rv/new_rv.tscn")
const BARREL := preload("res://props/oil_barrel.tscn")
const EFFECT := preload("res://enemies/barrel_explosion_effect.gd")
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func steps(count: int = 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func fixture() -> Dictionary:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, .2, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -.1
	world.add_child(floor_body)
	var shell: Node3D = RV.instantiate()
	shell.position.y = .5
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	# Deterministic scripted carrier: real RV shapes remain, wheel dynamics do
	# not alter the velocity assigned just before a production release.
	rv.freeze = true
	rv.set_physics_process(false)
	var actor: CharacterBody3D = PLAYER.instantiate()
	actor.position = Vector3(0, .8, -7.3)
	world.add_child(actor)
	actor.set_physics_process(false)
	await steps(4)
	return {"world": world, "rv": rv, "actor": actor, "entities": WorldEntities.get_container(actor)}

func retire(data: Dictionary) -> void:
	data.world.queue_free()
	await steps(3)

func equip(actor: CharacterBody3D, id: String) -> void:
	check(actor.add_item("Oil Barrel", true, "res://props/oil_barrel.tscn", {"id": id, "condition": 37.0}), "Barrel grant enters real inventory: " + id)
	check(actor.held_item_node is OilBarrel, "Barrel grant creates a held presentation: " + id)

func find_barrel(entities: Node, id: String) -> OilBarrel:
	for child in entities.get_children():
		if child is OilBarrel and child.persistent_id == id and not child.is_queued_for_deletion(): return child
	return null

func press_g(actor: CharacterBody3D) -> void:
	var event := InputEventAction.new()
	event.action = &"drop_item"
	event.pressed = true
	actor._unhandled_input(event)

func set_held_pose(actor: CharacterBody3D, at: Vector3) -> Transform3D:
	var pose := Transform3D(Basis.IDENTITY, at)
	actor.held_item_node.global_transform = pose
	return pose

func volume_hits(body: OilBarrel, pose: Transform3D, actor: CharacterBody3D) -> Array:
	var hits: Array = []
	for child in body.get_children():
		if not child is CollisionShape3D or child.shape == null: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = pose * child.transform
		query.collision_mask = 1
		query.exclude = [body.get_rid(), actor.get_rid()]
		hits.append_array(body.get_world_3d().direct_space_state.intersect_shape(query, 32))
	return hits

func observe_effects(events: Array[int]) -> Callable:
	var observe := func(node: Node) -> void:
		if node.get_script() == EFFECT: events.append(node.get_instance_id())
	node_added.connect(observe)
	return observe

func parked_toss() -> void:
	var data: Dictionary = await fixture()
	var actor: CharacterBody3D = data.actor
	actor.rotation.y = PI
	equip(actor, "parked-g")
	var pose := set_held_pose(actor, Vector3(0, .85, -6.6))
	check(volume_hits(actor.held_item_node, pose, actor).is_empty(), "Parked G fixture starts with a real gap from the RV wall")
	var effects: Array[int] = []
	var observer := observe_effects(effects)
	var engine_before: float = data.rv.get_engine().health
	press_g(actor)
	var barrel := find_barrel(data.entities, "parked-g")
	check(barrel != null and actor.inventory.items.is_empty(), "G transfers parked barrel from inventory exactly once")
	var contacts: Array[String] = []
	if barrel != null:
		check(barrel.global_transform.is_equal_approx(pose), "Clear parked release retains the visible held pose")
		check(barrel.linear_velocity.is_equal_approx(Vector3(0, 0, 3)), "Parked G retains the original 3 m/s toss")
		check(barrel.vehicle_explosion_speed == 6.0 and barrel.fall_explosion_height == 2.0, "Cargo uses 6 m/s crash and unchanged 2 m fall thresholds")
		barrel.body_entered.connect(func(body: Node) -> void:
			if RVConnection.resolve(body) == data.rv: contacts.append(str(body.name)))
	await steps(90)
	check(not contacts.is_empty(), "Parked G toss physically hits an actual RV body")
	check(is_instance_valid(barrel) and not barrel.is_destroyed and effects.is_empty(), "Low RV wall impact after G keeps barrel intact without an explosion")
	check(data.rv.get_engine().health == engine_before, "Low G wall impact causes no engine blast damage")
	if is_instance_valid(barrel): check(barrel.condition == 37.0, "Safe G toss preserves barrel condition")
	node_added.disconnect(observer)
	await retire(data)

func carrier_launch() -> void:
	var data: Dictionary = await fixture()
	var actor: CharacterBody3D = data.actor
	var rv: Chassis = data.rv
	actor.position = Vector3(0, 3.2, -4)
	actor.velocity = Vector3(1.2, 0, -.8)
	actor.rv_support.rv = rv
	actor.rv_support.surface = rv.get_node("RoofFront")
	actor.rv_support.carrier_velocity = Vector3(5.6, 0, -4)
	rv.linear_velocity = Vector3(8, 0, -4)
	rv.angular_velocity = Vector3(0, .6, 0)
	equip(actor, "rotating-g")
	var pose := set_held_pose(actor, Vector3(.6, 4, -4.5))
	check(volume_hits(actor.held_item_node, pose, actor).is_empty(), "Rotating carrier held pose clears actual roof geometry")
	press_g(actor)
	var barrel := find_barrel(data.entities, "rotating-g")
	check(barrel != null, "Supported G releases one barrel")
	if barrel != null:
		# At this off-center point, omega=(0,.6,0) contributes (-2.7,0,-.36).
		check(barrel.linear_velocity.is_equal_approx(Vector3(6.5, 0, -8.16)), "G inherits release-point rotation, relative walking and 3 m/s toss without double carrier motion")
		check(barrel.global_transform.is_equal_approx(pose), "Supported clear release preserves held pose")
		barrel.free()
	actor.rv_support.clear()
	check(actor.enter_seat_mode(rv.get_node("DriverSeat")), "Production player can enter the RV seat for release momentum coverage")
	actor.velocity = Vector3(99, 40, 99)
	equip(actor, "seated-g")
	# Isolate the seated momentum branch with a clear pose above the roof;
	# the upright full barrel cannot fit above the real seat back in the cabin.
	pose = set_held_pose(actor, Vector3(.2, 4, -3.5))
	check(volume_hits(actor.held_item_node, pose, actor).is_empty(), "Scripted seated release pose clears actual RV geometry")
	var seat_anchor := pose
	seat_anchor.origin.x = actor.global_position.x
	seat_anchor.origin.z = actor.global_position.z
	check(volume_hits(actor.held_item_node, seat_anchor, actor).is_empty(), "Scripted seated release has real anchor clearance")
	actor.drop_item()
	barrel = find_barrel(data.entities, "seated-g")
	check(barrel != null, "Seated production release transfers one barrel")
	if barrel != null:
		check(barrel.linear_velocity.is_equal_approx(Vector3(5.9, 0, -7.12)), "Seated release inherits carrier point motion and toss without stale player velocity")
		barrel.free()
	actor.exit_seat_mode(Vector3(12, 5, 0))
	actor.set_physics_process(false)
	# No physics tick may repair the stored movement before this G event.
	# The seat exit point inherits (8,0,-11.2) from the translating/turning RV.
	equip(actor, "seat-exit-g")
	set_held_pose(actor, Vector3(12, 5.8, -.8))
	press_g(actor)
	barrel = find_barrel(data.entities, "seat-exit-g")
	check(barrel != null, "Immediate G after seat exit releases one barrel before a movement tick")
	if barrel != null:
		check(barrel.linear_velocity.is_equal_approx(Vector3(8, 0, -14.2)), "Immediate seat-exit G inherits point velocity plus toss exactly once")
		barrel.free()
	# Establish the ordinary airborne movement representation before testing
	# the independent walking/jump momentum case below.
	actor._process_normal_movement(1.0 / 60.0)
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	actor.position = Vector3(12, 5, 0)
	actor.velocity = Vector3(1, -2, -1)
	actor.released_carrier_velocity = Vector3(8, 7, -4)
	equip(actor, "airborne-g")
	set_held_pose(actor, Vector3(12, 5.8, -.8))
	press_g(actor)
	barrel = find_barrel(data.entities, "airborne-g")
	check(barrel != null, "Airborne G releases one barrel")
	if barrel != null:
		check(barrel.linear_velocity.is_equal_approx(Vector3(9, -2, -8)), "Airborne G adds stored horizontal carrier motion once and retains player vertical velocity")
	await retire(data)

func overlapping_wall() -> void:
	var data: Dictionary = await fixture()
	var actor: CharacterBody3D = data.actor
	actor.rotation.y = PI
	equip(actor, "wall-clearance-g")
	var desired := set_held_pose(actor, Vector3(0, 1.3, -5.9))
	var hits := volume_hits(actor.held_item_node, desired, actor)
	check(hits.any(func(hit: Dictionary) -> bool: return RVConnection.resolve(hit.collider) == data.rv), "Held-wall fixture truly overlaps actual RV geometry before G")
	press_g(actor)
	var barrel := find_barrel(data.entities, "wall-clearance-g")
	check(barrel != null and actor.inventory.items.is_empty(), "G resolves a held-wall overlap and transfers inventory once")
	if barrel != null:
		check(volume_hits(barrel, barrel.global_transform, actor).is_empty(), "Corrected G barrel starts fully outside vehicle geometry")
		check(barrel.global_position.z < -6.3, "Corrected G release stays on the player's side of the RV wall")
		check(barrel.global_position.distance_to(desired.origin) < 1.5, "Wall correction stays near the visible held pose")
		check(barrel.persistent_id == "wall-clearance-g" and barrel.condition == 37.0, "Corrected release preserves Item identity and condition")
	await retire(data)

func blocked_release() -> void:
	var data: Dictionary = await fixture()
	var actor: CharacterBody3D = data.actor
	equip(actor, "blocked-g")
	var pose := set_held_pose(actor, Vector3(0, 1.3, -6.6))
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1.3, 1)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Vector3(0, 1.3, -7.3)
	data.world.add_child(blocker)
	await steps()
	set_held_pose(actor, pose.origin)
	var held: Node3D = actor.held_item_node
	var before: Array = actor.inventory.items.duplicate(true)
	check(not volume_hits(held, Transform3D(Basis.IDENTITY, blocker.position), actor).is_empty(), "Blocked G fixture has no clear player-side release volume")
	press_g(actor)
	press_g(actor)
	check(actor.inventory.items == before and actor.inventory.active_slot == 0, "Blocked G retains the complete inventory record and active slot")
	check(actor.held_item_node == held and is_instance_valid(held), "Blocked G keeps the held Item available")
	check(find_barrel(data.entities, "blocked-g") == null, "Blocked G creates no duplicate world barrel")
	blocker.free()
	await steps()
	set_held_pose(actor, pose.origin)
	press_g(actor)
	var barrel := find_barrel(data.entities, "blocked-g")
	check(barrel != null and actor.inventory.items.is_empty(), "G can release the same barrel after the obstruction is removed")
	if barrel != null: check(barrel.persistent_id == "blocked-g" and barrel.condition == 37.0, "Retried G preserves original identity and condition")
	await retire(data)

func roof_fall() -> void:
	var data: Dictionary = await fixture()
	var actor: CharacterBody3D = data.actor
	actor.position = Vector3(1.4, 3.2, -4)
	actor.rotation.y = -PI / 2
	actor.rv_support.rv = data.rv
	actor.rv_support.surface = data.rv.get_node("RoofFront")
	equip(actor, "roof-fall-g")
	var pose := set_held_pose(actor, Vector3(2.1, 4, -4))
	check(volume_hits(actor.held_item_node, pose, actor).is_empty(), "Roof-edge G begins clear of roof and wall geometry")
	var effects: Array[int] = []
	var observer := observe_effects(effects)
	press_g(actor)
	var barrel := find_barrel(data.entities, "roof-fall-g")
	check(barrel != null, "Roof-edge G releases an ordinary barrel")
	if barrel != null: check(barrel.linear_velocity.is_equal_approx(Vector3(3, 0, 0)), "Roof-edge G retains the original toss speed")
	# Real gravity carries the released barrel from roof height to the floor.
	await steps(150)
	check(not is_instance_valid(barrel) and effects.size() == 1, "A roof-height G fall still consumes the barrel and emits exactly one explosion")
	node_added.disconnect(observer)
	await retire(data)

func run() -> void:
	await parked_toss()
	await carrier_launch()
	await overlapping_wall()
	await blocked_release()
	await roof_fall()
	if failures.is_empty(): print("PASS: oil barrel G release, parked RV contact, rotating carrier momentum, airborne inheritance, wall clearance, inventory retention and roof fall explosion")
	quit(0 if failures.is_empty() else 1)

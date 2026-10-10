extends SceneTree
## Ordinary barrels require hard RV impacts; low-speed contacts remain cargo.
const BARREL := preload("res://props/oil_barrel.tscn")
const RV := preload("res://rv/new_rv.tscn")
const EFFECT := preload("res://enemies/barrel_explosion_effect.gd")
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func steps(count: int = 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func shape_for(body: Node3D, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)

func fixture() -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	shape_for(ground, Vector3(100, 0.2, 100))
	ground.position.y = -0.1
	world.add_child(ground)
	var shell: Node3D = RV.instantiate()
	shell.position.y = 1.8
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.allow_test_controls = true
	rv.handbrake = false
	rv.control_override = {"throttle": 0.0}
	for frame in 90: await physics_frame
	rv.set_physics_process(false)
	rv.brake = 0.0
	return {"world": world, "ground": ground, "rv": rv}

func retire(data: Dictionary) -> void:
	data.world.queue_free()
	await steps()

func barrel_at(world: Node3D, position: Vector3) -> OilBarrel:
	var barrel: OilBarrel = BARREL.instantiate()
	barrel.position = position
	world.add_child(barrel)
	return barrel

func observe_effects(events: Array[int]) -> Callable:
	var observe := func(node: Node) -> void:
		if node.get_script() == EFFECT: events.append(node.get_instance_id())
	node_added.connect(observe)
	return observe

func nearest_vehicle_surface(rv: Chassis, point: Vector3) -> Vector3:
	var nearest := rv.global_position
	var distance := INF
	# Item cargo is deliberately excluded; the production RV owns these shapes.
	for node: Node in rv.find_children("*", "CollisionShape3D", true, false):
		var collision := node as CollisionShape3D
		if collision == null or collision.disabled or collision.shape == null: continue
		var owner := collision.get_parent()
		while owner != rv and owner != null and not owner is Item: owner = owner.get_parent()
		if owner != rv: continue
		var sample := BarrelExplosion.closest_shape_point(collision.shape, collision.global_transform, point)
		if sample.is_empty(): continue
		var candidate: Vector3 = sample.point
		if point.distance_squared_to(candidate) < distance:
			nearest = candidate
			distance = point.distance_squared_to(candidate)
	return nearest

func overlaps_vehicle(barrel: OilBarrel, rv: Chassis) -> bool:
	for child in barrel.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.collision_mask = 1
		query.collide_with_areas = false
		query.exclude = [barrel.get_rid()]
		query.margin = .003
		for hit in barrel.get_world_3d().direct_space_state.intersect_shape(query, 32):
			if RVConnection.resolve(hit.collider) == rv: return true
	return false

func run() -> void:
	await production_contact(Vector3.FORWARD, 0.7, "slow front")
	await production_contact(Vector3.BACK, 0.7, "slow reverse")
	await production_contact(Vector3.FORWARD, 0.7, "slow fixed barrel", true)
	await production_contact(Vector3.FORWARD, 12.0, "fast front")
	await production_contact(Vector3.BACK, 6.0, "reverse rear")
	await production_contact(Vector3.RIGHT, 6.0, "side")
	await production_contact(Vector3.RIGHT, 6.0, "side mounted ladder")
	await production_contact(Vector3.FORWARD, 12.0, "fixed world barrel", true)
	await moving_barrel_contact()
	await stationary_contact()
	await threshold_contacts()
	await rejected_contacts()
	await ownership_and_world_guards()
	await shared_blast_and_persistence()
	if failures.is_empty(): print("PASS: ordinary oil barrel true RV contacts, shared blast, Item immunity, ownership guards and persistence")
	quit(0 if failures.is_empty() else 1)

func production_contact(direction: Vector3, speed: float, label: String, fixed := false) -> void:
	var data: Dictionary = await fixture()
	var rv: Chassis = data.rv
	var target := direction * 14 + Vector3.UP * 0.5
	# The side-door ladder protrudes into a centerline skid. This unobstructed
	# side scenario aims at the front wheel; the next scenario exercises the
	# mounted ladder itself. A small real gap keeps lateral tyre friction from
	# ending the wheel scenario's skid before body contact.
	if label == "side": target.z = -3.0
	var surface := nearest_vehicle_surface(rv, target)
	var offset := 0.45 if label == "side" else (0.4 if fixed and speed < 3.0 else 0.93)
	var barrel := barrel_at(data.world, Vector3(surface.x, 0.5, surface.z) + direction * offset)
	if fixed: barrel.confirm_placement(barrel.global_transform, data.ground, data.ground)
	var touched_bodies: Array[String] = []
	barrel.body_entered.connect(func(body: Node) -> void: touched_bodies.append(str(body.name)))
	var ladder := rv.get_node("SideDoorLadder") as Item
	var ladder_condition := ladder.condition
	var impacts: Array[Dictionary] = []
	rv.vehicle_impact.connect(func(kind: String, _loss: float, damage: float) -> void: impacts.append({"kind": kind, "damage": damage}))
	var effects: Array[int] = []
	var observer := observe_effects(effects)
	await physics_frame
	var health_before: float = rv.get_engine().health
	check(not overlaps_vehicle(barrel, rv), "%s moving contact fixture begins with a real gap from RV bodies" % label)
	rv.linear_velocity = direction * speed
	var speed_after := -1.0
	var touched_shape := false
	for frame in 180:
		await physics_frame
		if is_instance_valid(barrel): touched_shape = touched_shape or overlaps_vehicle(barrel, rv)
		if not effects.is_empty() and speed_after < 0.0: speed_after = rv.linear_velocity.dot(direction)
	var impact_damage := 0.0
	for event: Dictionary in impacts: impact_damage += event.damage
	if speed < 3.0:
		check(is_instance_valid(barrel) and not barrel.is_destroyed and effects.is_empty(), "%s gentle contact keeps barrel intact without a blast" % label)
		check(not touched_bodies.is_empty() or touched_shape, "%s physically reaches the barrel" % label)
		node_added.disconnect(observer)
		await retire(data)
		return
	check(effects.size() == 1, "%s actual production RV contact emits one blast effect" % label)
	check(not is_instance_valid(barrel), "%s blast consumes the ordinary Item barrel" % label)
	check(is_equal_approx(health_before - rv.get_engine().health - impact_damage, 60.0), "%s engine pays one shared 60 HP blast hit in addition to subsequent recorded impacts" % label)
	check(not impacts.any(func(event: Dictionary) -> bool: return event.kind in ["monster", "body"]), "%s yielding oil barrel charges no generic body or monster impact" % label)
	if speed >= 6.0: check(speed_after > speed * 0.5, "%s RV continues traveling when barrel yields" % label)
	if label == "side mounted ladder":
		check(touched_bodies.has("SideDoorLadder"), "Side-mounted-ladder scenario reaches actual secured RV equipment")
		check(is_instance_valid(ladder) and not ladder.is_destroyed and ladder.condition == ladder_condition, "RV ladder contact ignites the barrel while shared blast preserves Item immunity")
	print("OIL_BARREL_CONTACT label=%s speed=%.1f effects=%d speed_after=%.2f engine_delta=%.3f events=%s" % [label, speed, effects.size(), speed_after, health_before - rv.get_engine().health, impacts])
	node_added.disconnect(observer)
	await retire(data)

func stationary_contact() -> void:
	var data: Dictionary = await fixture()
	var rv: Chassis = data.rv
	rv.freeze = true
	var surface := nearest_vehicle_surface(rv, Vector3(14, 0.5, 0))
	var effects: Array[int] = []
	var observer := observe_effects(effects)
	var health_before: float = rv.get_engine().health
	var barrel := barrel_at(data.world, Vector3(surface.x + 0.25, 0.5, surface.z))
	check(overlaps_vehicle(barrel, rv), "Stationary fixture truly overlaps the vehicle")
	await steps(30)
	check(is_instance_valid(barrel) and not barrel.is_destroyed and effects.is_empty(), "Stationary production RV touching a loose barrel stays safe")
	check(is_equal_approx(health_before, rv.get_engine().health), "Stationary contact causes no explosion damage")
	node_added.disconnect(observer)
	await retire(data)

func rejected_contacts() -> void:
	var data: Dictionary = await fixture()
	var rv: Chassis = data.rv
	rv.freeze = true
	var barrel := barrel_at(data.world, Vector3(18, 0.5, 0))
	var effects: Array[int] = []
	var observer := observe_effects(effects)
	# This real player collider starts against the cylinder and physically moves.
	var player := CharacterBody3D.new()
	shape_for(player, Vector3(0.5, 1.0, 0.5))
	player.position = barrel.position + Vector3.RIGHT * 0.55
	data.world.add_child(player)
	player.add_to_group(Groups.PLAYER)
	var area := Area3D.new()
	shape_for(area, Vector3(2, 2, 2))
	rv.add_child(area)
	area.global_position = barrel.global_position
	await steps()
	var player_hit := player.move_and_collide(Vector3.LEFT * 0.1)
	check(player_hit != null and player_hit.get_collider() == barrel, "Player-contact rejection fixture physically touches the barrel")
	check(area.get_overlapping_bodies().has(barrel), "Predictive RV Area overlaps the barrel while RV body stays distant")
	check(not barrel.receive_vehicle_body_contact(player, Vector3.LEFT, barrel.global_position), "Player is rejected by the RV contact hook")
	check(not barrel.receive_vehicle_body_contact(data.ground, Vector3.UP, barrel.global_position), "Floor body is rejected by the RV contact hook")
	await steps(45)
	check(is_instance_valid(barrel) and not barrel.is_destroyed and effects.is_empty(), "Floor/player contact and RV trigger overlap cannot arm an ordinary barrel")
	player.queue_free()
	area.queue_free()
	# The real vehicle surface is close enough for mimic proximity arming, with a gap.
	var surface := nearest_vehicle_surface(rv, Vector3(14, 0.5, 0))
	barrel.position = Vector3(surface.x + 0.95, 0.5, surface.z)
	barrel.linear_velocity = Vector3.ZERO
	await steps(45)
	check(is_instance_valid(barrel) and not barrel.is_destroyed and effects.is_empty(), "RV body proximity across an air gap never starts the mimic fuse on an ordinary Item")
	node_added.disconnect(observer)
	await retire(data)

func ownership_and_world_guards() -> void:
	var data: Dictionary = await fixture()
	var rv: Chassis = data.rv
	rv.freeze = true
	for state: String in ["preview", "placement", "processing", "transfer"]:
		var barrel: OilBarrel = BARREL.instantiate()
		barrel.position = Vector3(20, 0.5, 0)
		barrel.presentation_only = state == "preview"
		barrel.is_being_placed = state == "placement"
		if state == "processing": barrel.processing_owner = rv
		if state == "transfer": barrel.begin_world_transfer()
		data.world.add_child(barrel)
		check(not barrel.receive_vehicle_body_contact(rv, Vector3.LEFT, barrel.global_position) and not barrel.is_destroyed, "%s Item ownership gate rejects vehicle ignition" % state)
		barrel.queue_free()
	await steps()
	var mounted := barrel_at(data.world, Vector3(20, 1, 0))
	mounted.confirm_placement(mounted.global_transform, rv, rv)
	check(mounted.is_fixed and mounted.get_connected_rv() == rv, "Mounted protection fixture owns the canonical RV connection")
	check(not mounted.receive_vehicle_body_contact(rv, Vector3.LEFT, mounted.global_position) and not mounted.is_destroyed, "Mounted cargo ignores its own RV body")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var interior := Node3D.new()
	viewport.add_child(interior)
	var other_shell: Node3D = RV.instantiate()
	interior.add_child(other_shell)
	var other: Chassis = other_shell.get_node("Chassis")
	other.freeze = true
	other.set_physics_process(false)
	await steps()
	check(not mounted.receive_vehicle_body_contact(other, Vector3.LEFT, mounted.global_position) and not mounted.is_destroyed, "Independent World3D contact cannot ignite outdoor cargo")
	viewport.queue_free()
	await steps()
	other_shell = RV.instantiate()
	other_shell.position = Vector3(40, 2, 0)
	data.world.add_child(other_shell)
	other = other_shell.get_node("Chassis")
	other.freeze = true
	other.set_physics_process(false)
	await steps()
	var health_before: float = other.get_engine().health
	var effects: Array[int] = []
	var observer := observe_effects(effects)
	other._impact_age = 0.0
	other.angular_velocity = Vector3.ZERO
	other.linear_velocity = Vector3.LEFT * 6.0
	rv._impact_age = 0.0
	rv.angular_velocity = Vector3.ZERO
	rv.linear_velocity = other.linear_velocity
	check(not mounted.receive_vehicle_body_contact(other, Vector3.LEFT, mounted.global_position), "Cargo on a co-moving foreign RV has zero closing speed")
	rv.linear_velocity = Vector3.ZERO
	check(mounted.receive_vehicle_body_contact(other, Vector3.LEFT, mounted.global_position), "Mounted barrel accepts true body contact from a foreign RV in its world")
	check(mounted.is_destroyed and WorldActorSnapshot.capture(mounted).is_empty(), "Contact latches consumption before deferred blast so snapshots cannot resurrect it")
	mounted.receive_vehicle_body_contact(other, Vector3.LEFT, mounted.global_position)
	await steps()
	check(not is_instance_valid(mounted) and effects.size() == 1 and is_equal_approx(health_before - other.get_engine().health, 60.0), "Duplicate foreign-RV callbacks consume once and emit/pay exactly one explosion")
	node_added.disconnect(observer)
	await retire(data)

func shared_blast_and_persistence() -> void:
	var data: Dictionary = await fixture()
	var rv: Chassis = data.rv
	rv.freeze = true
	var barrel := barrel_at(data.world, Vector3(20, 0.5, 0))
	barrel.condition = 37.0
	barrel.enabled = false
	barrel.set_meta("recycle_result", {ItemNames.METAL_PARTS: 3})
	barrel.linear_velocity = Vector3(0.1, 0.2, 0.3)
	var saved := WorldActorSnapshot.capture(barrel)
	check(saved.get("kind") == "item" and saved.get("scene") == "res://props/oil_barrel.tscn" and WorldActorSnapshot.validation_error(saved, "barrel").is_empty(), "Ordinary barrel remains a valid canonical Item snapshot")
	var identity := barrel.persistent_id
	barrel.begin_world_transfer()
	barrel.free()
	var restored := WorldActorSnapshot.restore(saved, data.world) as OilBarrel
	check(restored != null and restored.persistent_id == identity and restored.condition == 37.0 and not restored.enabled and restored.get_meta("recycle_result") == {ItemNames.METAL_PARTS: 3}, "Item restore retains barrel behavior, ID, condition and recycling state")
	check(restored.global_transform.is_equal_approx(saved.transform) and restored.linear_velocity.is_equal_approx(saved.physics.linear), "Barrel restores Item transform and physics state")
	restored.linear_velocity = Vector3.ZERO
	restored.freeze = true
	var neighbor := barrel_at(data.world, restored.position + Vector3.RIGHT)
	neighbor.freeze = true
	var cargo: Item = load("res://props/scrap.tscn").instantiate()
	cargo.position = restored.position + Vector3.LEFT
	data.world.add_child(cargo)
	cargo.freeze = true
	var neighbor_condition := neighbor.condition
	var cargo_condition := cargo.condition
	var effects: Array[int] = []
	var observer := observe_effects(effects)
	await steps()
	rv._impact_age = 0.0
	rv.angular_velocity = Vector3.ZERO
	rv.linear_velocity = Vector3.LEFT * 6.0
	check(restored.receive_vehicle_body_contact(rv, Vector3.LEFT, restored.global_position), "Restored ordinary barrel retains contact-triggered explosion")
	check(WorldActorSnapshot.capture(restored).is_empty(), "Consumed restored barrel is excluded even before queued removal")
	restored.receive_vehicle_body_contact(rv, Vector3.LEFT, restored.global_position)
	await steps(45)
	check(not is_instance_valid(restored) and effects.size() == 1, "Repeated restored-barrel contact dispatches one complete shared blast")
	check(is_instance_valid(neighbor) and not neighbor.is_destroyed and neighbor.condition == neighbor_condition, "Neighboring ordinary oil barrel is blast immune and never chains")
	check(is_instance_valid(cargo) and not cargo.is_destroyed and cargo.condition == cargo_condition, "Shared blast preserves ordinary Item health")
	check(not WorldActorSnapshot.capture(neighbor).is_empty(), "Surviving neighboring barrel remains available to canonical Item snapshots")
	node_added.disconnect(observer)
	await retire(data)

func threshold_contacts() -> void:
	var data: Dictionary = await fixture()
	var rv: Chassis = data.rv
	rv.freeze = true
	var barrel := barrel_at(data.world, Vector3(20, 0.5, 0))
	barrel.freeze = true
	# Test closing speed along the true normal, not total road speed.
	rv._impact_age = 0.0
	rv.angular_velocity = Vector3.ZERO
	rv.linear_velocity = Vector3.LEFT * 2.99
	check(not barrel.receive_vehicle_body_contact(rv, Vector3.LEFT, barrel.global_position), "Below 3 m/s normal impact stays safe")
	rv.linear_velocity = Vector3(0.1, 0, -12)
	check(not barrel.receive_vehicle_body_contact(rv, Vector3.BACK, barrel.global_position), "Fast vehicle moving away from normal cannot ignite barrel")
	check(not barrel.receive_vehicle_body_contact(rv, Vector3.LEFT, barrel.global_position), "Fast tangential graze stays safe")
	barrel.freeze = false
	barrel.linear_velocity = Vector3.LEFT * 12.0
	rv.linear_velocity = barrel.linear_velocity
	check(not barrel.receive_vehicle_body_contact(rv, Vector3.LEFT, barrel.global_position), "Co-moving loose cargo has zero closing speed")
	rv.linear_velocity = Vector3.ZERO
	barrel.linear_velocity = Vector3.RIGHT * 3.0
	check(barrel.receive_vehicle_body_contact(rv, Vector3.LEFT, barrel.global_position), "Barrel striking parked RV at the 3 m/s boundary explodes")
	check(barrel.is_destroyed and WorldActorSnapshot.capture(barrel).is_empty(), "Qualified impact latches destruction before deferred blast")
	await steps()
	await retire(data)

func moving_barrel_contact() -> void:
	var data: Dictionary = await fixture()
	var rv: Chassis = data.rv
	rv.freeze = true
	rv._impact_age = 0.0
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	var panel := rv.get_node("RightFront") as Node3D
	var collision := panel.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	var direction := rv.global_basis.x.normalized()
	var barrel := barrel_at(data.world, collision.global_position + direction * 1.0)
	var touched: Array[Node] = []
	barrel.body_entered.connect(func(body: Node) -> void: touched.append(body))
	var effects: Array[int] = []
	var observer := observe_effects(effects)
	check(not overlaps_vehicle(barrel, rv), "Moving-barrel fixture begins outside the tall side panel")
	barrel.linear_velocity = -direction * 6.0
	await steps(180)
	check(touched.has(panel), "Thrown barrel actually touches the parked RV side panel")
	check(not is_instance_valid(barrel) and effects.size() == 1, "Moving loose barrel physically strikes parked RV and emits one blast")
	node_added.disconnect(observer)
	await retire(data)

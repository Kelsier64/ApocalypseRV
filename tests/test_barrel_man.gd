extends SceneTree
## Actor behavior with real shapes and isolated explosion dispatch observation.
var failures: Array[String] = []

class ProbeBarrel extends BarrelMan:
	var explosions := 0
	var explosion_vehicle: Node3D
	func _resolve_explosion(_origin: Vector3, vehicle_ref: WeakRef) -> void:
		explosions += 1
		explosion_vehicle = vehicle_ref.get_ref() if vehicle_ref != null else null
		body_collision_shape.disabled = true

class TestPlayer extends CharacterBody3D:
	var seated_in: Node3D
	var is_player_dead := false

class TestVehicle extends RigidBody3D:
	var queued := 0
	var charges := true
	func add_item(_item): pass
	func deduct_materials(_materials): pass
	func queue_monster_impact(_monster, _normal, _point, _approach, charges_damage := true):
		queued += 1
		charges = charges_damage

func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func shape_for(node: Node3D, size: Vector3, center: Vector3, name := "CollisionShape") -> void:
	var collision := CollisionShape3D.new()
	collision.name = name
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	node.add_child(collision)

func fixture(use_default_proximity := false) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	shape_for(floor_body, Vector3(100, 0.2, 100), Vector3(0, -0.1, 0))
	world.add_child(floor_body)
	var barrel := ProbeBarrel.new()
	# Keep the exact 1.5 m boundary and thirty-tick countdown regression even
	# when gameplay tuning changes. Fractional settings must remain supported.
	if not use_default_proximity:
		barrel.settings.proximity_trigger_radius = 1.5
		barrel.settings.proximity_fuse_duration = 0.5
	shape_for(barrel, Vector3.ONE, Vector3.UP * 0.5)
	world.add_child(barrel)
	return {"world": world, "barrel": barrel}

func player_at(world: Node3D, point: Vector3) -> TestPlayer:
	var player := TestPlayer.new()
	shape_for(player, Vector3(0.5, 1.6, 0.5), Vector3.UP * 0.8)
	player.position = point
	world.add_child(player)
	player.add_to_group(Groups.PLAYER)
	return player

func vehicle_at(world: Node3D, point: Vector3) -> TestVehicle:
	var vehicle := TestVehicle.new()
	shape_for(vehicle, Vector3(2, 2, 4), Vector3.ZERO)
	vehicle.position = point
	vehicle.freeze = true
	world.add_child(vehicle)
	vehicle.add_to_group(Groups.CHASSIS)
	vehicle.add_to_group(Groups.RV)
	return vehicle

func retire(data: Dictionary) -> void:
	data.world.queue_free()
	await process_frame
	await physics_frame

func run() -> void:
	await pursuit_and_retraction()
	await occlusion()
	await ceiling_and_contact()
	await vehicle_priority()
	await contact_contract()
	await proximity_boundary_and_countdown()
	await proximity_fixed_step_timing()
	await proximity_automatic_processing()
	await proximity_default_processing()
	await proximity_keeps_pursuing()
	await proximity_contact_short_circuits()
	await proximity_occlusion_and_immunity()
	await proximity_vehicle_surfaces()
	await state_and_world()
	if failures.is_empty(): print("PASS: barrel mimic perception, motion, proximity fuse, true contacts and save state")
	quit(0 if failures.is_empty() else 1)

func pursuit_and_retraction() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	var player := player_at(data.world, Vector3(0, 0, -7))
	for index in 3: await physics_frame
	check(barrel.phase == BarrelMan.Phase.RISING, "Visible player inside eight metres starts rising")
	check(barrel.visual_height >= 0.5 and barrel.visual_height < 1.4, "Rising starts with barrel on the ground")
	for index in 52: await physics_frame
	check(barrel.phase == BarrelMan.Phase.CHASE and is_equal_approx(barrel.visual_height, 1.4), "Rise completes and reaches standing barrel height")
	for index in 25: await physics_frame
	check(barrel.velocity.slide(Vector3.UP).length() > 2 and barrel.velocity.slide(Vector3.UP).length() <= 6.01, "Chase accelerates and respects six metre per second player cap")
	player.position = Vector3(0, 0, -60)
	for index in 370: await physics_frame
	check(barrel.phase == BarrelMan.Phase.DISGUISED and is_equal_approx(barrel.visual_height, 0.5), "Five seconds without target retracts to a grounded disguise")
	check(barrel.locomotion_state == Monster.LocomotionState.NORMAL and barrel.contact_damage == 0, "Mimic has no climbing or generic contact attack")
	check(BarrelMan.validate_barrel_state(barrel.capture_barrel_state()), "Idle timer produces valid persistent state")
	await retire(data)

func occlusion() -> void:
	var data := fixture()
	var wall := StaticBody3D.new()
	shape_for(wall, Vector3(4, 3, 0.3), Vector3(0, 1.5, -3))
	data.world.add_child(wall)
	player_at(data.world, Vector3(0, 0, -5))
	for index in 15: await physics_frame
	check(data.barrel.phase == BarrelMan.Phase.DISGUISED, "Player within detection range behind a solid wall cannot wake disguise")
	wall.queue_free()
	for index in 15: await physics_frame
	check(data.barrel.phase == BarrelMan.Phase.RISING, "Removing visual obstruction wakes nearby disguise")
	await retire(data)

func ceiling_and_contact() -> void:
	var data := fixture()
	var ceiling := StaticBody3D.new()
	shape_for(ceiling, Vector3(3, 0.2, 3), Vector3(0, 1.3, 0))
	data.world.add_child(ceiling)
	var player := player_at(data.world, Vector3(0, 0, -4))
	for index in 90: await physics_frame
	var barrel: ProbeBarrel = data.barrel
	check(barrel.phase == BarrelMan.Phase.RISING and is_equal_approx(barrel.visual_height, 0.5), "Insufficient standing clearance holds disguise height")
	ceiling.queue_free()
	for index in 58: await physics_frame
	check(barrel.phase == BarrelMan.Phase.CHASE, "Removing obstruction permits full rise")
	player.position = barrel.position
	for index in 3: await physics_frame
	check(barrel.phase == BarrelMan.Phase.DETONATED and barrel.explosions == 1, "Actual player shape contact immediately dispatches one explosion")
	barrel.take_damage(100)
	barrel.detonate()
	await process_frame
	check(barrel.explosions == 1, "Repeated death and damage callbacks cannot duplicate explosion")
	await retire(data)

func vehicle_priority() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	var vehicle := vehicle_at(data.world, Vector3(7, 1, 0))
	var player := player_at(data.world, Vector3(0, 0, -7))
	await physics_frame
	barrel._refresh_barrel_target()
	check(barrel.target_player == player and barrel.target_vehicle == null, "Visible player takes priority over nearby empty car")
	player.seated_in = vehicle
	barrel._refresh_barrel_target()
	check(barrel.target_vehicle == vehicle, "Seated player's vehicle becomes chase target")
	check(barrel._barrel_destination().distance_to(vehicle.global_position) > 0.5, "Vehicle goal is on exterior rather than chassis centre")
	vehicle.linear_velocity = Vector3.RIGHT * 20
	for index in 100: await physics_frame
	check(barrel.velocity.slide(Vector3.UP).length() <= 10.01, "Vehicle pursuit obeys ten metre per second speed cap")
	await retire(data)

func contact_contract() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	var vehicle := vehicle_at(data.world, Vector3(10, 1, 0))
	await physics_frame
	check(not barrel._apply_vehicle_contact(vehicle, Vector3.LEFT, barrel.position), "Predictive forward probe is rejected")
	check(not barrel.is_dead, "Predictive probe does not ignite disguise")
	vehicle.linear_velocity = Vector3.LEFT * 12
	check(barrel.receive_vehicle_body_contact(vehicle, Vector3.LEFT, barrel.position), "Real-contact hook accepts car independent of gait or speed")
	barrel.receive_vehicle_body_contact(vehicle, Vector3.LEFT, barrel.position)
	await process_frame
	check(barrel.explosions == 1 and barrel.explosion_vehicle == vehicle, "Real repeated vehicle contact dispatches a single explosion with contacted vehicle")
	check(vehicle.queued == 1 and not vehicle.charges, "Soft yielding queues once without duplicate generic engine damage")
	await retire(data)
	data = fixture()
	barrel = data.barrel
	vehicle = vehicle_at(data.world, Vector3(0.8, 0.7, 0))
	for index in 3: await physics_frame
	check(barrel.explosions == 1, "Stationary car shape touching grounded disguised barrel detonates")
	await retire(data)

func proximity_boundary_and_countdown() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	barrel.set_physics_process(false)
	check(is_equal_approx(barrel.settings.proximity_trigger_radius, 1.5) and is_equal_approx(barrel.settings.proximity_fuse_duration, 0.5), "Boundary fixture accepts a fractional 1.5 m radius and 0.5 s fuse")
	# Player's real box extends 0.25 m toward the barrel. Its root stays
	# outside 1.5 m in both cases so a centre-distance shortcut cannot pass.
	var player := player_at(data.world, Vector3(1.76, 0, 0))
	await physics_frame
	await physics_frame
	barrel._refresh_barrel_target()
	barrel._update_proximity_fuse(0.0)
	check(barrel.proximity_fuse_remaining < 0.0 and not barrel.is_dead, "A confirmed player surface at 1.51 m stays unarmed")
	player.position.x = 1.74
	await physics_frame
	await physics_frame
	barrel._refresh_barrel_target()
	barrel._update_proximity_fuse(0.0)
	check(is_equal_approx(barrel.proximity_fuse_remaining, 0.5) and not barrel.is_dead, "Entering 1.49 m from the real player surface arms without immediate detonation")
	var start := barrel.position
	player.position.x = 60.0
	await physics_frame
	await physics_frame
	barrel._refresh_barrel_target()
	barrel._update_proximity_fuse(0.2)
	check(is_equal_approx(barrel.proximity_fuse_remaining, 0.3), "Leaving detection range does not cancel or reset an armed fuse")
	barrel._update_proximity_fuse(0.2)
	barrel._update_proximity_fuse(0.099)
	check(not barrel.is_dead and barrel.explosions == 0, "Stationary armed barrel remains alive through 0.499 seconds")
	barrel._update_proximity_fuse(0.0011)
	check(barrel.is_dead and barrel.phase == BarrelMan.Phase.DETONATED and barrel.position == start, "Fuse expiry commits death after 0.5 seconds without motion or a current target")
	await process_frame
	barrel._update_proximity_fuse(1.0)
	barrel.detonate()
	await process_frame
	check(barrel.explosions == 1 and barrel.explosion_vehicle == null, "Expired proximity fuse resolves exactly once without granting true vehicle-contact damage")
	await retire(data)

func proximity_automatic_processing() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	barrel.settings.chase_speed = 0.0
	barrel.settings.acceleration = 0.0
	player_at(data.world, Vector3(1.74, 0, 0))
	for index in 5: await physics_frame
	check(barrel.proximity_fuse_remaining >= 0.0 and not barrel.is_dead, "Normal physics processing arms a stationary disguised barrel")
	for index in 35: await physics_frame
	await process_frame
	check(barrel.explosions == 1 and barrel.position.slide(Vector3.UP).length() < 0.01, "Normal physics processing ticks the fuse to detonation while stationary")
	await retire(data)

func proximity_default_processing() -> void:
	var data := fixture(true)
	var barrel: ProbeBarrel = data.barrel
	check(is_equal_approx(barrel.settings.proximity_trigger_radius, 3.0) and is_equal_approx(barrel.settings.proximity_fuse_duration, 2.0), "Gameplay defaults retain a 3 m proximity radius and a 2 s fuse")
	barrel.settings.chase_speed = 0.0
	barrel.settings.acceleration = 0.0
	# The real player surface is 2.99 m away, inside the current gameplay
	# radius but outside the fractional boundary fixture used above.
	player_at(data.world, Vector3(3.24, 0, 0))
	for index in 5: await physics_frame
	check(barrel.proximity_fuse_remaining > 0.0 and not barrel.is_dead, "Normal physics processing arms the current gameplay proximity radius")
	for index in 35: await physics_frame
	check(barrel.proximity_fuse_remaining > 0.0 and not barrel.is_dead, "Current gameplay fuse remains alive past the fractional half-second fixture duration")
	for index in 90: await physics_frame
	await process_frame
	check(barrel.explosions == 1 and barrel.position.slide(Vector3.UP).length() < 0.01, "Normal physics processing detonates the current two-second gameplay fuse while stationary")
	await retire(data)

func proximity_fixed_step_timing() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	barrel.set_physics_process(false)
	player_at(data.world, Vector3(1.74, 0, 0))
	await physics_frame
	await physics_frame
	barrel._update_proximity_fuse(0.0)
	check(is_equal_approx(barrel.proximity_fuse_remaining, 0.5), "Fixed-step timing begins with an armed half-second fuse")
	for index in 29: barrel._update_proximity_fuse(1.0 / 60.0)
	check(not barrel.is_dead and barrel.proximity_fuse_remaining > 0.0, "Half-second fuse stays alive after twenty-nine fixed 60 Hz ticks")
	barrel._update_proximity_fuse(1.0 / 60.0)
	check(barrel.is_dead and barrel.proximity_fuse_remaining == 0.0, "Thirtieth fixed 60 Hz tick commits detonation without a floating-point extra frame")
	await process_frame
	check(barrel.explosions == 1, "Exactly thirty fixed ticks dispatch one explosion")
	await retire(data)

func proximity_contact_short_circuits() -> void:
	for target_is_vehicle in [false, true]:
		var data := fixture()
		var barrel: ProbeBarrel = data.barrel
		barrel.set_physics_process(false)
		var target: Node3D = vehicle_at(data.world, Vector3(2.49, 1, 0)) if target_is_vehicle else player_at(data.world, Vector3(1.74, 0, 0))
		await physics_frame
		await physics_frame
		barrel._refresh_barrel_target()
		barrel._update_proximity_fuse(0.0)
		check(barrel.proximity_fuse_remaining > 0.0 and not barrel.is_dead, "%s proximity arms before physical contact" % ("RV" if target_is_vehicle else "Player"))
		target.position.x = 0.8 if target_is_vehicle else 0.0
		await physics_frame
		await physics_frame
		barrel._check_body_contacts()
		check(barrel.is_dead and barrel.proximity_fuse_remaining > 0.0, "%s real shape overlap bypasses the remaining countdown immediately" % ("RV" if target_is_vehicle else "Player"))
		barrel._check_body_contacts()
		barrel._update_proximity_fuse(1.0)
		barrel.detonate()
		await process_frame
		check(barrel.explosions == 1, "%s contact during an armed fuse resolves once" % ("RV" if target_is_vehicle else "Player"))
		check(barrel.explosion_vehicle == (target if target_is_vehicle else null), "Only genuine RV overlap records a contacted vehicle")
		await retire(data)

func proximity_keeps_pursuing() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	barrel._set_phase(BarrelMan.Phase.CHASE)
	player_at(data.world, Vector3(1.74, 0, 0))
	for index in 10: await physics_frame
	check(barrel.proximity_fuse_remaining > 0.0 and not barrel.is_dead, "Chasing barrel remains alive during the armed countdown")
	check(barrel.velocity.x > 0.5 and barrel.position.x > 0.03, "Arming the fuse preserves pursuit motion toward the player")
	await retire(data)

func proximity_occlusion_and_immunity() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	barrel.set_physics_process(false)
	var wall := StaticBody3D.new()
	shape_for(wall, Vector3(0.2, 4, 6), Vector3(0.8, 2, 0))
	data.world.add_child(wall)
	player_at(data.world, Vector3(1.74, 0, 0))
	await physics_frame
	await physics_frame
	barrel._refresh_barrel_target()
	barrel._update_proximity_fuse(0.0)
	check(barrel.proximity_fuse_remaining < 0.0, "Solid wall blocks arming even when the player collision surface is within 1.5 m")
	wall.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	barrel._refresh_barrel_target()
	barrel._update_proximity_fuse(0.0)
	check(barrel.proximity_fuse_remaining > 0.0, "Removing the wall confirms the nearby surface and arms the fuse")
	await retire(data)
	data = fixture()
	barrel = data.barrel
	barrel.set_physics_process(false)
	var vehicle := vehicle_at(data.world, Vector3(10, 1, 0))
	var item := Item.new()
	item.freeze = true
	shape_for(item, Vector3.ONE, Vector3.ZERO)
	item.position = Vector3(-8.5, -0.5, 0)
	vehicle.add_child(item)
	# A separate collision body beneath an Item also inherits Item immunity.
	var item_body := StaticBody3D.new()
	shape_for(item_body, Vector3.ONE, Vector3.ZERO)
	item.add_child(item_body)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var foreign_world := Node3D.new()
	viewport.add_child(foreign_world)
	player_at(foreign_world, Vector3(1.74, 0, 0))
	vehicle_at(foreign_world, Vector3(2.49, 1, 0))
	await physics_frame
	await physics_frame
	barrel._refresh_barrel_target()
	barrel._update_proximity_fuse(0.0)
	check(barrel.proximity_fuse_remaining < 0.0 and not barrel.is_dead, "Nearby Item and its child collider cannot arm through a distant RV ancestor; foreign World3D targets cannot arm")
	viewport.queue_free()
	await retire(data)

func proximity_vehicle_surfaces() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	barrel.set_physics_process(false)
	vehicle_at(data.world, Vector3(0, 1, -3.5))
	await physics_frame
	await physics_frame
	barrel._refresh_barrel_target()
	barrel._update_proximity_fuse(0.0)
	check(barrel.proximity_fuse_remaining > 0.0 and not barrel.is_dead, "Rear RV surface at the inclusive 1.5 m boundary arms even though its chassis origin is farther away")
	await retire(data)
	data = fixture()
	barrel = data.barrel
	barrel.set_physics_process(false)
	var vehicle := vehicle_at(data.world, Vector3(10, 1, 0))
	var panel := RVStructurePanel.new()
	shape_for(panel, Vector3(0.4, 1, 1), Vector3.ZERO)
	panel.position = Vector3(-8.31, -0.5, 0)
	vehicle.add_child(panel)
	await physics_frame
	await physics_frame
	barrel._refresh_barrel_target()
	barrel._update_proximity_fuse(0.0)
	check(barrel.proximity_fuse_remaining > 0.0 and not barrel.is_dead, "Connected vehicle panel surface arms while the chassis body remains outside proximity range")
	await retire(data)

func state_and_world() -> void:
	var data := fixture()
	var barrel: ProbeBarrel = data.barrel
	barrel.set_physics_process(false)
	var state := {"phase": BarrelMan.Phase.RISING, "phase_elapsed": 0.4, "visual_height": 0.95, "lost_interest_elapsed": 1.0}
	check(BarrelMan.validate_barrel_state(state), "Mid-rise snapshot is accepted")
	barrel.restore_barrel_state(state)
	check(barrel.capture_barrel_state() == state and is_equal_approx(barrel.body_collision_shape.position.y, 0.725), "Mid-rise snapshot restores progression and grounded collider")
	var armed_state := state.duplicate()
	armed_state.proximity_fuse_remaining = 0.37
	barrel.restore_barrel_state(armed_state)
	check(barrel.capture_barrel_state() == armed_state, "Armed snapshot restores the remaining fuse exactly")
	barrel.restore_barrel_state(state)
	check(barrel.proximity_fuse_remaining < 0.0 and barrel.capture_barrel_state() == state, "Legacy state with no fuse resets an armed actor to unarmed without adding save keys")
	var invalid := state.duplicate()
	invalid.phase = BarrelMan.Phase.DETONATED
	check(not BarrelMan.validate_barrel_state(invalid), "Detonated monster cannot be restored from save")
	invalid = state.duplicate()
	invalid.visual_height = NAN
	check(not BarrelMan.validate_barrel_state(invalid), "Nonfinite saved height rejected")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var foreign_world := Node3D.new()
	viewport.add_child(foreign_world)
	var foreign_player := player_at(foreign_world, Vector3(0, 0, -2))
	barrel._refresh_barrel_target()
	check(barrel.target_player == null, "Foreign World3D player is never targeted")
	var foreign_rv := vehicle_at(foreign_world, Vector3.ZERO)
	check(not barrel.receive_vehicle_body_contact(foreign_rv, Vector3.RIGHT, Vector3.ZERO), "Foreign World3D vehicle cannot trigger contact explosion")
	check(not barrel.is_dead and foreign_player != null, "Foreign callbacks leave mimic alive")
	viewport.queue_free()
	barrel.take_damage(1)
	check(barrel.phase == BarrelMan.Phase.RISING and not barrel.is_dead, "Nonlethal damage wakes mimic")
	barrel.take_damage(100)
	await process_frame
	check(barrel.explosions == 1, "Lethal damage explodes rather than drops loot")
	await retire(data)

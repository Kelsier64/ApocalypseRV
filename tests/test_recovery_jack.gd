extends SceneTree

const Fixture := preload("res://tests/support/rv_handling_fixture.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	Fixture.ground(world)
	var vehicle := Fixture.vehicle(world, Vector3.UP * 2.9, PI)
	var person := Fixture.player(world, Vector3(4.7, 0.2, 0.0))
	var jack: RecoveryJack = preload("res://props/recovery_jack.tscn").instantiate()
	jack.position = Vector3(3.3, 0.02, 0.0)
	jack.freeze = true
	world.add_child(jack)
	for i in 135: await physics_frame
	var recipe := RecipeCatalog.find("recovery_jack")
	check(recipe != null and recipe.scene_path == RecoveryJack.SCENE, "Workbench resolves the Recovery Jack recipe")
	var stored := VehicleSnapshot.capture(vehicle)
	check(VehicleSnapshot.validate(stored) and stored.items.any(func(entry: Dictionary) -> bool: return entry.scene_path == RecoveryJack.SCENE), "Starter jack is trusted and included with the inverted RV snapshot")
	check(VehicleSnapshot.apply(vehicle, stored), "Inverted vehicle and starter supplies restore")
	var record := WorldActorSnapshot.capture(jack)
	var scene := SaveSceneCatalog.resolve(record.scene, "Item")
	check(scene != null and record.state.id == jack.persistent_id, "Loose Recovery Jack is a trusted save actor")
	jack.free()
	jack = WorldActorSnapshot.restore(record, world) as RecoveryJack
	check(jack != null and jack.persistent_id == record.state.id and jack.global_transform.is_equal_approx(record.transform), "Loose jack reload preserves identity and pose")
	for i in 45: await physics_frame
	var first := jack.interact_hold(person)
	for i in 600:
		if jack._vehicle == null: break
		await physics_frame
	for i in 60: await physics_frame
	print("RECOVERY 1 ", first, " up=", vehicle.global_basis.y.y, " position=", vehicle.global_position, " velocity=", vehicle.linear_velocity, " lifting=", jack._vehicle != null)
	check(first == "Lifting RV" and vehicle.rollover_state() == Chassis.Rollover.SIDE, "First lift leaves an inverted RV on its side")
	var forward := vehicle.global_basis.z.slide(Vector3.UP).normalized()
	var right := Vector3.UP.cross(forward)
	var direction := signf(vehicle.global_basis.y.cross(Vector3.UP).dot(forward))
	jack.global_position = (vehicle.global_position + right * direction * 3.0).slide(Vector3.UP) + Vector3.UP * 0.02
	person.global_position = jack.global_position + right * direction * 1.3
	for i in 15: await physics_frame
	var second := jack.interact_hold(person)
	for i in 600:
		if not jack.is_lifting(): break
		await physics_frame
	for i in 60: await physics_frame
	print("RECOVERY 2 ", second, " up=", vehicle.global_basis.y.y, " position=", vehicle.global_position)
	check(second == "Lifting RV" and vehicle.rollover_state() == Chassis.Rollover.UPRIGHT, "Second lift returns the RV to its wheels")
	await check_inventory_recovery()
	await check_placement_clearance()
	var workbench := vehicle.get_equipment().filter(func(device: Node) -> bool: return device is CraftingStation).front() as CraftingStation
	vehicle.deposit_materials(recipe.costs)
	var completed: Array[String] = []
	workbench.output_committed.connect(func(_rv_id: String, _item_id: String, recipe_id: String) -> void: completed.append(recipe_id))
	check(workbench.request_craft(recipe.recipe_id), "The production workstation accepts the recovery recipe")
	workbench.step_work(recipe.duration)
	check(completed == [recipe.recipe_id], "Crafting produces one physical jack")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: jack recovery stages, item persistence and recipe registration")
	quit(1 if not failures.is_empty() else 0)

func check_inventory_recovery() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	world.position.z = 250.0
	root.add_child(world)
	var ground := Fixture.ground(world)
	var rv := Fixture.vehicle(world, Vector3(0, 2.9, 0), PI)
	var player := Fixture.player(world, Vector3(4.0, 0.0, 0))
	var jack: RecoveryJack = load(RecoveryJack.SCENE).instantiate()
	jack.position = Vector3(3.25, 0.02, 0)
	jack.freeze = true
	jack.condition = 73.0
	world.add_child(jack)
	var known_state := jack.capture_item_state()
	for i in 135: await physics_frame
	aim(player, jack.global_position + Vector3.UP * 0.1)
	await press_interact(5)
	check(player.inventory.active_item().get("state") == known_state, "Tap E picks up the loose jack with its original identity and condition")
	if player.inventory.active_item().is_empty(): return

	var surface := ground.get_child(0) as CollisionShape3D
	surface.disabled = true
	await physics_frame
	var blocked := RecoveryJack.deploy_from_inventory(player, rv)
	check(not blocked.has("jack") and player.inventory.active_item().get("state") == known_state, "No deployment when the ground is unavailable and the tool stays in inventory")
	surface.disabled = false
	for i in 70: await physics_frame
	for stage in 2:
		var forward := rv.global_basis.z.slide(Vector3.UP).normalized()
		var side := Vector3.UP.cross(forward)
		if stage == 1: side *= signf(rv.global_basis.y.cross(Vector3.UP).dot(forward))
		var capsule: CapsuleShape3D = player.standing_collision_shape
		var foot_height: float = player.standing_collision_transform.origin.y - capsule.height * 0.5
		player.global_position = rv.global_position.slide(Vector3.UP) + side * 3.9 - Vector3.UP * foot_height
		player.velocity = Vector3.ZERO
		aim(player, rv.global_position + Vector3.UP * 0.3)
		await press_interact(72)
		var lifting: RecoveryJack = player.camera.get_node("InteractRay")._lifting_jack
		check(is_instance_valid(lifting) and lifting.is_lifting(), "Hold E while aiming at the overturned body starts lift %d" % (stage + 1))
		if not is_instance_valid(lifting):
			print("DEPLOYMENT REFUSED: ", player.camera.get_node("InteractRay")._recovery_message)
			break
		check(player.inventory.active_item().is_empty() and lifting.capture_item_state() == known_state, "Deployment transfers the existing jack into the world")
		var checked_contact := false
		for i in 660:
			if not is_instance_valid(lifting) or not lifting.is_lifting(): break
			if not checked_contact and lifting._extension > RecoveryJack.MAX_EXTENSION * 0.4 and not lifting._released:
				var contact_surface := lifting.load_surface()
				var tip := lifting.saddle.to_global(Vector3.UP * RecoveryJack.SHOE_REACH)
				check(tip.distance_to(contact_surface.origin) < 0.05, "Loaded ram stays beside the same point on the moving RV")
				check(lifting.saddle.global_basis.y.dot(contact_surface.basis.y) > 0.99, "The jack shoe turns to sit flat against the RV")
				var plane_clearance := contact_surface.basis.y.dot(contact_surface.origin - tip)
				check(plane_clearance >= -0.01, "The outside face of the shoe stays clear of the body")
				checked_contact = true
			await physics_frame
		check(checked_contact, "Recovery drives the ram through its loaded stroke")
		for i in 90: await physics_frame
		check(player.inventory.active_item().get("state") == known_state, "Completed lift returns the same jack to inventory")
		check(rv.rollover_state() == (Chassis.Rollover.SIDE if stage == 0 else Chassis.Rollover.UPRIGHT), "Inventory recovery reaches the expected roll state")
	world.queue_free()

func check_placement_clearance() -> void:
	var world := Node3D.new()
	world.position.z = 500.0
	root.add_child(world)
	var ground := Fixture.ground(world, deg_to_rad(16.0))
	for i in 2: await physics_frame
	var space := world.get_world_3d().direct_space_state
	var pose := RecoveryJack._foot_pose(space, Vector3(1.0, 0.5, 500.0), Vector3.RIGHT, [])
	check(pose != Transform3D.IDENTITY and pose.basis.y.dot(ground.global_basis.y) > 0.999, "Jack plate follows the slope")
	for x in [-RecoveryJack.FOOT_HALF_SIZE.x, RecoveryJack.FOOT_HALF_SIZE.x]:
		for z in [-RecoveryJack.FOOT_HALF_SIZE.y, RecoveryJack.FOOT_HALF_SIZE.y]:
			var corner: Vector3 = pose * Vector3(x, 0.0, z)
			var gap := (corner - ground.global_position).dot(ground.global_basis.y)
			check(gap >= 0.0 and gap <= RecoveryJack.FOOT_OFFSET * 2.0, "All base corners stay above the sloped ground")
	var contact_surface := Transform3D(Basis(Vector3.FORWARD, Vector3.LEFT, Vector3.UP), Vector3(1.0, 3.0, 500.0))
	var clearance := RecoveryJack._shoe_clearance_query([])
	check(RecoveryJack._shoe_is_clear(space, clearance, contact_surface), "Shoe fits on an open surface")
	var obstruction := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var lip := BoxShape3D.new()
	lip.size = Vector3.ONE * 0.028
	shape.shape = lip
	obstruction.add_child(shape)
	obstruction.position = contact_surface * Vector3(clearance.shape.size.x * 0.5, -0.035, 0.0) - world.position
	world.add_child(obstruction)
	for i in 2: await physics_frame
	var centerline := PhysicsRayQueryParameters3D.create(contact_surface * (Vector3.DOWN * 0.1), contact_surface.origin)
	check(space.intersect_ray(centerline).is_empty(), "The shoe's centerline misses the raised trim")
	check(not RecoveryJack._shoe_is_clear(space, clearance, contact_surface), "Raised trim at the shoe edge blocks deployment")
	world.queue_free()

func aim(player: Node3D, point: Vector3) -> void:
	var facing := point - player.global_position
	player.rotation.y = atan2(-facing.x, -facing.z)
	var view: Vector3 = point - player.camera.global_position
	player.camera.rotation = Vector3(atan2(view.y, view.slide(Vector3.UP).length()), 0.0, 0.0)

func press_interact(ticks: int) -> void:
	await physics_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	for i in ticks: await physics_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	for i in 3: await physics_frame

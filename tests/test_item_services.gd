extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	await process_frame
	await physics_frame
	var station: CraftingStation = rv.get_node("CraftingStation")
	var recycler: Item = rv.get_node("Scrapper")
	var generator: Item = rv.get_node("Generator")
	rv.add_item(ItemNames.UNREFINED_FUEL, 20)
	rv.add_item(ItemNames.METAL_PARTS, 10)
	rv.current_power = 50.0
	var fuel_before := rv.get_item_count(ItemNames.UNREFINED_FUEL)
	check(station.request_craft("gasoline"), "Mounted workstation accepts a funded job")
	station.prepare_pickup()
	check(station.jobs.is_empty() and rv.get_item_count(ItemNames.UNREFINED_FUEL) == fuel_before, "Pickup refunds the original vehicle once before item capture")
	station.prepare_pickup()
	check(rv.get_item_count(ItemNames.UNREFINED_FUEL) == fuel_before, "Repeated pickup preparation cannot duplicate refunds")
	check(station.capture_item_state().service.jobs.is_empty(), "Transported workstation has no live or serialized jobs")
	recycler.recycle_prop(generator)
	check(generator.processing_owner == null, "Recycler refuses fixed device obstacles")
	recycler.recycle_prop(recycler)
	check(recycler.processing_owner == null, "Recycler cannot consume itself")
	check(player.add_prop_item(generator, generator.scene_file_path), "Former equipment occupies the large inventory slot")
	var held: Item = player.held_item_node
	check(held.presentation_only and not held.can_operate() and held.get_connected_rv() == null, "Held preview cannot register or operate services")
	check(not held.is_in_group(Groups.RV_POWER_GENERATORS), "Held generator does not join service discovery")
	check(player.inventory.items.size() == 1 and player.inventory.is_holding_large_item(), "Equipment obeys large-item inventory rules")
	recycler.set_enabled(false)
	recycler.accept_held_item(player)
	check(player.inventory.items.size() == 1 and recycler.props_being_crushed.is_empty(), "Rejected held handoff preserves inventory ownership")
	recycler.set_enabled(true)
	var identity: String = player.inventory.active_item().state.id
	recycler.accept_held_item(player)
	check(player.inventory.items.is_empty() and recycler.props_being_crushed.size() == 1, "Ready recycler transfers large item into processing exactly once")
	if not recycler.props_being_crushed.is_empty():
		var input: Item = recycler.props_being_crushed[0].prop
		check(input.persistent_id == identity and input.processing_owner == recycler, "Recycling retains the exact item identity")
		recycler.prepare_pickup()
		check(input.processing_owner == null and not input.freeze and recycler.props_being_crushed.is_empty(), "Picking up recycler releases unfinished inputs with real physics")
	var socket: BatterySocket = rv.get_node("BatterySocket")
	if socket.installed_battery == null: socket.installed_battery = BatteryState.new()
	var battery_id: String = socket.installed_battery.id
	socket.prepare_pickup()
	check(socket.installed_battery == null, "Picking up socket ejects installed battery")
	var batteries := 0
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Item and actor.persistent_id == battery_id: batteries += 1
	check(batteries == 1, "Socket removal preserves one loose battery with its identity")
	var obstacle := Item.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 1)
	collider.shape = box
	collider.position.y = 1.0
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(12, 0, 0)), rv)
	var monster: Monster = load("res://enemies/raker.tscn").instantiate()
	world.add_child(monster)
	monster.set_physics_process(false)
	monster.position = Vector3(10, MonsterCabinRoute.ROOT_Y, 0)
	await physics_frame
	check(not MonsterCabinRoute.new().clear_segment(monster, rv, rv.to_local(monster.global_position), rv.to_local(Vector3(14, monster.position.y, 0))), "Cabin routing sweep treats fixed items as physical obstacles")
	check(monster.test_move(monster.global_transform, Vector3(4, 0, 0)), "Monster collision cannot phase through an immune item barrier")
	monster.position.x = 14
	check(not monster._has_attack_line_of_sight_to_target(rv), "Mounted item occludes its owning chassis instead of forwarding monster attacks")
	monster.position.x = 10
	obstacle.queue_free()
	await physics_frame
	check(MonsterCabinRoute.new().clear_segment(monster, rv, rv.to_local(monster.global_position), rv.to_local(Vector3(14, monster.position.y, 0))), "Removing item barrier clears the route on the next physics update")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: unified item services, refunds, previews and recycler ownership")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

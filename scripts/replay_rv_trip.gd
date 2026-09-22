extends SceneTree
## Scripted integration rehearsal in the production world, not manual play.
## Only setup supplies and engine damage are injected. Travel uses real controls.
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var caption: Label
var failed := false
func _init() -> void: run.call_deferred()
func phase(message: String) -> void:
	print("TRIP ", message)
	caption.text = "RV TRIP REPLAY\n" + message
func require(ok: bool, message: String) -> bool:
	if not ok:
		failed = true
		phase("FAIL: " + message)
		push_error("FAIL: " + message)
		Input.action_release("move_forward")
		if rv:
			rv.control_override = {"brake": 1.0}
			rv.handbrake = true
		if not "--stay" in OS.get_cmdline_user_args(): quit(1)
	return ok
func ticks(count: int) -> void:
	for i in range(count): await physics_frame
func walk(local: Vector3) -> bool:
	for i in range(1200):
		var target := rv.to_global(local)
		var direction := target - player.global_position
		direction.y = 0
		if direction.length() < 0.32:
			Input.action_release("move_forward")
			await ticks(8)
			return true
		player.global_rotation.y = atan2(-direction.x, -direction.z)
		player.camera.rotation = Vector3(-0.15, 0, 0)
		Input.action_press("move_forward")
		await physics_frame
	return require(false, "Walk blocked at %s towards %s" % [rv.to_local(player.global_position), local])
func outside() -> bool:
	for point in [Vector3(0, 0.5, -3.2), Vector3(0, 0.5, 4.7), Vector3(0, 0, 10.6)]:
		if not await walk(point): return false
	return true
func inside() -> bool:
	for point in [Vector3(0, 0.5, 5.2), Vector3(0, 0.5, 3.6)]:
		if not await walk(point): return false
	return true
func run() -> void:
	root.title = "ApocalypseRV - Production Trip Replay"
	root.size = Vector2i(1152, 768)
	world = load("res://world/test_world.tscn").instantiate()
	world.get_node("WorldGenerator").world_seed = 42
	root.add_child(world)
	current_scene = world
	var overlay := CanvasLayer.new()
	overlay.layer = 50
	root.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(24, 110)
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("ffdc86"))
	overlay.add_child(caption)
	phase("Waiting for production terrain and navigation")
	if not require(await world.wait_for_play(60000), "World did not become ready"): return
	rv = world.get_node("NewRv/Chassis")
	player = world.get_node("Player")
	var clock: WorldClock = world.get_node("WorldClock")
	clock.weather_running = false
	clock.weather.set_weather(Vector3.ZERO, true)
	clock.set_time(1, 22 if "--night" in OS.get_cmdline_user_args() else 8)
	clock.set_process(false)
	# Controlled service scenario: no combat interference, original production RV.
	for actor in get_nodes_in_group(Groups.MONSTER_DAMAGEABLE):
		if actor is CharacterBody3D and actor != player: actor.queue_free()
	var seat: Equipment = rv.get_node("DriverSeat")
	seat.interact_hold(player)
	rv.allow_test_controls = true
	rv.set_engine_running(true)
	rv.headlights_requested = true
	rv.set_handbrake(false)
	phase("Depart, turn gently, brake and park using production wheels")
	rv.control_override = {"throttle": 0.35, "steering": 0.1}
	await ticks(240)
	rv.control_override = {"brake": 1.0}
	await ticks(180)
	if not require(rv.road_speed() < 0.2, "Vehicle did not stop"): return
	rv.set_handbrake(true)
	rv.control_override.clear()
	seat.exit_seat()
	if not require(player.seated_in == null, "Aisle exit blocked"): return
	rv.set_engine_running(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	phase("Walk down aisle; open rear doors and deploy two-fold ramp")
	if not await walk(Vector3(0, 0.5, -3.2)): return
	if not await walk(Vector3(0, 0.5, 4.4)): return
	var door := rv.get_node("RearDoor")
	door.toggle_leaf(0)
	door.toggle_leaf(1)
	await ticks(120)
	var reason: String = rv.rear_ramp.interact(player)
	await ticks(210)
	if not require(rv.rear_ramp.deployed, "Ramp deployment: " + reason + rv.rear_ramp.blocked_message): return
	if not await walk(Vector3(0, 0, 10.6)): return
	# Reproducible test supplies are spawned only once, outside the parked RV.
	var spare: Prop = load("res://props/engine_upgraded.tscn").instantiate()
	WorldEntities.get_container(world).add_child(spare)
	spare.global_position = player.global_position + Vector3.UP * 0.5
	await ticks(30)
	spare.interact(player)
	var spare_id: String = player.inventory.active_item().get("state", {}).get("engine", {}).get("id", "")
	if not require(not spare_id.is_empty(), "Cannot pick up spare engine"): return
	phase("Carry large engine up ramp and store it in the item box")
	if not await inside(): return
	if not require(rv.store_player_item(player, player.inventory.active_slot), "Cannot store engine"): return
	# The existing supplies are used for the fault/recovery portion.
	if not require(rv.take_stored_item(player, 0), "Cannot retrieve repair kit"): return
	phase("Recycle a deterministic scrap fixture and queue gasoline")
	if not await walk(Vector3(-0.25, 0.5, -2.2)): return
	var loot: Prop = load("res://props/oil_barrel.tscn").instantiate()
	loot.scrap_yields = {ItemNames.METAL_PARTS: Vector2(4, 4), ItemNames.UNREFINED_FUEL: Vector2(10, 10)}
	WorldEntities.get_container(world).add_child(loot)
	loot.global_position = rv.get_node("Scrapper").global_position + Vector3.UP
	# Fixture feeds the real hopper, avoiding random loot quantity in a rehearsal.
	rv.get_node("Scrapper").recycle_prop(loot)
	await ticks(240)
	if not await walk(Vector3(0, 0.5, 1.0)): return
	var station: CraftingStation = rv.get_node("CraftingStation")
	if not require(station.request_craft("gasoline"), "Gasoline queue: " + station.last_error): return
	rv.interior_requested.work = true
	if not await walk(Vector3(0, 0.5, 2.5)): return
	await ticks(240)
	var produced: Prop
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Prop and actor.item_name == ItemNames.GAS_CAN and actor.global_position.distance_to(station.global_position) < 3.0: produced = actor
	if not require(produced != null, "Gasoline did not leave workstation: " + station.last_error + " jobs=" + str(station.jobs.size())): return
	produced.interact(player)
	phase("Inject engine fault; verify service access and repair with held kit")
	rv.take_damage(10000)
	if not require(not rv.set_engine_running(true) and rv.drive_blocked(), "Failed engine/ramp interlock"): return
	if not await walk(Vector3(0, 0.5, 4.8)): return
	if not await walk(Vector3(0, 0, 10.6)): return
	if not await walk(Vector3(-3.1, 0, 10.6)): return
	if not await walk(Vector3(-3.1, 0, -8.0)): return
	if not await walk(Vector3(0, 0, -8.0)): return
	rv.interior_requested.service = true
	var hatch := rv.engine_bay.get_node("Hatch")
	var hatch_reason: String = hatch.interact(player)
	await ticks(90)
	if not require(rv.engine_bay.hatch_open, "Hatch service: " + hatch_reason): return
	for i in range(player.inventory.items.size()):
		if player.inventory.items[i].scene_path == "res://props/engine_repair_kit.tscn": player.inventory.active_slot = i
	player.refresh_inventory()
	var repair := RepairOperation.new()
	for i in range(190):
		repair.step(player, rv.engine_bay, true, 1.0 / 60)
		await physics_frame
	if not require(rv.get_engine().health == 150, "Repair kit did not restore faulted engine"): return
	phase("Retrieve stored replacement; exchange engine through open hatch")
	for point in [Vector3(-3.1, 0, -8), Vector3(-3.1, 0, 10.6), Vector3(0, 0, 10.6)]:
		if not await walk(point): return
	if not await inside(): return
	var stored_index := -1
	for i in range(rv.stored_items.size()):
		if rv.stored_items[i].get("state", {}).get("engine", {}).get("id", "") == spare_id: stored_index = i
	if not require(stored_index >= 0 and rv.take_stored_item(player, stored_index), "Replacement engine identity lost"): return
	for point in [Vector3(0, 0.5, 4.8), Vector3(0, 0, 10.6), Vector3(-3.1, 0, 10.6), Vector3(-3.1, 0, -8), Vector3(0, 0, -8)]:
		if not await walk(point): return
	rv.exchange_engine(player)
	if not require(rv.get_engine().id == spare_id, "Engine exchange failed"): return
	hatch.interact(player)
	await ticks(90)
	for point in [Vector3(-3.1, 0, -8), Vector3(-3.1, 0, 10.6), Vector3(0, 0, 10.6)]:
		if not await walk(point): return
	if not await inside(): return
	rv.store_player_item(player, player.inventory.active_slot)
	phase("Stow ramp, close rear doors and save stable production world")
	if not await walk(Vector3(0, 0.5, 4.3)): return
	rv.rear_ramp.interact(player)
	await ticks(210)
	if not require(not rv.drive_blocked(), "Ramp failed to stow"): return
	door.toggle_leaf(0)
	door.toggle_leaf(1)
	await ticks(120)
	if not await walk(Vector3(0, 0.5, 1.0)): return
	var checkpoint := root.get_node("Checkpoint")
	var save_path := "user://driving_trip_validation.save"
	if not require(checkpoint.save_world(world, save_path), "Save rejected: " + checkpoint.error_message()): return
	if not require(await checkpoint.load_world(world, save_path), "Reload rejected: " + checkpoint.error_message()): return
	world = current_scene
	player = world.get_node("Player")
	for vehicle in get_nodes_in_group(Groups.CHASSIS):
		if world.is_ancestor_of(vehicle): rv = vehicle
	if not require(rv.get_engine().id == spare_id and rv.interior_requested.work and rv.interior_requested.service, "Reload changed engine or switches"): return
	for device in rv.get_equipment():
		if device.has_method("exit_seat"): seat = device
	seat.interact_hold(player)
	rv.set_engine_running(true)
	rv.set_handbrake(false)
	rv.allow_test_controls = true
	rv.control_override = {"throttle": 0.35}
	var before := rv.global_position
	await ticks(180)
	if not require(rv.global_position.distance_to(before) > 1.0, "Reloaded vehicle cannot depart"): return
	rv.control_override = {"brake": 1.0}
	await ticks(180)
	rv.set_handbrake(true)
	phase("PASS: production departure, walking/hauling, crafting, fault/repair/exchange, stow, checkpoint and second departure")
	if not "--stay" in OS.get_cmdline_user_args():
		var generator := world.get_node("WorldGenerator")
		generator.set_process(false)
		while generator.building: await process_frame
		quit()

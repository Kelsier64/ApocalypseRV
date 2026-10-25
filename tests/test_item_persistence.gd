extends SceneTree
## One Item representation across world, fixed supports, inventory and POI.
class StreamingFixture extends "res://world/world_generator.gd":
	func _ready() -> void:
		profile = WorldProfile.new()
		set_process(false)
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok:
		failures.append(text)
		push_error("FAIL: " + text)

func _check_printed_body() -> void:
	var scene: PackedScene = load("res://props/printed_player.tscn")
	var original := scene.instantiate() as PrintedPlayerBody
	check(original.survival.capture() == {"hunger": 100.0, "starvation_elapsed": 0.0}, "New printed body starts fully fed")
	original.crouching = true
	original.stamina = 37.0
	original.survival.restore({"hunger": 0.0, "starvation_elapsed": 4.25})
	original.body_state.sever(&"right_arm")
	var saved := original.capture_item_state()
	check(ItemState.valid(PrintedPlayerBody.SCENE, saved), "Current printed-body Item has a complete saved posture and body")
	var incomplete := saved.duplicate(true)
	incomplete.printed_body.erase("crouching")
	check(not ItemState.valid(PrintedPlayerBody.SCENE, incomplete), "Printed-body state requires its saved posture")
	incomplete = saved.duplicate(true)
	incomplete.printed_body.erase("survival")
	check(not ItemState.valid(PrintedPlayerBody.SCENE, incomplete), "Printed-body state requires hunger and starvation remainder")
	incomplete = saved.duplicate(true)
	incomplete.printed_body.version = 1
	check(not ItemState.valid(PrintedPlayerBody.SCENE, incomplete), "Previous printed-body version is rejected without migration")
	var restored := scene.instantiate() as PrintedPlayerBody
	restored.restore_item_state(saved)
	check(restored.capture_item_state().printed_body == saved.printed_body, "Printed-body restoration preserves posture, stamina, hunger and missing limbs")
	original.free()
	restored.free()

func _run() -> void:
	_check_printed_body()
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	await _exercise_printed_body_survival(world)
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	world.add_child(wall)
	var container := WorldEntities.get_container(world)
	var shelf := load("res://props/scrap.tscn").instantiate() as Item
	container.add_child(shelf)
	shelf.condition = 43.0
	shelf.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), wall)
	var scrapper := load("res://equipment/scrapper.tscn").instantiate() as Item
	container.add_child(scrapper)
	scrapper.condition = 61.0
	scrapper.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), shelf)
	scrapper.enabled = false
	var shelf_id: String = shelf.persistent_id
	var scrapper_id: String = scrapper.persistent_id
	var records := [WorldActorSnapshot.capture(scrapper), WorldActorSnapshot.capture(shelf)]
	check(WorldActorSnapshot.validation_error(records[0], "scrapper").is_empty(), "Former device uses canonical Item world schema")
	check(WorldActorSnapshot.validation_error(records[1], "shelf").is_empty(), "Fixed ordinary Item uses same world schema")
	check(WorldActorSnapshot.graph_error(records).is_empty(), "Valid dependency chain accepted")
	check(records[1].support == {"kind": "static", "path": "Wall"}, "Static support is relative to world domain")
	for missing_field in ["id", "condition"]:
		var invalid: Dictionary = records[0].state.duplicate(true)
		invalid.erase(missing_field)
		check(not ItemState.valid(records[0].scene, invalid), "Canonical Item state rejects missing " + missing_field)
		invalid = records[0].state.duplicate(true)
		invalid[missing_field] = "" if missing_field == "id" else NAN
		check(not ItemState.valid(records[0].scene, invalid), "Canonical Item state rejects invalid " + missing_field)
	for invalid_state in [{}, {"condition": 100.0}, {"id": ""}, {"id": 7}]:
		check(not ItemState.unique_ids({"items": [{"state": invalid_state}]}, {}), "Ownership rejects absent or invalid identity")
	for missing_battery in [{"id": "battery", "condition": 100.0}, {"id": "battery", "condition": 100.0, "battery": {}}]:
		check(not ItemState.valid("res://props/battery.tscn", missing_battery), "Battery Item requires its complete charge and durability payload")
	var invalid_battery := BatteryState.new().snapshot()
	invalid_battery.capacity = 1001.0
	check(not VehicleSnapshot.valid_battery(invalid_battery), "Persisted battery values cannot be silently clamped during restoration")
	check(not ItemState.unique_ids({"wheels": [42]}, {}), "Malformed wheel ownership is rejected without accessing invalid records")
	check(ItemState.unique_ids({"actors": records}, {}), "Each world Item has one owner")
	var duplicate := {"actors": records, "inventory": [{"state": records[0].state}]}
	check(not ItemState.unique_ids(duplicate, {}), "Cross-domain duplicated equipment ID rejected")
	var cycle: Array = records.duplicate(true)
	cycle[1].support = {"kind": "item", "id": scrapper_id}
	check(not WorldActorSnapshot.graph_error(cycle).is_empty(), "Support cycle rejected before restore")
	scrapper.begin_world_transfer()
	shelf.begin_world_transfer()
	scrapper.free()
	shelf.free()
	var restored: Array = []
	for saved in records: restored.append(WorldActorSnapshot.restore(saved, container))
	WorldActorSnapshot.restore_supports(records, restored, world)
	scrapper = restored[0]
	shelf = restored[1]
	check(scrapper.is_fixed and shelf.is_fixed and scrapper.mount_support == shelf and shelf.mount_support == wall, "Out-of-order records restore full support chain")
	check(scrapper.persistent_id == scrapper_id and shelf.persistent_id == shelf_id and scrapper.condition == 61.0 and shelf.condition == 43.0, "Support restore preserves ID and durability")
	check(not scrapper.enabled and not scrapper.can_operate(), "Fixed indoor scrapper retains settings without RV service")
	wall.queue_free()
	await process_frame
	await process_frame
	check(not scrapper.is_fixed and not shelf.is_fixed and not scrapper.freeze and not shelf.freeze, "Removed wall releases the entire support chain")
	check(scrapper.persistent_id == scrapper_id and scrapper.condition == 61.0, "Dropped former device retains canonical state")
	var missing: Array = records.duplicate(true)
	missing[1].support.path = "MissingWall"
	for item in restored: item.begin_world_transfer(); item.free()
	restored.clear()
	for saved in missing: restored.append(WorldActorSnapshot.restore(saved, container))
	WorldActorSnapshot.restore_supports(missing, restored, world)
	check(not restored[0].is_fixed and not restored[1].is_fixed, "Missing static anchor restores items loose rather than deleting them")
	wall = StaticBody3D.new()
	wall.name = "Wall"
	world.add_child(wall)
	shelf = restored[1]
	scrapper = restored[0]
	shelf.confirm_placement(records[1].transform, wall)
	scrapper.confirm_placement(records[0].transform, shelf)
	var streamer := StreamingFixture.new()
	world.add_child(streamer)
	streamer._store_items([shelf, scrapper])
	check(streamer.dormant_items.size() == 1 and streamer.dormant_items[0].size() == 2 and container.get_child_count() == 0, "Outdoor retirement snapshots complete chain before freeing actors")
	check(ItemState.unique_ids({"dormant_items": streamer.dormant_items}, {}), "Dormant outdoor ledger has unique item ownership")
	streamer.restore_dormant_items(0)
	check(streamer.dormant_items.is_empty() and container.get_child_count() == 2, "Revisiting terrain restores dormant Items exactly once")
	var restored_scrapper: Item
	var restored_shelf: Item
	for item in container.get_children():
		if item.persistent_id == scrapper_id: restored_scrapper = item
		if item.persistent_id == shelf_id: restored_shelf = item
	check(restored_scrapper != null and restored_shelf != null and restored_scrapper.mount_support == restored_shelf and restored_shelf.mount_support == wall, "Outdoor revisit retains fixed Item support chain")
	await _exercise_queue_replace(world)
	world.free()
	if failures.is_empty(): print("PASS: unified Item state, ownership, support graph and wall-loss persistence")
	quit(0 if failures.is_empty() else 1)


func _exercise_printed_body_survival(world: Node3D) -> void:
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(200, 2, 0)
	world.add_child(player)
	player.set_physics_process(false)
	player.survival.restore({"hunger": 0.0, "starvation_elapsed": 4.25})
	check(player.add_item("Scrap", false, "res://props/scrap.tscn"), "Body swap fixture carries one inventory Item")
	var inventory: Array = player.inventory.items.duplicate(true)
	var controller := player.get_instance_id()
	var body := load(PrintedPlayerBody.SCENE).instantiate() as PrintedPlayerBody
	body.position = Vector3(204, 1.75, 0)
	body.freeze = true
	WorldEntities.get_container(world).add_child(body)
	await physics_frame
	await process_frame
	check(body.transfer_control(player), "Production controller transfers into a new printed body")
	check(player.survival.capture() == {"hunger": 100.0, "starvation_elapsed": 0.0}, "New body supplies full hunger to active controller")
	check(body.survival.capture() == {"hunger": 0.0, "starvation_elapsed": 4.25}, "Abandoned body retains its starvation remainder")
	player.set_physics_process(false)
	var dormant: Dictionary = body.survival.capture()
	await physics_frame
	await process_frame
	check(body.survival.capture() == dormant, "Inactive printed body does not advance starvation")
	player.survival.restore({"hunger": 22.5, "starvation_elapsed": 0.0})
	check(body.transfer_control(player), "Production controller returns to its starving physical body")
	player.set_physics_process(false)
	check(player.survival.capture() == dormant and body.survival.capture() == {"hunger": 22.5, "starvation_elapsed": 0.0}, "Roundtrip swaps both physical hunger states exactly")
	check(player.get_instance_id() == controller and player.inventory.items == inventory, "Body transfers retain controller and inventory ownership")
	var pose: Transform3D = player.global_transform
	var body_pose := body.global_transform
	body.survival.hunger = NAN
	check(not body.transfer_control(player), "Malformed target survival rejects body transfer")
	check(player.global_transform == pose and body.global_transform == body_pose and player.inventory.items == inventory and player.survival.capture() == dormant, "Rejected target survival leaves both poses, inventory and active hunger intact")
	body.survival.restore({"hunger": 22.5, "starvation_elapsed": 0.0})
	player.survival.hunger = INF
	check(not body.transfer_control(player) and body.survival.hunger == 22.5 and body.global_transform == body_pose, "Malformed active survival cannot overwrite the dormant body")
	player.free()
	body.free()


func _exercise_queue_replace(world: Node3D) -> void:
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(50, 0, 0)
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await process_frame
	await process_frame
	_exercise_cheat_job_refunds(world, rv)
	_exercise_food_persistence(world, rv)
	var recycler: Item = rv.get_node("Scrapper")
	var input := load("res://props/scrap.tscn").instantiate() as Item
	WorldEntities.get_container(world).add_child(input)
	input.global_position = recycler.global_position + Vector3.UP
	var input_id: String = input.persistent_id
	recycler.recycle_prop(input)
	check(recycler.props_being_crushed.size() == 1, "Recycler fixture accepts one world Item")
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved) and VehicleSnapshot.apply(rv, saved), "Standalone vehicle apply restores processing queue")
	var matching := 0
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Item and actor.persistent_id == input_id:
			matching += 1
			check(is_instance_valid(actor.processing_owner), "Restored queue input has a live owner")
	check(matching == 1, "Standalone apply replaces old queue actors without duplicate IDs")
	await _exercise_socket_durability(world, rv)
	_exercise_destroyed_support(world, rv)

func _exercise_food_persistence(world: Node3D, rv: Chassis) -> void:
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(300, 2, 0)
	world.add_child(player)
	player.set_physics_process(false)
	var foods: Array[Dictionary] = []
	var container := WorldEntities.get_container(world)
	for scene_path in ["res://props/food/canned_food.tscn", "res://props/food/energy_bar.tscn", "res://props/food/beef_jerky.tscn"]:
		var food := load(scene_path).instantiate() as Item
		food.position = Vector3(300, 1, 3)
		food.freeze = true
		container.add_child(food)
		var ground := WorldActorSnapshot.capture(food)
		check(not food.is_large and WorldActorSnapshot.validation_error(ground, "food").is_empty(), "Food is a small Item with valid ground persistence: " + scene_path)
		food.begin_world_transfer()
		food.free()
		food = WorldActorSnapshot.restore(ground, container) as Item
		check(food.capture_item_state() == ground.state, "Ground food restores its canonical identity and state: " + scene_path)
		check(player.add_prop_item(food, scene_path), "Restored ground food enters inventory: " + scene_path)
		food.free()
		var record: Dictionary = player.inventory.active_item().duplicate(true)
		foods.append(record)
		check(VehicleSnapshot.valid_item(record) and record.state == ground.state, "Inventory food preserves ground identity: " + scene_path)
		check(rv.store_player_item(player, 0) and player.inventory.items.is_empty(), "Food transfers to RV storage with one owner: " + scene_path)
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved) and VehicleSnapshot.apply(rv, saved), "Vehicle snapshot restores stored food through normal Item records")
	for food in foods:
		var matching: Array = rv.stored_items.filter(func(record): return record.state.id == food.state.id)
		check(matching.size() == 1 and matching[0] == food, "Restored storage contains one unchanged food record: " + food.scene_path)
		var index := rv.stored_items.find(food)
		check(index >= 0 and rv.take_stored_item(player, index), "Restored food returns from RV storage: " + food.scene_path)
	check(ItemState.unique_ids({"player": {"items": player.inventory.items}, "vehicle": {"items": rv.stored_items}}, {}), "Retrieved food identities have one inventory/storage owner")
	check(player.inventory.items == foods, "Food inventory roundtrip preserves all three records")
	player.free()

func _exercise_cheat_job_refunds(world: Node3D, rv: Chassis) -> void:
	var station := rv.get_node("CraftingStation") as CraftingStation
	var original_materials := rv.get_all_items()
	var original_fuel := rv.current_fuel
	var original_power := rv.current_power
	var costs: Dictionary = RecipeCatalog.find("gasoline").costs
	rv.inventory = {ItemNames.METAL_PARTS: 20, ItemNames.UNREFINED_FUEL: 30}
	rv.current_fuel = 37.0
	rv.current_power = 64.0
	var available := rv.get_all_items()
	check(station.request_craft("gasoline"), "Paid job reserves materials before enabling cheats")
	rv.unlimited_materials = true
	station.cancel_jobs()
	check(rv.get_all_items() == available, "Enabling cheats before cancellation returns the paid reservation")
	check(station.request_craft("gasoline"), "Free job queues with unlimited materials")
	check(station.jobs.size() == 1 and station.jobs[0].costs.is_empty(), "Free job records an empty paid reservation")
	rv.unlimited_materials = false
	station.cancel_jobs()
	check(rv.get_all_items() == available, "Disabling cheats before cancellation creates no materials")
	check(station.request_craft("gasoline"), "Paid job queues for mixed reservation snapshot")
	rv.unlimited_materials = true
	check(station.request_craft("gasoline"), "Free job queues beside a paid reservation")
	rv.unlimited_fuel = true
	rv.unlimited_power = true
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved), "Mixed paid and empty free reservations form a valid snapshot")
	# A gameplay load creates a new chassis; standalone apply on the original
	# actor is deliberately not the session-reset boundary.
	var domain := Node3D.new()
	domain.set_meta("entity_domain", true)
	world.add_child(domain)
	var restored: Chassis = load("res://rv/chassis.tscn").instantiate()
	domain.add_child(restored)
	restored.freeze = true
	restored.set_physics_process(false)
	check(VehicleSnapshot.apply(restored, saved), "Fresh chassis restores mixed material reservations")
	check(not restored.unlimited_materials and not restored.unlimited_fuel and not restored.unlimited_power, "Fresh snapshot actor starts with all session cheats disabled")
	check(is_finite(restored.current_fuel) and is_finite(restored.current_power) and restored.current_fuel == saved.fuel and restored.current_power == 64.0 and restored.get_all_items() == saved.materials, "Snapshot preserves finite fuel, power and material stocks while cheats are active")
	var restored_station: CraftingStation
	for device in restored.get_equipment():
		if device is CraftingStation: restored_station = device
	check(restored_station != null and restored_station.jobs.size() == 2, "Fresh actor retains both queued jobs")
	if restored_station != null and restored_station.jobs.size() == 2:
		check(restored_station.jobs[0].costs == costs and restored_station.jobs[1].costs.is_empty(), "Saved jobs retain actual paid costs independently of session cheats")
		restored_station.cancel_jobs()
		check(restored.get_all_items() == available, "Restored mixed queue refunds only the paid job")
		restored_station.cancel_jobs()
		check(restored.get_all_items() == available, "Repeated restored queue cancellation cannot duplicate refunds")
	domain.free()
	station.cancel_jobs()
	rv.unlimited_materials = false
	rv.unlimited_fuel = false
	rv.unlimited_power = false
	rv.inventory = original_materials
	rv.current_fuel = original_fuel
	rv.current_power = original_power

func _exercise_socket_durability(world: Node3D, rv: Chassis) -> void:
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(100, 2, 0)
	player.set_physics_process(false)
	var socket := rv.get_battery_socket()
	socket.installed_battery.condition = 82.0
	socket.installed_battery.charge = 61.0
	var old_id: String = socket.installed_battery.id
	var battery := load("res://props/battery_large.tscn").instantiate() as Item
	var battery_id: String = battery.persistent_id
	battery.condition = 37.0
	world.add_child(battery)
	battery.battery.charge = 23.0
	battery.set_meta("recycle_result", {ItemNames.METAL_PARTS: 3})
	battery.enabled = false
	check(battery.persistent_id == battery_id and battery.battery.id == battery_id, "Fresh battery initialization preserves Item identity")
	check(player.add_prop_item(battery, battery.scene_file_path), "Damaged battery enters inventory")
	battery.free()
	check(rv.exchange_battery(player, socket), "Damaged battery inserts atomically")
	check(socket.installed_battery.id == battery_id and socket.installed_battery.condition == 37.0 and socket.installed_battery.charge == 23.0, "Battery insertion preserves durability independently of charge")
	check(player.inventory.active_item().state.id == old_id and player.inventory.active_item().state.condition == 82.0 and player.inventory.active_item().state.battery.condition == 82.0, "Battery swap returns canonical original durability")
	check(rv.remove_battery_to_player(player, socket), "Damaged battery removes to inventory")
	var removed: Dictionary = player.inventory.items[1]
	check(removed.state.id == battery_id and removed.state.condition == 37.0 and removed.state.battery.charge == 23.0 and ItemState.valid(removed.scene_path, removed.state), "Battery removal keeps valid ID, durability and charge")
	check(removed.scene_path == "res://props/battery_large.tscn", "Battery slot removal preserves the original battery scene")
	check(removed.state.recycle_result == {ItemNames.METAL_PARTS: 3} and not removed.state.enabled, "Battery slot preserves decided recycling output and enabled state")
	player.inventory.items.clear()
	player.refresh_inventory()
	check(player.add_item(removed.name, removed.is_large, removed.scene_path, removed.state) and rv.exchange_battery(player, socket), "Removed battery can be reinserted")
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved) and VehicleSnapshot.apply(rv, saved), "Battery durability survives vehicle snapshot apply")
	socket = rv.get_battery_socket()
	check(socket.installed_battery.condition == 37.0 and socket.installed_battery.charge == 23.0, "Restored installed battery retains durability separately from energy")
	socket.detach_from_support()
	var battery_matches := 0
	for item in WorldEntities.get_container(world).get_children():
		if item is Item and item.persistent_id == battery_id:
			battery_matches += 1
			check(item.condition == 37.0 and item.battery.charge == 23.0 and item.scene_file_path == "res://props/battery_large.tscn", "Socket support loss drops the original durable battery without resetting it")
			check(item.get_meta("recycle_result") == {ItemNames.METAL_PARTS: 3} and not item.enabled, "Socket support loss preserves the existing recycling decision")
	check(battery_matches == 1, "Socket loss ejects one battery owner")
	player.inventory.items.clear()
	player.refresh_inventory()
	rv.remove_wheel(0)
	check(player.add_item(ItemNames.WHEEL, false, "res://props/wheel.tscn", {"id": "durable-wheel", "condition": 46.0, "recycle_result": {ItemNames.METAL_PARTS: 2}, "enabled": false}), "Damaged wheel enters inventory")
	check(rv.install_wheel_from_player(player, 0) and rv.wheel_ids[0] == "durable-wheel" and rv.wheel_health[0] == 46.0, "Wheel insertion preserves identity and Item durability")
	var wheel_saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(wheel_saved) and VehicleSnapshot.apply(rv, wheel_saved), "Installed wheel Item extras survive the vehicle snapshot")
	check(rv.remove_wheel_to_world(0), "Damaged wheel removes into world")
	var wheel_matches := 0
	for item in WorldEntities.get_container(world).get_children():
		if item is Item and item.persistent_id == "durable-wheel":
			wheel_matches += 1
			check(item.condition == 46.0, "Wheel removal restores the same Item durability")
			check(item.get_meta("recycle_result") == {ItemNames.METAL_PARTS: 2} and not item.enabled, "Wheel removal preserves decided recycling output and enabled state")
	check(wheel_matches == 1, "Wheel removal produces one durable owner")
	player.inventory.items.clear()
	player.refresh_inventory()
	rv.handbrake = true
	rv.engine_bay.get_node("Hatch").set_open(true)
	var engine_record := EngineState.new({"id": "durable-extra-engine", "model": "standard", "health": 190.0}).item()
	engine_record.state["recycle_result"] = {ItemNames.METAL_PARTS: 7}
	engine_record.state["scrap_yields"] = {ItemNames.METAL_PARTS: Vector2(7, 7)}
	engine_record.state["enabled"] = false
	check(player.add_item(engine_record.name, true, engine_record.scene_path, engine_record.state), "Engine with decided recycling output enters inventory")
	rv.exchange_engine(player)
	check(rv.get_engine().id == "durable-extra-engine", "Engine installs into dedicated socket")
	player.inventory.items.clear()
	player.refresh_inventory()
	var engine_saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(engine_saved) and VehicleSnapshot.apply(rv, engine_saved), "Installed engine Item extras survive the vehicle snapshot")
	rv.remove_engine(player)
	var removed_engine: Dictionary = player.inventory.active_item()
	check(not removed_engine.is_empty() and removed_engine.state.id == "durable-extra-engine" and removed_engine.state.recycle_result == {ItemNames.METAL_PARTS: 7} and removed_engine.state.scrap_yields == engine_record.state.scrap_yields and not removed_engine.state.enabled, "Engine removal preserves recycling decision, yields, and enabled state")

func _exercise_destroyed_support(world: Node3D, rv: Chassis) -> void:
	var socket: BatterySocket
	for actor in WorldEntities.get_container(world).get_children():
		if actor is BatterySocket: socket = actor
	check(socket != null, "Released socket remains available for support recovery fixture")
	if socket == null: return
	socket.confirm_placement(rv.global_transform, rv, rv)
	socket.installed_battery = BatteryState.new()
	rv.add_item(ItemNames.METAL_PARTS, 10)
	rv.add_item(ItemNames.UNREFINED_FUEL, 10)
	var station: CraftingStation
	for item in rv.get_equipment():
		if item is CraftingStation: station = item
	check(station != null and station.request_craft("gasoline"), "Workstation reserves a job before support restore")
	if station == null or station.jobs.is_empty(): return
	var costs: Dictionary = station.jobs[0].costs.duplicate(true)
	var station_id: String = station.persistent_id
	var station_condition: float = station.condition
	var saved := VehicleSnapshot.capture(rv)
	for structure in saved.structures:
		if structure.slot == "front": structure.health = 0.0
	for item in saved.mounted_items:
		if item.state.id == station_id: item.support = {"kind": "structure", "rv": rv.persistent_id, "slot": "front"}
	check(VehicleSnapshot.validate(saved), "Destroyed support references are structurally valid fallback records")
	check(VehicleSnapshot.apply(rv, saved), "Destroyed mounted support falls back to loose Item")
	var loose_station: CraftingStation
	for item in WorldEntities.get_container(world).get_children():
		if item is CraftingStation and item.persistent_id == station_id: loose_station = item
	check(loose_station != null and not loose_station.is_fixed and not loose_station.freeze and loose_station.condition == station_condition and loose_station.jobs.is_empty(), "Restored workstation survives missing wall with ID and durability intact")
	for material in costs:
		check(rv.get_item_count(material) == saved.materials.get(material, 0) + costs[material], "Destroyed support refunds reserved materials exactly once: " + material)
	if loose_station != null: loose_station.detach_from_support()
	for material in costs:
		check(rv.get_item_count(material) == saved.materials.get(material, 0) + costs[material], "Repeated support release cannot refund again: " + material)

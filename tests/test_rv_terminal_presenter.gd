extends SceneTree

const PRESENTER = preload("res://equipment/rv_terminal_presenter.gd")
var failures: Array[String] = []
var registry_signals := 0

func _init() -> void:
	_run.call_deferred()

func expect(condition: bool, detail: String) -> void:
	if not condition: failures.append(detail)

func _run() -> void:
	_check_names_and_messages()
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await physics_frame
	_check_warnings(rv)
	_check_crafting(rv)
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: RV terminal presenter and read-only craft eligibility")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_names_and_messages() -> void:
	expect(PRESENTER.slot_name("right_1") == "Right middle", "Stable side slot translated")
	expect(PRESENTER.slot_name("roof_2") == "Rear roof", "Stable roof slot translated")
	expect(PRESENTER.type_name("rv_ceiling_hatch") == "Roof with left hatch", "Roof type is descriptive English")
	for type_id in RVStructureSlots.TYPES:
		var definition := RVStructureSlots.definition_for(type_id)
		var part: RVStructurePanel = load(definition.scene_path).instantiate()
		expect(PRESENTER.display_name(part) == PRESENTER.type_name(type_id), "Structure display uses its authoritative type")
		part.free()
	for recipe in RecipeCatalog.all():
		expect(not PRESENTER._has_cjk(PRESENTER.recipe_name(recipe)), "Every catalog recipe has an English name")
	expect(PRESENTER.recipe_name(RecipeCatalog.find("engine_repair_kit")) == "Engine Repair Kit", "Chinese recipe translated by ID")
	for scene_path in ["res://props/engine_standard.tscn", "res://equipment/fuel_port.tscn", "res://equipment/cabin_light_strip.tscn"]:
		var item: Item = load(scene_path).instantiate()
		expect(not PRESENTER._has_cjk(PRESENTER.display_name(item)), "Installed Item names remain English before ready")
		item.free()
	var unknown := Item.new()
	unknown.name = "AuxiliaryPump"
	unknown.item_name = "新設備"
	expect(PRESENTER.display_name(unknown) == "Auxiliary Pump", "Unknown names use a stable English node identifier")
	unknown.free()
	var examples := {
		"請先熄火": "Stop the engine first",
		"未安裝引擎，請到車頭引擎艙裝入": "No engine installed: use the front engine bay",
		"已裝入 強化引擎": "Installed Upgraded Engine",
		"請先移走附掛設備：車內燈條, SensorRig": "Move attached equipment first: Cabin light strip, SensorRig",
		"施工空間被 StorageCrate_02 擋住": "Construction space blocked by StorageCrate_02",
		"請先移走附掛設備：新設備, SensorRig": "Move attached equipment first: Unidentified equipment, SensorRig",
		"門被 道具箱 擋住，請移開或退後": "Door blocked by Item storage box; move it or step back",
		"附掛設備：車內登頂梯、Crafting Station": "Attached equipment: Interior roof ladder, Crafting Station",
		"維修 完整屋頂｜2.5 秒｜施工期間不能保存": "Repair Solid roof | 2.5s | Saving unavailable during construction",
		"RV 充電中：最高 +1.8 電量／秒": "RV charging: up to +1.8 charge/s",
		"已達保留油量；引擎仍消耗運轉燃油": "Fuel reserve reached; the running engine still consumes fuel",
		"工作燈｜已開啟，等待供電／設備就緒": "Work lights | On; waiting for power or equipment",
		"引擎維修 50%｜完成消耗 1 維修包、回復 150 耐久": "Engine repair 50% | Completion uses 1 repair kit and restores 150 durability",
		"左前爆胎、右後缺輪｜請停穩熄火，維修或換胎": "Front left tire flat, Rear right wheel missing | Stop the vehicle and engine; repair or replace tires",
	}
	for source: String in examples:
		expect(PRESENTER.message(source) == examples[source], "Translated detail preserves dynamic data: " + source)
	expect(PRESENTER.message("Unknown output at 42%") == "Unknown output at 42%", "Existing English remains unchanged")
	expect(PRESENTER.message("").is_empty(), "Empty service reason remains empty")
	expect(PRESENTER.message("未定義的新服務狀態").contains("vehicle and equipment"), "Unknown Chinese service messages have an actionable English fallback")

func _check_warnings(rv: Chassis) -> void:
	rv.current_power = rv.max_power
	rv.current_fuel = rv.max_fuel
	rv.handbrake = true
	var raw := VehicleStatus.read(rv)
	var rows := PRESENTER.warnings(rv)
	expect(rows.size() == raw.size(), "Warnings retain all VehicleStatus domains")
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		expect(not PRESENTER._has_cjk(row.label + row.message), "Warning labels and details are English")
		expect(row.id == raw[index].id, "Warning preserves source identity")
		expect(row.level == (1 if row.id == "brake" else raw[index].level), "Only applied brake presentation changes severity")
	rv.current_power = rv.max_power * 0.1
	rv.wheel_health[0] = 0.0
	for row in PRESENTER.warnings(rv):
		if row.id == "battery": expect(row.level == 2 and row.message == "Battery charge low", "Low battery remains a warning")
		if row.id == "tire": expect(row.level == 3 and row.message.contains("Front left tire flat"), "Flat tire retains severity and wheel position")
	rv.wheel_health[0] = 100.0
	rv.current_power = 0.0
	for row in PRESENTER.warnings(rv):
		if row.id == "battery": expect(row.level == 3 and row.message.contains("replace it or start the engine"), "Empty battery exposes recovery action")

func _check_crafting(rv: Chassis) -> void:
	var station: CraftingStation = rv.get_node("CraftingStation")
	station.confirm_placement(station.global_transform, rv)
	rv.current_power = 20.0
	rv.inventory = {ItemNames.METAL_PARTS: 20, ItemNames.UNREFINED_FUEL: 20}
	rv.equipment_changed.connect(func() -> void: registry_signals += 1)
	# A presentation refresh must not refresh either station or battery caches.
	station._connected_rv_cache = null
	for device in rv.get_equipment():
		if device is BatterySocket: device._connected_rv_cache = null
	station.last_error = "Previous status"
	var materials := rv.inventory.duplicate(true)
	var registry := rv.equipment_registry.duplicate()
	var saved_jobs := station.capture_service_state().duplicate(true)
	var battery: BatterySocket = null
	for device in rv.get_equipment():
		if device is BatterySocket and device.installed_battery: battery = device
	var charge := battery.installed_battery.charge
	for index in range(3): expect(station.craft_rejection_reason("gasoline").is_empty(), "Eligible query accepts repeated reads")
	expect(station.last_error == "Previous status" and station.capture_service_state() == saved_jobs, "Queries preserve status, jobs and visual inputs")
	expect(rv.inventory == materials and battery.installed_battery.charge == charge, "Queries cannot debit materials or battery")
	expect(rv.equipment_registry == registry and registry_signals == 0, "Queries cannot change registry or emit equipment signals")
	expect(station._connected_rv_cache == null and battery._connected_rv_cache == null, "Queries preserve unpopulated connection caches")
	_check_rejected(station, "not_a_recipe", "Workstation unavailable")
	station.enabled = false
	_check_rejected(station, "gasoline", "Workstation unavailable")
	station.enabled = true
	station._committing = true
	_check_rejected(station, "gasoline", "Workstation unavailable")
	station._committing = false
	rv.current_power = 0.1
	_check_rejected(station, "gasoline", "Insufficient battery charge")
	rv.current_power = 20.0
	rv.inventory.clear()
	_check_rejected(station, "gasoline", "Insufficient materials")
	rv.inventory = materials.duplicate(true)
	station.queue_capacity = 1
	expect(station.craft_rejection_reason("gasoline").is_empty() and station.request_craft("gasoline"), "Query and transaction accept the same eligible recipe")
	expect(rv.get_item_count(ItemNames.METAL_PARTS) == 18 and rv.current_power == 20.0, "Request reserves materials but keeps gradual power charging")
	_check_rejected(station, "gasoline", "Queue full")
	station.cancel_jobs()
	expect(station.jobs.is_empty() and rv.inventory == materials, "Cancel retains full material refunds")
	expect(station.craft_rejection_reason("gasoline").is_empty(), "Cancellation immediately restores eligibility")

func _check_rejected(station: CraftingStation, recipe_id: String, expected: String) -> void:
	var reason := station.craft_rejection_reason(recipe_id)
	expect(reason == expected, "Query explains rejection: " + expected)
	expect(not station.request_craft(recipe_id) and station.last_error == reason, "Request uses identical query rejection: " + expected)

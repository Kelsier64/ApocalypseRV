extends SceneTree
## Optional receipt/schema checks complement the native workshop journey.
const COURSE = preload("res://world/tutorial_shelter/orientation_controller.gd")
const WORKSHOP = preload("res://world/tutorial_shelter/orientation_workshop.gd")
var failures: Array[String] = []

class VehicleFixture extends Chassis:
	var fixture_engine: EngineState
	func get_engine() -> EngineState: return fixture_engine

class ControllerFixture extends Node:
	signal progress_changed
	var rv_id := "original-rv"
	var vehicle: Chassis
	func designated_rv() -> Chassis: return vehicle

class ReceiptFixture extends OrientationWorkshop:
	var powered := false
	var accepting := true
	var objects := {}
	var inventory_ids: Array[String] = []
	func _active() -> bool: return accepting
	func mounted(_key: String) -> bool: return true
	func installed(_key: String) -> bool: return powered
	func wall_ready(_slot: String) -> bool: return true
	func wheel_ready() -> bool: return true
	func battery_ready() -> bool: return true
	func engine_ready() -> bool: return true
	func by_id(identity: String) -> Item: return objects.get(identity)
	func _inventory_has(identity: String, _scene: String) -> bool: return identity in inventory_ids
	func _changed() -> void: controller.progress_changed.emit()

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func valid(data: Dictionary) -> bool:
	return WORKSHOP.validation_error(data).is_empty()

func run() -> void:
	var workshop := WORKSHOP.new()
	check(valid(workshop.capture()), "Unconfigured workshop serializes without invented evidence")
	workshop.configured = true
	for key in WORKSHOP.TARGET_KEYS:
		workshop.targets[key] = "id:" + key
	workshop.targets.wall_a = "left_0"
	workshop.targets.wall_b = "right_0"
	workshop.targets.wheel_slot = 0
	var base := workshop.capture()
	check(valid(base), "Configured initial workshop preserves designated IDs")
	var historical := base.duplicate(true)
	historical.version = 1
	for key in ["battery_exchanged", "engine_repaired", "roof_rebuilt"]: historical.flags.erase(key)
	check(valid(historical), "Historical mandatory workshop schema remains accepted")
	for step in range(2, 7):
		var forged := base.duplicate(true)
		forged.step = step
		check(valid(forged), "Advisory step does not impose completed optional receipts: " + str(step))
		var old := historical.duplicate(true)
		old.step = step
		check(not valid(old), "Historical v1 evidence consistency remains enforced: " + str(step))
	workshop.placed_ids.assign([workshop.targets.scrapper, workshop.targets.workbench])
	workshop.flags.scrapper_placed = true
	workshop.flags.workbench_placed = true
	workshop.step = 2
	check(valid(workshop.capture()), "Mount evidence advances only to recycling")
	workshop.recycled_ids.assign([workshop.targets.scrap_a, workshop.targets.scrap_b, workshop.targets.barrel])
	workshop.step = 3
	check(valid(workshop.capture()), "Three designated committed inputs permit manufacture")
	var bad := workshop.capture()
	bad.recycled_ids[1] = "unrelated-scrap"
	check(not valid(bad), "Other input ID cannot replace designated recycling evidence")
	bad = workshop.capture()
	bad.recycled_ids[1] = bad.recycled_ids[0]
	check(not valid(bad), "Duplicate processing cannot replace the second input")
	workshop.output_ids.assign(["produced-gasoline"])
	workshop.gasoline_id = "produced-gasoline"
	workshop.step = 4
	check(valid(workshop.capture()), "Output and pickup evidence permit repairs")
	bad = workshop.capture()
	bad.gasoline_id = "unrelated-can"
	check(not valid(bad), "Picked gasoline must reference a committed output")
	workshop.repaired_ids.assign(["left_0", "right_0"])
	workshop.removed_wheel_ids.assign([workshop.targets.original_wheel])
	workshop.flags.wheel_removed = true
	workshop.flags.wheel_installed = true
	workshop.step = 5
	check(valid(workshop.capture()), "Both wall repairs and native original tire removal permit refueling")
	bad = workshop.capture()
	bad.removed_wheel_ids.clear()
	bad.flags.wheel_removed = false
	check(not valid(bad), "Spare installation cannot omit original tire removal")
	workshop.flags.refueled = true
	workshop.empty_can_id = "returned-empty"
	workshop.refuel_amount = 20.0
	workshop.step = 6
	var complete := workshop.capture()
	check(valid(complete), "All five workshop steps preserve their evidence")
	for field in ["gasoline_id", "empty_can_id"]:
		bad = complete.duplicate(true)
		bad[field] = ""
		check(not valid(bad), "Fuel completion retains can identity: " + field)
	bad = complete.duplicate(true)
	bad.refuel_amount = INF
	check(not valid(bad), "Nonfinite transferred fuel is rejected")
	bad = complete.duplicate(true)
	bad.empty_can_id = bad.gasoline_id
	check(not valid(bad), "Returned empty can cannot alias the consumed full can")
	bad = complete.duplicate(true)
	bad.output_ids.append(bad.targets.scrapper)
	check(not valid(bad), "Manufactured output cannot alias a designated equipment ID")
	var roundtrip := WORKSHOP.new()
	roundtrip.restore(complete)
	check(roundtrip.capture() == complete, "Workshop state copies all transaction evidence independently")
	complete.flags.refueled = false
	check(roundtrip.flags.refueled, "Saved dictionaries do not alias live evidence")
	var course := COURSE.new()
	var legacy := {"version": 1, "course": COURSE.COURSE, "stage": 2, "status": "active", "terminal_id": "original-terminal",
		"flags": {"boot_complete": true, "terminal_taken": true, "workshop_entered": true}}
	check(course.apply_state(legacy), "Stage-one v1 save already inside workshop upgrades")
	var migrated := course.capture()
	check(migrated.version == COURSE.STATE_VERSION and not migrated.departure_started and migrated.workshop.migration_pending and not migrated.workshop.configured and migrated.workshop.step == 1 and migrated.workshop.recycled_ids.is_empty(), "Legacy migration schedules setup without inventing any completed transaction or departure")
	check(COURSE.validate_state(migrated), "Migrated stage-two course validates before world setup")
	var rejected := migrated.duplicate(true)
	rejected.workshop.step = 6
	check(not course.apply_state(rejected) and course.capture() == migrated, "Rejected restore leaves current course untouched")
	var finished_course := migrated.duplicate(true)
	finished_course.rv_id = "original-rv"
	finished_course.workshop = roundtrip.capture()
	check(course.apply_state(finished_course) and course.capture() == finished_course, "Configured typed runtime arrays validate with numeric wheel-slot metadata")
	rejected = finished_course.duplicate(true)
	rejected.terminal_id = rejected.workshop.targets.scrapper
	check(not COURSE.validate_state(rejected), "Designated equipment cannot alias the field terminal")
	rejected = finished_course.duplicate(true)
	rejected.rv_id = rejected.workshop.gasoline_id
	check(not COURSE.validate_state(rejected), "Produced gasoline cannot alias the original vehicle")
	var upgrade := WORKSHOP.upgrade_state(historical)
	check(upgrade.version == 2 and upgrade.targets == historical.targets and upgrade.configured and valid(upgrade), "Configured workshop v1 upgrades without adding supply IDs or another setup transaction")
	for key in ["battery_exchanged", "engine_repaired", "roof_rebuilt"]: check(not upgrade.flags[key], "Upgrade does not invent " + key + " evidence")
	check(historical.version == 1 and not historical.flags.has("engine_repaired"), "Upgrade preserves the source and retry snapshot records")
	test_optional_receipts(base)
	course.free()
	roundtrip.free()
	workshop.free()
	if failures.is_empty(): print("PASS: orientation optional workshop receipts, schema and compatible migration")
	quit(0 if failures.is_empty() else 1)

func test_optional_receipts(base: Dictionary) -> void:
	var receipts := ReceiptFixture.new()
	receipts.restore(base)
	receipts.step = 6 # Every handler must remain usable beyond its suggested step.
	receipts.targets.scrap_c = "extra-scrap"
	var owner := ControllerFixture.new()
	owner.vehicle = VehicleFixture.new()
	owner.vehicle.fixture_engine = EngineState.new()
	receipts.controller = owner
	receipts._wall("left_0", "repair")
	receipts._wall("roof_1", "repair")
	check(receipts.repaired_ids == ["left_0"] and not receipts.flags.roof_rebuilt, "Wall repair can be first; a roof repair cannot count as reconstruction")
	receipts._wall("roof_1", "rebuild")
	receipts._placed(receipts.targets.scrapper, owner.rv_id)
	check(receipts.flags.roof_rebuilt and receipts.flags.scrapper_placed and not receipts.installed("scrapper"), "Roof reconstruction and unpowered native mounting are recorded in any order")
	receipts._recycled(owner.rv_id, receipts.targets.scrap_c, {"Metal Parts": 3})
	check(receipts.recycled_ids.is_empty(), "Unpowered recycling cannot fabricate material receipts")
	receipts.powered = true
	receipts._recycled("other-rv", receipts.targets.scrap_c, {"Metal Parts": 3})
	receipts._recycled(owner.rv_id, receipts.targets.scrap_c, {"Metal Parts": 2})
	check(receipts.recycled_ids.is_empty(), "Wrong vehicle and incorrect material commits do not count")
	receipts._recycled(owner.rv_id, receipts.targets.scrap_c, {"Metal Parts": 3})
	check(receipts.targets.scrap_c in receipts.recycled_ids, "Additional designated scrap commits are retained outside the recycling suggestion")
	var output: Item = load("res://props/gas_can.tscn").instantiate()
	output.persistent_id = "output-can"
	receipts.objects[output.persistent_id] = output
	receipts._output(owner.rv_id, output.persistent_id, "gasoline")
	receipts.inventory_ids.append(output.persistent_id)
	receipts.acquired(output.persistent_id, "res://props/gas_can.tscn")
	receipts.inventory_ids.append("empty-can")
	receipts._refuel(receipts.targets.fuel_port, output.persistent_id, "empty-can", 20.0)
	check(receipts.flags.refueled and receipts.gasoline_id == output.persistent_id, "Manufacturing, pickup and refueling can precede other optional tasks")
	receipts._removed(0, receipts.targets.original_wheel)
	receipts._wheel(0, receipts.targets.spare)
	check(receipts.flags.wheel_removed and receipts.flags.wheel_installed, "Original tire removal and marked spare installation remain native receipts")
	var socket := BatterySocket.new()
	socket.installed_battery = BatteryState.new()
	receipts.objects[receipts.targets.socket] = socket
	receipts._battery(receipts.targets.socket, "empty-battery", socket.installed_battery.id)
	receipts._engine(owner.vehicle.get_engine().id, "consumed-kit")
	check(receipts.flags.battery_exchanged and receipts.flags.engine_repaired, "Successful battery exchange and H repair record independent receipts")
	check(valid(receipts.capture()), "Out-of-order runtime receipts and additional supplies form a valid v2 save")
	var page := receipts.page()
	check(page.conditions.size() == 10 and page.steps.any(func(text): return "roof_1" in text) and page.reference.any(func(text): return "H:" in text), "Full optional guide retains battery, engine, roof and native controls at every suggestion")
	receipts.accepting = false
	receipts._wall("right_0", "repair")
	check("right_0" not in receipts.repaired_ids, "Closed course still refuses new receipts")
	output.free()
	socket.free()
	owner.vehicle.fixture_engine = null
	owner.vehicle.free()
	owner.free()
	receipts.free()

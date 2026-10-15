extends SceneTree
## Pure evidence/schema checks complement the native workshop journey.
const COURSE = preload("res://world/tutorial_shelter/orientation_controller.gd")
const WORKSHOP = preload("res://world/tutorial_shelter/orientation_workshop.gd")
var failures: Array[String] = []

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
	for step in range(2, 7):
		var forged := base.duplicate(true)
		forged.step = step
		check(not valid(forged), "Step cannot skip required transaction evidence: " + str(step))
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
	check(migrated.version == 2 and migrated.workshop.migration_pending and not migrated.workshop.configured and migrated.workshop.step == 1 and migrated.workshop.recycled_ids.is_empty(), "Legacy migration schedules setup without inventing any completed transaction")
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
	course.free()
	roundtrip.free()
	workshop.free()
	if failures.is_empty(): print("PASS: orientation workshop evidence, sequential schema and v1 migration")
	quit(0 if failures.is_empty() else 1)

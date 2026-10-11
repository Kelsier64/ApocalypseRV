extends SceneTree
const Settle := preload("res://tests/support/vehicle_settle.gd")
const Wait := preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)

func sample(wait: RefCounted, position := Vector3.ZERO, angle := 0.0, contacts := 4) -> bool:
	return wait.observe(position, Quaternion(Vector3.UP, angle), contacts)

func boundaries() -> void:
	check(Settle.within_limits(.019999, .009999, .004999), "Values strictly below all limits pass")
	for limits in [Vector3(.02, 0, 0), Vector3(0, .01, 0), Vector3(0, 0, .005)]:
		# Scalar thresholds avoid Vector3's float32 rounding at exact equality.
		var horizontal: float = Settle.HORIZONTAL_LIMIT if limits.x > 0 else 0.0
		var vertical: float = Settle.VERTICAL_LIMIT if limits.y > 0 else 0.0
		var angle: float = Settle.ROTATION_LIMIT if limits.z > 0 else 0.0
		check(not Settle.within_limits(horizontal, vertical, angle), "Equality fails independently on each limit: %s" % limits)
	check(not Settle.within_limits(.020001, 0, 0), "Horizontal excess fails")
	check(not Settle.within_limits(0, .010001, 0), "Vertical excess fails")
	check(not Settle.within_limits(0, 0, .005001), "Rotation excess fails")
	var wait := Settle.new()
	for tick in 59: check(not sample(wait), "59 ticks cannot complete a 60-tick window")
	check(sample(wait) and wait.ticks == 60, "Exactly 60 stable grounded samples succeed")
	for contacts in [0, 1, 2, 3]:
		wait = Settle.new()
		for tick in 59: sample(wait)
		check(not sample(wait, Vector3.ZERO, 0.0, contacts) and wait.positions.is_empty(), "Any missing wheel contact clears the window")
		for tick in 59: check(not sample(wait), "A lost contact requires 60 fresh grounded ticks")
		check(sample(wait), "Ground contact recovery succeeds after 60 ticks")
	var vehicle := Chassis.new()
	check(Settle.count_contacts(vehicle) == 0, "Missing installed wheels do not count as grounded")
	vehicle.free()

func whole_window() -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var wait := Settle.new()
		for tick in 60: sample(wait, axis * float(tick) * .0005)
		check(not wait.settled, "Slow drift fails the whole-window range: %s" % axis)
	var wait := Settle.new()
	for tick in 60: sample(wait, Vector3.ZERO, tick * .0001)
	check(not wait.settled, "Slow rotation drift fails despite tiny adjacent differences")
	for axis in [Vector3.RIGHT, Vector3.UP]:
		wait = Settle.new()
		for tick in 60:
			var excursion := .008 if axis == Vector3.UP else .014
			var offset := excursion if tick == 20 else (-excursion if tick == 40 else 0.0)
			sample(wait, axis * offset)
		check(not wait.settled, "Opposite excursions fail even with matching first/last poses: %s" % axis)
	wait = Settle.new()
	for tick in 60: sample(wait, Vector3.ZERO, .003 if tick == 20 else (-.003 if tick == 40 else 0.0))
	check(not wait.settled, "Rotation diameter catches a swing around the first orientation")
	wait = Settle.new()
	for tick in 60: sample(wait, Vector3(.015, 0, .015) if tick == 30 else Vector3.ZERO)
	check(not wait.settled, "Horizontal range includes diagonal XZ distance")
	wait = Settle.new()
	sample(wait, Vector3(.03, 0, 0))
	for tick in 59: check(not sample(wait), "Outlier remains in the full rolling window")
	check(sample(wait) and wait.ticks == 61, "Rolling window succeeds as the old outlier leaves")
	wait = Settle.new()
	for tick in 60: sample(wait, Vector3.ZERO, PI - .001 if tick % 2 else -PI + .001)
	check(wait.settled, "Quaternion comparison handles angle wrapping")
	wait = Settle.new()
	for tick in 60:
		wait.observe(Vector3.ZERO, Quaternion(0, 0, 0, -1 if tick % 2 else 1), 4)
	check(wait.settled, "Quaternion sign does not change orientation")

func deadlines() -> void:
	var wait := Settle.new()
	for tick in 840: sample(wait, Vector3.ZERO, 0.0, 3)
	for tick in 59: check(not sample(wait), "Final window remains incomplete at tick 899")
	check(sample(wait) and wait.ticks == 900, "Success is permitted exactly at tick 900")
	wait = Settle.new()
	for tick in 841: sample(wait, Vector3.ZERO, 0.0, 3)
	for tick in 59: sample(wait)
	check(not wait.settled and wait.ticks == 900, "An incomplete window times out at tick 900")
	check(not sample(wait) and wait.ticks == 900, "Tick 901 cannot turn timeout into success")
	wait = Settle.new()
	for tick in 900: sample(wait, Vector3(float(tick) * .001, 0, 0))
	check(not wait.settled and wait.ticks == 900, "Persistent grounded drift times out")
	check("ticks=900/900" in wait.diagnostic() and "grounded=4/4" in wait.diagnostic() and "horizontal=" in wait.diagnostic() and "rotation=" in wait.diagnostic(), "Timeout includes diagnostic ticks, contacts and ranges")

func physics_timeout() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	stage.add_child(vehicle)
	var rv: Chassis = vehicle.get_node("Chassis")
	var wait := Settle.new()
	var start := Engine.get_physics_frames()
	# No floor: a real vehicle must time out without modifying its physics.
	var ready := await wait.wait_for_vehicle(self, rv, func() -> bool: return true)
	check(not ready and not wait.settled, "An airborne production vehicle cannot report success")
	check(wait.ticks == 900 and Engine.get_physics_frames() - start == 900, "Wait samples exactly 900 actual physics ticks")
	check(not rv.freeze and rv.linear_velocity.y < -1.0 and rv.global_position.y < -1.0, "Timeout preserves free fall and normal velocity")
	var cancelled := Settle.new()
	check(not await cancelled.wait_for_vehicle(self, rv, func() -> bool: return false), "A superseded generation cancels its wait")
	check(cancelled.ticks == 0, "Cancellation cannot observe or report an old vehicle as stable")
	# Readiness observes a reported setup failure immediately, never as success.
	var failed_stage: Node3D = load("res://tests/slender_speaker_playground.gd").new()
	failed_stage.setup_error = "SLENDER_RUNTIME vehicle settle timeout " + wait.diagnostic()
	check(not await Wait.playground_ready(self, failed_stage), "Playground setup failure cannot become test readiness")
	failed_stage.free()
	stage.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	boundaries()
	whole_window()
	deadlines()
	await physics_timeout()
	if failures.is_empty(): print("PASS: Vehicle settle requires a complete grounded physics window, strict whole-window ranges and a 900-tick deadline")
	for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

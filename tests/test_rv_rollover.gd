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
	var vehicle := Fixture.vehicle(world, Vector3(0.0, 4.0, 0.0), PI)
	vehicle.freeze = true
	var player := Fixture.player(world, Vector3(10.0, 0.2, 0.0))
	for i in 90: await physics_frame
	var seat := vehicle.get_node("DriverSeat")
	var slots := vehicle.get_node("StructureSlots") as RVStructureSlots
	var roof := slots.panel("roof_0")
	var health := roof.current_health
	var engine := vehicle.get_engine()
	var engine_health := engine.health
	seat.interact_hold(player)
	vehicle.energy.engine_running = true
	vehicle.freeze = false
	for i in 55: await physics_frame
	vehicle.linear_velocity = Vector3.DOWN * 5.0
	for i in 75: await physics_frame
	check(vehicle.rollover_state() == Chassis.Rollover.INVERTED, "RV stays inverted after settling on the roof")
	check(vehicle.global_position.y > 2.0, "Roof hull supports the chassis above the ground")
	check(not vehicle.energy.engine_running and not vehicle.set_engine_running(true), "Overturning stops and blocks the engine")
	var roof_total := 0.0
	for slot in ["roof_0", "roof_1", "roof_2"]: roof_total += slots.panel(slot).max_health - slots.panel(slot).current_health
	check(roof.current_health < health or roof_total > 0.0, "A roof impact reduces roof health")
	check(is_equal_approx(engine.health, engine_health), "A roof impact does not damage the engine")
	seat.exit_seat()
	check(player.seated_in == null and absf(player.global_position.x) > 2.5, "A seated driver exits an inverted RV onto outside ground")
	roof.set_health(0.0)
	for i in 3: await physics_frame
	var enabled := false
	var seen := false
	for child in vehicle.get_children():
		if child is CollisionShape3D and child.get_meta(&"rv_hull_slot", "") == "roof_0":
			enabled = enabled or not child.disabled
			seen = true
	check(seen and not enabled, "Destroying the roof disables its chassis shapes")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: rollover shell, localized damage and emergency seat exit")
	quit(1 if not failures.is_empty() else 0)

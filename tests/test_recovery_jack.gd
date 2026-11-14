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
	for i in 180: await physics_frame
	print("RECOVERY 2 ", second, " up=", vehicle.global_basis.y.y, " position=", vehicle.global_position)
	check(second == "Lifting RV" and vehicle.rollover_state() == Chassis.Rollover.UPRIGHT, "Second lift returns the RV to its wheels")
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

extends SceneTree
## Keep the production printer inside the real RV cabin and exercise full-size output.
var failures: Array[String] = []
const BODY_SCENE := "res://props/printed_player.tscn"

func _init() -> void:
	_run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

func _bodies(world: Node) -> Array[PrintedPlayerBody]:
	var result: Array[PrintedPlayerBody] = []
	for node in WorldEntities.get_container(world).get_children():
		if node is PrintedPlayerBody: result.append(node)
	return result

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
	player.global_position = Vector3(10, 3, 0)
	await process_frame
	await physics_frame
	var station: CraftingStation = rv.get_node("CraftingStation")
	check(station.position.is_equal_approx(Vector3(-1.15, .5, 1)), "Fixture keeps production mounted printer coordinates inside the RV")
	var body_recipe := RecipeCatalog.find("printed_player")
	rv.inventory = {}
	rv.deposit_materials(body_recipe.costs)
	rv.deposit_materials(body_recipe.costs)
	rv.current_power = 50
	var power_before: float = rv.current_power
	check(station.request_craft("printed_player") and station.request_craft("printed_player"), "Two official full-size bodies queue inside cabin")
	var rig: Node3D = station.get_node("Details")
	var gantry: Node3D = rig.get_node("Gantry")
	station.step_work(body_recipe.duration * .5)
	rig._physics_process(2.0)
	var halfway_height := gantry.position.y
	station.step_work(body_recipe.duration * .49)
	rig._physics_process(2.0)
	var near_complete_height := gantry.position.y
	check(near_complete_height > halfway_height, "Standing-player print raises machine from half to near-complete height")
	station.step_work(body_recipe.duration * .01 + .0001)
	check(station.jobs.size() == 1 and _bodies(world).size() == 1, "Ceiling-blocked bed delivers first body beside the machine and advances the queue")
	check(is_equal_approx(power_before - rv.current_power, body_recipe.power_cost), "First cabin fabrication charges its power exactly once")
	check(is_zero_approx(station.print_visual.progress), "Second queue entry owns the cleared bed preview at zero progress")
	var body: PrintedPlayerBody = _bodies(world)[0] if not _bodies(world).is_empty() else null
	if body != null:
		check(body.global_position.distance_to(station.spawn_marker.global_position) > .5, "Full-size body leaves the obstructed print bed")
		check(body.global_position.y + 1.6 < 2.500574, "Floor delivery keeps the complete standing body below the RV roof")
		check(body.global_position.distance_to(station.global_position) < 1.5, "Delivered body remains within immediate use range of its machine")
		await _check_real_e(world, player, body)
	# A completed print transitions into a gradual lowering for the next item.
	var before_lowering := gantry.position.y
	rig._physics_process(.5)
	check(gantry.position.y < before_lowering and gantry.position.y > .9, "Completion starts a visible gradual machine descent without snapping")
	for step in 20: rig._physics_process(.25)
	check(gantry.position.y < halfway_height, "Next queued item returns the frame below the first half-height")
	# Vacate the immediate area after interaction so the next body has safe floor space.
	player.global_position = Vector3(10, 3, 0)
	if body != null: body.global_position = Vector3(10, 3, -3)
	await physics_frame
	station.step_work(body_recipe.duration * .99)
	rig._physics_process(2)
	var second_high := gantry.position.y
	station.step_work(body_recipe.duration * .01 + .0001)
	check(station.jobs.is_empty() and _bodies(world).size() == 2, "Second body completes after first leaves bed and produces one new persistent actor")
	check(station.print_visual.preview == null, "Final completion removes mesh-only print preview")
	check(is_equal_approx(power_before - rv.current_power, body_recipe.power_cost * 2), "Two cabin bodies consume exactly two recipe power costs")
	var completed_height := gantry.position.y
	check(completed_height >= second_high, "Final frame is preserved until return animation ticks")
	rig._physics_process(.5)
	check(gantry.position.y < completed_height, "Final completion lowers the machine toward ready height")
	var count := _bodies(world).size()
	station.step_work(0)
	station.step_work(body_recipe.duration)
	check(_bodies(world).size() == count, "Repeated completed updates cannot duplicate bodies")
	for item in _bodies(world):
		item.global_position = Vector3(10 + _bodies(world).find(item) * 2, 3, -3)
		item.freeze = true
	await physics_frame
	await _check_blocked_resume(world, rv, station)
	await _check_ordinary_block(world, rv, station)
	for existing in WorldEntities.get_container(world).get_children(): existing.global_position = Vector3(10 + WorldEntities.get_container(world).get_children().find(existing) * 2, 3, -3)
	# The production starter RV mounts its tablet on RightFront, away from
	# the hatch-rim fixture; new_rv's older table-mounted tablet would block
	# the floor-level delivery path before shoulder-clearance can be tested.
	rv.get_node("TabletScreen").global_position = Vector3(1.7, 1.7, -4)
	station.position = Vector3(-1.15, .5, .5)
	await physics_frame
	await _check_narrow_hatch(world, rv, station, player)
	await _check_no_wall_crossing_or_void(world)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: real RV cabin full-size body output, E use, next job, machine descent and safe blocked-output retry")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_real_e(world: Node3D, player: CharacterBody3D, body: PrintedPlayerBody) -> void:
	for frame in 5: await physics_frame
	var ray: RayCast3D = player.camera.get_node("InteractRay")
	var reached := false
	var feet := body.global_position
	for direction in [Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3(1, 0, -1).normalized()]:
		var candidate: Vector3 = feet + direction * 1.15 - Vector3.UP * .25
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player.standing_collision_shape
		query.transform = Transform3D(Basis.IDENTITY, candidate) * player.standing_collision_transform
		query.collision_mask = 1
		query.exclude = [player.get_rid(), body.get_rid()]
		if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
		player.global_position = candidate
		player.camera.look_at(feet + Vector3.UP * .9)
		ray.force_raycast_update()
		if ray.get_collider() == body:
			reached = true
			break
	check(reached, "Delivered cabin body is reachable through a real unobstructed interaction ray")
	if not reached: return
	var instance_id := player.get_instance_id()
	var before := player.global_position
	Input.action_press("interact")
	for frame in 3: await physics_frame
	Input.action_release("interact")
	for frame in 3: await physics_frame
	check(player.get_instance_id() == instance_id and player.global_position.distance_to(before) > .5, "Real E input transfers the single production controller into the delivered cabin body")
	check(player.global_position.distance_to(feet - Vector3.UP * .25) < .1, "E lands at the physical body rather than the noninteractive print preview")

func _check_blocked_resume(world: Node3D, rv: Chassis, station: CraftingStation) -> void:
	var recipe := RecipeCatalog.find("printed_player")
	rv.deposit_materials(recipe.costs)
	rv.current_power = 50
	check(station.request_craft("printed_player"), "Blocked-output fixture queues an official body")
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 6)
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = station.global_position + Vector3.UP
	await physics_frame
	var before_count := _bodies(world).size()
	station.step_work(recipe.duration)
	check(station.jobs.size() == 1 and is_zero_approx(station.jobs[0].remaining) and station.last_error.begins_with("Output blocked"), "All floor candidates blocked retain the completed job with explicit blocked-output state")
	check(is_equal_approx(station.print_visual.progress, 1), "Fully blocked floor delivery preserves the completed visual")
	var power_after: float = rv.current_power
	station.step_work(recipe.duration)
	station.step_work(0)
	check(_bodies(world).size() == before_count and rv.current_power == power_after, "Blocked completion retries neither duplicate bodies nor charge additional power")
	obstacle.queue_free()
	await physics_frame
	station.step_work(0)
	check(station.jobs.is_empty() and _bodies(world).size() == before_count + 1 and rv.current_power == power_after, "Clearing floor obstruction resumes the already-paid completed job exactly once")
	station.step_work(0)
	check(_bodies(world).size() == before_count + 1, "Resumed completion cannot duplicate its body")

func _check_ordinary_block(world: Node3D, rv: Chassis, station: CraftingStation) -> void:
	var recipe := RecipeCatalog.find("gasoline")
	rv.deposit_materials(recipe.costs)
	rv.current_power = 50
	check(station.request_craft("gasoline"), "Ordinary product fixture queues")
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = station.spawn_marker.global_position + Vector3.UP * .3
	await physics_frame
	station.step_work(recipe.duration)
	check(station.jobs.size() == 1 and station.last_error == "Output blocked", "Ordinary products retain existing blocked-bed behavior instead of using body floor fallback")
	obstacle.queue_free()
	await physics_frame
	station.step_work(0)
	check(station.jobs.is_empty(), "Ordinary product completes once its original bed obstruction clears")


func _check_narrow_hatch(world: Node3D, rv: Chassis, station: CraftingStation, player: CharacterBody3D) -> void:
	var recipe := RecipeCatalog.find("printed_player")
	rv.deposit_materials(recipe.costs)
	rv.current_power = 50
	var before := _bodies(world).duplicate()
	check(station.request_craft("printed_player"), "Narrow hatch fixture queues real body")
	station.step_work(recipe.duration)
	var output: PrintedPlayerBody
	for body in _bodies(world):
		if not before.has(body): output = body
	check(output != null and station.jobs.is_empty(), "Narrow idle-body hatch fit still produces a usable body: " + station.last_error)
	if output == null: return
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4
	capsule.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(output.global_basis, output.global_position + Vector3.UP * .8)
	query.collision_mask = 1
	query.exclude = [output.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Hatch-rim clearance reserves playable shoulder width rather than only narrow idle-body width")
	check(output._destination_clear(player, Transform3D(output.global_basis, output.global_position - Vector3.UP * .25)), "Every hatch body destination satisfies actual playable controller transfer clearance")


func _check_no_wall_crossing_or_void(world: Node3D) -> void:
	var fixture: CraftingStation = load("res://equipment/crafting_station.tscn").instantiate()
	fixture.presentation_only = true
	world.add_child(fixture)
	fixture.global_position = Vector3(30, 0, 0)
	var item: Item = load(BODY_SCENE).instantiate()
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6, .1, 6)
	collider.shape = shape
	floor.add_child(collider)
	world.add_child(floor)
	floor.global_position = fixture.global_position - Vector3.UP * .05
	await physics_frame
	check(not CraftingOutputPlacement.body_floor_output(fixture, item).is_empty(), "Open adjacent floor supplies a valid control-ready body destination")
	var walls: Array[StaticBody3D] = []
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wall := StaticBody3D.new()
		var wall_collision := CollisionShape3D.new()
		var wall_shape := BoxShape3D.new()
		wall_shape.size = Vector3(.04, 1.6, .64) if absf(direction.x) > .5 else Vector3(.64, 1.6, .04)
		wall_collision.shape = wall_shape
		wall.add_child(wall_collision)
		world.add_child(wall)
		wall.global_position = fixture.global_position + direction * .30 + Vector3.UP * .8
		walls.append(wall)
	await physics_frame
	var endpoint := Transform3D(Basis.IDENTITY, fixture.global_position + Vector3(0, .06, -.95))
	check(CraftingOutputPlacement.is_clear(fixture, item, endpoint, false) and CraftingOutputPlacement.body_can_stand(fixture, endpoint), "Thin-wall fixture leaves a valid clear endpoint beyond its enclosing wall")
	check(CraftingOutputPlacement.body_floor_output(fixture, item).is_empty(), "Clear endpoints behind thin walls are rejected by the actual capsule delivery path")
	for wall in walls: wall.queue_free()
	floor.queue_free()
	await physics_frame
	check(CraftingOutputPlacement.body_floor_output(fixture, item).is_empty(), "Missing adjacent floor prevents fabrication into empty air")
	item.free()
	fixture.queue_free()
	await process_frame

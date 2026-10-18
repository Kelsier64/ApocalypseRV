extends SceneTree
## Transaction events must describe physical production and accepted storage.
var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var recycler: Item
var station: CraftingStation
var recycled: Array[Dictionary] = []
var produced: Array[Dictionary] = []
var acquired: Array[Dictionary] = []

func _init() -> void: _run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

func _run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await process_frame
	await physics_frame
	rv.current_power = 50.0
	recycler = rv.get_node("Scrapper")
	station = rv.get_node("CraftingStation")
	recycler.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(10, 3, 0)), rv)
	station.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(15, 3, 0)), rv)
	recycler.connect("recycle_committed", _on_recycle)
	station.output_committed.connect(_on_output)
	await physics_frame
	_check_recycling()
	await _check_crafting()
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: material and queued physical output commit events")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _input(scene_path: String, amounts: Dictionary) -> Item:
	var item: Item = load(scene_path).instantiate()
	WorldEntities.get_container(world).add_child(item)
	item.global_position = recycler.to_global(Vector3(0, 1.5, 0))
	item.scrap_yields = amounts
	recycler.recycle_prop(item)
	return item

func _check_recycling() -> void:
	var scrap := _input("res://props/scrap.tscn", {ItemNames.METAL_PARTS: Vector2(2, 2)})
	var first_id := scrap.persistent_id
	check(recycled.is_empty(), "Accepting a recycler input emits no deposit event")
	rv.current_power = 0.0
	recycler.step_work(recycler.crush_time)
	check(recycled.is_empty() and recycler.props_being_crushed.size() == 1, "Unpowered recycling cannot commit materials")
	rv.current_power = 50.0
	var capacity := rv.material_capacity
	rv.material_capacity = 0
	recycler.step_work(recycler.crush_time)
	recycler.step_work(0.01)
	check(recycled.is_empty() and not scrap.is_queued_for_deletion() and rv.get_item_count(ItemNames.METAL_PARTS) == 0, "Repeated full-storage completion emits nothing and retains input")
	check(recycler.props_being_crushed.size() == 1 and is_zero_approx(float(recycler.props_being_crushed[0].timer)), "Rejected material deposit preserves the finished recycler job")
	rv.material_capacity = capacity
	recycler.step_work(0.01)
	check(recycled.size() == 1 and recycled[0].item == first_id and scrap.is_queued_for_deletion(), "Retry after storage clears commits the original input exactly once")
	check(not recycler._finish_recycle(scrap) and recycled.size() == 1 and rv.get_item_count(ItemNames.METAL_PARTS) == 2, "A consumed input cannot deposit twice before deferred deletion")

	var cancelled := _input("res://props/scrap.tscn", {ItemNames.METAL_PARTS: Vector2(7, 7)})
	recycler._on_service_stopped()
	check(recycled.size() == 1 and recycler.props_being_crushed.is_empty() and cancelled.processing_owner == null and not cancelled.is_queued_for_deletion(), "Releasing an unfinished input emits no material commit")
	cancelled.queue_free()
	var second := _input("res://props/scrap.tscn", {ItemNames.METAL_PARTS: Vector2(2, 2)})
	var second_id := second.persistent_id
	recycler.step_work(recycler.crush_time)
	var barrel := _input("res://props/oil_barrel.tscn", {ItemNames.METAL_PARTS: Vector2(2, 2), ItemNames.UNREFINED_FUEL: Vector2(10, 10)})
	var barrel_id := barrel.persistent_id
	recycler.step_work(recycler.crush_time)
	check(recycled.size() == 3 and recycled[1].item == second_id and recycled[2].item == barrel_id and first_id != second_id, "Two scraps and the oil barrel commit distinct actual input identities")
	check(rv.get_item_count(ItemNames.METAL_PARTS) == 6 and rv.get_item_count(ItemNames.UNREFINED_FUEL) == 10, "Only committed physical inputs fund the crafting inventory")

func _check_crafting() -> void:
	var recipe := RecipeCatalog.find("gasoline")
	check(not station.request_craft("missing_recipe") and produced.is_empty(), "Rejected recipe emits no manufactured output")
	var before := rv.get_all_items()
	check(station.request_craft("gasoline") and produced.is_empty(), "Queue acceptance reserves costs without reporting a physical output")
	station.step_work(recipe.duration * 0.5)
	check(produced.is_empty(), "An unfinished print emits no physical output")
	rv.current_power = 0.0
	station.step_work(recipe.duration)
	check(produced.is_empty() and station.jobs.size() == 1, "Paused print emits no physical output")
	rv.current_power = 50.0
	station.cancel_jobs()
	station.cancel_jobs()
	check(produced.is_empty() and rv.get_all_items() == before, "Repeated cancellation refunds inputs once without manufacturing events")
	check(station.request_craft("gasoline") and station.request_craft("gasoline"), "Distinct funded gasoline jobs queue")
	var blocker := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 3)
	collider.shape = shape
	blocker.add_child(collider)
	world.add_child(blocker)
	blocker.global_position = station.spawn_marker.global_position + Vector3.UP * 0.5
	await physics_frame
	station.step_work(recipe.duration)
	station.step_work(recipe.duration)
	check(produced.is_empty() and station.jobs.size() == 2 and is_zero_approx(float(station.jobs[0].remaining)), "Repeated blocked completion retains the job without reporting manufacture")
	blocker.queue_free()
	await physics_frame
	station.step_work(0.0)
	check(produced.size() == 1 and station.jobs.size() == 1, "Clearing a finished print bed commits one physical queued output")
	station.step_work(0.0)
	check(produced.size() == 1, "Zero-time retry does not duplicate the committed output")
	station.cancel_jobs()
	check(produced.size() == 1, "Cancelling a following identical recipe emits no additional output")
	if produced.is_empty(): return
	var output := _find_item(produced[0].item)
	check(output != null and output.scene_file_path == recipe.scene_path and produced[0].recipe == recipe.recipe_id and produced[0].rv == rv.persistent_id, "Manufacture payload identifies the actual recipe, RV and physical product")
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(25, 3, 0)
	world.add_child(player)
	player.set_physics_process(false)
	player.connect("item_acquired", func(identity: String, scene: String): acquired.append({"item": identity, "scene": scene}))
	check(acquired.is_empty() and player.inventory.items.is_empty(), "Manufacturing does not implicitly grant or acquire the gasoline can")
	if output != null: output.interact(player)
	check(acquired.size() == 1 and acquired[0].item == produced[0].item and player.inventory.active_item().state.id == produced[0].item, "Actual pickup preserves the manufactured item identity in inventory")
	await process_frame
	check(station.spawn_item(recipe.scene_path, {}, 0.0), "Legacy direct spawn still creates a physical item")
	check(produced.size() == 1, "Direct service output cannot impersonate queued recipe manufacture")
	check(not station.spawn_item("res://props/missing_output.tscn", {}, 0.0) and produced.size() == 1, "Failed direct output emits no recipe manufacture")

func _find_item(identity: String) -> Item:
	for node in WorldEntities.get_container(world).get_children():
		if node is Item and node.persistent_id == identity: return node
	return null

func _on_recycle(rv_id: String, item_id: String, amounts: Dictionary) -> void:
	var input := _find_item(item_id)
	check(input != null and not input.is_queued_for_deletion(), "Recycle event retains the consumed item until observers read its identity")
	check(rv_id == rv.persistent_id, "Recycle event names the RV that accepted materials")
	for material in amounts:
		check(rv.get_item_count(material) >= int(amounts[material]), "Recycle observers see deposited materials")
	if input != null:
		check(not recycler._finish_recycle(input), "Synchronous recycle observer cannot repeat the material transaction")
	recycled.append({"rv": rv_id, "item": item_id, "amounts": amounts.duplicate(true)})
	amounts.clear()
	if input != null: check(not input.get_meta("recycle_result").is_empty(), "Observer payload mutation cannot alter the committed yield")

func _on_output(rv_id: String, item_id: String, recipe_id: String) -> void:
	check(_find_item(item_id) != null, "Queued output event fires after the actual Item enters the world")
	produced.append({"rv": rv_id, "item": item_id, "recipe": recipe_id})
	station.step_work(0.0)

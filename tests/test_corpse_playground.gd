extends SceneTree
## Observe the real playground clock and anatomical ingestion, never advance work.
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok and note not in failures: failures.append(note); push_error("FAIL: " + note)

func step(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func finish_feed(corpse, recycler: Item, rv: Chassis, before: int, note: String) -> void:
	if not is_instance_valid(corpse):
		check(false, note + " must retain anatomy until physical feed can be observed")
		return
	var initial_count: int = corpse.bodies.size() + corpse.fed_bones.size()
	var saw_segments: bool = not corpse.fed_bones.is_empty()
	for frame in 300:
		if not is_instance_valid(corpse): break
		check(corpse.processing_owner == recycler and corpse.physical_feed, note + " keeps one owner and active bone physics")
		saw_segments = saw_segments or (not corpse.fed_bones.is_empty() and corpse.bodies.size() < initial_count)
		if not corpse.bodies.is_empty():
			check(rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == before, note + " cannot deposit while anatomy remains above the teeth")
		for bone: PhysicalBone3D in corpse.bodies.values():
			var local := recycler.to_local(bone.global_position)
			check(local.is_finite() and local.length() < 5.0, note + " keeps anatomical joints finite and near the intake")
			if bone.collision_mask != 0: continue
			for shape: CollisionShape3D in bone.find_children("*", "CollisionShape3D", true, false):
				var box := shape.shape.get_debug_mesh().get_aabb()
				for corner in 8:
					var point := recycler.to_local(shape.to_global(box.get_endpoint(corner)))
					check(absf(point.x) <= recycler.FEED.HALF_OPENING + .02 and absf(point.z) <= recycler.FEED.HALF_OPENING + .02, note + " only disables bone collision inside the full opening")
		await step(1)
	check(saw_segments, note + " consumes actual bone segments instead of moving the pickup proxy")
	if is_instance_valid(corpse):
		var remaining := {}
		for key: String in corpse.bodies: remaining[key] = recycler.to_local(corpse.bodies[key].global_position)
		print("PLAYGROUND_FEED_TIMEOUT ", note, " power=", rv.current_power, " bones=", remaining)
	check(not is_instance_valid(corpse) and recycler.props_being_crushed.is_empty(), note + " finishes every segment and releases the processing slot within five seconds")
	check(rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == before + 3, note + " deposits exactly the original payload")
	await step(60)
	check(rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == before + 3 and recycler.props_being_crushed.is_empty(), note + " never deposits a second payload")

func run() -> void:
	var stage: Node3D = load("res://tests/corpse_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	await step(12)
	var rv: Chassis = stage.rv
	var recycler: Item = rv.get_node("Scrapper")
	var parked_position := rv.global_position
	var before: int = rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
	var corpse: CorpseProp = load("res://props/corpse.tscn").instantiate()
	corpse.position = recycler.to_global(Vector3(0, 2.4, 0))
	corpse.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(3, 3)}
	WorldEntities.get_container(stage).add_child(corpse)
	await step(2)
	var bounds: AABB = recycler.FEED.geometry_bounds(corpse)
	check(recycler.to_local(corpse.global_position).y + bounds.position.y > .9, "Natural fixture starts with the complete full-size anatomy above the rim")
	for frame in 120:
		if not is_instance_valid(corpse) or corpse.physical_feed: break
		await step(1)
	check(is_instance_valid(corpse) and corpse.processing and corpse.processing_owner == recycler, "Natural hopper contact claims the corpse in the playground")
	await finish_feed(corpse, recycler, rv, before, "Natural hopper")
	check(rv.global_position.distance_to(parked_position) < .001, "Device updates leave the parked RV stationary")
	# F6 transfers the original monster identity and yield through production intake.
	for child in WorldEntities.get_container(stage).get_children():
		if child is CorpseProp and child.processing_owner == null:
			child.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(3, 3)}
	stage._pick_nearby()
	await step(10)
	check(stage.player.held_item_node is CorpseProp, "F6 fixture picks up the original monster corpse")
	before = rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
	if stage.player.held_item_node is CorpseProp:
		var identity: String = stage.player.inventory.active_item().state.id
		stage._recycle()
		stage._recycle()
		check(stage.player.inventory.items.is_empty() and recycler.props_being_crushed.size() == 1, "Repeated F6 hands off one input and consumes inventory once")
		if not recycler.props_being_crushed.is_empty():
			corpse = recycler.props_being_crushed[0].prop
			check(corpse.persistent_id == identity, "F6 preserves the original corpse identity")
			var timer_before: float = recycler.props_being_crushed[0].timer
			await step(45)
			check(recycler.props_being_crushed.size() == 1 and is_equal_approx(recycler.props_being_crushed[0].timer, timer_before - .75), "F6 advances exactly one 60 Hz work clock")
			await finish_feed(corpse, recycler, rv, before, "F6 hopper")
	check(rv.global_position.distance_to(parked_position) < .001, "F6 work also leaves the parked RV stationary")
	stage.queue_free()
	await step(2)
	if failures.is_empty(): print("PASS: corpse playground natural/F6 anatomical feed, single clock and exactly-once yield")
	quit(0 if failures.is_empty() else 1)

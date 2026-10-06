extends SceneTree
## Exercise the real playground's clock; never manually advance RV/device work.
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note); push_error("FAIL: " + note)

func step(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

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
	corpse.position = recycler.global_position + Vector3.UP * .7
	corpse.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(3, 3)}
	WorldEntities.get_container(stage).add_child(corpse)
	await step(8)
	check(corpse.processing and corpse.processing_owner == recycler, "Natural hopper contact claims the corpse in the playground")
	var feed_height: float = recycler.to_local(corpse.global_position).y
	await step(20)
	check(recycler.to_local(corpse.global_position).y < feed_height - .1, "Accepted corpse continues moving into the rollers without F6")
	await step(90)
	check(not is_instance_valid(corpse), "Playground automatically finishes crushing and removes the corpse")
	check(rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == before + 3, "Normal hopper feeding deposits its material yield")
	check(rv.global_position.distance_to(parked_position) < .001, "Device updates leave the parked RV stationary")
	# F6 must use the same running clock, without adding a second set of work ticks.
	stage._pick_nearby()
	await step(10)
	check(stage.player.held_item_node is CorpseProp, "F6 fixture picks up the original monster corpse")
	before = rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
	stage._recycle()
	await step(45)
	check(recycler.props_being_crushed.size() == 1, "F6 does not double the crushing speed")
	await step(65)
	check(recycler.props_being_crushed.is_empty() and rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) > before, "F6 finishes through the same continuous device updates")
	stage.queue_free()
	await step(2)
	if failures.is_empty(): print("PASS: corpse playground automatic hopper work and single-clock F6 recycling")
	quit(0 if failures.is_empty() else 1)

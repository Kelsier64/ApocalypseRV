extends SceneTree

const PLAYER := preload("res://player/player.tscn")
const SCRAP := preload("res://props/scrap.tscn")

class SmallInterior extends PoiInterior:
	func _init() -> void:
		room_count = 2
		target_floors = 1
		populate_content = false

var failures: Array[String] = []
var arena: Node3D
var manager: PoiInstanceManager
var player: CharacterBody3D
var building: Node3D

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _add_scrap(label: String) -> Prop:
	var item := SCRAP.instantiate() as Prop
	item.item_name = label
	item.freeze = true
	manager.interior.entities.add_child(item)
	item.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 2))
	return item

func _enter(id: String) -> bool:
	await manager.enter(player, building, id, 913)
	var ok: bool = manager.state == PoiInstanceManager.State.INDOOR and manager.interior != null and player.get_parent() == manager.interior
	check(ok, id + " enters a complete real interior: " + manager.last_error)
	return ok

func _retired(label: String) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while manager.get_children().any(func(child: Node): return child is SubViewport) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not manager.get_children().any(func(child: Node): return child is SubViewport), label + " retires viewport")

func _interrupt_exit(mode: String, label: String) -> void:
	manager.transition_timeout_ms = 60000
	if mode == "timeout": manager.transition_timeout_ms = 0
	manager.leave()
	check(manager.state == PoiInstanceManager.State.LEAVING, label + " starts leave")
	match mode:
		"cancel": manager.cancel_transition("Injected exit cancellation")
		"death":
			player.current_player_health = 0
			manager._process(0)
		"timeout": manager._process(0)
	await process_frame
	player.current_player_health = player.max_player_health
	check(manager.state == PoiInstanceManager.State.FAILED and not manager.busy and manager.active_id.is_empty(), label + " releases transition")
	check(player.get_parent() == arena and not player.in_ui_mode, label + " restores player and controls")
	await _retired(label)
	manager.transition_timeout_ms = 60000

func _case(mode: String) -> void:
	var id := "exit-" + mode
	if not await _enter(id): return
	var room := manager.interior
	var picked := _add_scrap(id + "-picked-first")
	var remaining := _add_scrap(id + "-remaining-first")
	var remaining_id: String = remaining.persistent_id
	check(picked.interact(player).begins_with("已拾取"), id + " first visit picks up a real prop")
	await process_frame
	check(player.inventory.items.size() > 0 and room.entities.get_child_count() == 1, id + " inventory and room reflect pickup")
	var first_room_id: String = room.layout.rooms[0].id
	if first_room_id not in room.explored: room.explored.append(first_room_id)
	var first_inventory: int = player.inventory.items.size()
	await _interrupt_exit(mode, id + " first visit")
	var first: Dictionary = manager.saved_instances.get(id, {})
	check(not first.is_empty() and first.actors.size() == 1 and first.actors[0].state.id == remaining_id, id + " first exit commits the unpicked prop")
	check(first.get("explored", []).has(first_room_id) and player.inventory.items.size() == first_inventory, id + " first exit commits exploration with inventory")
	if not await _enter(id): return
	room = manager.interior
	check(room.entities.get_child_count() == 1, id + " revisit does not duplicate picked prop")
	var restored: Prop
	if room.entities.get_child_count() == 1: restored = room.entities.get_child(0) as Prop
	check(restored != null and restored.persistent_id == remaining_id, id + " revisit restores surviving prop identity")
	if restored != null:
		check(restored.interact(player).begins_with("已拾取"), id + " revisit picks up the restored prop")
	var next := _add_scrap(id + "-remaining-second")
	var next_id: String = next.persistent_id
	var revisited_room_id: String = room.layout.rooms[1].id
	if revisited_room_id not in room.explored: room.explored.append(revisited_room_id)
	await process_frame
	var second_inventory: int = player.inventory.items.size()
	await _interrupt_exit(mode, id + " revisit")
	var second: Dictionary = manager.saved_instances.get(id, {})
	check(not second.is_empty() and second.actors.size() == 1 and second.actors[0].state.id == next_id, id + " revisit commits current actors, not previous manifest")
	check(second.get("explored", []).has(revisited_room_id) and player.inventory.items.size() == second_inventory, id + " revisit commits exploration with inventory")

func _run() -> void:
	arena = Node3D.new()
	arena.name = "PoiTransitionArena"
	manager = PoiInstanceManager.new()
	manager.name = "PoiInstances"
	manager.interior_factory = func(): return SmallInterior.new()
	arena.add_child(manager)
	player = PLAYER.instantiate()
	player.name = "Player"
	arena.add_child(player)
	building = Node3D.new()
	building.name = "EntranceBuilding"
	var return_point := Marker3D.new()
	return_point.name = "ReturnPoint"
	building.add_child(return_point)
	arena.add_child(building)
	root.add_child(arena)
	current_scene = arena
	player.set_physics_process(false)
	for mode in ["cancel", "death", "timeout"]:
		await _case(mode)
	if await _enter("exit-cancel"):
		await manager.leave()
		check(manager.state == PoiInstanceManager.State.OUTDOOR and player.get_parent() == arena, "Normal exit returns the player")
		await _retired("normal exit")
	# Entering failure must not overwrite a previously committed visit.
	var preserved: Dictionary = manager.saved_instances["exit-cancel"].duplicate(true)
	manager.interior_factory = func(): return PoiInterior.new()
	manager.transition_timeout_ms = 0
	await manager.enter(player, building, "exit-cancel", 913)
	check(manager.saved_instances["exit-cancel"] == preserved, "Failed entry keeps the prior saved interior")
	await _retired("failed entry")
	if failures.is_empty(): print("PASS: POI first/revisited exit cancellation, death, timeout, and prior-entry persistence")
	quit(0 if failures.is_empty() else 1)

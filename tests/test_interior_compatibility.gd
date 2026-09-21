extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	var outdoor := Node3D.new()
	root.add_child(outdoor)
	current_scene = outdoor
	var player: CharacterBody3D = preload("res://player/player.tscn").instantiate()
	outdoor.add_child(player)
	player.set_physics_process(false)
	var manager := PoiInstanceManager.new()
	outdoor.add_child(manager)
	var building := Node3D.new()
	var landing := Marker3D.new()
	landing.name = "ReturnPoint"
	building.add_child(landing)
	building.set_meta("poi_interior_profile", &"maintenance_v2")
	outdoor.add_child(building)
	manager.saved_instances["legacy"] = {"actors": []}
	await manager.enter(player,building,"legacy",42)
	check(manager.interior != null and not manager.interior is MaintenanceInterior,"Actor-only visited instance retains old generator")
	if manager.interior != null:
		check(manager.interior.layout == MazeLayout.generate(42),"Old seed rebuilds original geometry")
		check(manager.interior.entities.get_child_count() == 0,"Empty old instance does not restock")
		await manager.leave()
	await manager.enter(player,building,"fresh",43)
	check(manager.interior is MaintenanceInterior,"Fresh production profile selects v2")
	if manager.interior != null:
		await manager.leave()
	var memory: Dictionary = manager.saved_instances.get("fresh",{})
	check(memory.has("layout"),"New memory carries versioned manifest")
	if memory.has("layout"):
		manager.saved_instances["bad"] = memory.duplicate(true)
		manager.saved_instances.bad.layout.version = 999
		await manager.enter(player,building,"bad",43)
		check(manager.interior == null and manager.active_id.is_empty() and not manager.busy and not player.in_ui_mode,"Unsupported saved content restores outdoor controls")
		check(manager.saved_instances.bad.layout.version == 999,"Failed load does not silently reset stored progress")
	await process_frame
	outdoor.free()
	if failures.is_empty(): print("PASS: legacy geometry/empty loot, new profile dispatch, corrupt-version rollback and preserved source state")
	quit(0 if failures.is_empty() else 1)

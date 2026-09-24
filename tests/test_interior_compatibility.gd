extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	var checkpoint := root.get_node("Checkpoint")
	var fresh := {"layout": InteriorLayout.generate(91), "actors": [], "explored": []}
	var source := {"version": 3, "vehicles": [], "player": {"sentinel": 19}, "actors": [], "poi": {"v1": {"actors": []}, "v2": {"actors": [], "layout": {"version": 2, "profile": "maintenance_v2"}}, "fresh": fresh}}
	var original := source.duplicate(true)
	var upgraded: Dictionary = checkpoint._upgrade_checkpoint(source)
	check(source == original, "Migration does not mutate source checkpoint")
	check(upgraded.poi.size() == 1 and upgraded.poi.fresh == fresh and upgraded.player == source.player and upgraded.vehicles == source.vehicles, "Migration removes only known old POIs and preserves new/world state")
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
	building.set_meta("poi_interior_profile", &"bunker")
	outdoor.add_child(building)
	manager.saved_instances["legacy"] = {"actors": []}
	await manager.enter(player,building,"legacy",42)
	check(manager.interior != null,"Actor-only old instance replaced by bunker")
	if manager.interior != null:
		check(manager.interior.layout.version == 3,"Old geometry discarded")
		check(manager.interior.entities.get_child_count() == 0,"Empty old instance does not restock")
		await manager.leave()
	await manager.enter(player,building,"fresh",43)
	check(manager.interior is PoiInterior,"Fresh production profile selects v2")
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
	if failures.is_empty(): print("PASS: legacy removal/empty population, new profile dispatch, corrupt-version rollback and preserved source state")
	quit(0 if failures.is_empty() else 1)

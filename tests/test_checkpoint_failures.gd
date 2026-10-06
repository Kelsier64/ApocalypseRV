extends SceneTree
var failures: Array[String] = []
const PATH := "res://.godot/test-checkpoint-failures.save"
const WAIT = preload("res://tests/support/test_wait.gd")

class FaultFiles extends CheckpointFiles:
	var fault := ""
	func open_file(path: String, mode: int) -> FileAccess:
		if fault == "open": return null
		return super.open_file(path, mode)
	func store(file: FileAccess, data: Dictionary) -> Error:
		if fault == "write": return ERR_FILE_CANT_WRITE
		if fault == "corrupt": return super.store(file, {})
		return super.store(file, data)
	func copy_file(source: String, target: String) -> Error:
		if fault == "backup": return ERR_FILE_CANT_WRITE
		return super.copy_file(source, target)
	func rename_file(source: String, target: String) -> Error:
		if fault == "rename" and not target.ends_with(".bak"): return ERR_FILE_CANT_WRITE
		return super.rename_file(source, target)

class FailedInterior extends PoiInterior:
	func build(_seed: int, _saved: Dictionary = {}) -> bool:
		return false

class SlowInterior extends PoiInterior:
	func build(_seed: int, _saved: Dictionary = {}) -> bool:
		while not cancelled:
			await get_tree().process_frame
		return false

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	var world: Node3D = load("res://world/test_world.tscn").instantiate()
	# Disk faults and transactional rollback do not require seven terrain bands
	# on every staged load. Keep real terrain/navigation with a fixed fixture.
	var fixture_generator: Node = world.get_node("WorldGenerator")
	fixture_generator.world_seed = 42
	fixture_generator.profile = WorldProfile.new()
	fixture_generator.profile.chunks_ahead = 1
	fixture_generator.profile.chunks_behind = 1
	root.add_child(world)
	current_scene = world
	check(await world.wait_for_play(), "Production world becomes ready")
	world.play_ready = false
	check(not await world.wait_for_play(20), "Never-ready state times out instead of passing by frame count")
	world.play_ready = true
	var checkpoint: Node = root.get_node("Checkpoint")
	check(checkpoint.save_world(world, PATH), "Valid fixture writes")
	var saved: Dictionary = checkpoint.read_checkpoint(PATH)
	check(not saved.is_empty(), "Valid fixture reads")
	if saved.is_empty(): quit(1); return
	check(saved.player.get("body") == world.get_node("Player").body_state.capture(), "Checkpoint captures authoritative player body state")
	var wounded := saved.duplicate(true)
	wounded.player.body.present.left_leg = false
	wounded.player.body.present.right_arm = false
	check(checkpoint.write_checkpoint(PATH + ".body", wounded), "Dismembered checkpoint fixture writes")
	var wounded_roundtrip: Dictionary = checkpoint.read_checkpoint(PATH + ".body")
	check(not wounded_roundtrip.is_empty() and wounded_roundtrip.player.body == wounded.player.body, "Player limb state survives checkpoint serialization")
	var legacy_body := saved.duplicate(true)
	legacy_body.player.erase("body")
	check(checkpoint.validation_error(legacy_body).is_empty(), "Legacy checkpoint without body remains valid")
	for kind in ["missing_part", "unknown_part", "part_type", "body_version", "headless_alive"]:
		var bad_body := saved.duplicate(true)
		match kind:
			"missing_part": bad_body.player.body.present.erase("right_leg")
			"unknown_part": bad_body.player.body.present["tail"] = true
			"part_type": bad_body.player.body.present.left_arm = 1
			"body_version": bad_body.player.body.version = 2
			"headless_alive": bad_body.player.body.present.head = false
		check(checkpoint.validation_error(bad_body).begins_with("player.body"), "Reject malformed body " + kind + " before mutation")
	var headless_dead := saved.duplicate(true)
	headless_dead.player.health = 0.0
	headless_dead.player.body.present.head = false
	check(checkpoint.validation_error(headless_dead).is_empty(), "Dead headless player body is valid")
	var retired := saved.duplicate(true)
	var retired_scene := "res://enemies/retired_monster.tscn"
	retired.actors.append({"kind": "monster", "scene": retired_scene, "transform": Transform3D.IDENTITY, "health": 40.0})
	var old_layout := InteriorLayout.generate(42, 12)
	var old_content := {"version": 1, "cargo_id": "", "cargo_room": ""}
	retired.poi["retired-test"] = {"layout": old_layout, "actors": [{"id": "retired-poi", "scene": retired_scene, "transform": Transform3D.IDENTITY, "health": 30.0}], "explored": [], "content": old_content, "caches": []}
	var station: PoiDefinition = POIConfig.definition(&"gas_station")
	retired.outdoor_sites["retired-test"] = {"definition_id": "gas_station", "content_version": station.content_version, "loaded": false,
		"actors": [{"kind": "monster", "scene": retired_scene, "transform": Transform3D.IDENTITY, "health": 20.0}]}
	check(checkpoint.write_checkpoint(PATH + ".retired", retired), "Retired-monster fixture writes")
	check(checkpoint.read_checkpoint(PATH + ".retired").is_empty(), "Unknown retired scenes are rejected in v5 without migration")
	var bad_missing_prop := saved.duplicate(true)
	bad_missing_prop.actors[0].scene = "res://props/retired_prop.tscn"
	check(checkpoint.write_checkpoint(PATH + ".missing-prop", bad_missing_prop), "Missing-prop fixture writes")
	check(checkpoint.read_checkpoint(PATH + ".missing-prop").is_empty(), "Current schema rejects an unrelated missing Item")
	for kind in ["non_scene", "wrong_kind", "device_type", "nan", "singular", "slot", "profile", "physics", "poi", "service"]:
		var bad := saved.duplicate(true)
		match kind:
			"non_scene": bad.actors[0].scene = "res://project.godot"
			"wrong_kind": bad.actors[0].kind = "monster"
			"device_type": bad.vehicles[0].mounted_items[0].scene = "res://equipment/rv_side_panel.tscn"
			"nan": bad.player.transform.origin.x = NAN
			"singular": bad.player.transform.basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
			"slot": bad.player.slot = 6
			"profile": bad.profile.stop_spacing = "broken"
			"physics": bad.vehicles[0].mounted_items[0].physics = {"mode": 0}
			"poi": bad.poi = {"visited": {"actors": [42]}}
			"service": bad.vehicles[0].mounted_items[0].state.service["charging"] = 42
		check(not checkpoint.validation_error(bad).is_empty(), "Reject " + kind + " before mutation")
	var overflow := saved.duplicate(true)
	overflow.vehicles[0].materials[ItemNames.METAL_PARTS] = 10000
	check(checkpoint.validation_error(overflow).is_empty(), "Preserve legal material overflow")
	var empty := saved.duplicate(true)
	empty.player.items = []
	empty.player.slot = 5
	check(checkpoint.validation_error(empty).is_empty(), "Empty hotbar slot remains legal")
	var malformed_legacy := saved.duplicate(true)
	malformed_legacy.version = 1
	malformed_legacy.vehicles = [{"version": 3}]
	check(checkpoint.write_checkpoint(PATH + ".legacy", malformed_legacy), "Malformed legacy fixture writes")
	check(checkpoint.read_checkpoint(PATH + ".legacy").is_empty(), "Older checkpoint rejected without attempting migration")
	var bytes := FileAccess.get_file_as_bytes(PATH)
	var files := FaultFiles.new()
	checkpoint.file_operations = files
	for fault in ["open", "write", "rename", "backup", "corrupt"]:
		files.fault = fault
		check(not checkpoint.write_checkpoint(PATH, saved), fault + " failure reported")
		check(checkpoint.last_error.code == ("write" if fault == "corrupt" else fault), fault + " failure distinguished")
		check(FileAccess.get_file_as_bytes(PATH) == bytes, fault + " keeps previous save")
		check(not FileAccess.file_exists(PATH + ".tmp"), fault + " cleans temporary file")
	checkpoint.file_operations = CheckpointFiles.new()
	check(checkpoint.write_checkpoint(PATH, saved), "Successful replacement")
	check(FileAccess.get_file_as_bytes(PATH + ".bak") == bytes, "Previous valid save backed up")
	var second := saved.duplicate(true)
	var extra: Dictionary = second.vehicles[0].duplicate(true)
	extra.id += "-second"
	extra.engine_item = {}
	extra.items = []
	var replacements := {}
	for device in extra.mounted_items:
		replacements[device.state.id] = device.state.id + "-second"
	for device in extra.mounted_items:
		device.state.id = replacements[device.state.id]
		if device.support.kind == "item": device.support.id = replacements.get(device.support.id, device.support.id)
		elif device.support.kind in ["chassis", "structure"]: device.support.rv = extra.id
		if device.state.service.has("battery") and not device.state.service.battery.is_empty(): device.state.service.battery.id += "-second"
	for wheel in extra.wheels: wheel.id += "-second"
	second.vehicles.append(extra)
	var original: Chassis = world.get_node("NewRv/Chassis")
	var player: Node = world.get_node("Player")
	var player_pose: Transform3D = player.global_transform
	checkpoint.vehicle_applier = func(rv: Node3D, data: Dictionary) -> bool:
		return false if data.id.ends_with("-second") else VehicleSnapshot.apply(rv, data)
	checkpoint.pending = second
	var result: Dictionary = checkpoint.restore_world(world)
	check(not result.ok and checkpoint.last_error.field == "vehicles[1]", "Second vehicle failure is identified")
	check(is_instance_valid(original) and original.is_inside_tree(), "Failed restore keeps original vehicle")
	check(player.global_transform == player_pose and player.is_physics_processing(), "Failed restore keeps player and input")
	check(get_nodes_in_group(Groups.CHASSIS).size() == 1, "Failed staging leaks no vehicles")
	check(checkpoint.write_checkpoint(PATH + ".two", second), "Two vehicle fixture writes")
	check(not await checkpoint.load_world(world, PATH + ".two"), "Full load rejects failed second vehicle")
	check(current_scene == world and world.process_mode != Node.PROCESS_MODE_DISABLED, "Full load rollback restores old world")
	await process_frame
	check(get_nodes_in_group(Groups.CHASSIS).size() == 1, "Full load rollback frees staging groups")
	checkpoint.vehicle_applier = VehicleSnapshot.apply
	checkpoint.world_timeout_ms = 0
	var old_time: Dictionary = world.get_node("WorldClock").capture()
	check(not await checkpoint.load_world(world, PATH), "World readiness timeout aborts loading")
	check(current_scene == world and not checkpoint.loading, "Timed-out world leaves original playable")
	check(world.get_node("WorldClock").capture() == old_time, "Failed load does not advance original clock")
	checkpoint.world_timeout_ms = 60000
	var manager: PoiInstanceManager = world.get_node("PoiInstances")
	var building := Node3D.new()
	var return_point := Marker3D.new()
	return_point.name = "ReturnPoint"
	building.add_child(return_point)
	world.add_child(building)
	manager.interior_factory = func(): return FailedInterior.new()
	print("FAULT TEST: enter failed build")
	await manager.enter(player, building, "failure", 42)
	print("FAULT TEST: failed build returned")
	check(not manager.busy and manager.active_id.is_empty() and not player.in_ui_mode, "Build failure unlocks player")
	manager.interior_factory = func(): return SlowInterior.new()
	manager.transition_timeout_ms = 20
	print("FAULT TEST: enter timeout")
	await manager.enter(player, building, "timeout", 42)
	print("FAULT TEST: timeout returned")
	check(not manager.busy and manager.state == PoiInstanceManager.State.FAILED and not player.in_ui_mode, "Build timeout clears state")
	manager.transition_timeout_ms = 60000
	manager.enter(player, building, "cancel", 42)
	var first_operation := manager.operation
	manager.enter(player, building, "duplicate", 42)
	check(manager.operation == first_operation, "Repeated entry cannot start a second transition")
	await process_frame
	manager.cancel_transition()
	await process_frame
	check(not manager.busy and player.get_parent() == world and not player.in_ui_mode, "Explicit cancellation restores outdoor player")
	var health: float = player.current_player_health
	player.set_physics_process(false)
	player.current_player_health = 0
	await manager.enter(player, building, "death", 42)
	check(not manager.busy and not player.in_ui_mode, "Player death cancels entry")
	player.current_player_health = health
	player.set_physics_process(true)
	await process_frame
	check(not manager.get_children().any(func(child): return child is SubViewport), "Cancelled transitions release all viewports")
	check(await checkpoint.load_world(world, PATH), "Full load succeeds after previous failures")
	check(current_scene != world and current_scene.play_ready, "Only completed world becomes current")
	check(current_scene.get_node("WorldClock").capture() == saved.clock, "Staged world does not advance the saved clock")
	for vehicle in get_nodes_in_group(Groups.CHASSIS):
		if not current_scene.is_ancestor_of(vehicle): continue
		var restored := VehicleSnapshot.capture(vehicle)
		check(restored.materials == saved.vehicles[0].materials, "World transfer does not refund materials")
		check(restored.mounted_items.size() == saved.vehicles[0].mounted_items.size(), "World transfer retains equipment registry")
		for device in restored.mounted_items:
			var source: Array = saved.vehicles[0].mounted_items.filter(func(entry): return entry.state.id == device.state.id)
			check(source.size() == 1 and device.state.service == source[0].state.service, "World transfer preserves device service " + device.state.id)
	check(FileAccess.get_file_as_bytes(PATH) == bytes, "Loading never rewrites source")
	# Finish navigation work before destroying the restored procedural world.
	# A successful behavior check must also be able to shut down cleanly.
	if not await WAIT.retired_candidates(self, checkpoint):
		check(false, "Failed checkpoint staging retirement timed out within 60 seconds")
		quit(1)
		return
	var generator: Node = current_scene.get_node("WorldGenerator")
	generator.set_process(false)
	if not await WAIT.until(self, func() -> bool: return not generator.building):
		check(false, "Restored checkpoint terrain build timed out within 60 seconds")
		quit(1)
		return
	if not await WAIT.navigation_bakes_finished(self, current_scene):
		check(false, "Restored checkpoint navigation bake timed out within 60 seconds")
		quit(1)
		return
	await physics_frame
	await process_frame
	current_scene.free()
	await process_frame
	if failures.is_empty(): print("PASS: checkpoint schema, disk faults, second-vehicle rollback, full-world commit and POI failure recovery")
	quit(0 if failures.is_empty() else 1)

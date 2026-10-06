extends SceneTree
## Fixed structure ownership, typed support references and v4 disk rejection.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

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
	await physics_frame
	await process_frame
	var slots: Node = rv.get_node("StructureSlots")
	for part in rv.get_structures():
		check(part.definition != null, "Structure definition loaded: " + str(part.name))
	if not failures.is_empty():
		world.free()
		quit(1)
		return
	var saved := VehicleSnapshot.capture(rv)
	check(saved.version == 5 and saved.structures.size() == 12 and VehicleSnapshot.validate(saved), "V5 separates twelve fixed structures including three roof panels from Item")
	if saved.structures.size() != 12 or not VehicleSnapshot.validate(saved):
		world.free()
		quit(1)
		return
	for device in saved.mounted_items:
		check(SaveSceneCatalog.resolve(device.scene, "Item") != null and not device.state.service.has("mount_slot"), "Item snapshot contains only portable devices")
	check(SaveSceneCatalog.resolve("res://equipment/rv_side_panel.tscn", "Item") == null, "Structure cannot be injected into Item catalog")
	var wall_type: String = slots.panel("left_0").definition.type_id
	var door_type: String = slots.panel("right_1").definition.type_id
	check(wall_type != door_type, "Side wall and side door have distinct stable type IDs")
	for structure in saved.structures:
		match structure.slot:
			"front": structure.health = 37.0
			"left_2": structure.health = 0.0
			"left_0":
				structure.type = door_type
				structure.door_angles = [-0.3]
			"rear": structure.door_angles = [-0.2, 0.4]
			"roof_0": structure.health = 37.0
			"roof_1":
				structure.type = "rv_ceiling_hatch"
				structure.health = 40.0
			"roof_2": structure.health = 0.0
	# A destroyed rear panel cannot keep attached devices in the installed graph.
	saved.mounted_items = saved.mounted_items.filter(func(entry): return entry.support != {"kind": "structure", "rv": rv.persistent_id, "slot": "roof_2"})
	var light: Item = rv.get_node("CabinLightFront")
	var light_id := light.persistent_id
	var chained: Item = rv.get_node("Generator")
	chained.set_mount_support(light)
	var chain_id := chained.persistent_id
	for device in saved.mounted_items:
		if device.state.id == chain_id: device.support = {"kind": "item", "id": light_id}
		if device.state.id == light_id:
			device.support = {"kind": "structure", "rv": rv.persistent_id, "slot": "roof_1"}
			device.transform.origin = Vector3(0.5, 2.4405738, 0)
	check(VehicleSnapshot.validate(saved) and VehicleSnapshot.apply(rv, saved), "Restore accepts damaged panel, destroyed socket, swapped door and chained Item")
	var restored := VehicleSnapshot.capture(rv)
	check(restored.structures == saved.structures, "Structure types, durability, gaps and individual door angles roundtrip exactly")
	check(slots.occupant("left_2") == null and slots.panel("left_2").is_destroyed, "Destroyed slot stays empty after restore")
	check(slots.panel("left_0").definition.type_id == door_type, "Side door configuration is restored from slot definition")
	check(slots.panel("roof_1").definition.type_id == "rv_ceiling_hatch" and slots.occupant("roof_2") == null, "Mixed roof variants and an independently destroyed roof segment survive restore")
	var restored_light: Item
	var restored_chain: Item
	for device in rv.get_equipment():
		if device.persistent_id == light_id: restored_light = device
		if device.persistent_id == chain_id: restored_chain = device
	check(restored_light != null and restored_light.mount_support == slots.panel("roof_1"), "Roof segments restore before their supported Item")
	check(restored_chain != null and restored_chain.mount_support == restored_light, "Tagged Item support resolves chained device identity")
	for fault in ["duplicate_slot", "missing_slot", "unknown_type", "wrong_kind", "health_range", "door_angle", "door_direction", "support_cycle", "legacy_support"]:
		var bad := saved.duplicate(true)
		match fault:
			"duplicate_slot": bad.structures[1].slot = bad.structures[0].slot
			"missing_slot": bad.structures.pop_back()
			"unknown_type": bad.structures[0].type = "untrusted_type"
			"wrong_kind":
				for structure in bad.structures:
					if structure.slot == "floor":
						structure.type = wall_type
			"health_range": bad.structures[0].health = 999999.0
			"door_angle":
				for structure in bad.structures:
					if structure.slot == "rear": structure.door_angles = [INF, 0.0]
			"door_direction":
				for structure in bad.structures:
					if structure.slot == "rear": structure.door_angles = [0.2, -0.4]
			"destroyed_support": bad.mounted_items[0].support = {"kind": "structure", "rv": rv.persistent_id, "slot": "left_2"}
			"missing_support": bad.mounted_items[0].support = {"kind": "item", "id": "missing"}
			"support_cycle": bad.mounted_items[0].support = {"kind": "item", "id": bad.mounted_items[0].state.id}
			"legacy_support": bad.mounted_items[0].support = "chassis"
		check(not VehicleSnapshot.validate(bad) and not VehicleSnapshot.apply(rv, bad), "Reject " + fault + " before changing live state")
		check(VehicleSnapshot.capture(rv).structures == restored.structures, "Rejected " + fault + " leaves structures unchanged")
	var old_layout := saved.duplicate(true)
	old_layout.structures = old_layout.structures.filter(func(entry): return not entry.slot.begins_with("roof_"))
	old_layout.structures.append({"slot": "roof", "type": "rv_ceiling", "health": 0.0, "door_angles": []})
	check(old_layout.structures.size() == 10 and not VehicleSnapshot.validate(old_layout), "Single-roof v4 layout is rejected without silently splitting or healing it")
	slots.restore(old_layout.structures)
	check(not VehicleSnapshot.apply(rv, old_layout) and slots.snapshot() == restored.structures, "Rejected prior roof layout leaves all current panel types and gaps unchanged")
	var checkpoint: Node = root.get_node("Checkpoint")
	check(checkpoint.PATH == "user://rv_checkpoint_v5.save" and checkpoint.PATH + ".bak" == "user://rv_checkpoint_v5.save.bak", "Default v5 checkpoint and backup use new filenames")
	check(checkpoint.LEGACY_PATH == "user://rv_checkpoint_v4.save", "Prior v4 checkpoint remains a separate legacy path")
	var default_fixture := "res://.godot/default-checkpoint-" + InstanceIds.create()
	var current_path := default_fixture + "-v5.save"
	var legacy_path := default_fixture + "-legacy.save"
	check(checkpoint.read_default_checkpoint(current_path, legacy_path).is_empty() and checkpoint.last_error.code == "open", "No checkpoint at either default path reports a missing file")
	check(checkpoint.write_checkpoint(legacy_path, {"version": 4}), "Legacy default-path fixture writes without touching user saves")
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
	check(checkpoint.read_default_checkpoint(current_path, legacy_path).is_empty() and checkpoint.last_error.code == "version", "F9 with only the previous filename explains incompatible save format")
	check(checkpoint.error_message().contains("new run") and FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes, "F9 legacy detection preserves bytes and explains recovery")
	var current_data := {"version": 5, "vehicles": [restored], "actors": [], "seed": 12, "bands": [0], "poi": {},
		"player": {"items": [], "slot": 0, "health": 100.0, "transform": Transform3D.IDENTITY}}
	check(checkpoint.validation_error(current_data).is_empty() and checkpoint.write_checkpoint(current_path, current_data), "Current default-path fixture validates and writes")
	var malformed_dormant := current_data.duplicate(true)
	malformed_dormant["dormant_items"] = {0: [42]}
	check(checkpoint.validation_error(malformed_dormant) == "dormant_items.actor", "Malformed dormant actors reject without a script error")
	check(checkpoint.read_default_checkpoint(current_path, legacy_path) == current_data, "Existing v5 default takes precedence over preserved legacy filename")
	check(FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes, "Reading v5 also leaves the prior filename unchanged")
	var old_layout_data := current_data.duplicate(true)
	old_layout_data.vehicles = [old_layout]
	var old_layout_path := default_fixture + "-single-roof.save"
	check(checkpoint.write_checkpoint(old_layout_path, old_layout_data), "Old single-roof v4 fixture writes")
	var old_layout_bytes := FileAccess.get_file_as_bytes(old_layout_path)
	check(checkpoint.read_checkpoint(old_layout_path).is_empty() and checkpoint.last_error.code == "data", "Disk reader rejects old v4 roof layout before world restoration")
	check(FileAccess.get_file_as_bytes(old_layout_path) == old_layout_bytes, "Rejected single-roof checkpoint stays unchanged on disk")
	for version in [1, 2, 3, 4]:
		var path := "res://.godot/structure-checkpoint-v%d.save" % version
		check(checkpoint.write_checkpoint(path, {"version": version}), "Legacy fixture writes")
		var original := FileAccess.get_file_as_bytes(path)
		check(checkpoint.read_checkpoint(path).is_empty() and checkpoint.last_error.code == "version", "Checkpoint version %d requires new run" % version)
		check(checkpoint.error_message().contains("new run"), "Version rejection explains recovery")
		check(FileAccess.get_file_as_bytes(path) == original, "Rejected checkpoint is preserved byte for byte")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: fixed structure v5 snapshot, typed support graph, validation and preserved legacy saves")
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Fixed structure ownership, deck reversion and incompatible format rejection.
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
	check(saved.version == 5 and saved.structures.size() == 11 and VehicleSnapshot.validate(saved), "V5 separates eleven damageable structures including three roof panels from Item")
	check(RVStructureSlots.slot_info("floor").is_empty() and RVStructureSlots.definition_for("rv_floor") == null, "Fixed chassis deck is not a configurable structure")
	if saved.structures.size() != 11 or not VehicleSnapshot.validate(saved):
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
	# The narrowly compatible previous v5 layout retains every wall/roof value.
	var old_deck := restored.duplicate(true)
	old_deck.structures.append({"slot": "floor", "type": "rv_floor", "health": 57.0, "door_angles": []})
	for entry in old_deck.mounted_items:
		if entry.state.id == chain_id: entry.support = {"kind": "structure", "rv": old_deck.id, "slot": "floor"}
	var old_deck_original := old_deck.duplicate(true)
	var converted := VehicleSnapshot.upgrade(old_deck)
	check(VehicleSnapshot.validate(converted) and converted.get("structures", []) == restored.structures, "Deck reversion retains damaged walls, roof variants, gaps and door angles")
	check(old_deck == old_deck_original, "Compatible deck conversion never mutates the source dictionary")
	check(VehicleSnapshot.apply(rv, old_deck), "Previous twelve-slot v5 snapshot restores through fixed-deck conversion")
	var converted_roundtrip := VehicleSnapshot.capture(rv)
	check(converted_roundtrip.structures == restored.structures, "Compatible deck restoration preserves all eleven surviving socket states")
	for entry in converted_roundtrip.mounted_items:
		if entry.state.id == chain_id:
			check(entry.support == {"kind": "chassis", "rv": old_deck.id}, "Former floor attachment roundtrips as a chassis mount")
	var broken_deck := old_deck.duplicate(true)
	broken_deck.structures[-1].health = 0.0
	check(VehicleSnapshot.upgrade(broken_deck).is_empty() and not VehicleSnapshot.apply(rv, broken_deck), "Destroyed former floor cannot retain installed attachments")
	for entry in broken_deck.mounted_items:
		if entry.state.id == chain_id: entry.support = {"kind": "chassis", "rv": broken_deck.id}
	check(VehicleSnapshot.upgrade(broken_deck).get("structures", []) == restored.structures and VehicleSnapshot.apply(rv, broken_deck), "Destroyed former floor without attachments converts to the fixed chassis deck")
	for fault in ["duplicate_floor", "missing_floor", "floor_type", "floor_health", "floor_nan", "floor_angles", "floor_fields", "bad_roof", "floor_support_rv", "floor_support_fields", "malformed_item"]:
		var invalid_deck := old_deck.duplicate(true)
		match fault:
			"duplicate_floor": invalid_deck.structures[0] = invalid_deck.structures[-1].duplicate(true)
			"missing_floor": invalid_deck.structures[-1].slot = "unknown"
			"floor_type": invalid_deck.structures[-1].type = "rv_ceiling"
			"floor_health": invalid_deck.structures[-1].health = 121.0
			"floor_nan": invalid_deck.structures[-1].health = NAN
			"floor_angles": invalid_deck.structures[-1].door_angles = [0.0]
			"floor_fields": invalid_deck.structures[-1]["unexpected"] = true
			"bad_roof": invalid_deck.structures[8].health = 999999.0
			"floor_support_rv", "floor_support_fields":
				for entry in invalid_deck.mounted_items:
					if entry.state.id == chain_id:
						if fault == "floor_support_rv": entry.support.rv = "another-rv"
						else: entry.support["unexpected"] = true
			"malformed_item": invalid_deck.mounted_items = [42]
		var before_rejection := VehicleSnapshot.capture(rv)
		check(VehicleSnapshot.upgrade(invalid_deck).is_empty() and not VehicleSnapshot.apply(rv, invalid_deck), "Reject malformed twelve-slot conversion: " + fault)
		check(VehicleSnapshot.capture(rv) == before_rejection, "Rejected deck conversion has no live-state side effect: " + fault)
	for fault in ["duplicate_slot", "missing_slot", "unknown_type", "wrong_kind", "health_range", "door_angle", "door_direction", "missing_support", "wrong_rv_support", "removed_floor_support", "support_cycle", "legacy_support"]:
		var bad := saved.duplicate(true)
		match fault:
			"duplicate_slot": bad.structures[1].slot = bad.structures[0].slot
			"missing_slot": bad.structures.pop_back()
			"unknown_type": bad.structures[0].type = "untrusted_type"
			"wrong_kind":
				for structure in bad.structures:
					if structure.slot == "roof_0":
						structure.type = wall_type
			"health_range": bad.structures[0].health = 999999.0
			"door_angle":
				for structure in bad.structures:
					if structure.slot == "rear": structure.door_angles = [INF, 0.0]
			"door_direction":
				for structure in bad.structures:
					if structure.slot == "rear": structure.door_angles = [0.2, -0.4]
			"missing_support": bad.mounted_items[0].support = {"kind": "item", "id": "missing"}
			"wrong_rv_support": bad.mounted_items[0].support = {"kind": "chassis", "rv": "another-rv"}
			"removed_floor_support": bad.mounted_items[0].support = {"kind": "structure", "rv": rv.persistent_id, "slot": "floor"}
			"support_cycle": bad.mounted_items[0].support = {"kind": "item", "id": bad.mounted_items[0].state.id}
			"legacy_support": bad.mounted_items[0].support = "chassis"
		check(not VehicleSnapshot.validate(bad) and not VehicleSnapshot.apply(rv, bad), "Reject " + fault + " before changing live state")
		check(VehicleSnapshot.capture(rv).structures == restored.structures, "Rejected " + fault + " leaves structures unchanged")
	var fallback := saved.duplicate(true)
	for entry in fallback.mounted_items:
		if entry.state.id == light_id: entry.support = {"kind": "structure", "rv": rv.persistent_id, "slot": "left_2"}
	check(VehicleSnapshot.validate(fallback) and VehicleSnapshot.apply(rv, fallback), "Known destroyed socket retains the current Item fallback restoration rule")
	var fallen_ids: Array[String] = []
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Item and actor.persistent_id in [light_id, chain_id]:
			check(not actor.is_fixed and not actor.freeze, "Destroyed support drops direct and chained Item instead of reviving the structure")
			fallen_ids.append(actor.persistent_id)
			actor.free()
	check(fallen_ids.size() == 2 and slots.occupant("left_2") == null, "Fallback preserves both Item identities and the destroyed wall gap")
	check(VehicleSnapshot.apply(rv, saved), "Normal support graph can be restored after observing fallback")
	var old_layout := saved.duplicate(true)
	old_layout.structures = old_layout.structures.filter(func(entry): return not entry.slot.begins_with("roof_"))
	old_layout.structures.append({"slot": "roof", "type": "rv_ceiling", "health": 0.0, "door_angles": []})
	check(old_layout.structures.size() == 9 and not VehicleSnapshot.validate(old_layout), "Single-roof layout is rejected without silently splitting or healing it")
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
	var deck_data := current_data.duplicate(true)
	deck_data.vehicles = [old_deck]
	var deck_source := deck_data.duplicate(true)
	var deck_path := default_fixture + "-old-deck.save"
	check(checkpoint.write_checkpoint(deck_path, deck_data), "Previous twelve-slot v5 disk fixture writes")
	var deck_bytes := FileAccess.get_file_as_bytes(deck_path)
	var read_deck: Dictionary = checkpoint.read_checkpoint(deck_path)
	check(not read_deck.is_empty() and read_deck.get("vehicles", []) == [converted], "Checkpoint reader converts only the former floor and mount references")
	check(checkpoint._upgrade_checkpoint(deck_data).get("vehicles", []) == [converted] and deck_data == deck_source, "Checkpoint normalization retains its input dictionary")
	check(FileAccess.get_file_as_bytes(deck_path) == deck_bytes, "Reading a compatible old deck leaves source save bytes unchanged")
	var invalid_deck_data := deck_data.duplicate(true)
	invalid_deck_data.vehicles[0].structures[-1].health = -1.0
	var invalid_deck_path := default_fixture + "-invalid-deck.save"
	check(checkpoint.write_checkpoint(invalid_deck_path, invalid_deck_data), "Malformed previous-deck disk fixture writes")
	var invalid_deck_bytes := FileAccess.get_file_as_bytes(invalid_deck_path)
	check(checkpoint.read_checkpoint(invalid_deck_path).is_empty() and checkpoint.last_error.code == "data", "Malformed twelve-slot checkpoint rejects before restoration")
	check(FileAccess.get_file_as_bytes(invalid_deck_path) == invalid_deck_bytes, "Rejected malformed deck save remains byte-identical")
	var old_layout_data := current_data.duplicate(true)
	old_layout_data.vehicles = [old_layout]
	var old_layout_path := default_fixture + "-single-roof.save"
	check(checkpoint.write_checkpoint(old_layout_path, old_layout_data), "Old single-roof layout fixture writes")
	var old_layout_bytes := FileAccess.get_file_as_bytes(old_layout_path)
	check(checkpoint.read_checkpoint(old_layout_path).is_empty() and checkpoint.last_error.code == "data", "Disk reader rejects old single-roof layout before world restoration")
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

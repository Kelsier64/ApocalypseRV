extends SceneTree
## Canonical weapon ownership, subtype boundaries and the v5 disk/streaming path.
const SAVE_PATH := "res://.godot/test-pistol-persistence.save"
var failures: Array[String] = []

class SiteOwner extends Node3D:
	var outdoor_sites: Dictionary = {}
	var field: WorldField

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func find_item(container: Node, identity: String) -> Item:
	for actor in container.get_children():
		if actor is Item and actor.persistent_id == identity and not actor.is_queued_for_deletion(): return actor
	return null

func validate_counts(scene: String, subtype: String, field: String, minimum: int, maximum: int) -> void:
	var valid := {"id": "validation-fixture", "condition": 100.0, subtype: {field: minimum}}
	check(ItemState.valid(scene, valid), "Subtype accepts its minimum: " + subtype)
	valid[subtype][field] = maximum
	check(ItemState.valid(scene, valid), "Subtype accepts its maximum: " + subtype)
	for value in [minimum - 1, maximum + 1, 1.0, NAN, INF, "1", true, null]:
		valid[subtype][field] = value
		check(not ItemState.valid(scene, valid), "Subtype rejects invalid count %s: %s" % [str(value), subtype])
	valid[subtype] = {field: minimum, "untrusted": 1}
	check(not ItemState.valid(scene, valid), "Subtype rejects unexpected data: " + subtype)
	valid[subtype] = minimum
	check(not ItemState.valid(scene, valid), "Subtype rejects scalar payload: " + subtype)
	valid.erase(subtype)
	check(not ItemState.valid(scene, valid), "New weapon scene requires its subtype: " + subtype)
	valid[subtype] = {field: minimum}
	check(not ItemState.valid("res://props/scrap.tscn", valid), "Old scene rejects weapon subtype: " + subtype)

func _run() -> void:
	validate_counts(PistolRules.PISTOL_SCENE, "pistol", "loaded_rounds", 0, 12)
	validate_counts(PistolRules.AMMO_SCENE, "ammo", "rounds", 1, 24)
	check(ItemState.valid("res://props/scrap.tscn", {"id": "old-scrap", "condition": 57.0}), "Existing v5 Item without weapon fields still validates")
	check(not ItemState.valid(PistolRules.PISTOL_SCENE, {"id": "mixed", "condition": 100.0, "pistol": {"loaded_rounds": 5}, "ammo": {"rounds": 4}}), "Pistol rejects ammo subtype")
	check(not ItemState.valid(PistolRules.AMMO_SCENE, {"id": "mixed", "condition": 100.0, "pistol": {"loaded_rounds": 5}, "ammo": {"rounds": 4}}), "Ammo rejects pistol subtype")
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(0, 2, 100)
	player.set_physics_process(false)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	shell.position = Vector3(0, 2, 100)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.stored_items.clear()
	await physics_frame
	var container := WorldEntities.get_container(world)
	check(not player.add_item(ItemNames.PISTOL, false, PistolRules.PISTOL_SCENE, {"pistol": {"loaded_rounds": 1.5}}), "New item grant rejects fractional magazine before restoring a node")
	check(not player.add_item(ItemNames.PISTOL_AMMO, false, PistolRules.AMMO_SCENE, {"ammo": {"rounds": 0}}), "New item grant rejects an empty ammo box")
	check(not player.add_item(ItemNames.WHEEL, false, "res://props/wheel.tscn", {"pistol": {"loaded_rounds": 5}}) and player.inventory.items.is_empty(), "New item grant rejects weapon subtype on a wheel without creating inventory ownership")
	var pistol: Item = load(PistolRules.PISTOL_SCENE).instantiate()
	container.add_child(pistol)
	pistol.freeze = true
	pistol.position = player.position + Vector3(1, 0, 0)
	var pistol_id := pistol.persistent_id
	check(pistol.capture_item_state().pistol.loaded_rounds == 12, "New pistol starts loaded")
	pistol.set("loaded_rounds", 5)
	check(pistol.pickup(player).contains("已拾取"), "Real pistol pickup succeeds")
	await process_frame
	check(player.inventory.active_item().state.id == pistol_id and player.inventory.active_item().state.pistol.loaded_rounds == 5, "Pickup preserves identity and partial magazine")
	player.drop_item()
	await process_frame
	var dropped := find_item(container, pistol_id)
	check(dropped != null and dropped.capture_item_state().pistol.loaded_rounds == 5 and player.inventory.items.is_empty(), "Drop creates one world owner with the same magazine")
	if dropped == null:
		world.free()
		quit(1)
		return
	dropped.freeze = true
	check(dropped.pickup(player).contains("已拾取"), "Dropped pistol can be picked up")
	await process_frame
	check(rv.store_player_item(player, 0), "Pistol enters shared vehicle storage")
	check(rv.stored_items.size() == 1 and rv.stored_items[0].state.id == pistol_id and rv.stored_items[0].state.pistol.loaded_rounds == 5, "Storage retains the single canonical pistol")
	for index in range(PlayerInventory.MAX_SLOTS): player.add_item(ItemNames.WHEEL, false, "res://props/wheel.tscn")
	var stored_before := rv.stored_items.duplicate(true)
	check(not rv.take_stored_item(player, 0) and rv.stored_items == stored_before, "Full backpack refuses withdrawal without mutating storage")
	var refused: Item = load(PistolRules.AMMO_SCENE).instantiate()
	container.add_child(refused)
	refused.freeze = true
	refused.set("rounds", 7)
	var refused_before := refused.capture_item_state()
	check(not refused.pickup(player).contains("已拾取") and refused.capture_item_state() == refused_before and not refused.is_queued_for_deletion(), "Full backpack leaves ammo identity and count in world")
	refused.free()
	player.inventory.items.clear()
	player.refresh_inventory()
	check(rv.take_stored_item(player, 0), "Pistol leaves vehicle storage")
	check(player.inventory.active_item().state.id == pistol_id and player.inventory.active_item().state.pistol.loaded_rounds == 5, "Withdrawal preserves partial magazine")
	# Dormant site restoration must use saved contents rather than fresh markers.
	var profile := WorldProfile.new()
	profile.generation_version = 7
	var owner := SiteOwner.new()
	owner.field = WorldField.new(42, profile)
	world.add_child(owner)
	var site := owner.field.stop(0)
	var chunk := Node3D.new()
	owner.add_child(chunk)
	POISpawner.new().spawn_site(site, chunk)
	var ammo: Item = load(PistolRules.AMMO_SCENE).instantiate()
	container.add_child(ammo)
	ammo.freeze = true
	ammo.global_position = site.building * Vector3(7.2, 0.2, 5.3)
	ammo.set("rounds", 9)
	var ammo_id := ammo.persistent_id
	owner.outdoor_sites[site.id] = {"definition_id": "starting_shelter", "content_version": POIConfig.definition(&"starting_shelter").content_version, "loaded": true, "actors": []}
	WalkInSites.deactivate(owner, site)
	check(owner.outdoor_sites[site.id].actors.size() == 1 and owner.outdoor_sites[site.id].actors[0].state.ammo.rounds == 9, "Streaming captures only the remaining partial ammo box")
	var stored_ammo: Item = load(PistolRules.AMMO_SCENE).instantiate()
	container.add_child(stored_ammo)
	stored_ammo.freeze = true
	stored_ammo.global_position = player.global_position
	stored_ammo.set("rounds", 13)
	var stored_id := stored_ammo.persistent_id
	check(stored_ammo.pickup(player).contains("已拾取"), "Second partial ammo box enters inventory")
	await process_frame
	check(rv.store_player_item(player, 1), "Partial ammo box enters vehicle storage")
	var checkpoint := root.get_node("Checkpoint")
	var data := {"version": 5, "generation_version": 7, "world_id": "shelter", "start_state": {"version": 1, "phase": "preparing"},
		"seed": 42, "bands": [0], "generated_bands": [0], "outdoor_sites": owner.outdoor_sites.duplicate(true),
		"poi": {}, "actors": [], "vehicles": [VehicleSnapshot.capture(rv)],
		"player": {"items": player.inventory.items.duplicate(true), "slot": 0, "health": 100.0, "transform": player.global_transform}}
	check(checkpoint.validation_error(data).is_empty(), "v5 weapon ownership snapshot validates")
	check(checkpoint.write_checkpoint(SAVE_PATH, data), "Weapon snapshot writes to disk")
	var saved: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(not saved.is_empty(), "Weapon snapshot validates when read from disk")
	if not saved.is_empty():
		check(saved.version == 5 and saved.player.items[0].state.id == pistol_id and saved.player.items[0].state.pistol.loaded_rounds == 5, "Disk preserves carried pistol identity and magazine without a format bump")
		player.restore_checkpoint_state(saved.player)
		check(await VehicleSnapshot.apply(rv, saved.vehicles[0]), "Saved vehicle applies through the production restore contract")
		check(rv.stored_items.size() == 1 and rv.stored_items[0].state.id == stored_id and rv.stored_items[0].state.ammo.rounds == 13, "Disk restores stored ammo identity and partial count")
		owner.outdoor_sites = saved.outdoor_sites.duplicate(true)
		WalkInSites.activate(owner, site, chunk)
		var returned := find_item(container, ammo_id)
		check(returned != null and returned.capture_item_state().ammo.rounds == 9, "Streaming restores partial ammo with its original identity")
		check(container.get_child_count() == 1, "Previously visited shelter receives no new pistol or ammo")
		var duplicate := saved.duplicate(true)
		duplicate.player.items.append(saved.player.items[0].duplicate(true))
		check(checkpoint.validation_error(duplicate) == "item.id.duplicate", "Duplicate weapon ownership rejected")
		var malformed := saved.duplicate(true)
		malformed.player.items[0].state.pistol.loaded_rounds = NAN
		check(not checkpoint.validation_error(malformed).is_empty(), "Corrupt weapon checkpoint rejected before restore")
		var old := saved.duplicate(true)
		old.player.items.clear()
		old.vehicles[0].items.clear()
		old.outdoor_sites[site.id].actors.clear()
		check(checkpoint.write_checkpoint(SAVE_PATH + ".old", old) and not checkpoint.read_checkpoint(SAVE_PATH + ".old").is_empty(), "Existing v5 checkpoint with no weapon records remains readable")
		WalkInSites.deactivate(owner, site)
		owner.outdoor_sites = old.outdoor_sites.duplicate(true)
		WalkInSites.activate(owner, site, chunk)
		check(container.get_child_count() == 0, "Old emptied shelter record remains empty with new assets installed")
	world.free()
	if failures.is_empty(): print("PASS: pistol/ammo strict state, pickup/drop/storage identity, disk and dormant site round trip without refill")
	quit(0 if failures.is_empty() else 1)

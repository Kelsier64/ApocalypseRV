extends Node
## Main-world checkpoint. Serialized Variants contain no objects or executable code.
const VERSION := 6
const PATH := "user://rv_checkpoint_v6.save"
const WORLD_SCENE := "res://world/main_world.tscn"
const ROUTE_PRESSURE = preload("res://world/deviation_pressure.gd")
const REAR_WRECK_LAYOUT = preload("res://world/starting_shelter/rear_wreck_layout.gd")
var pending: Dictionary = {}
var message: String = ""
var label: Label
var last_error: Dictionary = {}
var loading := false
var world_timeout_ms := 60000
# Injectable storage/application boundaries for controlled failure tests.
var file_operations: RefCounted = CheckpointFiles.new()
var vehicle_applier: Callable = VehicleSnapshot.apply

func _fail(code: String, field := "", detail := "") -> bool:
	last_error = {"code": code, "field": field, "detail": detail}
	print("CHECKPOINT FAILURE: ", last_error)
	return false

func error_message() -> String:
	if last_error.get("code", "") == "motion": return last_error.get("detail", "")
	match last_error.get("code", ""):
		"state": return "Cannot save/load: return outdoors, finish interaction and wait for terrain"
		"preview": return "Confirm or cancel Item placement before saving"
		"open": return "Cannot open checkpoint; check the save folder permissions"
		"write": return "Cannot write checkpoint; check free disk space and permissions"
		"rename", "backup": return "Cannot replace checkpoint; close programs locking the save file and retry"
		"version": return "This checkpoint is incompatible; start a new run"
		"timeout": return "World preparation timed out; current world retained"
		_: return "Checkpoint rejected at %s; current world retained" % last_error.get("field", "data")

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	label = Label.new()
	label.position = Vector2(24, 280)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	layer.add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_tree().get_nodes_in_group(Groups.PLAYER).any(func(player): return player.get("settings_open") == true):
		return
	var world := get_tree().current_scene
	# The F6 orientation playground inherits the complete production world;
	# its saves still restore the trusted main scene, without review cameras.
	if world == null or world.scene_file_path not in [WORLD_SCENE, "res://tests/orientation_playground.tscn"]:
		return
	if loading: return
	if event.physical_keycode == KEY_F6:
		message = "Checkpoint saved" if save_world(world, PATH) else error_message()
	elif event.physical_keycode == KEY_F9:
		load_world.call_deferred(world, PATH)
		return
	label.text = message

func save_world(world: Node, path: String) -> bool:
	var data := capture_world(world)
	if data.is_empty(): return false
	return write_checkpoint(path, data)

func capture_world(world: Node, include_retry := true, allow_tutorial_ui := false) -> Dictionary:
	last_error = {}
	if loading:
		_fail("state")
		return {}
	var start_run := world.get_node_or_null("StartRun")
	if start_run == null:
		_fail("state", "start_state")
		return {}
	if start_run != null and not start_run.save_block_reason().is_empty():
		_fail("motion", "start_state", start_run.save_block_reason())
		return {}
	var manager: Node = world.get_node_or_null("PoiInstances")
	var generator: Node = world.get_node_or_null("WorldGenerator")
	var player: Node = world.get_node_or_null("Player")
	if manager == null or generator == null or player == null or manager.busy or not manager.active_id.is_empty() or generator.building:
		_fail("state")
		return {}
	if player.has_method("is_grabbed") and player.is_grabbed():
		_fail("motion", "player", "Player is grabbed")
		return {}
	for monster in get_tree().get_nodes_in_group(Groups.MONSTERS):
		if world.is_ancestor_of(monster) and WorldEntities.same_world(player, monster) and monster.has_method("can_save") and not monster.can_save():
			_fail("motion", "monster", "Monster grab or execution is active")
			return {}
	# Actors are committed by navigation publication, after terrain building.
	# Saving in that interval would persist generated_bands without its Rakers.
	if generator.active_chunks.any(func(entry): return not entry.node.navigation_ready):
		_fail("state")
		return {}
	generator._spawn_giant_segments(player.global_position)
	# An open construction terminal puts the operator in UI mode. Report the
	# vehicle's concrete blocker before the generic player interaction gate.
	var matching_vehicles: Array[Node] = []
	for rv in get_tree().get_nodes_in_group(Groups.CHASSIS):
		# A successfully replaced world remains queued until the end of the frame.
		# Its RVs share this World3D but do not belong to the requested snapshot.
		if world.is_ancestor_of(rv) and WorldEntities.same_world(player, rv):
			var reason: String = rv.save_block_reason()
			if not reason.is_empty():
				_fail("motion", "vehicle", reason)
				return {}
			matching_vehicles.append(rv)
	if player.has_method("is_placing_equipment") and player.is_placing_equipment():
		_fail("preview")
		return {}
	if player.get_player_mode() != player.PlayerMode.NORMAL and not (allow_tutorial_ui and not include_retry and _orientation_ui_capture_allowed(world, player, start_run)):
		_fail("state")
		return {}
	# A carried articulated body may have advanced since the previous frame.
	# Commit its live pose to its single inventory owner before serialization.
	if player.has_method("_sync_held_item_state"): player._sync_held_item_state()
	var vehicles: Array[Dictionary] = []
	for rv in matching_vehicles:
		var state := VehicleSnapshot.capture(rv)
		if state.is_empty():
			_fail("state")
			return {}
		vehicles.append(state)
	var actors: Array[Dictionary] = []
	_collect_actors(world, actors)
	var bands: Array[int] = []
	for chunk in generator.active_chunks:
		bands.append(chunk.index)
	var profile_data := {}
	for property in generator.profile.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not generator.profile.get(property.name) is Object:
			profile_data[property.name] = generator.profile.get(property.name)
	var data := {"generation_version": generator.profile.generation_version, "profile": profile_data, "version": VERSION, "seed": generator.world_seed, "bands": bands, "vehicles": vehicles,
		"actors": actors, "poi": manager.saved_instances.duplicate(true),
		"player": {"transform": player.global_transform, "items": player.inventory.items.duplicate(true),
		"slot": player.inventory.active_slot, "health": player.current_player_health,
		"stamina": player.current_stamina, "stamina_exhausted": player.stamina_exhausted,
		"crouching": player.is_crouching(),
		"body": player.body_state.capture()}}
	data["outdoor_sites"] = generator.outdoor_sites.duplicate(true)
	data["dormant_items"] = generator.dormant_items.duplicate(true)
	data["destroyed_trees"] = generator.destroyed_trees.duplicate()
	data["generated_bands"] = generator.generated_bands.duplicate()
	data["generated_giant_segments"] = generator.generated_giant_segments.duplicate()
	# Keep the plan when its rear chunk is unloaded; returning must rebuild
	# precisely the same wrecks rather than roll against a new actor footprint.
	data["rear_wreck_layout"] = generator.rear_wreck_layout.duplicate(true)
	var pressure := world.get_node_or_null("DeviationPressure")
	if pressure != null: data["route_pressure"] = pressure.capture()
	data["world_id"] = "shelter"
	data["start_state"] = start_run.capture(include_retry)
	var clock := world.get_node_or_null("WorldClock") as WorldClock
	if clock != null:
		data["clock"] = clock.capture()
		data["weather"] = clock.weather.capture()
	var field := validation_error(data)
	if not field.is_empty():
		_fail("data", field)
		return {}
	return data

func _orientation_ui_capture_allowed(world: Node, player: Node, start_run: Node) -> bool:
	# Retry entrances may capture a settled native transaction while its read
	# interface remains open. UI is never serialized and manual saves keep their
	# ordinary interaction gate; all job/vehicle/placement checks run above.
	if start_run == null or start_run.phase != "preparing" or player.get("settings_open") == true or player.get_player_mode() != player.PlayerMode.UI: return false
	var generator := world.get_node_or_null("WorldGenerator")
	var tutorial := start_run.get_node_or_null("Tutorial")
	if generator == null or generator.profile.generation_version != 15 or tutorial == null or tutorial.get("status") != "active": return false
	var item_scripts := ["res://equipment/tablet_screen.gd", "res://equipment/training_terminal.gd"]
	for item in get_tree().get_nodes_in_group(Groups.ITEMS):
		if not world.is_ancestor_of(item) or not WorldEntities.same_world(world, item) or item.is_queued_for_deletion(): continue
		var script: Script = item.get_script()
		if script == null or script.resource_path not in item_scripts or item.get("current_user") != player: continue
		var ui: Node = item.get("ui_instance")
		if is_instance_valid(ui) and ui.get("visible") == true: return true
	for reader in player.get_children():
		var script: Script = reader.get_script()
		if script == null or script.resource_path != "res://equipment/training_terminal_reader.gd" or reader.get("current_user") != player or reader.is_queued_for_deletion(): continue
		var ui: Node = reader.get("ui_instance")
		if is_instance_valid(ui) and ui.get("visible") == true and reader.has_method("_user_valid") and reader._user_valid(): return true
	return false

func _collect_actors(node: Node, result: Array[Dictionary]) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion() or child.is_in_group(Groups.CHASSIS) or child.is_in_group(Groups.PLAYER): continue
		var saved := WorldActorSnapshot.capture(child)
		if not saved.is_empty(): result.append(saved)
		elif not (child is Item or child is Monster): _collect_actors(child, result)

func write_checkpoint(path: String, data: Dictionary) -> bool:
	last_error = {}
	var result: Dictionary = file_operations.write(path, data)
	if not result.ok: return _fail(result.code, path, str(result.get("error", "")))
	last_error = {}
	return true

func read_checkpoint(path: String) -> Dictionary:
	last_error = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("open", path, str(FileAccess.get_open_error()))
		return {}
	if file.get_length() > CheckpointSchema.MAX_BYTES:
		file.close()
		_fail("data", "file.size")
		return {}
	var data: Variant = file.get_var(false)
	var read_error := file.get_error()
	file.close()
	if read_error != OK or not data is Dictionary or not CheckpointSchema.bounded(data, 0, [CheckpointSchema.MAX_ENTRIES]):
		_fail("data", "file", str(read_error))
		return {}
	if not data.get("version") is int or data.version != VERSION:
		_fail("version", "version")
		return {}
	var field := validation_error(data)
	if not field.is_empty():
		_fail("data", field)
		return {}
	return data

func validation_error(data: Dictionary) -> String:
	return _validation_error(data, true)

func _validation_error(data: Dictionary, allow_entry: bool) -> String:
	if not CheckpointSchema.bounded(data, 0, [CheckpointSchema.MAX_ENTRIES]): return "data.size/depth"
	if not data.get("version") is int or data.version != VERSION: return "version"
	if not data.has_all(["vehicles", "player", "actors", "seed", "bands", "poi", "profile", "generation_version", "generated_giant_segments", "route_pressure", "rear_wreck_layout", "world_id", "start_state", "clock", "weather", "dormant_items", "outdoor_sites", "destroyed_trees", "generated_bands"]): return "data.fields"
	if not data.vehicles is Array: return "vehicles"
	if not data.actors is Array: return "actors"
	if not data.player is Dictionary: return "player"
	if not data.bands is Array or data.bands.is_empty() or data.bands.size() > 256: return "bands"
	var seen := {}
	for band in data.bands:
		if not band is int or seen.has(band): return "bands"
		seen[band] = true
	if not data.seed is int: return "seed"
	if not data.profile is Dictionary: return "profile"
	var profile_error := CheckpointSchema.profile_error(data.profile)
	if not profile_error.is_empty(): return profile_error
	if not data.generation_version is int or data.generation_version != 15: return "generation_version"
	if data.profile.generation_version != data.generation_version: return "profile.generation_version"
	if not SlenderSpeakerSpawns.valid_ledger(data.generated_giant_segments): return "generated_giant_segments"
	if not ROUTE_PRESSURE.valid_state(data.route_pressure): return "route_pressure"
	if not REAR_WRECK_LAYOUT.valid_checkpoint(data): return "rear_wreck_layout"
	if not data.world_id is String or data.world_id != "shelter": return "world_id"
	var start_state: Variant = data.start_state
	if not start_state is Dictionary or not start_state.get("version") is int or start_state.version != 1: return "start_state.version"
	if not start_state.get("phase") is String or start_state.phase not in ["preparing", "started", "sealed"]: return "start_state.phase"
	if not StartRun.valid_bay_gates(start_state.get("bay_gates"), 1): return "start_state.bay_gates"
	if not start_state.has("tutorial"): return "start_state.tutorial"
	var tutorial_error := _tutorial_error(start_state.tutorial, allow_entry)
	if not tutorial_error.is_empty(): return "start_state.tutorial." + tutorial_error
	var phase_error := CheckpointSchema.orientation_phase_error(start_state)
	if not phase_error.is_empty(): return "start_state.tutorial." + phase_error
	if not WorldClock.valid_state(data.clock): return "clock"
	if not WorldWeather.valid_state(data.weather): return "weather"
	var player: Dictionary = data.player
	if not player.get("items") is Array: return "player.items"
	# Selection is a hotbar index, including empty slots, not an item index.
	if not player.get("slot") is int or player.slot < 0 or player.slot >= PlayerInventory.MAX_SLOTS: return "player.slot"
	if not VehicleSnapshot._number(player.get("health")) or player.health < 0 or player.health > 100: return "player.health"
	var body_error := CheckpointSchema.player_body_error(player)
	if not body_error.is_empty(): return body_error
	if not VehicleSnapshot._number(player.get("stamina")) or player.stamina < 0 or player.stamina > 100: return "player.stamina"
	if not player.get("stamina_exhausted") is bool: return "player.stamina_exhausted"
	if not player.get("crouching") is bool: return "player.crouching"
	if not CheckpointSchema.valid_transform(player.get("transform")): return "player.transform"
	for i in range(player.items.size()):
		if not VehicleSnapshot.valid_item(player.items[i]): return "player.items[%d]" % i
	var vehicle_ids := {}
	for i in range(data.vehicles.size()):
		var vehicle: Variant = data.vehicles[i]
		if not vehicle is Dictionary or not VehicleSnapshot.validate(vehicle): return "vehicles[%d]" % i
		if vehicle_ids.has(vehicle.id): return "vehicles[%d].id" % i
		vehicle_ids[vehicle.id] = true
	for i in range(data.actors.size()):
		var actor_error := WorldActorSnapshot.validation_error(data.actors[i], "actors[%d]" % i)
		if not actor_error.is_empty(): return actor_error
	var dormant: Variant = data.dormant_items
	if not dormant is Dictionary: return "dormant_items"
	var outdoor_graph: Array = data.actors.duplicate()
	for vehicle in data.vehicles: outdoor_graph.append_array(vehicle.mounted_items)
	for band in dormant:
		if not band is int or not dormant[band] is Array: return "dormant_items.band"
		for actor in dormant[band]:
			if not WorldActorSnapshot.validation_error(actor, "dormant_items.actor").is_empty() or actor.kind != "item": return "dormant_items.actor"
		outdoor_graph.append_array(dormant[band])
	var graph_error := WorldActorSnapshot.graph_error(outdoor_graph)
	if not graph_error.is_empty(): return graph_error
	var outdoor_error := WalkInSites.validation_error(data)
	if not TreeImpact.valid_ledger(data.destroyed_trees): return "destroyed_trees"
	if not outdoor_error.is_empty(): return outdoor_error
	var poi_error := CheckpointSchema.poi_error(data.poi)
	if not poi_error.is_empty(): return poi_error
	# Tutorial references are not Item owners. Retry worlds have their own
	# independently validated ownership domain and can reuse every live ID.
	var owned_data := data.duplicate()
	owned_data.erase("start_state")
	if not ItemState.unique_ids(owned_data, {}): return "item.id.duplicate"
	var orientation_error := _orientation_items_error(owned_data, data.start_state.tutorial)
	if not orientation_error.is_empty(): return "start_state.tutorial." + orientation_error
	return ""

func _orientation_items_error(owned_data: Dictionary, tutorial: Dictionary) -> String:
	# The course references one persistent Item owner, including a carried or
	# dormant terminal. A lost terminal is valid; retry will recover it later.
	var records: Array[Dictionary] = []
	_find_item_records(owned_data, tutorial.terminal_id, records)
	if not records.is_empty():
		var record := records[0]
		if record.get("scene", record.get("scene_path", "")) != "res://equipment/training_terminal.tscn": return "terminal_id"
		var terminal: Dictionary = record.get("state", {}).get("training_terminal", {})
		if terminal.get("version") != 2: return "terminal_id"
		if terminal.get("initialized", false) != tutorial.flags.boot_complete: return "flags.boot_complete"
	if not tutorial.workshop.configured: return ""
	# References may outlive consumed, recycled or destroyed Items. Any owner
	# that still exists must retain its actual Item type, wherever it is stored.
	var scenes := {"scrapper": "res://equipment/scrapper.tscn", "workbench": "res://equipment/crafting_station.tscn",
		"scrap_a": "res://props/scrap.tscn", "scrap_b": "res://props/scrap.tscn", "barrel": "res://props/oil_barrel.tscn",
		"spare": "res://props/wheel.tscn", "original_wheel": "res://props/wheel.tscn", "socket": "res://rv/battery_socket.tscn",
		"tablet": "res://equipment/tablet_screen.tscn", "fuel_port": "res://equipment/fuel_port.tscn"}
	var extra_scenes := {"battery": "res://props/battery.tscn", "engine_kit_a": "res://props/engine_repair_kit.tscn",
		"engine_kit_b": "res://props/engine_repair_kit.tscn", "barrel_b": "res://props/oil_barrel.tscn",
		"original_battery": ["res://props/battery.tscn", "res://props/battery_large.tscn"],
		"engine": ["res://props/engine_standard.tscn", "res://props/engine_upgraded.tscn"]}
	for letter in ["c", "d", "e", "f", "g", "h"]: extra_scenes["scrap_" + letter] = "res://props/scrap.tscn"
	for key in extra_scenes:
		scenes[key] = extra_scenes[key]
	for key in scenes:
		if not _orientation_item_scene(owned_data, tutorial.workshop.targets[key], scenes[key]): return "workshop.targets." + key
	for key in ["gasoline_id", "empty_can_id"]:
		var scene := "res://props/gas_can.tscn" if key == "gasoline_id" else "res://props/gas_can_empty.tscn"
		if not _orientation_item_scene(owned_data, tutorial.workshop[key], scene): return "workshop." + key
	return ""

func _orientation_item_scene(owned_data: Dictionary, identity: String, scene: Variant) -> bool:
	if identity.is_empty(): return true
	var records: Array[Dictionary] = []
	_find_item_records(owned_data, identity, records)
	var allowed: Array = scene if scene is Array else [scene]
	for record in records:
		if record.get("scene", record.get("scene_path", "")) not in allowed: return false
	return true

func _find_item_records(value: Variant, identity: String, result: Array[Dictionary]) -> void:
	if value is Dictionary:
		if value.get("state") is Dictionary and value.state.get("id") is String and value.state.id == identity:
			result.append(value)
		elif value.get("id") is String and value.id == identity:
			# Installed service parts own their state directly, without an Item
			# wrapper. Check these identities as well as loose/inventory forms.
			if value.has_all(["charge", "capacity", "scene_path"]):
				result.append({"scene": value.scene_path})
			elif value.has_all(["model", "health"]) and EngineState.valid(value, false):
				result.append({"scene": "res://props/engine_" + str(value.model) + ".tscn"})
			elif value.has_all(["installed", "health"]):
				result.append({"scene": "res://props/wheel.tscn"})
		for child in value.values(): _find_item_records(child, identity, result)
	elif value is Array:
		for child in value: _find_item_records(child, identity, result)

func _tutorial_error(value: Variant, allow_entry: bool) -> String:
	var state_error := CheckpointSchema.tutorial_error(value)
	if not state_error.is_empty(): return state_error
	if not value.has("entry_snapshot"): return ""
	if not allow_entry: return "entry_snapshot.nested"
	var entry: Variant = value.entry_snapshot
	if not entry is Dictionary: return "entry_snapshot"
	var entry_error := _validation_error(entry, false)
	if not entry_error.is_empty(): return "entry_snapshot." + entry_error
	var entry_tutorial: Dictionary = entry.start_state.tutorial
	for field in ["version", "stage", "terminal_id", "rv_id", "course"]:
		if entry_tutorial[field] != value[field]: return "entry_snapshot.tutorial." + field
	if entry_tutorial.workshop.targets != value.workshop.targets: return "entry_snapshot.tutorial.workshop.targets"
	for field in ["step", "configured"]:
		if entry_tutorial.workshop[field] != value.workshop[field]: return "entry_snapshot.tutorial.workshop." + field
	if entry_tutorial.status != "active": return "entry_snapshot.tutorial.status"
	return ""

func prepare_world(world: Node) -> void:
	if pending.is_empty(): return
	var clock := world.get_node_or_null("WorldClock") as WorldClock
	if clock != null:
		clock.restore(pending.clock)
		clock.weather.restore(pending.weather)
	world.get_node("Player").transform = pending.player.transform
	world.get_node("WorldGenerator").world_seed = pending.seed
	var profile := WorldProfile.new()
	for key in pending.profile:
		if key in profile and key != "terrain_half_width": profile.set(key, pending.profile[key])
	profile.generation_version = pending.generation_version
	world.get_node("WorldGenerator").profile = profile
	var start_run := world.get_node_or_null("StartRun")
	if start_run != null: start_run.restore(pending.start_state)
	world.get_node("WorldGenerator").restore_bands.assign(pending.bands)
	world.get_node("WorldGenerator").restoring_entities = true
	world.get_node("WorldGenerator").outdoor_sites = pending.outdoor_sites.duplicate(true)
	world.get_node("WorldGenerator").dormant_items = pending.dormant_items.duplicate(true)
	world.get_node("WorldGenerator").destroyed_trees = pending.destroyed_trees.duplicate()
	world.get_node("WorldGenerator").generated_bands.assign(pending.generated_bands)
	world.get_node("WorldGenerator").generated_giant_segments.assign(pending.generated_giant_segments)
	var generator := world.get_node("WorldGenerator")
	generator.rear_wreck_layout = pending.rear_wreck_layout.duplicate(true)
	generator.rear_wreck_exclusions.clear()
	if generator.rear_wreck_layout.is_empty(): generator.rear_wreck_exclusions.assign(REAR_WRECK_LAYOUT.exclusions_for_checkpoint(pending))
	var pressure := world.get_node_or_null("DeviationPressure")
	if pressure != null: pressure.restore(pending.route_pressure)

func restore_world(world: Node) -> Dictionary:
	if pending.is_empty(): return {"ok": true}
	var data := pending
	pending = {}
	var field := validation_error(data)
	if not field.is_empty():
		_fail("data", field)
		return {"ok": false, "error": last_error}
	# No awaits during actor staging/commit: old actors never simulate alongside new ones.
	# A separate World3D and entity domain contain physics and recycler side effects.
	var staging := SubViewport.new()
	staging.own_world_3d = true
	staging.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(staging)
	PhysicsServer3D.space_set_active(staging.find_world_3d().space, false)
	var domain := Node3D.new()
	domain.set_meta("entity_domain", true)
	staging.add_child(domain)
	var container := WorldEntities.get_container(domain)
	for i in range(data.vehicles.size()):
		var saved: Dictionary = data.vehicles[i]
		var rv: Node3D = SaveSceneCatalog.resolve("res://rv/chassis.tscn", "vehicle").instantiate()
		domain.add_child(rv)
		if not vehicle_applier.call(rv, saved):
			staging.free()
			_fail("apply", "vehicles[%d]" % i, saved.id)
			return {"ok": false, "error": last_error}
	var restored_actors: Array = []
	for saved in data.actors:
		restored_actors.append(WorldActorSnapshot.restore(saved, container))
	var old: Array[Node] = []
	_collect_removable(world, old)
	for actor in old:
		if is_instance_valid(actor): actor.free()
	var destination := WorldEntities.get_container(world)
	for actor in container.get_children(): WorldEntities.transfer(actor, destination)
	for rv in domain.get_children():
		if rv != container: WorldEntities.transfer(rv, world)
	staging.free()
	WorldActorSnapshot.restore_supports(data.actors, restored_actors, world)
	for chunk in world.get_node("WorldGenerator").active_chunks: world.get_node("WorldGenerator").restore_dormant_items(chunk.index)
	world.get_node("PoiInstances").saved_instances = data.poi.duplicate(true)
	world.get_node("Player").restore_checkpoint_state(data.player)
	world.get_node("WorldGenerator").restoring_entities = false
	world.get_node("WorldGenerator")._bind_giants()
	var start_run := world.get_node_or_null("StartRun")
	if start_run != null: start_run.apply_actor_state()
	message = "Checkpoint restored"
	label.text = message
	return {"ok": true}

func load_world(old_world: Node, path: String) -> bool:
	if loading: return false
	var data := read_checkpoint(path)
	if data.is_empty():
		message = error_message()
		label.text = message
		return false
	return await load_snapshot(old_world, data)

func load_snapshot(old_world: Node, data: Dictionary) -> bool:
	if loading: return false
	last_error = {}
	var manager: Node = old_world.get_node("PoiInstances")
	var player: Node = old_world.get_node("Player")
	if manager.busy or not manager.active_id.is_empty() or player.get_player_mode() != player.PlayerMode.NORMAL:
		_fail("state")
		message = error_message()
		label.text = message
		return false
	var field := validation_error(data)
	if not field.is_empty():
		_fail("data", field)
		message = error_message()
		label.text = message
		return false
	# A caller can retain or mutate its retry dictionary while preparation awaits.
	# The candidate must apply precisely the data that passed validation.
	data = data.duplicate(true)
	loading = true
	message = "Preparing checkpoint..."
	label.text = message
	var staging := SubViewport.new()
	staging.own_world_3d = true
	staging.render_target_update_mode = SubViewport.UPDATE_DISABLED
	staging.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(staging)
	PhysicsServer3D.space_set_active(staging.find_world_3d().space, false)
	var candidate: Node3D = load(WORLD_SCENE).instantiate()
	candidate.set_meta("checkpoint_staging", true)
	candidate.set_meta("entity_domain", true)
	pending = data
	prepare_world(candidate)
	pending = {}
	var previous_mode := old_world.process_mode
	old_world.process_mode = Node.PROCESS_MODE_DISABLED
	var old_space: RID = old_world.get_world_3d().space
	PhysicsServer3D.space_set_active(old_space, false)
	staging.add_child(candidate)
	var ready: bool = await candidate.wait_for_play(world_timeout_ms)
	var result := {"ok": false}
	if ready:
		pending = data
		result = restore_world(candidate)
	else:
		_fail("timeout", "world.ready_for_play")
	if result.ok:
		WorldEntities.transfer(candidate, get_tree().root)
		candidate.remove_meta("checkpoint_staging")
		get_tree().current_scene = candidate
		old_world.queue_free()
		candidate.get_node("Player").camera.make_current()
	else:
		old_world.process_mode = previous_mode
		message = error_message()
		label.text = message
	PhysicsServer3D.space_set_active(old_space, true)
	_retire_world(staging, candidate if not result.ok else null)
	loading = false
	return result.ok

func _retire_world(staging: SubViewport, candidate: Node) -> void:
	if candidate != null:
		_remove_gameplay_groups(candidate)
		for region in candidate.find_children("*", "NavigationRegion3D", true, false):
			# Outdoor bakes are detached from the live region until publication.
			var mesh: NavigationMesh = region.get_meta("pending_navigation_bake", region.navigation_mesh)
			while mesh != null and NavigationServer3D.is_baking_navigation_mesh(mesh):
				await get_tree().process_frame
	if is_instance_valid(staging): staging.queue_free()

func _remove_gameplay_groups(node: Node) -> void:
	for group in node.get_groups():
		if not str(group).begins_with("_"): node.remove_from_group(group)
	for child in node.get_children(): _remove_gameplay_groups(child)

func _collect_removable(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child.is_in_group(Groups.PLAYER): continue
		if child is Item or child is Monster or child.is_in_group(Groups.CHASSIS):
			result.append(child)
		else:
			_collect_removable(child, result)

func _unique_engine_ids(data: Dictionary) -> bool:
	return EngineState.unique_ids(data)

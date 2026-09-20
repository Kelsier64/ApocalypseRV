extends Node
## Main-world checkpoint. Serialized Variants contain no objects or executable code.
const VERSION := 3
const PATH := "user://rv_checkpoint.save"
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
	match last_error.get("code", ""):
		"state": return "Cannot save/load: return outdoors, finish interaction and wait for terrain"
		"open": return "Cannot open checkpoint; check the save folder permissions"
		"write": return "Cannot write checkpoint; check free disk space and permissions"
		"rename", "backup": return "Cannot replace checkpoint; close programs locking the save file and retry"
		"version": return "Unsupported checkpoint version"
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
	var world := get_tree().current_scene
	if world == null or world.scene_file_path != "res://world/test_world.tscn":
		return
	if loading: return
	if event.physical_keycode == KEY_F6:
		message = "Checkpoint saved" if save_world(world, PATH) else error_message()
	elif event.physical_keycode == KEY_F9:
		load_world.call_deferred(world, PATH)
		return
	label.text = message

func save_world(world: Node, path: String) -> bool:
	last_error = {}
	if loading: return _fail("state")
	var manager: Node = world.get_node_or_null("PoiInstances")
	var generator: Node = world.get_node_or_null("WorldGenerator")
	var player: Node = world.get_node_or_null("Player")
	if manager == null or generator == null or player == null or manager.busy or not manager.active_id.is_empty() or generator.building:
		return _fail("state")
	if player.get_player_mode() != player.PlayerMode.NORMAL:
		return _fail("state")
	var vehicles: Array[Dictionary] = []
	for rv in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if WorldEntities.same_world(player, rv):
			var state := VehicleSnapshot.capture(rv)
			if state.is_empty(): return _fail("state")
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
		"slot": player.inventory.active_slot, "health": player.current_player_health}}
	data["outdoor_sites"] = generator.outdoor_sites.duplicate(true)
	data["generated_bands"] = generator.generated_bands.duplicate()
	var clock := world.get_node_or_null("WorldClock") as WorldClock
	if clock != null: data["clock"] = clock.capture()
	var field := validation_error(data)
	if not field.is_empty(): return _fail("data", field)
	return write_checkpoint(path, data)

func _collect_actors(node: Node, result: Array[Dictionary]) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion() or child.is_in_group(Groups.CHASSIS) or child.is_in_group(Groups.PLAYER): continue
		var saved := WorldActorSnapshot.capture(child)
		if not saved.is_empty(): result.append(saved)
		elif not (child is Prop or child is Equipment or child is Monster): _collect_actors(child, result)

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
	if not data.get("version") is int or data.version not in [1, 2, VERSION]:
		_fail("version", "version")
		return {}
	data = _upgrade_checkpoint(data)
	var field := validation_error(data)
	if not field.is_empty():
		_fail("data", field)
		return {}
	return data

func validation_error(data: Dictionary) -> String:
	if not CheckpointSchema.bounded(data, 0, [CheckpointSchema.MAX_ENTRIES]): return "data.size/depth"
	if not data.get("version") is int or data.version != VERSION: return "version"
	if not data.has_all(["vehicles", "player", "actors", "seed", "bands", "poi"]): return "data.fields"
	if not data.vehicles is Array: return "vehicles"
	if not data.actors is Array: return "actors"
	if not data.player is Dictionary: return "player"
	if not data.bands is Array or data.bands.is_empty() or data.bands.size() > 256: return "bands"
	var seen := {}
	for band in data.bands:
		if not band is int or seen.has(band): return "bands"
		seen[band] = true
	if not data.seed is int: return "seed"
	if not data.get("profile", {}) is Dictionary: return "profile"
	var profile_error := CheckpointSchema.profile_error(data.get("profile", {}))
	if not profile_error.is_empty(): return profile_error
	if not data.get("generation_version", 2) is int or data.get("generation_version", 2) not in [2, 3, 4, 5]: return "generation_version"
	if data.has("clock") and not WorldClock.valid_state(data.clock): return "clock"
	var player: Dictionary = data.player
	if not player.get("items") is Array: return "player.items"
	# Selection is a hotbar index, including empty slots, not an item index.
	if not player.get("slot") is int or player.slot < 0 or player.slot >= PlayerInventory.MAX_SLOTS: return "player.slot"
	if not VehicleSnapshot._number(player.get("health")) or player.health < 0 or player.health > 100: return "player.health"
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
	var outdoor_error := WalkInSites.validation_error(data)
	if not outdoor_error.is_empty(): return outdoor_error
	var poi_error := CheckpointSchema.poi_error(data.poi)
	if not poi_error.is_empty(): return poi_error
	if not _unique_engine_ids(data): return "engine.id.duplicate"
	return ""

func prepare_world(world: Node) -> void:
	if pending.is_empty(): return
	var clock := world.get_node_or_null("WorldClock") as WorldClock
	if clock != null and pending.has("clock"): clock.restore(pending.clock)
	world.get_node("Player").transform = pending.player.transform
	world.get_node("WorldGenerator").world_seed = pending.seed
	var profile := WorldProfile.new()
	for key in pending.get("profile", {}):
		if key in profile and key != "terrain_half_width": profile.set(key, pending.profile[key])
	profile.generation_version = pending.get("generation_version", 2)
	world.get_node("WorldGenerator").profile = profile
	world.get_node("WorldGenerator").restore_bands.assign(pending.bands)
	world.get_node("WorldGenerator").restoring_entities = true
	world.get_node("WorldGenerator").outdoor_sites = pending.get("outdoor_sites", {}).duplicate(true)
	world.get_node("WorldGenerator").generated_bands.assign(pending.get("generated_bands", pending.bands))

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
	for saved in data.actors:
		WorldActorSnapshot.restore(saved, container)
	var old: Array[Node] = []
	_collect_removable(world, old)
	for actor in old:
		if is_instance_valid(actor): actor.free()
	var destination := WorldEntities.get_container(world)
	for actor in container.get_children(): WorldEntities.transfer(actor, destination)
	for rv in domain.get_children():
		if rv != container: WorldEntities.transfer(rv, world)
	staging.free()
	world.get_node("PoiInstances").saved_instances = data.poi.duplicate(true)
	world.get_node("Player").restore_checkpoint_state(data.player)
	world.get_node("WorldGenerator").restoring_entities = false
	message = "Checkpoint restored"
	label.text = message
	return {"ok": true}

func load_world(old_world: Node, path: String) -> bool:
	if loading: return false
	var manager: Node = old_world.get_node("PoiInstances")
	var player: Node = old_world.get_node("Player")
	if manager.busy or not manager.active_id.is_empty() or player.get_player_mode() != player.PlayerMode.NORMAL:
		_fail("state")
		message = error_message()
		label.text = message
		return false
	var data := read_checkpoint(path)
	if data.is_empty():
		message = error_message()
		label.text = message
		return false
	loading = true
	message = "Preparing checkpoint..."
	label.text = message
	var staging := SubViewport.new()
	staging.own_world_3d = true
	staging.render_target_update_mode = SubViewport.UPDATE_DISABLED
	staging.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(staging)
	PhysicsServer3D.space_set_active(staging.find_world_3d().space, false)
	var candidate: Node3D = load("res://world/test_world.tscn").instantiate()
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
			var mesh: NavigationMesh = region.navigation_mesh
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
		if child is Prop or child is Equipment or child is Monster or child.is_in_group(Groups.CHASSIS):
			result.append(child)
		else:
			_collect_removable(child, result)

# Convert only recognized v1 structures, in memory. Original save stays untouched.
func _upgrade_checkpoint(source: Dictionary) -> Dictionary:
	if source.get("version", 0) in [2, VERSION]:
		if not source.get("vehicles") is Array: return {}
		var upgraded := source.duplicate(true)
		upgraded.version = VERSION
		for index in range(upgraded.vehicles.size()):
			if not upgraded.vehicles[index] is Dictionary: return {}
			upgraded.vehicles[index] = VehicleSnapshot.upgrade(upgraded.vehicles[index])
		return upgraded
	if source.get("version", 0) != 1 or not source.get("vehicles") is Array or not source.get("actors") is Array or not source.get("player") is Dictionary or not source.player.get("items") is Array or not source.get("poi") is Dictionary: return {}
	var data := source.duplicate(true)
	for index in range(data.vehicles.size()):
		if not data.vehicles[index] is Dictionary: return {}
		data.vehicles[index] = VehicleSnapshot.upgrade(data.vehicles[index])
		if data.vehicles[index].is_empty(): return {}
		var vehicle: Dictionary = data.vehicles[index]
		# Migration consumes these fields before the final current-schema validation.
		if not vehicle.get("materials") is Dictionary or not MaterialStorage.new().valid_amounts(vehicle.materials) or not VehicleSnapshot._number(vehicle.get("fuel")) or not VehicleSnapshot._number(vehicle.get("fuel_capacity")) or not vehicle.get("equipment") is Array: return {}
		for device in vehicle.equipment:
			if not device is Dictionary or not device.get("service") is Dictionary: return {}
	if data.vehicles.is_empty(): return {}
	var rv: Dictionary = data.vehicles[0]
	# Legacy material bundles (inventory, loose actors, POIs, recycler inputs)
	# are credited once to the first saved chassis, even if it exceeds capacity.
	if not _convert_legacy_entries(data.player.items, rv): return {}
	if not _convert_legacy_entries(data.actors, rv): return {}
	data.player.slot = mini(int(data.player.get("slot", 0)), maxi(0, data.player.items.size() - 1))
	for poi in data.poi.values():
		if not poi is Dictionary or not poi.get("actors", []) is Array: return {}
		if not _convert_legacy_entries(poi.get("actors", []), rv): return {}
	for vehicle in data.vehicles:
		for device in vehicle.equipment:
			if not _convert_legacy_entries(device.service.get("inputs", []), rv): return {}
	data.version = VERSION
	return data

func _convert_legacy_entries(entries: Array, rv: Dictionary) -> bool:
	for index in range(entries.size() - 1, -1, -1):
		var entry: Variant = entries[index]
		if not entry is Dictionary: return false
		var scene: Variant = entry.get("scene", entry.get("scene_path", ""))
		var state: Variant = entry.get("state", {})
		if scene == "res://props/material_bundle.tscn":
			if not state is Dictionary or not state.get("materials") is Dictionary or not MaterialStorage.new().valid_amounts(state.materials): return false
			for material in state.materials:
				rv.materials[material] = int(rv.materials.get(material, 0)) + state.materials[material]
			entries.remove_at(index)
		elif scene == "res://equipment/fuel_tank.tscn":
			var service: Variant = entry.get("service", {})
			if not service is Dictionary or not VehicleSnapshot._number(service.get("fuel", 0.0)): return false
			rv.fuel += maxf(0.0, service.get("fuel", 0.0))
			rv.fuel_capacity = maxf(rv.fuel_capacity, rv.fuel)
			entry.scene = "res://equipment/fuel_port.tscn"
			service.erase("fuel")
			service.erase("capacity")
		elif scene == "res://equipment/material_rack.tscn":
			entry.scene = "res://equipment/item_box.tscn"
			if entry.get("service", {}) is Dictionary: entry.get("service", {}).erase("capacity")
		if entry.get("service", {}) is Dictionary:
			var inputs: Variant = entry.get("service", {}).get("inputs", [])
			if not inputs is Array or not _convert_legacy_entries(inputs, rv): return false
	return true

func _unique_engine_ids(data: Dictionary) -> bool:
	return EngineState.unique_ids(data)

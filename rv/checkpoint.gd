extends Node
## Main-world checkpoint. Serialized Variants contain no objects or executable code.
const VERSION := 2
const PATH := "user://rv_checkpoint.save"
var pending: Dictionary = {}
var message: String = ""
var label: Label

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
	if event.physical_keycode == KEY_F6:
		message = "Checkpoint saved" if save_world(world, PATH) else "Cannot save: return outdoors, finish placement and wait for terrain"
	elif event.physical_keycode == KEY_F9:
		var data := read_checkpoint(PATH)
		if data.is_empty():
			message = "No compatible checkpoint"
		else:
			pending = data
			message = "Loading checkpoint..."
			get_tree().reload_current_scene()
	label.text = message

func save_world(world: Node, path: String) -> bool:
	var manager: Node = world.get_node_or_null("PoiInstances")
	var generator: Node = world.get_node_or_null("WorldGenerator")
	var player: Node = world.get_node_or_null("Player")
	if manager == null or generator == null or player == null or manager.busy or not manager.active_id.is_empty() or generator.building:
		return false
	if player.get_player_mode() != player.PlayerMode.NORMAL:
		return false
	var vehicles: Array[Dictionary] = []
	for rv in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if WorldEntities.same_world(player, rv):
			var state := VehicleSnapshot.capture(rv)
			if state.is_empty(): return false
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
	var data := {"profile": profile_data, "version": VERSION, "seed": generator.world_seed, "bands": bands, "vehicles": vehicles,
		"actors": actors, "poi": manager.saved_instances.duplicate(true),
		"player": {"transform": player.global_transform, "items": player.inventory.items.duplicate(true),
		"slot": player.inventory.active_slot, "health": player.current_player_health}}
	return write_checkpoint(path, data)

func _collect_actors(node: Node, result: Array[Dictionary]) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion() or child.is_in_group(Groups.CHASSIS) or child.is_in_group(Groups.PLAYER):
			continue
		if child is Prop:
			if not is_instance_valid(child.processing_owner):
				result.append({"kind": "prop", "scene": child.scene_file_path, "transform": child.global_transform,
					"state": child.capture_item_state(), "frozen": child.freeze, "linear": child.linear_velocity, "angular": child.angular_velocity})
		elif child is Equipment:
			if child.is_being_placed: continue
			var data := VehicleSnapshot.device_state(child)
			data["kind"] = "equipment"
			data["transform"] = child.global_transform
			data["frozen"] = child.freeze
			result.append(data)
		elif child is Monster:
			if not child.is_dead:
				result.append({"kind": "monster", "scene": child.scene_file_path, "transform": child.global_transform, "health": child.current_health})
		else:
			_collect_actors(child, result)

func write_checkpoint(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(data, false)
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	if not okay:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) == OK

func read_checkpoint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var data: Variant = file.get_var(false)
	file.close()
	if data is Dictionary: data = _upgrade_checkpoint(data)
	if not data is Dictionary or data.get("version", 0) != VERSION or not data.has_all(["vehicles", "player", "actors", "seed", "bands", "poi"]):
		return {}
	if not data.vehicles is Array or not data.actors is Array or not data.player is Dictionary or not data.bands is Array or data.bands.is_empty(): return {}
	if not data.player.has_all(["items", "slot", "health", "transform"]) or not data.player.items is Array or not data.player.transform is Transform3D: return {}
	if not data.seed is int or not data.poi is Dictionary or not data.get("profile", {}) is Dictionary or not data.player.slot is int or not VehicleSnapshot._number(data.player.health): return {}
	for band in data.bands:
		if not band is int: return {}
	for item in data.player.items:
		if not VehicleSnapshot.valid_item(item): return {}
	for vehicle in data.vehicles:
		if not vehicle is Dictionary or not VehicleSnapshot.validate(vehicle): return {}
	for actor in data.actors:
		if not actor is Dictionary or not actor.has_all(["kind", "scene", "transform"]) or not actor.scene is String or not actor.transform is Transform3D or not ResourceLoader.exists(actor.scene): return {}
		match actor.kind:
			"prop":
				if not actor.has_all(["state", "frozen", "linear", "angular"]) or not actor.state is Dictionary or not actor.frozen is bool or not actor.linear is Vector3 or not actor.angular is Vector3: return {}
			"equipment":
				if not actor.has_all(["id", "health", "enabled", "service", "frozen"]) or not actor.service is Dictionary or not VehicleSnapshot._number(actor.health): return {}
				if not VehicleSnapshot.valid_structure_service(actor.scene, actor.service): return {}
			"monster":
				if not actor.has("health") or not VehicleSnapshot._number(actor.health): return {}
			_: return {}
	return data

func prepare_world(world: Node) -> void:
	if pending.is_empty(): return
	world.get_node("Player").transform = pending.player.transform
	world.get_node("WorldGenerator").world_seed = pending.seed
	var profile := WorldProfile.new()
	for key in pending.get("profile", {}):
		if key in profile: profile.set(key, pending.profile[key])
	world.get_node("WorldGenerator").profile = profile
	world.get_node("WorldGenerator").restore_bands.assign(pending.bands)
	world.get_node("WorldGenerator").restoring_entities = true

func restore_world(world: Node) -> void:
	if pending.is_empty(): return
	var data := pending
	pending = {}
	var player: Node = world.get_node("Player")
	player.set_physics_process(false)
	var generator: Node = world.get_node("WorldGenerator")
	while generator.building:
		await get_tree().process_frame
	var old: Array[Node] = []
	_collect_removable(world, old)
	for actor in old:
		if is_instance_valid(actor): actor.free()
	var container := WorldEntities.get_container(world)
	for saved in data.vehicles:
		var rv: Node3D = load("res://rv/chassis.tscn").instantiate()
		rv.transform = world.global_transform.affine_inverse() * saved.transform
		world.add_child(rv)
		VehicleSnapshot.apply(rv, saved)
	for saved in data.actors:
		var actor: Node3D = load(saved.scene).instantiate()
		actor.transform = container.global_transform.affine_inverse() * saved.transform
		container.add_child(actor)
		if actor is Prop:
			actor.restore_item_state(saved.state)
			actor.freeze = saved.frozen
			actor.linear_velocity = saved.linear
			actor.angular_velocity = saved.angular
		elif actor is Equipment:
			actor.freeze = saved.frozen
			VehicleSnapshot.restore_device(actor, saved, null)
			if saved.has("physics"):
				actor.freeze_mode = saved.physics.mode
				actor.collision_layer = saved.physics.layer
				actor.collision_mask = saved.physics.mask
				actor.linear_velocity = saved.physics.linear
				actor.angular_velocity = saved.physics.angular
		elif actor is Monster:
			actor.current_health = saved.health
	world.get_node("PoiInstances").saved_instances = data.poi.duplicate(true)
	player.inventory.items.assign(data.player.items)
	player.inventory.active_slot = data.player.slot
	player.current_player_health = data.player.health
	player.global_transform = data.player.transform
	player.velocity = Vector3.ZERO
	player.refresh_inventory()
	player._update_health_bar()
	generator.restoring_entities = false
	player.set_physics_process(true)
	message = "Checkpoint restored"
	label.text = message

func _collect_removable(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child.is_in_group(Groups.PLAYER): continue
		if child is Prop or child is Equipment or child is Monster or child.is_in_group(Groups.CHASSIS):
			result.append(child)
		else:
			_collect_removable(child, result)

# Convert only recognized v1 structures, in memory. Original save stays untouched.
func _upgrade_checkpoint(source: Dictionary) -> Dictionary:
	if source.get("version", 0) == VERSION:
		if not source.get("vehicles") is Array: return {}
		var upgraded := source.duplicate(true)
		for index in range(upgraded.vehicles.size()):
			if not upgraded.vehicles[index] is Dictionary: return {}
			upgraded.vehicles[index] = VehicleSnapshot.upgrade(upgraded.vehicles[index])
		return upgraded
	if source.get("version", 0) != 1 or not source.get("vehicles") is Array or not source.get("actors") is Array or not source.get("player") is Dictionary or not source.player.get("items") is Array or not source.get("poi") is Dictionary: return {}
	var data := source.duplicate(true)
	for index in range(data.vehicles.size()):
		if not data.vehicles[index] is Dictionary: return {}
		data.vehicles[index] = VehicleSnapshot.upgrade(data.vehicles[index])
		if not VehicleSnapshot.validate(data.vehicles[index]): return {}
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

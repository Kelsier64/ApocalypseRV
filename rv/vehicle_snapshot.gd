extends RefCounted
class_name VehicleSnapshot
const VERSION := 5

static func device_state(device: Item) -> Dictionary:
	var data := WorldActorSnapshot.capture(device)
	data["transform"] = device.transform
	return data
static func capture(rv: Node3D) -> Dictionary:
	if not rv.save_block_reason().is_empty(): return {}
	var devices: Array[Dictionary] = []
	for device in rv.get_equipment():
		if device.is_being_placed:
			return {}
		devices.append(device_state(device))
	var wheels: Array[Dictionary] = []
	for index in range(4):
		wheels.append({"installed": rv.installed_wheels[index] != null, "health": rv.wheel_health[index], "id": rv.wheel_ids[index], "item_data": rv.wheel_item_data[index].duplicate(true)})
	return {"version": VERSION, "id": rv.persistent_id, "transform": rv.global_transform,
		"cabin_light_devices": true,
		"linear": rv.linear_velocity, "angular": rv.angular_velocity,
		"engine_item": rv.get_engine().snapshot() if rv.get_engine() else {}, "headlights": rv.headlights_requested, "comfort": rv.comfort_snapshot(),
		"hatch_open": rv.engine_bay.hatch_open, "ramp": rv.rear_ramp.snapshot() if rv.rear_ramp else {},
		"engine": rv.energy.engine_running, "gear": rv.gear, "handbrake": rv.handbrake,
		"materials": rv.get_all_items(), "items": rv.stored_items.duplicate(true),
		"fuel": rv.current_fuel, "fuel_capacity": rv.max_fuel, "material_capacity": rv.material_capacity, "item_capacity": rv.item_capacity,
		"mounted_items": devices, "structures": rv.get_node("StructureSlots").snapshot(), "wheels": wheels}

static func valid_comfort(data: Variant) -> bool:
	if not data is Dictionary or not data.has_all(["lights", "brightness", "vibration"]): return false
	if not data.lights is Dictionary or data.lights.size() != 3: return false
	for kind in ["cabin", "work", "service"]:
		if not data.lights.get(kind) is bool: return false
	return _number(data.brightness) and data.brightness >= 0.2 and data.brightness <= 1.0 and _number(data.vibration) and data.vibration >= 0.0 and data.vibration <= 1.0

static func validate(data: Dictionary) -> bool:
	if not data.get("version") is int: return false
	if data.has("cabin_light_devices") and (not data.cabin_light_devices is bool or not data.cabin_light_devices): return false
	if data.has("comfort") and not valid_comfort(data.comfort): return false
	if data.get("version", 0) != VERSION or not data.has_all(["structures", "mounted_items", "wheels", "transform", "materials", "items", "fuel", "fuel_capacity", "material_capacity", "item_capacity", "id", "engine_item", "headlights", "hatch_open", "ramp", "engine", "gear", "handbrake", "linear", "angular"]):
		return false
	if not RVStructureSlots.validate_snapshot(data.structures): return false
	if not data.mounted_items is Array or not data.wheels is Array or not data.materials is Dictionary or not data.items is Array:
		return false
	if not CheckpointSchema.valid_transform(data.transform) or not CheckpointSchema.vector(data.linear) or not CheckpointSchema.vector(data.angular) or data.wheels.size() != 4:
		return false
	if not data.id is String or data.id.is_empty() or not data.engine is bool or not data.handbrake is bool or not data.gear is int or data.gear < -1 or data.gear > 4: return false
	if not EngineState.valid(data.engine_item) or not data.headlights is bool or not data.hatch_open is bool or not RearRamp.valid_state(data.ramp): return false
	if not _number(data.fuel) or data.fuel < 0.0 or not _number(data.fuel_capacity) or data.fuel_capacity < data.fuel: return false
	if not data.material_capacity is int or data.material_capacity < 0 or not data.item_capacity is int or data.item_capacity < 0: return false
	for item in data.items:
		if not valid_item(item): return false
	for entry in data.mounted_items:
		if not WorldActorSnapshot.validation_error(entry, "mounted_items").is_empty() or entry.kind != "item" or not entry.fixed: return false
	if not _valid_mounted_supports(data): return false
	if not WorldActorSnapshot.graph_error(data.mounted_items).is_empty(): return false
	for wheel in data.wheels:
		if not wheel is Dictionary or not wheel.has_all(["installed", "health", "id"]) or not wheel.installed is bool or not _number(wheel.health) or not wheel.id is String or (wheel.installed and wheel.id.is_empty()): return false
		if not ItemState.valid_slot_data(wheel.get("item_data", {})): return false
	return MaterialStorage.new().valid_amounts(data.materials) and ItemState.unique_ids(data, {})

static func _valid_mounted_supports(data: Dictionary) -> bool:
	var slots := {}
	for structure in data.structures: slots[structure.slot] = true
	var identities := {}
	for entry in data.mounted_items: identities[entry.state.id] = true
	for entry in data.mounted_items:
		var support: Dictionary = entry.support
		match support.kind:
			"chassis":
				if support.rv != data.id: return false
			"structure":
				if support.rv != data.id or not slots.has(support.slot): return false
				# A known destroyed socket is an intentional Item fallback record:
				# restoration drops the item and stops/refunds its service once.
			"item":
				if not identities.has(support.id): return false
			_: return false
	return true

static func restore_device(device: Item, data: Dictionary, _rv: Node3D) -> void:
	device.restore_item_state(data.state)
static func apply(rv: Node3D, data: Dictionary) -> bool:
	data = upgrade(data)
	if not validate(data):
		return false
	var staged: Array[Item] = []
	for entry in data.mounted_items:
		var scene := load(entry.scene) as PackedScene
		var instance := scene.instantiate() if scene else null
		var device := instance as Item
		if device == null:
			if instance: instance.free()
			for allocated in staged: allocated.free()
			return false
		staged.append(device)
	var old_devices: Array[Node] = rv.get_equipment()
	# Processing actors are owned by queues but parented to the world container.
	# Replace them atomically; transfer suppression must not strand old inputs.
	var old_container := WorldEntities.get_container(rv)
	for actor in old_container.get_children():
		if actor is Item and old_devices.has(actor.processing_owner):
			actor.begin_world_transfer()
			actor.free()
	for device in old_devices:
		if device is BatterySocket: device.installed_battery = null
		device.begin_world_transfer()
		device.set_mount_support(null)
	for device in old_devices:
		device.free()
	rv.persistent_id = data.id
	rv.global_transform = data.transform
	rv.get_node("StructureSlots").restore(data.structures)
	var restored: Array = []
	var records: Array = []
	for index in range(staged.size()):
		var device := staged[index]
		var entry: Dictionary = data.mounted_items[index].duplicate(true)
		entry.transform = rv.global_transform * entry.transform
		device.transform = data.mounted_items[index].transform
		rv.add_child(device)
		device.is_fixed = false
		var initial: Dictionary = entry.state.duplicate(true)
		initial["service"] = {}
		device.restore_item_state(initial)
		restored.append(device)
		records.append(entry)
	rv.inventory = data.materials
	rv.stored_items.assign(data.items.duplicate(true))
	rv.material_capacity = data.material_capacity
	rv.item_capacity = data.item_capacity
	rv.max_fuel = data.fuel_capacity
	rv.current_fuel = data.fuel
	rv.engine_bay.installed_engine = null if data.engine_item.is_empty() else EngineState.new(data.engine_item)
	rv.headlights_requested = data.headlights
	rv.restore_comfort(data.get("comfort", {}))
	rv.engine_bay.get_node("Hatch").set_open(data.hatch_open)
	if rv.rear_ramp: rv.rear_ramp.restore_state(data.ramp)
	rv.energy.engine_running = data.engine and rv.has_working_engine() and rv.current_fuel > 0.0
	rv.gear = data.gear
	rv.handbrake = data.handbrake
	rv.linear_velocity = data.linear
	rv.angular_velocity = data.angular
	for index in range(4):
		rv.remove_wheel(index)
		var wheel: Dictionary = data.wheels[index]
		rv.wheel_health[index] = wheel.health
		rv.wheel_ids[index] = wheel.id
		rv.wheel_item_data[index] = wheel.get("item_data", {}).duplicate(true)
		if wheel.installed:
			rv._create_wheel_at(index)
			rv._update_wheel_condition(index)
	WorldActorSnapshot.restore_supports(records, restored, rv.get_parent())
	rv.update_load()
	rv.update_storage_capacity()
	return true

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func valid_battery(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if not ItemState.valid_slot_data(value.get("item_data", {})): return false
	return value.has_all(["id", "condition", "charge", "capacity", "weight", "scene_path"]) and value.id is String and not value.id.is_empty() and _number(value.condition) and value.condition >= 0 and value.condition <= 100 and _number(value.charge) and _number(value.capacity) and _number(value.weight) and value.charge >= 0 and value.charge <= value.capacity and value.capacity >= 1 and value.capacity <= 1000 and value.weight >= 1 and value.weight <= 200 and value.scene_path is String and value.scene_path in ["res://props/battery.tscn", "res://props/battery_large.tscn"]

static func valid_item(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["name", "is_large", "scene_path", "state"]): return false
	if not value.name is String or not value.is_large is bool or not value.scene_path is String or not value.state is Dictionary or not ResourceLoader.exists(value.scene_path): return false
	if not value.state.get("id") is String or value.state.id.is_empty(): return false
	if (value.scene_path.begins_with("res://equipment/") or value.scene_path == "res://rv/battery_socket.tscn") and not value.is_large: return false
	if value.state.has("materials"): return false
	if not valid_prop_state(value.scene_path, value.state): return false
	if value.scene_path == "res://props/corpse.tscn" and not value.is_large: return false
	if value.state.has("engine") and not value.is_large: return false
	if value.scene_path == "res://props/flashlight.tscn" and (value.name != ItemNames.FLASHLIGHT or value.is_large): return false
	return not value.state.has("battery") or valid_battery(value.state.battery)

static func upgrade(source: Dictionary) -> Dictionary:
	# Item ownership still requires v5. Only the fixed-deck reversion is compatible:
	# preserve the eleven remaining sockets and move former deck mounts to chassis.
	if source.get("version", 0) != VERSION: return {}
	var data := source.duplicate(true)
	if not data.get("structures") is Array or data.structures.size() != 12: return data
	var floor_index := -1
	for index in range(data.structures.size()):
		var entry: Variant = data.structures[index]
		if not entry is Dictionary: return {}
		if entry.get("slot") == "floor":
			if floor_index != -1 or entry.size() != 4 or not entry.has_all(["slot", "type", "health", "door_angles"]): return {}
			if not entry.slot is String or not entry.type is String: return {}
			if entry.type != "rv_floor" or not _number(entry.health) or entry.health < 0.0 or entry.health > 120.0: return {}
			if not entry.door_angles is Array or not entry.door_angles.is_empty(): return {}
			floor_index = index
	if floor_index == -1 or not data.get("mounted_items") is Array: return {}
	var floor_health: float = data.structures[floor_index].health
	data.structures.remove_at(floor_index)
	if not RVStructureSlots.validate_snapshot(data.structures): return {}
	for entry in data.mounted_items:
		if not entry is Dictionary or not valid_support(entry.get("support")): return {}
		var support: Dictionary = entry.support
		if support.kind == "structure" and support.slot == "floor":
			if floor_health <= 0.0 or support.rv != data.get("id"): return {}
			entry.support = {"kind": "chassis", "rv": support.rv}
	return data if validate(data) else {}

static func valid_support(value: Variant) -> bool:
	return WorldActorSnapshot.valid_support(value)

static func valid_prop_state(scene: String, state: Dictionary) -> bool:
	return ItemState.valid(scene, state)

static func valid_flashlight(value: Variant) -> bool:
	return value is Dictionary and value.size() == 2 and value.has_all(["charge", "on"]) and _number(value.charge) and value.charge >= 0.0 and value.charge <= Flashlight.FULL_CHARGE and value.on is bool and (value.charge > 0.0 or not value.on)

static func valid_device(entry: Dictionary) -> bool:
	return WorldActorSnapshot.validation_error(entry, "item").is_empty()

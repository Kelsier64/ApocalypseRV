extends RefCounted
class_name VehicleSnapshot
const VERSION := 3

static func device_state(device: Equipment) -> Dictionary:
	var support_id := "chassis"
	if is_instance_valid(device.mount_support) and device.mount_support is Equipment:
		support_id = device.mount_support.persistent_id
	var data := {"scene": device.scene_file_path, "id": device.persistent_id, "transform": device.transform,
		"health": device.current_health, "enabled": device.enabled, "support": support_id, "physics": {"mode": device.freeze_mode, "layer": device.collision_layer, "mask": device.collision_mask, "linear": device.linear_velocity, "angular": device.angular_velocity}, "service": {}}
	if device.get("structure_kind") is String and not device.structure_kind.is_empty():
		data.service["mount_slot"] = device.mount_slot
	if device.has_method("restore_angles"):
		data.service["door_angles"] = device.angles.duplicate()
	if device is BatterySocket:
		data.service["battery"] = device.installed_battery.snapshot() if device.installed_battery else {}
	for key in ["charging", "fuel_reserve", "recharge_below"]:
		if key in device: data.service[key] = device.get(key)
	if device is CraftingStation:
		var jobs: Array[Dictionary] = []
		for job in device.jobs:
			var saved: Dictionary = job.duplicate(true)
			saved.erase("rv")
			jobs.append(saved)
		data.service["jobs"] = jobs
	if "props_being_crushed" in device:
		var inputs: Array[Dictionary] = []
		for entry in device.props_being_crushed:
			if is_instance_valid(entry.prop):
				inputs.append({"scene": entry.prop.scene_file_path, "state": entry.prop.capture_item_state(),
					"timer": entry.timer, "local_position": entry.local_position, "physics": entry.physics})
		data.service["inputs"] = inputs
	return data

static func capture(rv: Node3D) -> Dictionary:
	var devices: Array[Dictionary] = []
	for device in rv.get_equipment():
		if device.is_being_placed:
			return {}
		devices.append(device_state(device))
	var wheels: Array[Dictionary] = []
	for index in range(4):
		wheels.append({"installed": rv.installed_wheels[index] != null, "health": rv.wheel_health[index], "id": rv.wheel_ids[index]})
	return {"version": VERSION, "id": rv.persistent_id, "transform": rv.global_transform,
		"linear": rv.linear_velocity, "angular": rv.angular_velocity,
		"engine_item": rv.get_engine().snapshot() if rv.get_engine() else {}, "headlights": rv.headlights_requested,
		"hatch_open": rv.engine_bay.hatch_open, "ramp": rv.rear_ramp.snapshot() if rv.rear_ramp else {},
		"engine": rv.energy.engine_running, "gear": rv.gear, "handbrake": rv.handbrake,
		"materials": rv.get_all_items(), "items": rv.stored_items.duplicate(true),
		"fuel": rv.current_fuel, "fuel_capacity": rv.max_fuel, "material_capacity": rv.material_capacity, "item_capacity": rv.item_capacity,
		"equipment": devices, "wheels": wheels}

static func validate(data: Dictionary) -> bool:
	if data.get("version", 0) != VERSION or not data.has_all(["equipment", "wheels", "transform", "materials", "items", "fuel", "fuel_capacity", "material_capacity", "item_capacity", "id", "engine_item", "headlights", "hatch_open", "ramp", "engine", "gear", "handbrake", "linear", "angular"]):
		return false
	if not data.equipment is Array or not data.wheels is Array or not data.materials is Dictionary or not data.items is Array:
		return false
	if not data.transform is Transform3D or not data.linear is Vector3 or not data.angular is Vector3 or data.wheels.size() != 4:
		return false
	if not data.id is String or not data.engine is bool or not data.handbrake is bool or not data.gear is int or data.gear < -1 or data.gear > 4: return false
	if not EngineState.valid(data.engine_item) or not data.headlights is bool or not data.hatch_open is bool or not RearRamp.valid_state(data.ramp): return false
	if not _number(data.fuel) or data.fuel < 0.0 or not _number(data.fuel_capacity) or data.fuel_capacity < data.fuel: return false
	if not data.material_capacity is int or data.material_capacity < 0 or not data.item_capacity is int or data.item_capacity < 0: return false
	for item in data.items:
		if not valid_item(item): return false
	var ids := {}
	var occupied_slots := {}
	for entry in data.equipment:
		if not entry is Dictionary or not entry.has_all(["scene", "id", "transform", "health", "enabled", "support", "service"]) or ids.has(entry.id):
			return false
		if not entry.scene is String or not entry.id is String or not entry.support is String or not entry.service is Dictionary or not entry.enabled is bool or not _number(entry.health) or not ResourceLoader.exists(entry.scene) or not entry.transform is Transform3D:
			return false
		if entry.service.has("battery") and not valid_battery(entry.service.battery): return false
		if not valid_structure_service(entry.scene, entry.service): return false
		var slot_id: String = entry.service.get("mount_slot", "")
		if not slot_id.is_empty():
			if occupied_slots.has(slot_id): return false
			occupied_slots[slot_id] = true
			for slot in RVStructureSlots.layout():
				if slot.id == slot_id and (entry.transform.origin.distance_to(slot.pose.origin) > 0.03 or not entry.transform.basis.is_equal_approx(slot.pose.basis)): return false
		ids[entry.id] = entry.support
	for entry in data.equipment:
		if entry.support != "chassis" and not ids.has(entry.support):
			return false
	for entry in data.equipment:
		var visited := {}
		var cursor: String = entry.id
		while cursor != "chassis":
			if visited.has(cursor) or not ids.has(cursor): return false
			visited[cursor] = true
			cursor = ids[cursor]
		if not entry.service.get("jobs", []) is Array or not entry.service.get("inputs", []) is Array: return false
		for job in entry.service.get("jobs", []):
			if not job is Dictionary or not job.has_all(["recipe", "remaining", "power", "costs"]) or not job.recipe is String or not _number(job.remaining) or not _number(job.power) or not job.costs is Dictionary or not MaterialStorage.new().valid_amounts(job.costs) or RecipeCatalog.find(job.recipe) == null: return false
		for input in entry.service.get("inputs", []):
			if not input is Dictionary or not input.has_all(["scene", "state", "timer", "local_position", "physics"]) or not input.scene is String or not input.state is Dictionary or not _number(input.timer) or not input.local_position is Vector3 or not input.physics is Dictionary or not input.physics.has_all(["freeze", "mode", "layer", "mask", "linear", "angular"]) or not ResourceLoader.exists(input.scene) or not valid_prop_state(input.scene, input.state): return false
	for wheel in data.wheels:
		if not wheel is Dictionary or not wheel.has_all(["installed", "health", "id"]) or not wheel.installed is bool or not _number(wheel.health) or not wheel.id is String: return false
	return MaterialStorage.new().valid_amounts(data.materials) and EngineState.unique_ids(data)

static func restore_device(device: Equipment, data: Dictionary, rv: Node3D) -> void:
	device.persistent_id = data.id
	device.current_health = clampf(data.health, 0.0, device.max_health)
	if device.current_health <= 0.0:
		device.remove_from_group(Groups.MONSTER_DAMAGEABLE)
	device.enabled = data.enabled
	if device.get("structure_kind") is String:
		device.mount_slot = data.service.get("mount_slot", device.mount_slot) if rv else ""
	if device.has_method("restore_angles"):
		device.restore_angles(data.service.get("door_angles", [0.0, 0.0] if device.leaf_count == 2 else [0.0]))
	if device is BatterySocket:
		var battery: Dictionary = data.service.get("battery", {})
		device.installed_battery = null if battery.is_empty() else BatteryState.new(battery)
	for key in ["charging", "fuel_reserve", "recharge_below"]:
		if key in device and data.service.has(key): device.set(key, data.service[key])
	if device is CraftingStation:
		device.jobs.clear()
		for saved in data.service.get("jobs", []):
			var job: Dictionary = saved.duplicate(true)
			job["rv"] = rv
			device.jobs.append(job)
	if "props_being_crushed" in device:
		for saved in data.service.get("inputs", []):
			var prop: Prop = load(saved.scene).instantiate()
			prop.restore_item_state(saved.state)
			WorldEntities.get_container(device).add_child(prop)
			prop.global_position = device.to_global(saved.local_position)
			prop.processing_owner = device
			prop.freeze = true
			prop.collision_layer = 0
			prop.collision_mask = 0
			device.props_being_crushed.append({"prop": prop, "timer": saved.timer,
				"local_position": saved.local_position, "physics": saved.physics})

static func apply(rv: Node3D, data: Dictionary) -> bool:
	data = upgrade(data)
	if not validate(data):
		return false
	var staged: Array[Equipment] = []
	for entry in data.equipment:
		var scene := load(entry.scene) as PackedScene
		var instance := scene.instantiate() if scene else null
		var device := instance as Equipment
		if device == null:
			if instance: instance.free()
			for allocated in staged: allocated.free()
			return false
		staged.append(device)
	var old_devices: Array[Node] = rv.get_equipment()
	for device in old_devices:
		if device is BatterySocket: device.installed_battery = null
		device.set_mount_support(null)
	for device in old_devices:
		device.free()
	rv.persistent_id = data.id
	rv.global_transform = data.transform
	var by_id := {}
	for index in range(staged.size()):
		var device := staged[index]
		var entry: Dictionary = data.equipment[index]
		device.transform = entry.transform
		rv.add_child(device)
		device.confirm_placement(rv.global_transform * entry.transform, rv)
		restore_device(device, entry, rv)
		by_id[entry.id] = device
	for entry in data.equipment:
		by_id[entry.id].set_mount_support(by_id[entry.support] if by_id.has(entry.support) else rv)
	rv.inventory = data.materials
	rv.stored_items.assign(data.items.duplicate(true))
	rv.material_capacity = data.material_capacity
	rv.item_capacity = data.item_capacity
	rv.max_fuel = data.fuel_capacity
	rv.current_fuel = data.fuel
	rv.engine_bay.installed_engine = null if data.engine_item.is_empty() else EngineState.new(data.engine_item)
	rv.headlights_requested = data.headlights
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
		if wheel.installed:
			rv._create_wheel_at(index)
			rv._update_wheel_condition(index)
	rv.update_load()
	rv.update_storage_capacity()
	return true

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func valid_battery(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	return value.has_all(["id", "charge", "capacity", "weight"]) and value.id is String and _number(value.charge) and _number(value.capacity) and _number(value.weight) and value.charge >= 0 and value.charge <= value.capacity and value.capacity > 0 and value.weight > 0

static func valid_item(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["name", "is_large", "scene_path", "state"]): return false
	if not value.name is String or not value.is_large is bool or not value.scene_path is String or not value.state is Dictionary or not ResourceLoader.exists(value.scene_path): return false
	if value.state.has("materials"): return false
	if not valid_prop_state(value.scene_path, value.state): return false
	if value.state.has("engine") and not value.is_large: return false
	return not value.state.has("battery") or valid_battery(value.state.battery)

static func upgrade(source: Dictionary) -> Dictionary:
	if source.get("version", 0) == VERSION: return source.duplicate(true)
	if source.get("version", 0) == 2: return _upgrade_engine(_upgrade_structure(source))
	if source.get("version", 0) != 1 or not source.get("equipment") is Array or not valid_battery(source.get("battery")): return {}
	var data := source.duplicate(true)
	var fuel := 0.0
	var fuel_capacity := 0.0
	var material_capacity := 0
	for device in data.equipment:
		if not device is Dictionary or not device.get("service") is Dictionary: return {}
		if device.get("scene") == "res://equipment/fuel_tank.tscn":
			if not _number(device.service.get("fuel")) or not _number(device.service.get("capacity")): return {}
			fuel += maxf(0.0, device.service.fuel)
			fuel_capacity += maxf(0.0, device.service.capacity)
			device.scene = "res://equipment/fuel_port.tscn"
		elif device.get("scene") == "res://equipment/material_rack.tscn":
			if not device.service.get("capacity") is int: return {}
			material_capacity += maxi(0, device.service.capacity)
			device.scene = "res://equipment/item_box.tscn"
		device.service.erase("fuel")
		device.service.erase("capacity")
	data.equipment.append({"scene": "res://rv/battery_socket.tscn", "id": InstanceIds.create(),
		"transform": Transform3D(Basis.IDENTITY, Vector3(2.16, 0.16, 1.5)),
		"health": 120.0, "enabled": true, "support": "chassis", "service": {"battery": data.battery}})
	data.erase("battery")
	data.version = VERSION
	data.fuel = fuel
	data.fuel_capacity = maxf(100.0, maxf(fuel, fuel_capacity))
	data.material_capacity = maxi(300, material_capacity)
	data.item_capacity = 24
	data.items = []
	return _upgrade_engine(_upgrade_structure(data))

static func valid_structure_service(scene: String, service: Dictionary) -> bool:
	var kind := ""
	if scene in ["res://equipment/rv_side_panel.tscn", "res://equipment/rv_side_door.tscn"]: kind = "side"
	elif scene == "res://equipment/rv_rear_door.tscn": kind = "rear"
	elif scene == "res://equipment/rv_wall_front.tscn": kind = "front"
	elif scene == "res://equipment/rv_ceiling.tscn": kind = "roof"
	if service.has("mount_slot"):
		if not service.mount_slot is String: return false
		if not service.mount_slot.is_empty():
			var found := false
			for slot in RVStructureSlots.layout():
				if slot.id == service.mount_slot and slot.kind == kind: found = true
			if not found: return false
	if service.has("door_angles"):
		var count := 2 if scene == "res://equipment/rv_rear_door.tscn" else (1 if scene == "res://equipment/rv_side_door.tscn" else 0)
		if not service.door_angles is Array or service.door_angles.size() != count or count == 0: return false
		for index in range(count):
			var angle: Variant = service.door_angles[index]
			if not _number(angle) or absf(angle) > deg_to_rad(100.0) + 0.0001: return false
			if (index == 0 and angle > 0.0) or (index == 1 and angle < 0.0): return false
	return true

static func _upgrade_structure(source: Dictionary) -> Dictionary:
	if not source.get("equipment") is Array: return source
	var data := source.duplicate(true)
	var updated: Array = []
	var replacements := {}
	for entry in data.equipment:
		if not entry is Dictionary or not entry.get("transform") is Transform3D or not entry.get("service") is Dictionary or not entry.get("id") is String:
			return {}
		var side := "right" if entry.get("scene") == "res://equipment/rv_wall_left.tscn" else ("left" if entry.get("scene") == "res://equipment/rv_wall_right.tscn" else "")
		var original := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1.9 if side == "right" else -1.9, 1.5, 0))
		if not side.is_empty() and entry.transform.is_equal_approx(original):
			var pieces: Array = []
			for i in range(3):
				var piece: Dictionary = entry.duplicate(true)
				piece.id = entry.id if i == 1 else entry.id + "-segment-" + str(i)
				piece.scene = "res://equipment/rv_side_door.tscn" if side == "right" and i == 1 else "res://equipment/rv_side_panel.tscn"
				piece.support = "chassis"
				piece.service = {"mount_slot": side + "_" + str(i)}
				for slot in RVStructureSlots.layout():
					if slot.id == piece.service.mount_slot: piece.transform = slot.pose
				pieces.append(piece)
				updated.append(piece)
			replacements[entry.id] = pieces
		elif entry.get("scene") == "res://equipment/rv_wall_back.tscn" and entry.transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 5.9))):
			entry.scene = "res://equipment/rv_rear_door.tscn"
			entry.service["mount_slot"] = "rear"
			entry.support = "chassis"
			updated.append(entry)
		else:
			updated.append(entry)
	for entry in updated:
		if replacements.has(entry.get("support", "")):
			var nearest: Dictionary = replacements[entry.support][0]
			for piece in replacements[entry.support]:
				if piece.transform.origin.distance_to(entry.transform.origin) < nearest.transform.origin.distance_to(entry.transform.origin):
					nearest = piece
			entry.support = nearest.id
	data.equipment = updated
	return data

static func _upgrade_engine(data: Dictionary) -> Dictionary:
	if data.is_empty() or not _number(data.get("health")) or not data.get("id") is String: return {}
	data.version = VERSION
	data.engine_item = {"id": data.id + "-legacy-engine", "model": "standard", "health": clampf(data.health, 0.0, 450.0)}
	data.erase("health")
	data.headlights = false
	data.hatch_open = false
	data.ramp = {"deployed": false, "angle": 0.0, "length": 3.6}
	return data

static func valid_prop_state(scene: String, state: Dictionary) -> bool:
	var is_engine := scene in ["res://props/engine_standard.tscn", "res://props/engine_upgraded.tscn"]
	if is_engine:
		return EngineState.valid(state.get("engine"), false) and state.get("id") == state.engine.id and scene == "res://props/engine_" + state.engine.model + ".tscn"
	return not state.has("engine")

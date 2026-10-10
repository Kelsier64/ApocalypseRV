extends RefCounted
class_name ItemState
## Canonical, object-free Item data shared by every ownership domain.

static func slot_data(state: Dictionary) -> Dictionary:
	var data := {}
	for key in ["enabled", "scrap_yields", "recycle_result"]:
		if state.has(key): data[key] = state[key].duplicate(true) if state[key] is Dictionary else state[key]
	return data

static func valid_slot_data(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in value:
		match key:
			"enabled":
				if not value[key] is bool: return false
			"scrap_yields":
				if not CheckpointSchema.yields_valid(value[key]): return false
			"recycle_result":
				if not value[key] is Dictionary or not MaterialStorage.new().valid_amounts(value[key]): return false
			_: return false
	return true

static func valid(scene: String, state: Dictionary) -> bool:
	if SaveSceneCatalog.resolve(scene, "item") == null: return false
	if not state.get("id") is String or state.id.is_empty(): return false
	if not VehicleSnapshot._number(state.get("condition")) or state.condition < 0 or state.condition > 100: return false
	if state.has("enabled") and not state.enabled is bool: return false
	if state.has("scrap_yields") and not CheckpointSchema.yields_valid(state.scrap_yields): return false
	if state.has("recycle_result") and (not state.recycle_result is Dictionary or not MaterialStorage.new().valid_amounts(state.recycle_result)): return false
	if state.has("service") and (not state.service is Dictionary or not valid_service(scene, state.service)): return false
	if scene == "res://props/corpse.tscn":
		if not load("res://props/corpse.gd").valid_state(state.get("corpse")): return false
	elif state.has("corpse"): return false
	if scene in ["res://props/battery.tscn", "res://props/battery_large.tscn"]:
		if not state.get("battery") is Dictionary or state.battery.is_empty() or not VehicleSnapshot.valid_battery(state.battery): return false
		if state.id != state.battery.id or scene != state.battery.scene_path or not is_equal_approx(float(state.condition), float(state.battery.condition)): return false
	elif state.has("battery"): return false
	if scene == "res://props/flashlight.tscn":
		if not VehicleSnapshot.valid_flashlight(state.get("flashlight")): return false
	elif state.has("flashlight"): return false
	if scene in ["res://props/engine_standard.tscn", "res://props/engine_upgraded.tscn"]:
		return EngineState.valid(state.get("engine"), false) and state.get("id") == state.engine.id and scene == "res://props/engine_" + state.engine.model + ".tscn" and is_equal_approx(float(state.condition), float(state.engine.health) * 100.0 / EngineState.definition_for(state.engine.model).max_health)
	return not state.has("engine")

static func valid_service(scene: String, service: Dictionary) -> bool:
	for key in service:
		match key:
			"fall_height":
				if scene != "res://props/oil_barrel.tscn" or not VehicleSnapshot._number(service[key]) or service[key] < 0: return false
			"battery":
				if scene != "res://rv/battery_socket.tscn" or not VehicleSnapshot.valid_battery(service.battery): return false
			"jobs":
				if scene != "res://equipment/crafting_station.tscn" or not service.jobs is Array: return false
				for job in service.jobs:
					if not job is Dictionary or not job.has_all(["recipe", "remaining", "power", "costs"]): return false
					if not job.recipe is String or RecipeCatalog.find(job.recipe) == null or not VehicleSnapshot._number(job.remaining) or job.remaining < 0 or not VehicleSnapshot._number(job.power) or job.power < 0 or not job.costs is Dictionary or not MaterialStorage.new().valid_amounts(job.costs): return false
			"inputs":
				if scene != "res://equipment/scrapper.tscn" or not service.inputs is Array: return false
				for input in service.inputs:
					if not input is Dictionary or not input.has_all(["scene", "state", "timer", "local_position", "physics"]): return false
					if not input.scene is String or not input.state is Dictionary or not valid(input.scene, input.state) or not VehicleSnapshot._number(input.timer) or input.timer < 0 or not CheckpointSchema.vector(input.local_position) or not CheckpointSchema.physics(input.physics, true): return false
			"charging":
				if scene != "res://equipment/generator.tscn" or not service.charging is bool: return false
			"fuel_reserve", "recharge_below":
				if scene != "res://equipment/generator.tscn" or not VehicleSnapshot._number(service[key]) or service[key] < 0 or (key == "recharge_below" and service[key] > 1): return false
			_: return false
	return true

static func unique_ids(value: Variant, seen: Dictionary = {}) -> bool:
	if value is Array:
		for entry in value:
			if not unique_ids(entry, seen): return false
	elif value is Dictionary:
		for key in value:
			var field_name := str(key)
			var child: Variant = value[key]
			if field_name == "state":
				if not child is Dictionary: return false
				var identity: Variant = child.get("id")
				if not _claim(identity, seen): return false
				# Embedded engine/battery is the same Item, not a second owner.
				if not unique_ids(child.get("service", {}), seen): return false
			elif field_name in ["engine_item", "battery"] and child is Dictionary and not child.is_empty():
				if not _claim(child.get("id", ""), seen): return false
			elif field_name == "wheels" and child is Array:
				for wheel in child:
					if not wheel is Dictionary: return false
					if wheel.get("installed", false) and not _claim(wheel.get("id", ""), seen): return false
			elif not unique_ids(child, seen): return false
	return true

static func _claim(identity: Variant, seen: Dictionary) -> bool:
	if not identity is String or identity.is_empty(): return false
	if seen.has(identity): return false
	seen[identity] = true
	return true

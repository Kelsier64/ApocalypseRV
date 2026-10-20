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
	if scene == "res://equipment/training_terminal.tscn":
		if not valid_training_terminal(state.get("training_terminal")): return false
	elif state.has("training_terminal"): return false
	if scene == "res://props/printed_player.tscn":
		if not load("res://props/printed_player.gd").valid_state(state.get("printed_body")): return false
		if state.condition > 0 and not state.printed_body.body.present["head"]: return false
	elif state.has("printed_body"): return false
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
	if scene == PistolRules.PISTOL_SCENE:
		if not valid_rounds(state.get("pistol"), "loaded_rounds", 0, PistolRules.MAGAZINE_CAPACITY): return false
	elif state.has("pistol"): return false
	if scene == PistolRules.AMMO_SCENE:
		if not valid_rounds(state.get("ammo"), "rounds", 1, PistolRules.BOX_CAPACITY): return false
	elif state.has("ammo"): return false
	if scene in ["res://props/engine_standard.tscn", "res://props/engine_upgraded.tscn"]:
		return EngineState.valid(state.get("engine"), false) and state.get("id") == state.engine.id and scene == "res://props/engine_" + state.engine.model + ".tscn" and is_equal_approx(float(state.condition), float(state.engine.health) * 100.0 / EngineState.definition_for(state.engine.model).max_health)
	return not state.has("engine")

static func valid_rounds(value: Variant, field: String, minimum: int, maximum: int) -> bool:
	return value is Dictionary and value.size() == 1 and value.get(field) is int and value[field] >= minimum and value[field] <= maximum

static func valid_training_terminal(value: Variant) -> bool:
	if not value is Dictionary or not value.get("version") is int: return false
	if value.version != 2 or value.size() != 9: return false
	if not value.get("manual_unlocked") is bool or not value.get("completion") is String: return false
	if value.completion not in ["locked", "completed", "skipped"]: return false
	if value.manual_unlocked != (value.completion != "locked"): return false
	for key in ["internal_power", "initialized", "boot_started", "dock_locked"]:
		if not value.get(key) is bool: return false
	if not value.internal_power: return false
	if not VehicleSnapshot._number(value.get("internal_charge")) or value.internal_charge < 0.0 or value.internal_charge > 100.0: return false
	if not VehicleSnapshot._number(value.get("boot_elapsed")) or value.boot_elapsed < 0.0 or value.boot_elapsed > 6.0: return false
	if value.initialized != (value.boot_started and value.boot_elapsed == 6.0): return false
	if not value.boot_started and value.boot_elapsed != 0.0: return false
	return value.dock_locked == (not value.initialized)

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
					if job.has("crouching") and (not job.crouching is bool or job.recipe != "printed_player"): return false
					if job.has("print_orientation") or job.has("print_offset"):
						if job.recipe == "printed_player" or not job.has_all(["print_orientation", "print_offset"]): return false
						if not job.print_orientation is int or job.print_orientation < 0 or job.print_orientation > 2: return false
						if not job.print_offset is int or job.print_offset < 0 or job.print_offset >= CraftingOutputPlacement.OFFSETS.size(): return false
					if not job.recipe is String or RecipeCatalog.find(job.recipe) == null or not VehicleSnapshot._number(job.remaining) or job.remaining < 0 or not VehicleSnapshot._number(job.power) or job.power < 0 or not job.costs is Dictionary or not MaterialStorage.new().valid_amounts(job.costs): return false
			"inputs":
				if scene != "res://equipment/scrapper.tscn" or not service.inputs is Array: return false
				for input in service.inputs:
					if not input is Dictionary or not input.has_all(["scene", "state", "timer", "local_position", "physics"]): return false
					if input.has("feed") and (not input.feed is Dictionary or not CheckpointSchema.valid_transform(input.feed.get("start")) or not CheckpointSchema.valid_transform(input.feed.get("pose"))): return false
					if input.has("feed") and input.feed.has("progress") and (not VehicleSnapshot._number(input.feed.progress) or input.feed.progress < 0 or input.feed.progress > 1): return false
					if not input.scene is String or not input.state is Dictionary or not valid(input.scene, input.state) or not VehicleSnapshot._number(input.timer) or input.timer < 0 or not CheckpointSchema.vector(input.local_position) or not CheckpointSchema.physics(input.physics, true): return false
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

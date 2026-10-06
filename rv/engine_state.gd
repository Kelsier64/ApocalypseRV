extends RefCounted
class_name EngineState
var id: String = InstanceIds.create()
var model_id: String = "standard"
var health: float = 450.0
var item_data: Dictionary = {}
static func definition_for(model: String) -> EngineDefinition:
	if model == "standard": return preload("res://rv/engine_standard.tres")
	if model == "upgraded": return preload("res://rv/engine_upgraded.tres")
	return null
func definition() -> EngineDefinition:
	return definition_for(model_id)
func _init(data: Dictionary = {}) -> void:
	id = data.get("id", id)
	model_id = data.get("model", "standard")
	health = float(data.get("health", definition().max_health if definition() else 0.0))
	item_data = data.get("item_data", {}).duplicate(true)
func snapshot() -> Dictionary:
	return {"id": id, "model": model_id, "health": health, "item_data": item_data.duplicate(true)}
func item() -> Dictionary:
	var state := item_data.duplicate(true)
	state.merge({"id": id, "condition": health * 100.0 / definition().max_health, "engine": snapshot()}, true)
	return {"name": definition().display_name, "is_large": true, "scene_path": "res://props/engine_" + model_id + ".tscn", "state": state}
static func valid(value: Variant, allow_empty: bool = true) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return allow_empty
	if not ItemState.valid_slot_data(value.get("item_data", {})): return false
	if not value.has_all(["id", "model", "health"]) or not value.id is String or value.id.is_empty() or not value.model is String: return false
	var spec := definition_for(value.model)
	return spec != null and (value.health is float or value.health is int) and is_finite(float(value.health)) and value.health >= 0.0 and value.health <= spec.max_health

static func unique_ids(data: Dictionary) -> bool:
	var seen := {}
	return _collect_engine_ids(data, seen)
static func _collect_engine_ids(value: Variant, seen: Dictionary) -> bool:
	if value is Array:
		for child in value:
			if not _collect_engine_ids(child, seen): return false
	elif value is Dictionary:
		for key in value:
			var child: Variant = value[key]
			if key in ["engine", "engine_item"] and child is Dictionary and not child.is_empty():
				if not EngineState.valid(child, false) or seen.has(child.id): return false
				seen[child.id] = true
			elif not _collect_engine_ids(child, seen): return false
	return true

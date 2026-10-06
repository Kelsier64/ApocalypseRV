extends Resource
class_name BatteryState

var id: String = InstanceIds.create()
var capacity: float = 100.0
var charge: float = 100.0
var condition: float = 100.0
var weight: float = 15.0
var scene_path: String = "res://props/battery.tscn"
var item_data: Dictionary = {}

func snapshot() -> Dictionary:
	return {"id": id, "capacity": capacity, "charge": charge, "weight": weight, "condition": condition, "scene_path": scene_path, "item_data": item_data.duplicate(true)}

func _init(data: Dictionary = {}) -> void:
	if data.is_empty(): return
	id = str(data.get("id", id))
	capacity = clampf(float(data.get("capacity", 100.0)), 1.0, 1000.0)
	charge = clampf(float(data.get("charge", 0.0)), 0.0, capacity)
	weight = clampf(float(data.get("weight", 15.0)), 1.0, 200.0)
	condition = clampf(float(data.get("condition", 100.0)), 0.0, 100.0)
	scene_path = str(data.get("scene_path", scene_path))
	item_data = data.get("item_data", {}).duplicate(true)

func item_state() -> Dictionary:
	var state := item_data.duplicate(true)
	state.merge({"id": id, "condition": condition, "battery": snapshot()}, true)
	return state

func item() -> Dictionary:
	return {"name": ItemNames.BATTERY, "is_large": false, "scene_path": scene_path, "state": item_state()}

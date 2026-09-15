extends Resource
class_name BatteryState

var id: String = InstanceIds.create()
var capacity: float = 100.0
var charge: float = 100.0
var weight: float = 15.0

func snapshot() -> Dictionary:
	return {"id": id, "capacity": capacity, "charge": charge, "weight": weight}

func _init(data: Dictionary = {}) -> void:
	if data.is_empty(): return
	id = str(data.get("id", id))
	capacity = clampf(float(data.get("capacity", 100.0)), 1.0, 1000.0)
	charge = clampf(float(data.get("charge", 0.0)), 0.0, capacity)
	weight = clampf(float(data.get("weight", 15.0)), 1.0, 200.0)

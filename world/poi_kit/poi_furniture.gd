@tool
extends Node3D
class_name PoiFurniture
## The occupied envelope and collision are independent of the visual model.
@export var furniture_id: StringName = &""
@export var footprint := Vector3.ONE

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if furniture_id.is_empty() or footprint.x <= 0 or footprint.y <= 0 or footprint.z <= 0:
		errors.append("Invalid furniture metadata: " + str(name))
	for required in ["Visuals", "Collision", "LootSpawns"]:
		if not has_node(required):
			errors.append("Missing furniture layer: " + required)
	if has_node("LootSpawns"):
		var ids: Array[StringName] = []
		for point in $LootSpawns.get_children():
			if point is PoiLootPoint:
				errors.append_array(point.validate())
				if ids.has(point.point_id):
					errors.append("Duplicate furniture loot ID")
				ids.append(point.point_id)
	return errors

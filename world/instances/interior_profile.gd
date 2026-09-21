@tool
extends Resource
class_name InteriorProfile
@export var profile_id: StringName = &"maintenance_v2"
@export var content_version := 1
@export var rooms: Array[InteriorRoomDefinition] = []
@export var min_rooms := 50
@export var max_rooms := 100
@export var floor_spacing := 6.0
@export var floor_count := 2
@export var loot_budget := 36
@export var enemy_budget := 8

func room(id: String) -> InteriorRoomDefinition:
	for definition in rooms:
		if str(definition.id) == id: return definition
	return null

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Array[StringName] = []
	for definition in rooms:
		if definition == null:
			errors.append("Missing room definition")
			continue
		if definition.id in ids: errors.append("Duplicate room: " + str(definition.id))
		ids.append(definition.id)
		errors.append_array(definition.validate())
	for required in ["entry", "junction", "stairs", "depot"]:
		if room(required) == null: errors.append("Missing route room: " + required)
	if floor_spacing != 6.0 or floor_count != 2 or min_rooms < 12 or max_rooms > 100 or min_rooms > max_rooms:
		errors.append("Unsupported profile dimensions/budget")
	return errors

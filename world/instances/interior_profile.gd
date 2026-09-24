@tool
extends Resource
class_name InteriorProfile
@export var profile_id: StringName = &"bunker"
@export var rooms: Array[InteriorRoomDefinition] = []
@export var group_weights: Dictionary = {"passage": 18.0, "corridor": 12.0, "small": 25.0, "medium": 22.0, "large": 15.0, "hall": 8.0}
@export var min_rooms := 10
@export var max_rooms := 30
@export var floor_spacing := 4.5
@export var max_floors := 3

func room(id: String, version := -1) -> InteriorRoomDefinition:
	for definition in rooms:
		if str(definition.id) == id and (version < 0 or definition.content_version == version): return definition
	return null

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Array[String] = []
	var entry_count := 0
	for definition in rooms:
		if definition == null:
			errors.append("Missing room definition")
			continue
		var key := "%s:%d" % [definition.id, definition.content_version]
		if key in ids: errors.append("Duplicate room version: " + key)
		ids.append(key)
		var room_errors := definition.validate()
		errors.append_array(room_errors)
		if not room_errors.is_empty(): continue
		if definition.role == &"stairs":
			var heights: Array[float] = []
			for socket: Dictionary in definition.describe().sockets.values(): heights.append(socket.transform.origin.y)
			if heights.size() < 2 or not is_zero_approx(heights.min()) or not is_equal_approx(heights.max(), floor_spacing):
				errors.append("Stair sockets must span the profile floor spacing")
		if definition.enabled and definition.role == &"entry": entry_count += 1
		if definition.enabled and definition.role == &"ordinary" and not group_weights.has(str(definition.selection_group)):
			errors.append("Missing selection group: " + str(definition.selection_group))
	for weight in group_weights.values():
		if not (weight is float or weight is int) or not is_finite(weight) or weight < 0: errors.append("Invalid group weight")
	if entry_count != 1 or min_rooms < 1 or max_rooms > 30 or min_rooms > max_rooms or not is_finite(floor_spacing) or floor_spacing <= 0 or max_floors < 1 or max_floors > 3:
		errors.append("Invalid bunker entry/dimensions/budget")
	return errors

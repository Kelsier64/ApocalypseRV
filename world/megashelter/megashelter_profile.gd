@tool
extends Resource
class_name MegashelterProfile
## Exterior dimensions only; these are not playable floor plans.
const CONTENT_VERSION := 4
const BAY := 4.0
const FLOOR := 4.5
const BAND := 13.5
@export var widths := PackedInt32Array([48, 56, 64])
@export var depths := PackedInt32Array([32, 40, 48])
@export var heights := PackedFloat32Array([54.0, 67.5, 81.0])

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if widths.is_empty() or depths.is_empty() or heights.is_empty():
		errors.append("Exterior dimension choices cannot be empty")
	for value in widths:
		if value < 48 or value > 64 or value % 4 != 0: errors.append("Invalid exterior width")
	for value in depths:
		if value < 32 or value > 48 or value % 4 != 0: errors.append("Invalid exterior depth")
	for value in heights:
		if not is_finite(value) or value < 54.0 or value > 81.0 or not is_equal_approx(fposmod(value, FLOOR), 0.0):
			errors.append("Invalid exterior height")
	return errors

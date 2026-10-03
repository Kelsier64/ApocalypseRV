class_name PlayerBodyState
extends RefCounted
## Persistent limb presence; health and detached physics remain owned by Player.

const PARTS: Array[StringName] = [&"head", &"left_arm", &"right_arm", &"left_leg", &"right_leg"]
var present: Dictionary = {"head": true, "left_arm": true, "right_arm": true, "left_leg": true, "right_leg": true}

func has_part(part: StringName) -> bool:
	return bool(present.get(String(part), false))

func sever(part: StringName) -> bool:
	if not PARTS.has(part) or not has_part(part): return false
	present[String(part)] = false
	return true

func reset() -> void:
	for part: StringName in PARTS: present[String(part)] = true

func capture() -> Dictionary:
	return {"version": 1, "present": present.duplicate()}

func restore(data: Dictionary) -> void:
	if data.is_empty():
		reset()
	elif valid_state(data):
		present = data.present.duplicate()

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 2: return false
	if not data.get("version") is int or data.version != 1: return false
	var values: Variant = data.get("present")
	if not values is Dictionary or values.size() != PARTS.size(): return false
	for part: StringName in PARTS:
		if not values.get(String(part)) is bool: return false
	return true

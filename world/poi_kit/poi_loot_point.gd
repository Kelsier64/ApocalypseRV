@tool
extends Marker3D
class_name PoiLootPoint
## An authoring marker only: loading a room NEVER spawns or rerolls loot.
## The instance owner snapshots remaining actors; reentry never rerolls markers.

@export var point_id: StringName = &""
@export var category: StringName = &"metal"
@export_range(0.0, 1.0) var spawn_chance: float = 0.7
@export var candidates: Array[PackedScene] = []

func roll_scene(rng: RandomNumberGenerator) -> PackedScene:
	if rng == null or candidates.is_empty() or rng.randf() >= spawn_chance:
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if point_id.is_empty():
		errors.append("Loot point needs a stable ID: " + str(name))
	if candidates.is_empty() or candidates.has(null):
		errors.append("Loot point needs valid candidate scenes: " + str(name))
	return errors

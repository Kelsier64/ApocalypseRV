@tool
extends Resource
class_name PoiDefinition
## Immutable authoring data. Site instances, loot and save state belong to world owners.
enum Kind { INSTANCE_ENTRANCE, WALK_IN }
@export var definition_id: StringName
@export var display_name: String
@export var kind: Kind = Kind.INSTANCE_ENTRANCE
@export_file("*.tscn") var scene_path: String
@export_range(1, 1000) var content_version: int = 1
## Building-local bounds: solid structure vs required clear approach/service area.
@export var building_bounds := AABB(Vector3(-12, -0.5, -10), Vector3(24, 19, 18))
@export var site_bounds := AABB(Vector3(-14, -0.5, -12), Vector3(28, 19, 24))
@export var entrance_path: NodePath = ^"Entrance"
@export var return_path: NodePath = ^"ReturnPoint"
@export var access_paths: Array[NodePath] = []
@export var interior_profile: StringName = &"bunker"
## Existing procedural silhouettes are explicitly grandfathered, not strict assets.
@export var legacy_visual_layout := false

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if definition_id.is_empty(): errors.append("Missing definition ID")
	if display_name.is_empty(): errors.append("Missing display name")
	if kind not in [Kind.INSTANCE_ENTRANCE, Kind.WALK_IN]: errors.append("Unknown POI kind")
	if content_version < 1: errors.append("Content version must be positive")
	if not scene_path.begins_with("res://") or not ResourceLoader.exists(scene_path, "PackedScene"):
		errors.append("Missing scene: " + scene_path)
	for bounds in [building_bounds, site_bounds]:
		if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0 or bounds.size.y <= 0 or bounds.size.z <= 0:
			errors.append("Bounds must be finite and positive")
	if not site_bounds.encloses(building_bounds): errors.append("Site bounds must enclose building")
	if kind == Kind.INSTANCE_ENTRANCE:
		if entrance_path.is_empty() or return_path.is_empty() or interior_profile.is_empty():
			errors.append("Instance entrance needs entrance, return and interior profile")
		for path in [entrance_path, return_path]:
			if path.is_absolute() or ".." in str(path).split("/"):
				errors.append("Transition paths must stay inside the building")
	elif kind == Kind.WALK_IN:
		if access_paths.is_empty(): errors.append("Walk-in building needs access markers")
		if not entrance_path.is_empty() or not return_path.is_empty() or not interior_profile.is_empty():
			errors.append("Walk-in building must not declare instance transition data")
	var seen: Array[NodePath] = []
	for path in access_paths:
		if path.is_empty() or path.is_absolute() or ".." in str(path).split("/") or path in seen:
			errors.append("Invalid or duplicate local access path: " + str(path))
		seen.append(path)
	return errors

func validate_scene(building: Node3D) -> PackedStringArray:
	var errors := validate()
	if not errors.is_empty(): return errors
	if building == null:
		errors.append("Missing building instance")
		return errors
	if not building.scale.is_equal_approx(Vector3.ONE): errors.append("Building root scale must be one")
	for layer in ["Visuals", "Collision", "Furnishings", "LootSpawns"]:
		if not building.get_node_or_null(layer) is Node3D: errors.append("Missing layer: " + layer)
	if kind == Kind.INSTANCE_ENTRANCE:
		if not building.get_node_or_null(entrance_path) is PoiEntrance: errors.append("Entrance must be PoiEntrance")
		if not building.get_node_or_null(return_path) is Marker3D: errors.append("Return point must be Marker3D")
	else:
		for node in building.find_children("*", "", true, false):
			if node is PoiEntrance or node is SubViewport: errors.append("Walk-in asset contains a transition node")
	for path in access_paths:
		var marker := building.get_node_or_null(path) as Marker3D
		if marker == null:
			errors.append("Missing access marker: " + str(path))
		elif not site_bounds.has_point(_local_position(building, marker)):
			errors.append("Access marker outside site bounds: " + str(path))
	if not legacy_visual_layout:
		for layer in building.find_children("Visuals", "Node3D", true, false):
			for node in layer.find_children("*", "", true, false):
				if node is CollisionObject3D or node is CollisionShape3D or node is PoiLootPoint:
					errors.append("Visuals must not own collision or loot: " + str(node.name))
	for node in building.find_children("*", "Marker3D", true, false):
		if node is PoiLootPoint: errors.append_array(node.validate())
	return errors

func _local_position(root: Node3D, child: Node3D) -> Vector3:
	var pose := Transform3D.IDENTITY
	var node: Node = child
	while node != root:
		if node is Node3D: pose = node.transform * pose
		node = node.get_parent()
	return pose.origin

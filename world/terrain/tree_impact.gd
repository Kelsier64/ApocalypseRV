extends RefCounted
class_name TreeImpact
## Actual chassis contacts only; scenery never scans the world each frame.
const MIN_SPEED := 3.0
const SPEED_RETAINED := 0.85

static func damage(speed: float) -> float:
	return clampf(speed * speed * 0.25, 3.0, 80.0)

static func forest_id(band: int, index: int) -> String:
	return "forest:%d:%d" % [band, index]

static func roadside_id(point: Vector3) -> String:
	return "roadside:%.4f:%.4f" % [point.x, point.z]

static func valid_ledger(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 20000: return false
	for key in value:
		if not key is String or key.length() > 96: return false
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 3: return false
		if parts[0] == "forest":
			if not parts[1].is_valid_int() or not parts[2].is_valid_int(): return false
			if absi(parts[1].to_int()) > 1000000 or parts[2].to_int() < 0 or parts[2].to_int() >= 2128: return false
		elif parts[0] == "roadside":
			if not parts[1].is_valid_float() or not parts[2].is_valid_float(): return false
			if not is_finite(parts[1].to_float()) or not is_finite(parts[2].to_float()): return false
		else: return false
		if not value[key] is bool or not value[key]: return false
	return true

static func target_for(collider: Node) -> Node:
	var target := collider
	while target != null and not target.has_method("vehicle_tree_impact"):
		target = target.get_parent()
	return target

static func hit(rv: Chassis, collider: Node, shape_index: int, velocity: Vector3, normal: Vector3) -> bool:
	if not velocity.is_finite() or not normal.is_finite() or absf(normal.y) > 0.65: return false
	var speed := velocity.slide(Vector3.UP).length()
	# Rounded bumper/side contacts can approach a trunk obliquely. Do not let
	# the solver brake a driving RV to zero before a frontal normal appears.
	if speed < MIN_SPEED or -velocity.dot(normal.normalized()) < 0.1: return false
	var target := target_for(collider)
	if target == null or not target.vehicle_tree_impact(shape_index, velocity, rv.global_position): return false
	rv.take_damage(damage(speed))
	rv.service_message = "撞毀樹木｜引擎耐久 -%.0f" % damage(speed)
	rv.feedback("blocked")
	return true

static func topple(node: Node3D, direction: Vector3, vehicle_position: Vector3 = Vector3.INF) -> void:
	TreeFall.spawn(node, direction, vehicle_position)

static func navigation_changed(chunk: ChunkGenerator, point: Vector3) -> void:
	chunk.request_navigation_rebuild()
	var generator := chunk.get_parent()
	if generator.has_method("tree_navigation_changed"):
		generator.tree_navigation_changed(chunk, point)

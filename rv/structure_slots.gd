extends Node3D
class_name RVStructureSlots
## Fixed sockets and their state survive destruction; all geometry is slot-owned.
const GROUP := "rv_structure_slots"
const TYPES := {
	"rv_side_panel": "res://equipment/rv_side_panel_definition.tres",
	"rv_side_door": "res://equipment/rv_side_door_definition.tres",
	"rv_rear_door": "res://equipment/rv_rear_door_definition.tres",
	"rv_wall_front": "res://equipment/rv_wall_front_definition.tres",
	"rv_ceiling": "res://equipment/rv_ceiling_definition.tres",
	"rv_ceiling_hatch": "res://equipment/rv_ceiling_hatch_definition.tres",
	"rv_floor": "res://equipment/rv_floor_definition.tres",
}
var construction: Node
var revision: int = 0
var _panels: Dictionary = {}

static func layout() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for side in ["right", "left"]:
		for i in range(3):
			slots.append({"id": side + "_" + str(i), "kind": "side", "label": ("右側" if side == "right" else "左側") + ["前段", "中段", "後段"][i],
				"pose": Transform3D(Basis(Vector3.UP, PI / 2.0 if side == "right" else -PI / 2.0), Vector3(1.9 if side == "right" else -1.9, 1.5, -4.0 + i * 4.0)),
				"size": Vector3(3.96, 1.98, 0.2), "center": Vector3.ZERO})
	slots.append({"id": "rear", "kind": "rear", "label": "後方大門", "pose": Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 5.9)), "size": Vector3(3.6, 1.98, 0.2), "center": Vector3.ZERO})
	slots.append({"id": "front", "kind": "front", "label": "車頭", "pose": Transform3D(Basis.IDENTITY, Vector3(0, 1, -5.9)), "size": Vector3(3.6, 2, 0.2), "center": Vector3(0, 0.5, 0)})
	for i in range(3):
		slots.append({"id": "roof_" + str(i), "kind": "roof", "label": "屋頂" + ["前段", "中段", "後段"][i],
			"pose": Transform3D(Basis.IDENTITY, Vector3(0, 2.6005738, -4.0 + i * 4.0)),
			"size": Vector3(4, 0.2, 4), "center": Vector3.ZERO})
	slots.append({"id": "floor", "kind": "floor", "label": "地板", "pose": Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)), "size": Vector3(4, 0.2, 12), "center": Vector3.ZERO})
	return slots

static func definition_for(type_id: String) -> RVStructureDefinition:
	return load(TYPES[type_id]) as RVStructureDefinition if TYPES.has(type_id) else null

static func slot_info(slot_id: String) -> Dictionary:
	for slot in layout():
		if slot.id == slot_id: return slot
	return {}

static func types_for_slot(slot_id: String) -> Array[String]:
	var slot := slot_info(slot_id)
	var result: Array[String] = []
	if slot.is_empty(): return result
	for type_id in TYPES:
		if definition_for(type_id).slot_kind == slot.kind: result.append(type_id)
	return result

func _ready() -> void:
	add_to_group(GROUP)
	construction = load("res://rv/structure_construction.gd").new()
	construction.name = "Construction"
	add_child(construction)
	call_deferred("_initialize_panels")

func _initialize_panels() -> void:
	for child in get_parent().get_children():
		if child is RVStructurePanel: register_panel(child)
	for slot in layout():
		if panel(slot.id) == null:
			replace_panel(slot.id, types_for_slot(slot.id)[0], 0.0)

func register_panel(part: RVStructurePanel) -> void:
	if part.mount_slot.is_empty(): part.mount_slot = identify(part.transform, part.structure_kind)
	var slot := slot_info(part.mount_slot)
	if slot.is_empty() or part.definition == null or not part.definition.type_id in types_for_slot(part.mount_slot): return
	var previous: RVStructurePanel = _panels.get(part.mount_slot)
	if is_instance_valid(previous) and previous != part: return
	_panels[part.mount_slot] = part
	if not part.availability_changed.is_connected(_changed): part.availability_changed.connect(_changed)
	_changed()

func _changed() -> void:
	revision += 1
	if get_parent().has_signal("structure_changed"): get_parent().structure_changed.emit()

func panel(slot_id: String) -> RVStructurePanel:
	var result: RVStructurePanel = _panels.get(slot_id)
	if is_instance_valid(result) and not result.is_queued_for_deletion(): return result
	for child in get_parent().get_children():
		if child is RVStructurePanel and child.mount_slot == slot_id and not child.is_queued_for_deletion(): return child
	return null

func occupant(slot_id: String) -> RVStructurePanel:
	var part := panel(slot_id)
	return part if is_instance_valid(part) and not part.is_destroyed else null

func identify(pose: Transform3D, kind: String) -> String:
	for slot in layout():
		if slot.kind == kind and slot.pose.origin.distance_to(pose.origin) < 0.03 and slot.pose.basis.is_equal_approx(pose.basis): return slot.id
	return ""

func replace_panel(slot_id: String, type_id: String, health: float) -> RVStructurePanel:
	if not type_id in types_for_slot(slot_id): return null
	var definition := definition_for(type_id)
	var next := load(definition.scene_path).instantiate() as RVStructurePanel
	if next == null: return null
	var previous := panel(slot_id)
	var part_name: String = str(previous.name) if previous else "Structure_" + slot_id
	if previous:
		previous.removing.emit()
		_panels.erase(slot_id)
		previous.free()
	next.name = part_name
	next.mount_slot = slot_id
	next.transform = slot_info(slot_id).pose
	get_parent().add_child(next)
	next.set_health(health)
	register_panel(next)
	return next

func is_building() -> bool:
	return is_instance_valid(construction) and construction.is_building()

func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in layout():
		var part := panel(slot.id)
		var type_id: String = part.definition.type_id if part else types_for_slot(slot.id)[0]
		var angles: Array = part.angles.duplicate() if part and part.has_method("restore_angles") else []
		if part == null and type_id == "rv_rear_door": angles = [0.0, 0.0]
		result.append({"slot": slot.id, "type": type_id, "health": part.current_health if part else 0.0, "door_angles": angles})
	return result

static func validate_snapshot(data: Variant) -> bool:
	if not data is Array or data.size() != layout().size(): return false
	var seen := {}
	for entry in data:
		if not entry is Dictionary or not entry.has_all(["slot", "type", "health", "door_angles"]): return false
		if not entry.slot is String or not entry.type is String or seen.has(entry.slot): return false
		if not entry.type in types_for_slot(entry.slot): return false
		var definition := definition_for(entry.type)
		if not (entry.health is float or entry.health is int) or not is_finite(float(entry.health)) or entry.health < 0.0 or entry.health > definition.health: return false
		var count := 2 if entry.type == "rv_rear_door" else (1 if entry.type == "rv_side_door" else 0)
		if not entry.door_angles is Array or entry.door_angles.size() != count: return false
		for index in range(entry.door_angles.size()):
			var angle: Variant = entry.door_angles[index]
			if not (angle is float or angle is int) or not is_finite(float(angle)) or absf(float(angle)) > deg_to_rad(100.0) + 0.001: return false
			if (index == 0 and angle > 0.0) or (index == 1 and angle < 0.0): return false
		seen[entry.slot] = true
	return true

func restore(data: Array) -> void:
	if not validate_snapshot(data): return
	if is_instance_valid(construction): construction.cancel("載入車體狀態")
	for entry in data:
		var part := replace_panel(entry.slot, entry.type, entry.health)
		if part.has_method("restore_angles"): part.restore_angles(entry.door_angles)

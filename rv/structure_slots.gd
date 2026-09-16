extends Node3D
class_name RVStructureSlots
## Removing a panel never removes its chassis-owned socket.
const GROUP := "rv_structure_slots"
static func layout() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for side in ["right", "left"]:
		for i in range(3):
			slots.append({"id": side + "_" + str(i), "kind": "side", "label": ("右側" if side == "right" else "左側") + ["前段", "中段", "後段"][i],
				"pose": Transform3D(Basis(Vector3.UP, PI / 2.0 if side == "right" else -PI / 2.0), Vector3(1.9 if side == "right" else -1.9, 1.5, -4.0 + i * 4.0)),
				"size": Vector3(3.96, 1.98, 0.2), "center": Vector3.ZERO})
	slots.append({"id": "rear", "kind": "rear", "label": "後方大門", "pose": Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 5.9)), "size": Vector3(3.6, 1.98, 0.2), "center": Vector3.ZERO})
	slots.append({"id": "front", "kind": "front", "label": "車頭", "pose": Transform3D(Basis.IDENTITY, Vector3(0, 1, -5.9)), "size": Vector3(3.6, 2, 0.2), "center": Vector3(0, 0.5, 0)})
	slots.append({"id": "roof", "kind": "roof", "label": "屋頂", "pose": Transform3D(Basis.IDENTITY, Vector3(0, 2.6005738, 0)), "size": Vector3(4, 0.2, 12), "center": Vector3.ZERO})
	return slots

var outlines: Dictionary = {}
var preview: WeakRef

func _process(_delta: float) -> void:
	var device: Object = preview.get_ref() if preview else null
	if device == null or not device.is_being_placed: hide_outlines()

func _ready() -> void:
	add_to_group(GROUP)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.85, 0.9)
	for slot in layout():
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		var half: Vector3 = slot.size * 0.5
		var corners: Array[Vector3] = []
		for i in range(8):
			corners.append(slot.center + Vector3(half.x if i & 1 else -half.x, half.y if i & 2 else -half.y, half.z if i & 4 else -half.z))
		for i in range(8):
			for bit in [1, 2, 4]:
				if (i & bit) == 0:
					mesh.surface_add_vertex(corners[i])
					mesh.surface_add_vertex(corners[i | bit])
		mesh.surface_end()
		var outline := MeshInstance3D.new()
		outline.mesh = mesh
		outline.transform = slot.pose
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outline.visible = false
		add_child(outline)
		outlines[slot.id] = outline

func show_empty(kind: String, ignored: Equipment) -> void:
	preview = weakref(ignored)
	for slot in layout():
		outlines[slot.id].visible = slot.kind == kind and occupant(slot.id, ignored) == null
func hide_outlines() -> void:
	for outline in outlines.values(): outline.hide()
func occupant(slot_id: String, ignored: Equipment = null) -> Equipment:
	for device in get_parent().get_equipment():
		if device == ignored or device.is_destroyed or device.is_being_placed: continue
		if device.get("mount_slot") == slot_id: return device
	return null
func identify(pose: Transform3D, kind: String) -> String:
	for slot in layout():
		if slot.kind == kind and slot.pose.origin.distance_to(pose.origin) < 0.03 and slot.pose.basis.is_equal_approx(pose.basis):
			return slot.id
	return ""
func pick(from: Vector3, direction: Vector3, reach: float, kind: String) -> Dictionary:
	var best: Dictionary = {}
	for slot in layout():
		if slot.kind != kind: continue
		var pose: Transform3D = global_transform * slot.pose
		var inverse := pose.affine_inverse()
		var origin := inverse * from
		var ray := inverse.basis * direction
		var axis := 1 if slot.kind == "roof" else 2
		if absf(ray[axis]) < 0.0001: continue
		var distance: float = (slot.center[axis] - origin[axis]) / ray[axis]
		if distance < 0.0 or distance > reach: continue
		var hit: Vector3 = origin + ray * distance - slot.center
		var half: Vector3 = slot.size * 0.5 + Vector3.ONE * 0.12
		if absf(hit.x) > half.x or absf(hit.y) > half.y or absf(hit.z) > half.z: continue
		if best.is_empty() or distance < best.distance:
			best = {"id": slot.id, "label": slot.label, "pose": pose, "distance": distance, "manager": self}
	return best

extends "res://equipment/rv_panel.gd"
## Hinged collision shapes stay owned by the frame Equipment, including damage and F gestures.
@export var leaf_count: int = 1
@export var leaf_width: float = 1.18
@export var hinge_span: float = 1.2
var angles: Array[float] = []
var targets: Array[float] = []
var open_requested: Array[bool] = []
var before_move: Array[float] = []
var blocked_message: String = ""

## Boarding uses the real leaf bounds; the surrounding frame is a roof climb route.
func boarding_leaf_at(point: Vector3) -> int:
	for index in range(angles.size()):
		if not boarding_leaf_closed(index): continue
		var shape: CollisionShape3D = get_node("LeafCollision" + str(index))
		var half: Vector3 = shape.shape.size * 0.5 + Vector3(0.04, 0.04, 0.08)
		if AABB(-half, half * 2.0).has_point(shape.to_local(point)): return index
	return -1

func boarding_leaf_closed(index: int) -> bool:
	return can_operate() and index >= 0 and index < angles.size() and absf(angles[index]) < deg_to_rad(12.0) and not open_requested[index]

func boarding_entry_point(index: int) -> Vector3:
	var offset := hinge_span * 0.25 * (1.0 if index == 0 else -1.0) if leaf_count == 2 else leaf_width * 0.5 + 0.01
	return to_global(leaf_pose(index, 0.0) * Vector3(offset, -0.03, 0.0))

func _ready() -> void:
	super._ready()
	for index in range(leaf_count):
		angles.append(0.0)
		targets.append(0.0)
		open_requested.append(false)
		get_node("LeafCollision" + str(index)).set_meta("door_leaf", index)
	_sync_leaves()

func leaf_pose(index: int, angle: float) -> Transform3D:
	var sign_side := -1.0 if index == 0 else 1.0
	var hinge := Vector3(sign_side * hinge_span * 0.5, 0, 0)
	return Transform3D(Basis(Vector3.UP, angle), hinge)

func _sync_leaves() -> void:
	for index in range(angles.size()):
		var pivot := leaf_pose(index, angles[index])
		get_node("Leaf" + str(index)).transform = pivot
		var sign_side := 1.0 if index == 0 else -1.0
		get_node("LeafCollision" + str(index)).transform = pivot * Transform3D(Basis.IDENTITY, Vector3(sign_side * hinge_span * 0.25 if leaf_count == 2 else leaf_width * 0.5 + 0.01, -0.03, 0))

func _physics_process(delta: float) -> void:
	if not can_operate(): return
	for index in range(angles.size()):
		if is_equal_approx(angles[index], targets[index]): continue
		var next := move_toward(angles[index], targets[index], minf(delta * 1.7, 0.06))
		var reason := swing_blocker(index, angles[index], next)
		if not reason.is_empty():
			targets[index] = angles[index]
			blocked_message = "門被 " + reason + " 擋住，移開後再按 E"
			get_connected_rv().feedback("blocked", position)
			continue
		angles[index] = next
		if is_equal_approx(next, targets[index]): get_connected_rv().feedback("mechanical", position)
	_sync_leaves()

func swing_blocker(index: int, start: float, finish: float) -> String:
	var collider: CollisionShape3D = get_node("LeafCollision" + str(index))
	var box := collider.shape.duplicate() as BoxShape3D
	# Extra depth covers the tiny arcs between angular samples.
	box.size += Vector3(0.005, -0.02, 0.05)
	var steps := maxi(1, ceili(absf(finish - start) / deg_to_rad(2.0)))
	var offset := hinge_span * 0.25 * (1.0 if index == 0 else -1.0) if leaf_count == 2 else leaf_width * 0.5 + 0.01
	for step in range(1, steps + 1):
		var angle := lerpf(start, finish, float(step) / steps)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = box
		query.transform = global_transform * leaf_pose(index, angle) * Transform3D(Basis.IDENTITY, Vector3(offset, -0.03, 0))
		query.exclude = [get_rid()]
		query.collision_mask = 0xFFFFFFFF
		var hits := get_world_3d().direct_space_state.intersect_shape(query, 1)
		if not hits.is_empty(): return PlacementRules.object_name(hits[0].collider)
	return ""

func aimed_leaf(player: Node3D) -> int:
	var ray := player.get_node_or_null("Camera3D/InteractRay") as RayCast3D
	if ray and ray.is_colliding() and ray.get_collider() == self:
		var owner_node := shape_owner_get_owner(shape_find_owner(ray.get_collider_shape()))
		if owner_node is Node and owner_node.has_meta("door_leaf"):
			return int(owner_node.get_meta("door_leaf"))
		return 1 if leaf_count == 2 and to_local(ray.get_collision_point()).x > 0 else 0
	return 0

func interact(player: Node3D) -> String:
	if not can_operate(): return "門尚未安裝到車上或已損壞"
	return toggle_leaf(aimed_leaf(player))

func toggle_leaf(index: int) -> String:
	if not can_operate() or index < 0 or index >= leaf_count: return "門無法操作"
	# A partly blocked leaf can be reversed by the next press.
	var opening := not open_requested[index]
	var goal := (-1.0 if index == 0 else 1.0) * deg_to_rad(100.0) if opening else 0.0
	var blocker := swing_blocker(index, angles[index], goal)
	if not blocker.is_empty():
		blocked_message = "門被 " + blocker + " 擋住，請移開或退後"
		return blocked_message
	blocked_message = ""
	targets[index] = goal
	open_requested[index] = opening
	get_connected_rv().feedback("mechanical", position)
	return "開門中" if opening else "關門中"

func get_interaction_prompt(player: Node3D) -> String:
	if not can_operate(): return equipment_name + "｜尚未接入或已損壞"
	var index := aimed_leaf(player)
	var action := "關門" if open_requested[index] else "開門"
	return equipment_name + (("（左扇）" if index == 0 else "（右扇）") if leaf_count == 2 else "") + "｜E " + action + "\n搬移整組門框；" + dependent_summary() + "\n" + blocked_message

func allows_mount_at(point: Vector3) -> bool:
	for index in range(leaf_count):
		var collider: CollisionShape3D = get_node("LeafCollision" + str(index))
		var half: Vector3 = collider.shape.size * 0.5 + Vector3.ONE * 0.03
		if AABB(-half, half * 2.0).has_point(collider.global_transform.affine_inverse() * point): return false
	return true

func _on_service_stopped() -> void:
	targets.assign(angles)
	if is_being_placed:
		before_move.assign(angles)
		angles.fill(0.0)
		targets.fill(0.0)
		open_requested.fill(false)
		_sync_leaves()

func cancel_placement() -> void:
	var restore := is_being_placed
	super.cancel_placement()
	if restore and before_move.size() == leaf_count:
		angles.assign(before_move)
		targets.assign(angles)
		for index in range(leaf_count): open_requested[index] = absf(angles[index]) > 0.02
		_sync_leaves()

func restore_angles(saved: Array) -> void:
	angles.clear()
	for value in saved: angles.append(float(value))
	targets.assign(angles)
	for index in range(leaf_count): open_requested[index] = absf(angles[index]) > 0.02
	_sync_leaves()

func get_placement_bounds() -> AABB:
	return AABB(Vector3(-1.98 if structure_kind == "side" else -1.8, -0.99, -0.1), Vector3(3.96 if structure_kind == "side" else 3.6, 1.98, 0.2))

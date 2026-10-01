extends Node3D
class_name ShelterGarageGate
## The two physical leaves slide in physics time; an occupied sweep reopens them.
signal opened
signal closed
signal obstructed
const TRAVEL := 3.6
const DURATION := 2.4
var progress := 0.0
var target := 0.0
var left: AnimatableBody3D
var right: AnimatableBody3D
var left_closed := Vector3(-1.75, 2.5, 0)
var right_closed := Vector3(1.75, 2.5, 0)

func configure() -> void:
	left = get_node("LeftLeaf")
	right = get_node("RightLeaf")
	left.sync_to_physics = false
	right.sync_to_physics = false
	set_physics_process(true)

func snap(open: bool) -> void:
	progress = 1.0 if open else 0.0
	target = progress
	_apply_pose()

func move_to(open: bool) -> void:
	target = 1.0 if open else 0.0

func stable() -> bool:
	return is_equal_approx(progress, target)

func is_open() -> bool:
	return progress >= 0.999 and target == 1.0

func sweep_occupied() -> bool:
	if not is_inside_tree(): return false
	var shape := BoxShape3D.new()
	# Cover each leaf's full travel, excluding floor/lintel boundary contact.
	shape.size = Vector3(3.5 + TRAVEL, 4.84, 0.7)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 3
	query.exclude = [left.get_rid(), right.get_rid()]
	for side in [-1.0, 1.0]:
		query.transform = global_transform * Transform3D(Basis.IDENTITY, Vector3(side * (1.75 + TRAVEL * 0.5), 2.5, 0))
		for hit in get_world_3d().direct_space_state.intersect_shape(query, 64):
			var body: Node = hit.collider
			if body is CharacterBody3D or body is RigidBody3D:
				return true
	return false

func _physics_process(delta: float) -> void:
	if not is_instance_valid(left) or stable(): return
	if target < progress and sweep_occupied():
		target = 1.0
		obstructed.emit()
	progress = move_toward(progress, target, delta / DURATION)
	_apply_pose()
	if stable():
		progress = target
		_apply_pose()
		if target == 1.0: opened.emit()
		else: closed.emit()

func _apply_pose() -> void:
	if not is_instance_valid(left): return
	left.position = left_closed + Vector3.LEFT * TRAVEL * progress
	right.position = right_closed + Vector3.RIGHT * TRAVEL * progress

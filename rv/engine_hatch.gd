extends StaticBody3D
const CLOSED := Vector3(0, -0.05, -0.58)
const OPEN := Vector3(0, 0.65, -1.35)
@export var travel_seconds := 1.0
var opened := false
var requested_open := false
var progress := 0.0
var moving := false
var blocked_message := ""
func bay() -> Node3D: return get_parent()
func stable() -> bool: return not moving and (progress == 0.0 or progress == 1.0)

func blocker(from: float, to: float) -> String:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape: BoxShape3D = $Collision.shape.duplicate()
	shape.size += Vector3.ONE * 0.02
	query.shape = shape
	query.exclude = [get_rid(), bay().get_rid(), bay().get_parent().get_rid()]
	query.collision_mask = 1
	var steps := maxi(1, ceili(absf(to - from) / 0.02))
	for i in range(1, steps + 1):
		query.transform = Transform3D(global_basis, bay().to_global(CLOSED.lerp(OPEN, lerpf(from, to, float(i) / steps))))
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return "維修蓋被擋住，請退後或移開物品"
	return ""

func interact(_player: Node3D) -> String:
	var rv := bay().get_parent()
	if rv.linear_velocity.length() > 0.5: return "請停穩後操作維修蓋"
	if moving: return "維修蓋移動中，請等停止後再操作"
	var next := not requested_open
	var reason := blocker(progress, 1.0 if next else 0.0)
	if not reason.is_empty(): return reason
	requested_open = next
	moving = true
	opened = false
	bay().hatch_open = false
	blocked_message = ""
	rv.feedback("mechanical")
	return "維修蓋打開中" if next else "維修蓋關閉中"

func _physics_process(delta: float) -> void:
	if not moving: return
	var target := 1.0 if requested_open else 0.0
	var next := move_toward(progress, target, minf(delta / travel_seconds, 0.02))
	var reason := blocker(progress, next)
	if bay().get_parent().linear_velocity.length() > 0.5: reason = "車輛移動，維修蓋已停止"
	if not reason.is_empty():
		moving = false
		blocked_message = reason
		bay().get_parent().service_message = reason
		bay().get_parent().feedback("blocked")
		return
	progress = next
	position = CLOSED.lerp(OPEN, progress)
	if progress == target:
		moving = false
		opened = requested_open
		bay().hatch_open = opened
		bay().get_parent().feedback("mechanical")

func set_open(value: bool) -> void:
	# Stable-state restoration only. Interactive operation always animates.
	opened = value
	requested_open = value
	progress = 1.0 if value else 0.0
	moving = false
	blocked_message = ""
	bay().hatch_open = value
	position = OPEN if value else CLOSED
func get_interaction_prompt(_player: Node3D) -> String:
	return "引擎維修蓋｜" + ("移動中" if moving else "E " + ("關閉" if requested_open else "打開")) + "\n" + blocked_message
func allows_mount_at(_point: Vector3) -> bool: return false

extends StaticBody3D
const CLOSED := Vector3(0, -0.05, -0.58)
const HINGE := Vector3(0, 0.28, -0.53)
const OPEN_ANGLE := deg_to_rad(105.0)
const SWEEP_STEP := deg_to_rad(1.0)
@export_range(0.1, 5.0) var travel_seconds := 1.0
var opened := false
var requested_open := false
var progress := 0.0
var moving := false
var blocked_message := ""
func bay() -> Node3D: return get_parent()
func stable() -> bool: return not moving and (progress == 0.0 or progress == 1.0)

func angle_at(value: float) -> float:
	return OPEN_ANGLE * smoothstep(0.0, 1.0, value)

func pose_at(value: float) -> Transform3D:
	# The cover's top rear edge stays on the chassis-mounted hinge pin.
	var orientation := Basis(Vector3.RIGHT, angle_at(value))
	return Transform3D(orientation, HINGE + orientation * (CLOSED - HINGE))

func apply_pose() -> void:
	transform = pose_at(progress)
	# Both gas stays join fixed bay sockets to sockets on the moving cover.
	for side in [-1, 1]:
		var stay: Node3D = bay().get_node("StayLeft" if side < 0 else "StayRight")
		var base := Vector3(side * 0.65, 0.13, -0.42)
		var tip := transform * Vector3(side * 0.65, -0.2, 0.025)
		var axis := tip - base
		stay.position = base
		stay.quaternion = Quaternion(Vector3.UP, axis.normalized())
		var housing: MeshInstance3D = stay.get_node("Housing")
		var rod: MeshInstance3D = stay.get_node("Rod")
		var length := axis.length()
		var housing_length := 0.32
		housing.position.y = housing_length * 0.5
		housing.scale.y = housing_length
		rod.position.y = (housing_length + length) * 0.5
		rod.scale.y = length - housing_length

func _ready() -> void:
	apply_pose()

func blocker(from: float, to: float) -> String:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape: BoxShape3D = $Collision.shape.duplicate()
	shape.size += Vector3.ONE * 0.02
	query.shape = shape
	query.exclude = [get_rid(), bay().get_rid(), bay().get_parent().get_rid()]
	query.collision_mask = 1
	var start_angle := angle_at(from)
	var end_angle := angle_at(to)
	var steps := maxi(1, ceili(absf(end_angle - start_angle) / SWEEP_STEP))
	for i in range(1, steps + 1):
		var orientation := Basis(Vector3.RIGHT, lerpf(start_angle, end_angle, float(i) / steps))
		var pose := Transform3D(orientation, HINGE + orientation * (CLOSED - HINGE))
		query.transform = bay().global_transform * pose * $Collision.transform
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
	var next := move_toward(progress, target, delta / maxf(travel_seconds, 0.1))
	var reason := blocker(progress, next)
	if bay().get_parent().linear_velocity.length() > 0.5: reason = "車輛移動，維修蓋已停止"
	if not reason.is_empty():
		moving = false
		blocked_message = reason
		bay().get_parent().service_message = reason
		bay().get_parent().feedback("blocked")
		return
	progress = next
	apply_pose()
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
	apply_pose()
func get_interaction_prompt(_player: Node3D) -> String:
	return "引擎維修蓋｜" + ("移動中" if moving else "E " + ("關閉" if requested_open else "打開")) + "\n" + blocked_message
func allows_mount_at(_point: Vector3) -> bool: return false

extends RefCounted
## Observe normal vehicle physics; never pin the body or alter its velocities.
const WINDOW_TICKS := 60
const MAX_TICKS := 900
const HORIZONTAL_LIMIT := 0.02
const VERTICAL_LIMIT := 0.01
const ROTATION_LIMIT := 0.005

var ticks := 0
var grounded_wheels := 0
var settled := false
var positions: Array[Vector3] = []
var rotations: Array[Quaternion] = []
var horizontal_range := INF
var vertical_range := INF
var rotation_range := INF

func observe(position: Vector3, rotation: Quaternion, contacts: int) -> bool:
	if settled or ticks >= MAX_TICKS: return settled
	ticks += 1
	grounded_wheels = contacts
	if contacts != 4:
		positions.clear()
		rotations.clear()
		horizontal_range = INF
		vertical_range = INF
		rotation_range = INF
		return false
	positions.append(position)
	rotations.append(rotation.normalized())
	if positions.size() > WINDOW_TICKS:
		positions.pop_front()
		rotations.pop_front()
	horizontal_range = 0.0
	vertical_range = 0.0
	rotation_range = 0.0
	# Pairwise diameters cover the entire window, including drift and swings
	# either side of the first pose. atan2 retains precision at small angles.
	for i in positions.size():
		for j in i:
			var offset := positions[i] - positions[j]
			horizontal_range = maxf(horizontal_range, Vector2(offset.x, offset.z).length())
			vertical_range = maxf(vertical_range, absf(offset.y))
			var relative := rotations[i].inverse() * rotations[j]
			var sine := Vector3(relative.x, relative.y, relative.z).length()
			rotation_range = maxf(rotation_range, 2.0 * atan2(sine, absf(relative.w)))
	settled = positions.size() == WINDOW_TICKS and within_limits(horizontal_range, vertical_range, rotation_range)
	return settled

static func within_limits(horizontal: float, vertical: float, angle: float) -> bool:
	return horizontal < HORIZONTAL_LIMIT and vertical < VERTICAL_LIMIT and angle < ROTATION_LIMIT

static func count_contacts(vehicle: Chassis) -> int:
	var count := 0
	for wheel in vehicle.installed_wheels:
		if is_instance_valid(wheel) and wheel.is_in_contact(): count += 1
	return count

func diagnostic() -> String:
	return "ticks=%d/%d grounded=%d/4 window=%d/%d horizontal=%.6fm (<%.3f) vertical=%.6fm (<%.3f) rotation=%.6frad (<%.3f)" % [ticks, MAX_TICKS, grounded_wheels, positions.size(), WINDOW_TICKS, horizontal_range, HORIZONTAL_LIMIT, vertical_range, VERTICAL_LIMIT, rotation_range, ROTATION_LIMIT]

func wait_for_vehicle(tree: SceneTree, vehicle: Chassis, is_current: Callable) -> bool:
	while ticks < MAX_TICKS:
		# No process_frame wait: rendering can batch multiple physics ticks.
		await tree.physics_frame
		if not is_current.call() or not is_instance_valid(vehicle): return false
		if observe(vehicle.global_position, vehicle.global_basis.get_rotation_quaternion(), count_contacts(vehicle)):
			return true
	return false

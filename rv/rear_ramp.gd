extends StaticBody3D
class_name RearRamp
var deployed: bool = false
var angle: float = 0.0
var length: float = 3.6
var rv: Node3D
var deck: CollisionShape3D
var visual: Node3D
@export var travel_seconds := 3.0
var progress := 0.0
var requested_deployed := false
var moving := false
var moving_visuals: Array[MeshInstance3D] = []
func _ready() -> void:
	rv = get_parent()
	deck = $DeckCollision
	visual = $Deck
	for i in range(2):
		var part := RoadsideKit.part(self, Vector3(1.4, 0.05, 1.8), Vector3.ZERO, Color("8a8f8d"))
		part.material_override = load("res://rv/visuals/metal.tres")
		for strip in range(8):
			var grip := RoadsideKit.part(part, Vector3(1.34, 0.012, 0.025), Vector3(0, 0.035, -0.78 + strip * 0.22), Color("282e30"))
			grip.material_override = load("res://rv/visuals/dark.tres")
		for side in [-1.0, 1.0]:
			var rail := RoadsideKit.part(part, Vector3(0.035, 0.055, 1.8), Vector3(side * 0.69, 0.015, 0), Color("c17836"))
			rail.material_override = load("res://rv/visuals/orange.tres")
		moving_visuals.append(part)
	_sync()
func stable() -> bool: return not moving and (progress == 0.0 or progress == 1.0)
func blocks_driving() -> bool: return deployed or moving or progress > 0.0

func folding_poses(value: float) -> Array[Transform3D]:
	var half := length * 0.5
	var slide := clampf(value / 0.3, 0.0, 1.0)
	var lift := clampf((value - 0.3) / 0.1, 0.0, 1.0)
	var unfold := clampf((value - 0.4) / 0.6, 0.0, 1.0)
	var lower := clampf((value - 0.8) / 0.2, 0.0, 1.0)
	var base := Transform3D(Basis(Vector3.RIGHT, angle * lower), Vector3(0, -0.18 * (1.0 - lift), -half * (1.0 - slide)))
	var hinge := base * Transform3D(Basis(Vector3.RIGHT, -PI * (1.0 - unfold)), Vector3(0, 0.08 * (1.0 - unfold), half))
	return [base * Transform3D(Basis.IDENTITY, Vector3(0, -0.025, half * 0.5)), hinge * Transform3D(Basis.IDENTITY, Vector3(0, -0.025, half * 0.5))]

func _physics_process(delta: float) -> void:
	if not moving: return
	var target := 1.0 if requested_deployed else 0.0
	var next := move_toward(progress, target, minf(delta / travel_seconds, 0.006))
	progress = next
	if progress == target:
		moving = false
		deployed = requested_deployed
		rv.feedback("mechanical", position)
	_sync()
func doors_open() -> bool:
	var slots := rv.get_node_or_null("StructureSlots")
	var device: Node = slots.occupant("rear") if slots else null
	# A breached rear slot is already clear; a live door needs both leaves open.
	if slots and device == null: return true
	if device and device.has_method("restore_angles"):
		return device.angles.size() == 2 and absf(device.angles[0]) >= deg_to_rad(85) and absf(device.angles[1]) >= deg_to_rad(85)
	return false
func exclusions() -> Array[RID]:
	return [get_rid(), rv.get_rid(), $Control.get_rid()]
func interact(_player: Node3D) -> String:
	if rv.linear_velocity.length() > 0.5 or not rv.handbrake: return "請停穩並拉起手煞車"
	if moving:
		requested_deployed = not requested_deployed
		rv.feedback("mechanical", position)
		_sync()
		return "坡板反向展開中" if requested_deployed else "坡板反向收起中"
	if deployed or progress > 0.0:
		requested_deployed = false
		moving = true
		rv.feedback("mechanical", position)
		_sync()
		return "坡板收起中"
	var end := to_global(Vector3(0, 0, 3.6))
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(end + Vector3.UP * 0.3, end - Vector3.UP * 3.0, 1, exclusions()))
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < cos(deg_to_rad(30)): return "後方沒有平穩地面可支撐坡板"
	var local_end := to_local(hit.position + Vector3.UP * 0.04)
	var next_angle := atan2(-local_end.y, local_end.z)
	if absf(next_angle) > deg_to_rad(30): return "地面高差太大，坡板坡度超過 30°"
	var next_length := local_end.length()
	if next_length < 3.0 or next_length > 4.3: return "地面高差太大，坡板無法接地"
	angle = next_angle
	length = next_length
	requested_deployed = true
	moving = true
	rv.feedback("mechanical", position)
	_sync()
	return "坡板展開中；收妥後才能行駛"
func _sync() -> void:
	var unfolded := progress == 1.0 and not moving
	deck.disabled = not unfolded
	$Stowed.visible = progress == 0.0 and not moving
	visual.visible = unfolded
	var poses := folding_poses(progress)
	for i in range(2):
		# Folding sections are visual only; enable a walkable deck at full deployment.
		moving_visuals[i].visible = moving or (progress > 0.0 and not unfolded)
		moving_visuals[i].transform = poses[i]
		moving_visuals[i].scale.z = length / 3.6
	var pose := Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0, -0.025, length * 0.5))
	deck.transform = pose
	(deck.shape as BoxShape3D).size = Vector3(1.4, 0.05, length)
	visual.transform = pose
	visual.scale.z = length
	$Control.sync_state(moving, requested_deployed, unfolded)
func get_interaction_prompt(_player: Node3D) -> String:
	if moving: return "後方登車坡板｜E 反向" + ("收起" if requested_deployed else "展開") + "（動畫中無碰撞）"
	return "後方登車坡板｜E " + ("收起" if blocks_driving() else "展開（停穩、手煞車）")
func snapshot() -> Dictionary:
	return {"deployed": deployed, "angle": angle, "length": length}
func restore_state(data: Dictionary) -> void:
	deployed = data.get("deployed", false)
	angle = data.get("angle", 0.0)
	length = data.get("length", 3.6)
	progress = 1.0 if deployed else 0.0
	requested_deployed = deployed
	moving = false
	_sync()
static func valid_state(data: Variant) -> bool:
	return data is Dictionary and data.has_all(["deployed", "angle", "length"]) and data.deployed is bool and (data.angle is float or data.angle is int) and (data.length is float or data.length is int) and is_finite(data.angle) and is_finite(data.length) and absf(data.angle) <= deg_to_rad(30.0) and data.length >= 3.0 and data.length <= 4.3
func allows_mount_at(_point: Vector3) -> bool: return false

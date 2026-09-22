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
var blocked_message := ""
var moving_colliders: Array[CollisionShape3D] = []
var moving_visuals: Array[MeshInstance3D] = []
func _ready() -> void:
	rv = get_parent()
	deck = $DeckCollision
	visual = $Deck
	for i in range(2):
		var collider := CollisionShape3D.new()
		collider.shape = BoxShape3D.new()
		add_child(collider)
		moving_colliders.append(collider)
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

func motion_blocker(from: float, to: float) -> String:
	var steps := maxi(1, ceili(absf(to - from) / 0.003))
	var end := to_global(Basis(Vector3.RIGHT, angle) * Vector3(0, 0, length))
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(end + Vector3.UP * 0.08, end - Vector3.UP * 0.15, 1, exclusions()))
	var support := RID()
	if not hit.is_empty() and hit.collider is StaticBody3D and not hit.collider is Equipment and hit.position.y <= end.y and hit.normal.dot(Vector3.UP) >= cos(deg_to_rad(30)):
		support = hit.rid
	for step in range(1, steps + 1):
		var value := lerpf(from, to, float(step) / steps)
		for pose in folding_poses(value):
			# At the final contact only, let the tip rest on its verified floor.
			# Actors/props and all other terrain remain in the sweep query.
			var reason := blockage(global_transform * pose, Vector3(1.4, 0.08, length * 0.5 + 0.02), support if value > 0.98 else RID())
			if not reason.is_empty(): return reason
	return ""

func _physics_process(delta: float) -> void:
	if not moving: return
	var target := 1.0 if requested_deployed else 0.0
	var next := move_toward(progress, target, minf(delta / travel_seconds, 0.006))
	var blocker := motion_blocker(progress, next)
	if not doors_open() or not rv.handbrake or rv.linear_velocity.length() > 0.5: blocker = "車門或駐車狀態改變"
	if not blocker.is_empty():
		moving = false
		blocked_message = "坡板被 " + blocker + " 擋住；移開後按 E 反向"
		rv.service_message = blocked_message
		rv.feedback("blocked", position)
		return
	progress = next
	if progress == target:
		moving = false
		deployed = requested_deployed
		rv.feedback("mechanical", position)
	_sync()
func doors_open() -> bool:
	for device in rv.get_equipment():
		if device.get("structure_kind") == "rear" and device.has_method("restore_angles"):
			return device.angles.size() == 2 and absf(device.angles[0]) >= deg_to_rad(85) and absf(device.angles[1]) >= deg_to_rad(85)
	return false
func exclusions() -> Array[RID]:
	return [get_rid(), rv.get_rid(), $Control.get_rid()]
func blockage(pose: Transform3D, size: Vector3, support: RID = RID()) -> String:
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size
	query.shape = box
	query.transform = pose
	var excluded := exclusions()
	if support.is_valid(): excluded.append(support)
	query.exclude = excluded
	query.collision_mask = 1
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 1)
	return PlacementRules.object_name(hits[0].collider) if not hits.is_empty() else ""
func interact(_player: Node3D) -> String:
	if rv.linear_velocity.length() > 0.5 or not rv.handbrake: return "請停穩並拉起手煞車"
	if moving: return "坡板移動中，請等停止後再操作"
	if deployed or progress > 0.0:
		var occupied := blockage(global_transform * deck.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), Vector3(1.42, 1.15, length))
		if not occupied.is_empty(): return "坡板上有 " + occupied + "，無法收起"
		var next_request := not requested_deployed if progress < 1.0 else false
		var target := 1.0 if next_request else 0.0
		var reason := motion_blocker(progress, target)
		if not reason.is_empty(): return "坡板路徑被 " + reason + " 擋住"
		requested_deployed = next_request
		moving = true
		blocked_message = ""
		rv.feedback("mechanical", position)
		return "坡板收起中" if not requested_deployed else "坡板展開中"
	if not doors_open(): return "請先充分打開後門兩扇"
	var end := to_global(Vector3(0, 0, 3.6))
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(end + Vector3.UP * 0.3, end - Vector3.UP * 3.0, 1, exclusions()))
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < cos(deg_to_rad(30)): return "後方沒有平穩地面可支撐坡板"
	var local_end := to_local(hit.position + Vector3.UP * 0.04)
	var next_angle := atan2(-local_end.y, local_end.z)
	if absf(next_angle) > deg_to_rad(30): return "地面高差太大，坡板坡度超過 30°"
	# Check both corners: the end must be supported, not balanced over an edge.
	for side in [-0.62, 0.62]:
		var point: Vector3 = hit.position + global_basis.x * side
		var support := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.18, point - Vector3.UP * 0.18, 1, exclusions()))
		if support.is_empty() or absf(support.position.y - hit.position.y) > 0.12: return "坡板兩側缺少地面支撐"
	var next_length := local_end.length()
	# Deployment extends the two telescoping/folding sections from the sill outwards.
	for i in range(1, 21):
		var fraction := i / 20.0
		var extent := next_length * fraction
		var pose := global_transform * Transform3D(Basis(Vector3.RIGHT, next_angle), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0, 0.12, extent * 0.5))
		var blocker := blockage(pose, Vector3(1.38, 0.16, extent))
		if not blocker.is_empty(): return "坡板展開路徑被 " + blocker + " 擋住"
	angle = next_angle
	length = next_length
	var motion_reason := motion_blocker(0.0, 1.0)
	if not motion_reason.is_empty(): return "坡板折疊路徑被 " + motion_reason + " 擋住"
	requested_deployed = true
	moving = true
	blocked_message = ""
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
		moving_colliders[i].disabled = unfolded or (progress == 0.0 and not moving)
		moving_colliders[i].transform = poses[i]
		moving_colliders[i].shape.size = Vector3(1.4, 0.05, length * 0.5)
		moving_visuals[i].visible = not moving_colliders[i].disabled
		moving_visuals[i].transform = poses[i]
		moving_visuals[i].scale.z = length / 3.6
	var pose := Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0, -0.025, length * 0.5))
	deck.transform = pose
	(deck.shape as BoxShape3D).size = Vector3(1.4, 0.05, length)
	visual.transform = pose
	visual.scale.z = length
func get_interaction_prompt(_player: Node3D) -> String:
	return "後方登車坡板｜" + ("移動中" if moving else "E " + ("收起／反向（上方需淨空）" if blocks_driving() else "展開（停穩、手煞車、後門全開）")) + "\n" + blocked_message
func snapshot() -> Dictionary:
	return {"deployed": deployed, "angle": angle, "length": length}
func restore_state(data: Dictionary) -> void:
	deployed = data.get("deployed", false)
	angle = data.get("angle", 0.0)
	length = data.get("length", 3.6)
	progress = 1.0 if deployed else 0.0
	requested_deployed = deployed
	moving = false
	blocked_message = ""
	_sync()
static func valid_state(data: Variant) -> bool:
	return data is Dictionary and data.has_all(["deployed", "angle", "length"]) and data.deployed is bool and (data.angle is float or data.angle is int) and (data.length is float or data.length is int) and is_finite(data.angle) and is_finite(data.length) and absf(data.angle) <= deg_to_rad(30.0) and data.length >= 3.0 and data.length <= 4.3
func allows_mount_at(_point: Vector3) -> bool: return false

extends StaticBody3D
class_name RearRamp
var deployed: bool = false
var angle: float = 0.0
var length: float = 3.6
var rv: Node3D
var deck: CollisionShape3D
var visual: Node3D
func _ready() -> void:
	rv = get_parent()
	deck = $DeckCollision
	visual = $Deck
	_sync()
func doors_open() -> bool:
	for device in rv.get_equipment():
		if device.get("structure_kind") == "rear" and device.has_method("restore_angles"):
			return device.angles.size() == 2 and absf(device.angles[0]) >= deg_to_rad(85) and absf(device.angles[1]) >= deg_to_rad(85)
	return false
func exclusions() -> Array[RID]:
	return [get_rid(), rv.get_rid(), $Control.get_rid()]
func blockage(pose: Transform3D, size: Vector3) -> String:
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size
	query.shape = box
	query.transform = pose
	query.exclude = exclusions()
	query.collision_mask = 1
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 1)
	return PlacementRules.object_name(hits[0].collider) if not hits.is_empty() else ""
func interact(_player: Node3D) -> String:
	if rv.linear_velocity.length() > 0.5 or not rv.handbrake: return "請停穩並拉起手煞車"
	if deployed:
		var occupied := blockage(global_transform * deck.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), Vector3(1.42, 1.15, length))
		if not occupied.is_empty(): return "坡板上有 " + occupied + "，無法收起"
		deployed = false
		_sync()
		return "坡板已收妥"
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
	deployed = true
	_sync()
	return "坡板已展開；收妥後才能行駛"
func _sync() -> void:
	deck.disabled = not deployed
	$Stowed.visible = not deployed
	visual.visible = deployed
	var pose := Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0, -0.025, length * 0.5))
	deck.transform = pose
	(deck.shape as BoxShape3D).size = Vector3(1.4, 0.05, length)
	visual.transform = pose
	visual.scale.z = length
func get_interaction_prompt(_player: Node3D) -> String:
	return "後方登車坡板｜E " + ("收起（上方需淨空）" if deployed else "展開（停穩、手煞車、後門全開）")
func snapshot() -> Dictionary:
	return {"deployed": deployed, "angle": angle, "length": length}
func restore_state(data: Dictionary) -> void:
	deployed = data.get("deployed", false)
	angle = data.get("angle", 0.0)
	length = data.get("length", 3.6)
	_sync()
static func valid_state(data: Variant) -> bool:
	return data is Dictionary and data.has_all(["deployed", "angle", "length"]) and data.deployed is bool and (data.angle is float or data.angle is int) and (data.length is float or data.length is int) and is_finite(data.angle) and is_finite(data.length) and absf(data.angle) <= deg_to_rad(30.0) and data.length >= 3.0 and data.length <= 4.3
func allows_mount_at(_point: Vector3) -> bool: return false

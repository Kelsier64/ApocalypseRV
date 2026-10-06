extends Node3D
## Weather exclusion belongs to the roof, independently of lighting equipment.
var clear_air: FogVolume
var volumes: Array[FogVolume] = []
var regions: Array[Dictionary] = []
func _ready() -> void:
	# Use the solid roof pieces, rather than the bounds of the whole panel.
	# An opening must admit both rain and fog, including on a tilted vehicle.
	for child in get_parent().get_children():
		if not child is CollisionShape3D or child.disabled or not child.shape is BoxShape3D: continue
		var roof_size: Vector3 = child.shape.size
		var size := Vector3(roof_size.x, 2.6, roof_size.z)
		var transform: Transform3D = child.transform
		transform.origin += transform.basis * Vector3(0, -roof_size.y * 0.5 - size.y * 0.5, 0)
		regions.append({"transform": transform, "size": size})
	if not ForestFog.supported(): return
	var air := FogMaterial.new()
	air.density = -1.0
	for region in regions:
		var volume := FogVolume.new()
		volume.size = region.size
		volume.transform = region.transform
		volume.material = air
		add_child(volume)
		volumes.append(volume)
	if not volumes.is_empty(): clear_air = volumes[0]

func shelters(local_point: Vector3) -> bool:
	if not get_parent().can_operate(): return false
	for region in regions:
		var point: Vector3 = region.transform.affine_inverse() * local_point
		var half: Vector3 = region.size * 0.5
		if absf(point.x) <= half.x and absf(point.y) <= half.y and absf(point.z) <= half.z: return true
	return false

func _process(_delta: float) -> void:
	for volume in volumes: volume.visible = get_parent().can_operate()

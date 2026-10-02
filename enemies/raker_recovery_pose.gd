extends SkeletonModifier3D
## Blend the settled physical pose back into animation without snapping upright.
var poses: Array[Transform3D] = []
var weight := 0.0

func _process_modification_with_delta(_delta: float) -> void:
	if weight <= 0.0: return
	var sk := get_skeleton()
	for bone in poses.size():
		sk.set_bone_pose(bone, sk.get_bone_pose(bone).interpolate_with(poses[bone], weight))

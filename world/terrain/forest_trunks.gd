extends StaticBody3D
class_name ForestTrunks
## One compound body keeps dense forest physics cheap; shape owners identify trees.
var visuals: Dictionary = {}
var broken: Dictionary = {}

func vehicle_tree_is_broken(shape_index: int) -> bool:
	var shape := shape_owner_get_owner(shape_find_owner(shape_index)) as CollisionShape3D
	return shape != null and (shape.disabled or broken.has(shape))

func vehicle_tree_impact(shape_index: int, direction: Vector3, vehicle_position: Vector3 = Vector3.INF) -> bool:
	var shape := shape_owner_get_owner(shape_find_owner(shape_index)) as CollisionShape3D
	if shape == null or shape.disabled or broken.has(shape): return false
	broken[shape] = true
	var chunk := get_parent() as ChunkGenerator
	var key: String = shape.get_meta("tree_id")
	chunk.field.destroyed_trees[key] = true
	_break_tree.call_deferred(shape, direction, vehicle_position)
	return true

func _break_tree(shape: CollisionShape3D, direction: Vector3, vehicle_position: Vector3) -> void:
	if not is_instance_valid(shape) or not is_inside_tree(): return
	shape.disabled = true
	var point: Vector3 = shape.get_meta("tree_point")
	var entry: Dictionary = visuals[point]
	var batch_node: MultiMeshInstance3D = entry.node
	var pose: Transform3D = entry.pose
	var fallen := MeshInstance3D.new()
	fallen.mesh = batch_node.multimesh.mesh
	get_parent().add_child(fallen)
	fallen.global_transform = batch_node.global_transform * pose
	# Only the hit instance disappears; every other tree retains its transform.
	batch_node.multimesh.set_instance_transform(entry.index, Transform3D(Basis.from_scale(Vector3.ZERO), pose.origin))
	TreeImpact.topple(fallen, direction, vehicle_position)
	TreeImpact.navigation_changed(get_parent(), to_global(point))

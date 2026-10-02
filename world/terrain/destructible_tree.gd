extends Node3D
## Legacy roadside trees share the dense forest's chassis impact contract.
var broken := false
var tree_id := ""
var chunk: ChunkGenerator

func _ready() -> void:
	chunk = get_parent() as ChunkGenerator
	if chunk == null: return
	tree_id = TreeImpact.roadside_id(position)
	if chunk.field.destroyed_trees.has(tree_id):
		broken = true
		hide()
		for shape in find_children("*", "CollisionShape3D", true, false): shape.disabled = true

func vehicle_tree_is_broken(_shape_index: int) -> bool:
	return broken

func vehicle_tree_impact(_shape_index: int, direction: Vector3, vehicle_position: Vector3 = Vector3.INF) -> bool:
	if broken: return false
	broken = true
	if chunk != null: chunk.field.destroyed_trees[tree_id] = true
	_break_tree.call_deferred(direction, vehicle_position)
	return true

func _break_tree(direction: Vector3, vehicle_position: Vector3) -> void:
	for shape in find_children("*", "CollisionShape3D", true, false): shape.disabled = true
	if chunk != null: TreeImpact.navigation_changed(chunk, global_position)
	TreeImpact.topple(self, direction, vehicle_position)

extends StaticBody3D
class_name BreakableProps
## Light props (fence posts, marker posts, signs) that a moving RV knocks flat
## instead of stopping against. They share the forest's impact contract: only the
## chassis collides with them, and a destroyed prop stays destroyed in the save.
const DEBRIS_SECONDS := 8.0
## Read by Chassis: each prop costs far less speed and damage than a tree trunk.
var vehicle_speed_retained := 0.97
var visuals: Dictionary = {}
var broken: Dictionary = {}

func _init() -> void:
	collision_layer = TreeImpact.SHRUB_LAYER
	collision_mask = 0

## items: {"mesh": StringName, "pose": Transform3D}. Poses are in chunk space.
static func build(chunk: ChunkGenerator, title: String, items: Array[Dictionary]) -> BreakableProps:
	if items.is_empty(): return null
	var body := BreakableProps.new()
	body.name = title
	var poses := {}
	var shapes := {}
	for item: Dictionary in items:
		var pose: Transform3D = item.pose
		var key := TreeImpact.roadside_id(pose.origin)
		if chunk.field.destroyed_trees.has(key): continue
		var id: StringName = item.mesh
		if not poses.has(id):
			poses[id] = []
			var box := BoxShape3D.new()
			box.size = ScatterMeshes.solid(id).size
			shapes[id] = box
		poses[id].append(pose)
		var shape := CollisionShape3D.new()
		shape.shape = shapes[id]
		shape.transform = pose.translated_local(ScatterMeshes.solid(id).get_center())
		shape.set_meta("tree_id", key)
		shape.set_meta("tree_point", pose.origin)
		body.add_child(shape)
	for id: StringName in poses:
		var instances := ForestScenery.batch(chunk, "%s_%s" % [title, id], ScatterMeshes.mesh(id), poses[id])
		for entry: Dictionary in instances.values(): entry.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.visuals.merge(instances)
	chunk.add_child(body)
	return body

func vehicle_tree_is_broken(shape_index: int) -> bool:
	var shape := shape_owner_get_owner(shape_find_owner(shape_index)) as CollisionShape3D
	return shape != null and (shape.disabled or broken.has(shape))

func vehicle_tree_impact(shape_index: int, velocity: Vector3, _vehicle_position: Vector3 = Vector3.INF) -> bool:
	var shape := shape_owner_get_owner(shape_find_owner(shape_index)) as CollisionShape3D
	if shape == null or shape.disabled or broken.has(shape): return false
	broken[shape] = true
	var chunk := get_parent() as ChunkGenerator
	if chunk != null: chunk.field.destroyed_trees[shape.get_meta("tree_id")] = true
	_break.call_deferred(shape, velocity)
	return true

func _break(shape: CollisionShape3D, velocity: Vector3) -> void:
	if not is_instance_valid(shape) or not is_inside_tree(): return
	shape.disabled = true
	var entry: Dictionary = visuals[shape.get_meta("tree_point")]
	var batch_node: MultiMeshInstance3D = entry.node
	var pose: Transform3D = entry.pose
	batch_node.multimesh.set_instance_transform(entry.index, Transform3D(Basis.from_scale(Vector3.ZERO), pose.origin))
	# The knocked piece tumbles on the ground only; nothing else can snag on it.
	var debris := RigidBody3D.new()
	debris.collision_layer = 0
	debris.collision_mask = 1
	debris.mass = 12.0
	var visual := MeshInstance3D.new()
	visual.mesh = batch_node.multimesh.mesh
	visual.scale = pose.basis.get_scale()
	debris.add_child(visual)
	var collider := CollisionShape3D.new()
	collider.shape = shape.shape
	collider.position = shape.transform.origin - (batch_node.transform * pose).origin
	collider.basis = Basis.IDENTITY
	debris.add_child(collider)
	get_parent().add_child(debris)
	debris.global_transform = (batch_node.global_transform * pose).orthonormalized()
	collider.global_transform = shape.global_transform.orthonormalized()
	var push := velocity.slide(Vector3.UP)
	debris.linear_velocity = push * 0.7 + Vector3.UP * minf(3.0, 1.0 + push.length() * 0.15)
	debris.angular_velocity = Vector3.UP.cross(push.normalized() if push.length() > 0.1 else Vector3.FORWARD) * 5.0
	# Bound to the debris itself, so an unloaded band simply drops the connection.
	get_tree().create_timer(DEBRIS_SECONDS).timeout.connect(debris.set.bind(&"freeze", true))

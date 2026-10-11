extends SceneTree
## Real giant sweeps use the shared forest and roadside destruction contract.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const STEP := 1.0 / 60.0
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var chunk: ChunkGenerator

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func frames(count := 1) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func reset_at(point: Vector3) -> void:
	giant.reset_after_restore()
	giant.global_position = point
	giant.rotation.y = 0.0
	giant.velocity = Vector3.ZERO

func advance(speed: float, ticks: int) -> float:
	var maximum_step := 0.0
	for tick in ticks:
		await frames()
		var before := giant.global_position
		giant._move_swept(Vector3.FORWARD * speed, STEP)
		maximum_step = maxf(maximum_step, giant.global_position.distance_to(before))
	return maximum_step

func forest_contacts() -> void:
	var body := chunk.get_node("ForestTrunks") as ForestTrunks
	reset_at(Vector3(0, .1, 0))
	await frames(3)
	var contact := giant.move_and_collide(Vector3.FORWARD * 10.0, true)
	check(contact != null and contact.get_collider() == body, "Full production capsule sweep finds the compound forest body")
	if contact == null: return
	check(contact.get_collider_shape_index() == 1, "Sweep identifies the second trunk instead of assuming shape zero")
	for incoming in [Vector3.ZERO, Vector3.BACK * 3.0, Vector3.DOWN * 20.0]:
		giant.contact_approach_velocity = incoming
		check(not giant._break_contact_tree(contact), "Idle, separating and vertical-only motion preserve standing trees: %s" % incoming)
	check(chunk.field.destroyed_trees.is_empty(), "Rejected contacts create no tombstones")
	giant.global_position = Vector3(0, 16, -6)
	await frames(2)
	var landing := giant.move_and_collide(Vector3.DOWN * 5.0, true)
	check(landing != null and landing.get_normal().y > .65, "Vertical fixture contacts the real top of a standing trunk")
	if landing != null:
		giant.contact_approach_velocity = Vector3(3, -20, 0)
		check(not giant._break_contact_tree(landing), "A landing with horizontal drift cannot demolish a tree")
	reset_at(Vector3(0, .1, 0))
	var maximum_step := await advance(2.0, 330)
	await frames(2)
	check(body.get_child(1).disabled and not body.get_child(0).disabled, "Walking collision disables exactly the contacted trunk")
	check(chunk.field.destroyed_trees == {"forest:0:1": true}, "Walking impact records exactly the second tree tombstone")
	check(giant.global_position.z < -8.0, "Giant continues physically through the broken trunk")
	check(maximum_step < .2, "Tree demolition preserves continuous swept movement")
	check(chunk._navigation_dirty, "Tree demolition requests the shared navigation update")
	var debris := chunk.get_node_or_null("TreeDebris")
	check(debris != null and debris.get_child_count() == 1, "Exactly one tree fall is created")
	giant.contact_approach_velocity = Vector3.FORWARD * 2.0
	check(giant._break_contact_tree(contact), "Repeated contact with the same compound shape continues yielding")
	await frames(2)
	check(chunk.field.destroyed_trees == {"forest:0:1": true}, "Repeated compound contact preserves the single tombstone")
	check(debris != null and debris.get_child_count() == 1, "Repeated contact creates no duplicate debris")

func roadside_contacts(kind: String, x: float) -> void:
	var tree: Node3D = RoadsideKit.instantiate_module(kind)
	tree.position = Vector3(x, 0, -6)
	chunk.add_child(tree)
	reset_at(Vector3(x, .1, 0))
	await frames(3)
	var contact := giant.move_and_collide(Vector3.FORWARD * 10.0, true)
	check(contact != null and TreeImpact.target_for(contact.get_collider()) == tree, "Production %s nested collider resolves its tree owner" % kind)
	await advance(2.0, 210)
	await frames(2)
	check(tree.broken and chunk.field.destroyed_trees.has(TreeImpact.roadside_id(Vector3(x, 0, -6))), "Walking impact persists legacy %s destruction" % kind)
	for shape in tree.find_children("*", "CollisionShape3D", true, false):
		check(shape.disabled, "Legacy %s collision is disabled after its real contact" % kind)
	if contact != null:
		var ledger := chunk.field.destroyed_trees.duplicate()
		var debris := chunk.get_node("TreeDebris")
		var fall_count := debris.get_child_count()
		giant.contact_approach_velocity = Vector3.FORWARD * 2.0
		check(giant._break_contact_tree(contact), "Already broken legacy %s continues yielding" % kind)
		await frames(2)
		check(chunk.field.destroyed_trees == ledger and debris.get_child_count() == fall_count, "Repeated legacy %s contact preserves tombstones and debris count" % kind)

func wall_contact() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 20, 1)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(80, 10, -6)
	world.add_child(wall)
	reset_at(Vector3(80, .1, 0))
	var before := chunk.field.destroyed_trees.duplicate()
	await advance(5.0, 180)
	var touched := false
	for index in giant.get_slide_collision_count():
		if giant.get_slide_collision(index).get_collider() == wall: touched = true
	check(touched and giant.global_position.z > -4.5, "An ordinary static wall still stops the giant's full capsule")
	check(chunk.field.destroyed_trees == before, "Wall contact cannot create a tree tombstone")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	chunk = ChunkGenerator.new()
	chunk.field = WorldField.new(42)
	var planned: Array[Dictionary] = [
		{"point": Vector3(10, 0, -6), "height": 14.0, "width": 3.0, "angle": 0.0},
		{"point": Vector3(0, 0, -6), "height": 14.0, "width": 3.0, "angle": 0.0}]
	chunk.field.forest_cache = {0: planned, -1: [] as Array[Dictionary], 1: [] as Array[Dictionary]}
	world.add_child(chunk)
	await ForestScenery.build(chunk, false)
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	await forest_contacts()
	await roadside_contacts("tree", 40.0)
	await roadside_contacts("dead_tree", 60.0)
	await wall_contact()
	world.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: giant walking tree contacts, shape selection, safety gates, roadside trees and solid walls")
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Admission, confinement and saved/cancelled Item motion through the real hopper.
const OPENING_HALF := .435
var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var machine: Item
var hopper: Area3D

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok and note not in failures:
		failures.append(note)
		push_error("FAIL: " + note)

func steps(count: int = 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func fixture() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(30, 0, 0)
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await steps(3)
	rv.current_power = 30.0
	machine = rv.get_node("Scrapper")
	hopper = machine.get_node("HopperArea")
	check(machine.can_operate(), "Motion fixture uses the production mounted recycler")

func new_item(scene: String, fixed := false) -> Item:
	var item: Item = load(scene).instantiate()
	item.position = Vector3(-20, 4, 0)
	item.freeze = fixed
	item.gravity_scale = 0.0
	WorldEntities.get_container(world).add_child(item)
	return item

func feed(item: Item, local: Vector3, yaw := 0.0) -> void:
	item.global_transform = machine.global_transform * Transform3D(Basis(Vector3.UP, yaw), local)
	item.reset_physics_interpolation()

func visible_bounds(item: Item) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var bounds := mesh.get_aabb()
		for corner in 8:
			var point := bounds.position + bounds.size * Vector3(float(corner & 1), float((corner >> 1) & 1), float((corner >> 2) & 1))
			var local := machine.to_local(mesh.to_global(point))
			low = Vector3(minf(low.x, local.x), minf(low.y, local.y), minf(low.z, local.z))
			high = Vector3(maxf(high.x, local.x), maxf(high.y, local.y), maxf(high.z, local.z))
	return AABB(low, high - low)

func confined(item: Item, note: String) -> void:
	var bounds := visible_bounds(item)
	check(bounds.position.is_finite() and bounds.size.is_finite(), note + " keeps finite visual bounds")
	check(bounds.position.x >= -OPENING_HALF - .006 and bounds.end.x <= OPENING_HALF + .006 and bounds.position.z >= -OPENING_HALF - .006 and bounds.end.z <= OPENING_HALF + .006, note + " keeps the full rotated visible input inside the opening")
	check(item.global_basis.get_scale().distance_to(Vector3.ONE) < .001, note + " does not scale the physics root")

func rejection_preserves_physics() -> void:
	var edge := new_item("res://props/scrap.tscn", true)
	await steps(2)
	feed(edge, Vector3(.4, .62, 0))
	await steps(5)
	check(hopper.get_overlapping_bodies().has(edge), "Frame-edge fixture has a real partial hopper overlap")
	check(not is_instance_valid(edge.processing_owner) and machine.props_being_crushed.is_empty(), "Grazing input is not teleported through the frame or claimed")
	check(edge.collision_layer != 0 and edge.collision_mask != 0 and edge.freeze, "Rejected input retains its original physical collision state")
	var clear_pose := machine.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, .4, 0))
	check(edge.test_move(clear_pose, machine.global_basis * Vector3(.65, 0, 0)), "Rejected input's real collider still sees hopper walls")
	var wheel := new_item("res://props/wheel.tscn", true)
	await steps(2)
	feed(wheel, Vector3(0, .3, 0))
	await steps(5)
	check(hopper.get_overlapping_bodies().has(wheel), "Oversized production wheel physically overlaps the hopper")
	var wheel_pose := wheel.global_transform
	var power_before := rv.current_power
	var materials_before := rv.get_all_items()
	machine.recycle_prop(wheel)
	machine.step_work(.4)
	await steps(3)
	check(not is_instance_valid(wheel.processing_owner) and wheel.global_transform.is_equal_approx(wheel_pose) and wheel.collision_layer != 0, "An oversized wheel stays physical rather than shrinking into the opening")
	check(rv.current_power == power_before and rv.get_all_items() == materials_before and machine.props_being_crushed.is_empty(), "Rejected oversized input consumes no work power and produces no materials")
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(-30, .1, 0)
	world.add_child(player)
	player.set_physics_process(false)
	await steps(3)
	check(player.add_item("Wheel", true, "res://props/wheel.tscn"), "Oversized handoff fixture owns a real large Item record")
	check(player.inventory.active_item().get("is_large", false) and player.can_use_hands(2) and machine.can_operate(), "Held rejection fixture has an active large Item, both hands and an operating service")
	var bag_before: Array = player.inventory.items.duplicate(true)
	check(not machine.can_accept_held_item(player), "Held oversized input is rejected before inventory transfer")
	machine.accept_held_item(player)
	check(player.inventory.items == bag_before and machine.props_being_crushed.is_empty(), "Rejected held input preserves its exact inventory identity and state")
	player.queue_free()
	edge.queue_free()
	wheel.queue_free()
	await steps(3)

func orientation_and_confined_tumbling() -> void:
	var input := new_item("res://props/scrap.tscn", true)
	var mesh: MeshInstance3D
	for node: MeshInstance3D in input.find_children("*", "MeshInstance3D", true, false): mesh = node; break
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(.78, .3, .52)
	mesh.mesh = box_mesh
	for collider: CollisionShape3D in input.find_children("*", "CollisionShape3D", true, false):
		var box := BoxShape3D.new()
		box.size = box_mesh.size
		collider.shape = box
	await steps(2)
	feed(input, Vector3(0, .65, 0), PI * .25)
	await steps(5)
	check(hopper.get_overlapping_bodies().has(input), "Orientation fixture has real collider contact")
	check(not is_instance_valid(input.processing_owner) and input.collision_layer != 0, "Rotated visual/collider extents reject a centered but non-fitting item")
	input.global_position = Vector3(-20, 4, 0)
	await steps(3)
	feed(input, Vector3(0, .65, 0))
	await steps(5)
	check(input.processing_owner == machine and machine.props_being_crushed.size() == 1, "The same item is admitted when its actual orientation fits")
	if input.processing_owner != machine:
		input.queue_free()
		await steps(2)
		return
	input.scrap_yields = {ItemNames.METAL_PARTS: Vector2(2, 2)}
	var visual_start := mesh.global_basis
	var rotated := false
	for frame in 35:
		machine.step_work(1.0 / 60.0)
		await steps(1)
		if not is_instance_valid(input): break
		confined(input, "Confined tumble")
		rotated = rotated or not mesh.global_basis.orthonormalized().is_equal_approx(visual_start.orthonormalized())
	check(rotated, "Admitted input visibly turns instead of rigidly sinking vertically")
	var count_before := rv.get_item_count(ItemNames.METAL_PARTS)
	machine.step_work(2.0)
	await steps(3)
	check(not is_instance_valid(input) and rv.get_item_count(ItemNames.METAL_PARTS) == count_before + 2, "Confined visual motion still commits one original Item payload")

func save_restore_and_cancel() -> void:
	var input := new_item("res://props/scrap.tscn")
	await steps(2)
	feed(input, Vector3(0, .67, 0))
	await steps(5)
	check(input.processing_owner == machine, "Persistence fixture enters through actual hopper contact")
	if input.processing_owner != machine:
		input.queue_free()
		await steps(2)
		return
	machine.step_work(.25)
	await steps(2)
	var identity := input.persistent_id
	var pose_before := input.global_transform
	var saved := machine.capture_service_state()
	check(saved.inputs.size() == 1 and ItemState.valid_service(machine.scene_file_path, saved), "Partly ingested motion validates through the production service schema")
	check(WorldActorSnapshot.capture(input).is_empty(), "Partly ingested input still has a sole recycler save owner")
	machine.enabled = false
	machine._on_service_stopped()
	await steps(3)
	check(not is_instance_valid(input.processing_owner) and input.collision_layer != 0 and not input.freeze, "Cancelling partial ingestion restores the original free-body collision state")
	check(input.persistent_id == identity, "Cancellation preserves the input's original Item identity")
	input.queue_free()
	await steps(3)
	machine.restore_service_state(saved)
	await steps(3)
	check(machine.props_being_crushed.size() == 1, "Saved in-flight motion restores one original input")
	if machine.props_being_crushed.is_empty(): return
	var restored: Item = machine.props_being_crushed[0].prop
	check(restored.persistent_id == identity and restored.processing_owner == machine, "Restore keeps the original input identity and single processing owner")
	check(restored.global_transform.is_equal_approx(pose_before), "Restored feed resumes its full position/orientation rather than snapping upright")
	check(ItemState.valid_service(machine.scene_file_path, machine.capture_service_state()), "Restored partial feed still validates")
	machine.enabled = true
	machine.step_work(.1)
	await steps(2)
	confined(restored, "Restored feed")
	machine.enabled = false
	machine._on_service_stopped()
	await steps(3)
	check(restored.persistent_id == identity and not is_instance_valid(restored.processing_owner) and restored.collision_layer != 0 and not restored.freeze, "Repeated cancel/resume never duplicates or destroys the physical input")
	var collision: CollisionShape3D
	for node: CollisionShape3D in restored.find_children("*", "CollisionShape3D", true, false): collision = node; break
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = 1 | 2
	query.exclude = [restored.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Cancellation places the full-size restored collider clear of the hopper frame")
	restored.queue_free()
	await steps(2)

func obstructed_corpse_does_not_commit() -> void:
	machine.enabled = true
	# The preset under the RV roof deliberately obstructs a tall full rig.
	# Distal contacts may feed, but exterior anatomy must prevent final commit.
	var corpse: CorpseProp = load("res://props/corpse.tscn").instantiate()
	corpse.kind = "raker"
	corpse.transform = machine.global_transform * Transform3D(Basis.IDENTITY, Vector3(0,.62,0))
	corpse.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(4,4)}
	WorldEntities.get_container(world).add_child(corpse)
	await steps(5)
	check(corpse.initialized and corpse.processing_owner == machine and corpse.processing, "Obstructed full corpse enters through real physical hopper contact")
	if corpse.processing_owner != machine:
		corpse.queue_free()
		await steps(2)
		return
	var amount_before := rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
	for frame in 120:
		machine.step_work(1.0 / 60.0)
		await steps(1)
		if not is_instance_valid(corpse): break
	check(is_instance_valid(corpse) and rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == amount_before, "A physically blocked exterior rig cannot disappear or commit yield when its timer expires")
	if not is_instance_valid(corpse): return
	var exterior := false
	for bone: PhysicalBone3D in corpse.bodies.values():
		for shape: CollisionShape3D in bone.find_children("*", "CollisionShape3D", true, false):
			var box := shape.shape.get_debug_mesh().get_aabb()
			for corner in 8:
				var point := machine.to_local(shape.to_global(box.get_endpoint(corner)))
				exterior = exterior or point.y > .705 or absf(point.x) > OPENING_HALF or absf(point.z) > OPENING_HALF
	check(exterior and corpse.processing_owner == machine and machine.props_being_crushed.size() == 1, "Unconsumed exterior corpse geometry retains exactly one input owner")
	check(WorldActorSnapshot.capture(corpse).is_empty() and ItemState.valid_service(machine.scene_file_path,machine.capture_service_state()), "A jammed physical corpse retains one valid persistence owner")
	machine.enabled = false
	machine._on_service_stopped()
	await steps(3)
	check(not corpse.processing and not is_instance_valid(corpse.processing_owner) and corpse.simulator.is_simulating_physics(), "Cancelling a jam releases its full articulated physical corpse safely")
	check(corpse.bodies.size() == 15 and VehicleSnapshot.valid_prop_state(corpse.scene_file_path,corpse.capture_item_state()), "Cancelled physical jam restores a complete valid anatomical rig")
	check(rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == amount_before, "Jam cancellation cannot grant a partial or duplicate material payload")
	corpse.queue_free()
	await steps(2)

func run() -> void:
	await fixture()
	await rejection_preserves_physics()
	await orientation_and_confined_tumbling()
	await save_restore_and_cancel()
	await obstructed_corpse_does_not_commit()
	world.queue_free()
	await steps(3)
	if failures.is_empty(): print("PASS: physical recycler admission, rotated fit confinement and saved/cancelled Item motion")
	quit(0 if failures.is_empty() else 1)

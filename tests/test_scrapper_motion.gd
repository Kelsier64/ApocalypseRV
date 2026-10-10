extends SceneTree
## Real production inputs falling into the hopper, ownership and resumable feed.
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
	rv.current_power = 80.0
	machine = rv.get_node("Scrapper")
	# The actual service is connected to the RV, with clear space above it.
	machine.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 0, 8)), rv, rv)
	hopper = machine.get_node("HopperArea")
	await steps(3)
	check(machine.can_operate(), "Motion fixture uses the production mounted recycler")

func new_item(scene: String, fixed := false) -> Item:
	var item: Item = load(scene).instantiate()
	item.position = Vector3(-20, 4, 0)
	item.freeze = fixed
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
			var local := machine.to_local(mesh.to_global(bounds.get_endpoint(corner)))
			low = Vector3(minf(low.x, local.x), minf(low.y, local.y), minf(low.z, local.z))
			high = Vector3(maxf(high.x, local.x), maxf(high.y, local.y), maxf(high.z, local.z))
	return AABB(low, high - low)

func input_motion(item: Item) -> RefCounted:
	for entry: Dictionary in machine.props_being_crushed:
		if entry.prop == item: return entry.feed
	return null

func contact_points(contact: RefCounted) -> PackedVector3Array:
	var result := PackedVector3Array()
	var stride := maxi(1, contact.source_points.size() / 320)
	for index in range(0, contact.source_points.size(), stride):
		result.append(contact.deform_point(contact.source_points[index]))
	return result

func same_points(first: PackedVector3Array, second: PackedVector3Array) -> bool:
	if first.size() != second.size() or first.is_empty(): return false
	for index in first.size():
		if first[index].distance_to(second[index]) > .0001: return false
	return true

func check_contact(contact: RefCounted, note: String, every_point := false) -> int:
	var half: float = machine.FEED.HALF_OPENING
	var stride := 1 if every_point else maxi(1, contact.source_points.size() / 320)
	var upper := 0
	for index in range(0, contact.source_points.size(), stride):
		var rest: Vector3 = contact.source_points[index]
		var rigid: Vector3 = contact.body_pose * rest
		var point: Vector3 = contact.deform_point(rest)
		check(point.is_finite(), note + " keeps finite deformed mesh vertices")
		for mesh: MeshInstance3D in contact.meshes:
			check(mesh.custom_aabb.has_point(point), note + " keeps every rendered vertex inside its culling bounds while the connected body leans")
		if contact.grip <= .00001:
			check(point.distance_to(rigid) < .0001, note + " stays intact under one rigid transform before tooth contact")
		if point.y < .84:
			check(absf(point.x) <= half + .006 and absf(point.z) <= half + .006, note + " keeps actual descending mesh vertices clear of the hopper frame")
		if rigid.y >= 1.08:
			upper += 1
			check(point.distance_to(rigid) < .0001, note + " preserves the intact upper surface under one shared rigid transform")
	for material: ShaderMaterial in contact.surfaces:
		var rendered_pose: Transform3D = material.get_shader_parameter("body_pose")
		check(rendered_pose.is_equal_approx(contact.body_pose) and is_equal_approx(material.get_shader_parameter("grip"), contact.grip) and is_equal_approx(material.get_shader_parameter("tooth_phase"), contact.tooth_phase), note + " publishes the tested contact deformation to every rendered surface")
	return upper

func confined(item: Item, note: String) -> void:
	var half: float = machine.FEED.HALF_OPENING
	var motion := input_motion(item)
	if motion == null:
		# A just-claimed input keeps its physical arrival pose until paid setup.
		var bounds := visible_bounds(item)
		check(item.global_transform.is_finite() and item.global_basis.get_scale().distance_to(Vector3.ONE) < .001, note + " retains its original finite full-size arrival pose")
		check(bounds.position.y >= .705 or (bounds.position.x >= -half - .006 and bounds.end.x <= half + .006 and bounds.position.z >= -half - .006 and bounds.end.z <= half + .006), note + " keeps its intact arrival geometry above the frame until tooth contact")
		return
	if motion.contact_feed != null:
		check(not motion.contact_feed.source_points.is_empty(), note + " uses connected original surfaces without airborne voxel contacts")
		check_contact(motion.contact_feed, note)
	else:
		var bounds := visible_bounds(item)
		check(bounds.position.is_finite() and bounds.size.is_finite(), note + " keeps finite visual bounds")
		check(bounds.position.x >= -half - .006 and bounds.end.x <= half + .006 and bounds.position.z >= -half - .006 and bounds.end.z <= half + .006, note + " keeps the full rotated visible input inside the opening")
	check(item.global_basis.get_scale().distance_to(Vector3.ONE) < .001, note + " does not scale the physics root")

func visually_turned(item: Item, start_basis: Basis) -> bool:
	var motion := input_motion(item)
	if motion != null and motion.contact_feed != null:
		return not motion.contact_feed.body_pose.basis.is_equal_approx(Basis.IDENTITY)
	return not item.global_basis.is_equal_approx(start_basis)

func continuous_contact_deformation() -> void:
	for scene: String in ["res://equipment/generator.tscn", "res://props/wheel.tscn", "res://equipment/roof_ladder.tscn"]:
		var input := new_item(scene, true)
		await steps(2)
		var bounds: AABB = machine.FEED.geometry_bounds(input)
		feed(input, Vector3(0, 1.15 - bounds.position.y, 0))
		var root_pose := input.global_transform
		var motion: RefCounted = machine.FEED.new()
		check(motion.setup(input, machine), scene + " builds a production large-object intake")
		var contact: RefCounted = motion.contact_feed
		check(contact != null, scene + " exercises continuous contact deformation for an oversized input")
		if contact != null:
			check(contact.meshes.size() > 0 and not contact.source_points.is_empty(), scene + " uses the original mesh surfaces for local tooth deformation")
			for point: Vector3 in contact.source_points:
				check(contact.deform_point(point).distance_to(point) < .0001, scene + " begins as the exact intact object without a fragment lift or explosion")
			var upper_samples := 0
			var bent := false
			for progress in [.02, .12, .25, .50, .75, .95]:
				contact.advance(machine, progress)
				upper_samples += check_contact(contact, scene + " contact sample " + str(progress), true)
				for point: Vector3 in contact.source_points:
					bent = bent or contact.deform_point(point).distance_to(contact.body_pose * point) > .005
				check(input.global_transform.is_equal_approx(root_pose), scene + " leaves the full-size physical Item root unchanged while its contact surface yields")
			contact.advance(machine, 1.0)
			for point: Vector3 in contact.source_points:
				check(contact.deform_point(point).y < .69, scene + " finishes with every rendered vertex swallowed below the teeth, without a final popup")
			check(upper_samples > 0 and bent, scene + " retains connected upper geometry while the caught lower surface bends into the teeth")
		motion.dispose()
		input.queue_free()
		await steps(2)

func grazing_input_preserves_physics() -> void:
	var edge := new_item("res://props/scrap.tscn", true)
	await steps(2)
	var half: float = machine.FEED.HALF_OPENING
	feed(edge, Vector3(half - .025, .62, 0))
	await steps(5)
	check(hopper.get_overlapping_bodies().has(edge), "Side-grazing fixture has a real partial hopper overlap")
	check(not is_instance_valid(edge.processing_owner) and machine.props_being_crushed.is_empty(), "A side-grazing input is not teleported through the frame or claimed")
	check(edge.collision_layer != 0 and edge.collision_mask != 0 and edge.freeze, "Grazing input retains its original physical collision state")
	edge.queue_free()
	await steps(3)

func dropped_production_items() -> void:
	for case_: Dictionary in [{"scene": "res://props/oil_barrel.tscn", "roll": 0.0}, {"scene": "res://props/oil_barrel.tscn", "roll": PI * .5}, {"scene": "res://equipment/generator.tscn", "roll": 0.0}, {"scene": "res://props/wheel.tscn", "roll": 0.0}]:
		var scene: String = case_.scene
		var input := new_item(scene)
		await steps(2)
		var original := input.capture_item_state()
		var orientation := Basis(Vector3.FORWARD, case_.roll)
		var bounds: AABB = machine.FEED.rotated_box(machine.FEED.geometry_bounds(input), orientation)
		# Keep the authored collider/mesh and full scale; test upright and tipped falls.
		input.global_transform = machine.global_transform * Transform3D(orientation, Vector3(0, .95 - bounds.position.y, 0))
		input.reset_physics_interpolation()
		check(machine.to_local(input.global_position).y + bounds.position.y >= .94, scene + " starts wholly above the rim")
		var amounts_before := rv.get_all_items().duplicate(true)
		var power_before := rv.current_power
		var admitted := false
		var turned := false
		var start_basis := input.global_basis
		for frame in 300:
			machine.step_work(1.0 / 60.0)
			await steps(1)
			if not is_instance_valid(input): break
			if input.processing_owner == machine:
				admitted = true
				check(input.persistent_id == original.id, scene + " retains its physical input identity")
				confined(input, scene)
				turned = turned or visually_turned(input, start_basis)
		check(admitted, scene + " falls into the real Area3D and is automatically accepted")
		check(turned, scene + " turns during ingestion without changing the authored size")
		check(not is_instance_valid(input) and machine.props_being_crushed.is_empty(), scene + " fully feeds and releases its one processing slot")
		check(rv.current_power < power_before, scene + " completion pays work power")
		for material: String in original.scrap_yields:
			var range_: Vector2 = original.scrap_yields[material]
			var earned: int = rv.get_item_count(material) - int(amounts_before.get(material, 0))
			check(earned >= int(range_.x) and earned <= int(range_.y), scene + " commits only its original " + material + " yield")
		var after := rv.get_all_items().duplicate(true)
		machine.step_work(2.0)
		check(rv.get_all_items() == after, scene + " cannot produce another payload after completion")
		if is_instance_valid(input):
			machine.enabled = false
			machine._on_service_stopped()
			input.queue_free()
			await steps(3)
			machine.enabled = true

func save_restore_and_cancel() -> void:
	var input := new_item("res://equipment/generator.tscn")
	await steps(2)
	feed(input, Vector3(0, 1.25, 0))
	for frame in 90:
		await steps(1)
		if input.processing_owner == machine: break
	check(input.processing_owner == machine, "Large persistence fixture enters through actual hopper contact")
	if input.processing_owner != machine:
		input.queue_free()
		await steps(2)
		return
	machine.step_work(.25)
	await steps(2)
	var identity := input.persistent_id
	var pose_before := input.global_transform
	var saved := machine.capture_service_state()
	var saved_surface: RefCounted = input_motion(input).contact_feed
	var saved_points := contact_points(saved_surface)
	saved_surface.advance(machine, saved_surface.progress + .1 / machine.crush_time)
	var expected_resume_points := contact_points(saved_surface)
	saved_surface.advance(machine, saved.inputs[0].feed.progress)
	check(saved.inputs.size() == 1 and ItemState.valid_service(machine.scene_file_path, saved), "Partly ingested large Item validates through the production service schema")
	check(WorldActorSnapshot.capture(input).is_empty(), "Partly ingested large Item has a sole recycler save owner")
	for invalid_progress in [NAN, INF, -.01, 1.01, "invalid"]:
		var malformed := saved.duplicate(true)
		malformed.inputs[0].feed.progress = invalid_progress
		check(not ItemState.valid_service(machine.scene_file_path, malformed), "Saved contact progress rejects nonfinite, out-of-range or nonnumeric values")
	var timer_before: float = machine.props_being_crushed[0].timer
	var power_before := rv.current_power
	rv.current_power = 0
	machine.step_work(.5)
	await steps(2)
	check(same_points(saved_points, contact_points(saved_surface)), "An unpowered large Item preserves every sampled rendered vertex, including contact folds")
	check(input.global_transform.is_equal_approx(pose_before) and machine.props_being_crushed[0].timer == timer_before, "An unpowered large Item retains its exact in-flight pose and progress")
	rv.current_power = power_before
	machine.enabled = false
	machine._on_service_stopped()
	await steps(3)
	check(not is_instance_valid(input.processing_owner) and input.collision_layer != 0 and not input.freeze, "Cancelling large ingestion restores free-body collisions")
	check(input.persistent_id == identity, "Cancellation preserves the original large Item identity")
	input.queue_free()
	await steps(3)
	rv.current_power = 0
	machine.restore_service_state(saved)
	var immediate := machine.capture_service_state()
	check(immediate.inputs[0].get("feed", {}) == saved.inputs[0].feed and ItemState.valid_service(machine.scene_file_path, immediate), "Immediate unpowered resave before helper setup preserves saved contact deformation state")
	await steps(3)
	check(machine.props_being_crushed.size() == 1, "Saved large Item motion restores one original input")
	if machine.props_being_crushed.is_empty(): return
	var restored: Item = machine.props_being_crushed[0].prop
	check(restored.persistent_id == identity and restored.processing_owner == machine, "Restore retains the original large Item and sole owner")
	var restored_surface: RefCounted = input_motion(restored).contact_feed
	check(same_points(saved_points, contact_points(restored_surface)), "Paused restore reconstructs the same connected upper body and local tooth deformation")
	check(restored.global_transform.is_equal_approx(pose_before), "Restored large feed resumes its full saved position and orientation")
	check(ItemState.valid_service(machine.scene_file_path, machine.capture_service_state()), "Restored large feed still validates")
	var resaved := machine.capture_service_state()
	check(resaved.inputs[0].get("feed", {}) == saved.inputs[0].feed, "Resaving a paused restored large input preserves its original contact progress and pose")
	machine.enabled = true
	machine.step_work(0)
	var zero_step := machine.capture_service_state()
	check(same_points(saved_points, contact_points(restored_surface)), "Zero-duration unpowered restore keeps every rendered vertex fixed")
	machine.step_work(.3)
	check(same_points(saved_points, contact_points(restored_surface)) and machine.capture_service_state().inputs[0].feed == saved.inputs[0].feed, "Positive unpowered work after restore leaves connected geometry and cutting state unchanged")
	check(zero_step.inputs[0].feed == saved.inputs[0].feed and zero_step.inputs[0].timer == saved.inputs[0].timer and rv.current_power == 0, "Unpowered zero-duration restore step retains feed pose, timer and contact progress")
	rv.current_power = power_before
	machine.step_work(.1)
	await steps(2)
	confined(restored, "Restored large feed")
	var resumed := machine.capture_service_state()
	check(same_points(expected_resume_points, contact_points(restored_surface)), "Resumed large intake matches uninterrupted rendered vertices at the same paid progress")
	check(is_equal_approx(resumed.inputs[0].feed.progress, saved.inputs[0].feed.progress + .1 / machine.crush_time), "Restored connected surfaces advance from the saved cutting progress")
	machine.enabled = false
	machine._on_service_stopped()
	await steps(3)
	check(restored.persistent_id == identity and not is_instance_valid(restored.processing_owner) and restored.collision_layer != 0 and not restored.freeze, "Repeated cancel/resume never duplicates or destroys the large Item")
	for collision: CollisionShape3D in restored.find_children("*", "CollisionShape3D", true, false):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collision.shape
		query.transform = collision.global_transform
		query.collision_mask = 1 | 2
		query.exclude = [restored.get_rid()]
		check(world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Cancellation places the original full-size large collider clear of the frame")
	check(visible_bounds(restored).size.z > .9, "Cancellation restores the complete original generator visuals at their authored size")
	restored.queue_free()
	await steps(2)
	machine.enabled = true

func blocked_output_commits_once() -> void:
	var input := new_item("res://props/wheel.tscn")
	await steps(2)
	input.scrap_yields = {ItemNames.METAL_PARTS: Vector2(3, 3)}
	feed(input, Vector3(0, .95, 0))
	var amount_before := rv.get_item_count(ItemNames.METAL_PARTS)
	var capacity_before := rv.material_capacity
	rv.material_capacity = 0
	for frame in 240:
		machine.step_work(1.0 / 60.0)
		await steps(1)
	check(is_instance_valid(input) and input.processing_owner == machine and machine.props_being_crushed.size() == 1, "Full storage retains one completed large input")
	check(rv.get_item_count(ItemNames.METAL_PARTS) == amount_before, "Blocked large output grants no premature material")
	if is_instance_valid(input) and input.processing_owner == machine:
		check(input.get_meta("recycle_result", {}) == {ItemNames.METAL_PARTS: 3}, "Blocked output retains its one fixed original yield")
		var power_before := rv.current_power
		machine.step_work(.5)
		check(rv.current_power == power_before, "Waiting for storage does not charge more feed power")
	rv.material_capacity = capacity_before
	machine.step_work(.1)
	await steps(3)
	check(not is_instance_valid(input) and rv.get_item_count(ItemNames.METAL_PARTS) == amount_before + 3, "Clearing storage commits the large payload exactly once")
	machine.step_work(1.0)
	check(rv.get_item_count(ItemNames.METAL_PARTS) == amount_before + 3, "Repeated completion cannot duplicate large-input output")
	if is_instance_valid(input):
		machine._on_service_stopped()
		input.queue_free()
		await steps(3)

func run() -> void:
	await fixture()
	await continuous_contact_deformation()
	await grazing_input_preserves_physics()
	await dropped_production_items()
	await save_restore_and_cancel()
	await blocked_output_commits_once()
	world.queue_free()
	await steps(3)
	if failures.is_empty(): print("PASS: real large-item drops, frame confinement, power pause, saved/cancelled motion and exactly-once output")
	quit(0 if failures.is_empty() else 1)

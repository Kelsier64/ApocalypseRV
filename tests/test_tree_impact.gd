extends SceneTree
const WAIT = preload("res://tests/support/test_wait.gd")
const CONTACT_CHASSIS = preload("res://tests/support/tree_contact_chassis.gd")
const SAVE_PATH := "res://.godot/test-tree-impact.save"
var failures: Array[String] = []

func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	for heading in [0.0, PI / 2, PI]: await collision_scenario(heading)
	await collision_scenario(0, true)
	await collision_scenario(0, false, true)
	await debris_lifecycle_scenario()
	await physical_short_log_scenario()
	await continuous_chain_scenario(false)
	await continuous_chain_scenario()
	await persistence_scenario()
	for invalid in [[], {"forest:0:0": false}, {"forest:0:-1": true}, {"forest:0:2128": true}, {"other:0:0": true}, {"roadside:nan:0": true}]:
		check(not TreeImpact.valid_ledger(invalid), "Invalid destruction ledgers are rejected")
	if failures.is_empty(): print("PASS: actual RV tree contacts, per-tree damage, low-speed safety, navigation and checkpoint persistence")
	quit(0 if failures.is_empty() else 1)

func collision_scenario(heading: float, wall: bool = false, paired: bool = false) -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 0.2, 120)
	floor_shape.shape = box
	ground.add_child(floor_shape)
	world.add_child(ground)
	var chunk := ChunkGenerator.new()
	chunk.field = WorldField.new(42)
	world.add_child(chunk)
	var forward := Basis(Vector3.UP, heading) * Vector3.FORWARD
	var point := forward * 13
	var planned: Array[Dictionary] = [{"point": point, "height": 14.0, "width": 3.0, "angle": 0.0}, {"point": Vector3(30, 0, 30), "height": 15.0, "width": 3.0, "angle": 0.0}]
	if paired: planned.append({"point": point + Vector3.RIGHT * 1.0, "height": 14.0, "width": 3.0, "angle": 0.0})
	chunk.field.forest_cache = {0: planned, -1: [] as Array[Dictionary], 1: [] as Array[Dictionary]}
	var wall_body: StaticBody3D
	if wall:
		# Match the trunk's front plane so both enter the solver on the break frame.
		var barrier := RoadsideKit.part(world, Vector3(20, 6, 0.7), point + Vector3.UP * 3, Color.GRAY, true)
		barrier.rotation.y = heading
		wall_body = barrier.get_child(0)
	await ForestScenery.build(chunk, false)
	check(TreeFall.prepared and not TreeFall.preparing and TreeFall.mesh_arrays.has(ForestMeshes.tree(0)), "Tree loading prepares effect geometry before the first collision")
	check(TreeFall.VEHICLE_AUDIO.streams.has("blocked"), "Tree loading prepares the impact sound stream before the first collision")
	await process_frame
	check(chunk.find_children("*", "SubViewport", true, false).is_empty(), "Effect preparation removes its isolated rendering viewport before play")
	check(chunk.field.destroyed_trees.is_empty() and chunk.get_node_or_null("TreeDebris") == null, "Effect preparation creates no destruction ledger or visible gameplay debris")
	check(world.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(), "Effect preparation warms audio without creating playback cues")
	var body := chunk.get_node("ForestTrunks") as ForestTrunks
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	shell.rotation.y = heading
	var observed := shell.get_node("Chassis")
	observed.set_script(CONTACT_CHASSIS)
	observed.observed_tree = body
	observed.observed_wall = wall_body
	observed.observed_forward = forward
	if wall:
		# Avoid the separate truncated-contact safety guard masking wall rejection.
		observed.max_contacts_reported = 128
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	for i in range(90): await physics_frame
	rv.observed_tree_steps.clear()
	rv.set_physics_process(false)
	rv.brake = 0
	var health := rv.get_engine().health
	check(not TreeImpact.hit(rv, body, 0, forward * 2.0, -forward), "Slow contact retains trunk and vehicle health")
	check(not TreeImpact.hit(rv, body, 0, forward * 20.0, forward), "Moving away from trunk cannot break it")
	check(not TreeImpact.hit(rv, body, 0, Vector3.DOWN * 20, Vector3.UP), "Vertical landings do not count as driving into a trunk")
	check(rv.get_engine().health == health, "Rejected contacts do not damage vehicle")
	rv.linear_velocity = forward * 12.0
	var impact_speed := -1.0
	var impact_health := -1.0
	var observed_hits := 0
	var crown_samples: Dictionary = {}
	for i in range(150):
		await physics_frame
		observe_crowns(chunk.get_node_or_null("TreeDebris"), rv, forward, crown_samples)
		if not body.broken.is_empty() and impact_speed < 0:
			impact_speed = rv.linear_velocity.dot(forward)
		if body.broken.size() > observed_hits:
			observed_hits = body.broken.size()
			impact_health = rv.get_engine().health
	print("TREE_MOMENTUM heading=%.2f wall=%s paired=%s impact=%.2f final=%.2f distance=%.2f" % [heading, wall, paired, impact_speed, rv.linear_velocity.dot(forward), rv.global_position.dot(forward)])
	if wall:
		var simultaneous: Array[Dictionary] = rv.simultaneous_breaks
		check(not simultaneous.is_empty(), "Wall and newly broken trunk share an actual physics callback")
		for sample in simultaneous:
			print("TREE_WALL_CALLBACK %s" % sample)
			check(sample.contacts < rv.max_contacts_reported, "Wall regression receives a complete contact report")
			check(sample.incoming > 6.0 and sample.before < sample.incoming * 0.5, "Wall solver removes forward speed before tree handling")
			check(absf(sample.after - sample.before) < 0.001, "Tree handling adds no forward restoration against a simultaneous solid wall")
		check(rv.global_position.dot(forward) < 8.0 and rv.linear_velocity.dot(forward) < 0.5, "Solid wall still stops RV even when a tree breaks beside it")
	else:
		check(impact_speed >= (7.5 if paired else 9.0) and impact_speed < 12.0, "Broken trunks reduce RV momentum without stopping it")
		for sample in rv.observed_tree_steps:
			if sample.new_hits <= 0: continue
			var ratio: float = sample.after / sample.incoming
			check(absf(ratio - pow(0.85, sample.new_hits)) < 0.008, "Each newly broken tree retains approximately eighty-five percent of incoming speed")
		check(rv.global_position.dot(forward) > 16.0, "Vehicle continues several metres through the broken tree")
	check(rv.get_engine().health == impact_health, "Contacts after breaking do not repeatedly damage the engine")
	check(body.get_child(0).disabled, "Actual contact removes only hit trunk (heading=%.2f)" % heading)
	check(not body.get_child(1).disabled, "Adjacent trunk stays solid")
	check(rv.get_engine().health < health, "Actual collision damages engine")
	check(chunk.field.destroyed_trees.has("forest:0:0") and chunk.field.destroyed_trees.size() == (2 if paired else 1), "Actual contacts record exactly the hit trees")
	var debris := chunk.get_node("TreeDebris")
	check(debris.get_child_count() == (2 if paired else 1), "Only broken trees create debris")
	var fall := debris.get_child(0) as TreeFall
	check(fall.crown is RigidBody3D, "Broken crown is a physical rigid body")
	check((fall.crown.collision_layer & rv.collision_mask) != 0 and (rv.collision_layer & fall.crown.collision_mask) != 0, "Fallen crown and RV enable mutual collisions")
	check(not fall.crown.get_collision_exceptions().has(rv) and not rv.get_collision_exceptions().has(fall.crown), "Fallen crown does not exclude the RV from collision")
	if not wall:
		var contacts: Array = crown_samples.values().filter(func(sample: Dictionary) -> bool: return sample.contacted)
		for sample: Dictionary in contacts:
			var crown: RigidBody3D = sample.body
			var displacement := crown.global_position.distance_to(sample.first_position)
			print("TREE_DEBRIS_CONTACT heading=%.2f impulse=%.2f speed=%.2f displacement=%.2f" % [heading, sample.max_impulse, sample.max_forward_speed, displacement])
			check(sample.max_impulse > 0.01, "RV and falling trunk exchange a physical contact impulse")
			check(sample.max_forward_speed > 0.5 and displacement > 0.5, "Falling trunk moves onward after actual RV contact")
	# Landing is observed separately so the momentum regression keeps its 150-frame window.
	if not wall:
		for i in range(480):
			if fall.landed: break
			await physics_frame
			observe_crowns(debris, rv, forward, crown_samples)
	print("TREE_FALL direction=%s intended=%s crown=%s landed=%s" % [fall.direction, forward, fall.crown.basis.y, fall.landed])
	check(fall.global_position.y > 0 and fall.stump.visible, "Broken tree keeps a visible stump above ground")
	if not wall:
		check(fall.landed, "Unobstructed physical crown reaches real ground contact")
	check(not fall.wood_bodies.is_empty(), "Fallen bare wood remains represented by physical segments")
	for wood_body: RigidBody3D in fall.wood_bodies:
		var wood := wood_body.get_child(0) as MeshInstance3D
		var fallen_bounds: AABB = wood.transform * wood.mesh.get_aabb()
		check(fallen_bounds.size.y <= 3.3, "Bare wood is split into small physical segments")
		check(wood_body.mass <= 4.0 and wood_body.continuous_cd, "Every wood segment stays lightweight and uses continuous collision detection")
	check(is_instance_valid(fall.canopy) and fall.canopy.visible, "Actual foliage remains visible after the tree falls")
	var entry: Dictionary = body.visuals[point]
	# Dummy rendering cannot read GPU instance transforms; visible replay checks this.
	if DisplayServer.get_name() != "headless":
		check(entry.node.multimesh.get_instance_transform(entry.index).basis == Basis.from_scale(Vector3.ZERO), "Hit MultiMesh tree disappears independently")
	var damaged_health := rv.get_engine().health
	check(not TreeImpact.hit(rv, body, 0, forward * 12.0, -forward), "Repeated contact cannot charge twice")
	check(rv.get_engine().health == damaged_health, "One tree inflicts damage once")
	# The authored legacy trees use their nested collider, including dead trees.
	for kind in ["tree", "dead_tree"]:
		var tree: Node3D = RoadsideKit.instantiate_module(kind)
		tree.position = Vector3(40, 0, 40)
		world.add_child(tree)
		var collider := tree.find_children("*", "StaticBody3D", true, false)[0]
		check(TreeImpact.hit(rv, collider, 0, forward * 8, -forward), "Legacy %s resolves through its nested collider" % kind)
		await process_frame
		check(tree.find_children("*", "CollisionShape3D", true, false)[0].disabled, "Legacy trunk collision is disabled")
	var glancing: Node3D = RoadsideKit.instantiate_module("tree")
	glancing.position = Vector3(45, 0, 40)
	world.add_child(glancing)
	var glancing_body := glancing.find_children("*", "StaticBody3D", true, false)[0]
	var glancing_normal := Vector3(1.0, 0, 0.125).normalized()
	var glancing_health := rv.get_engine().health
	check(TreeImpact.hit(rv, glancing_body, 0, Vector3.FORWARD * 8, glancing_normal), "Fast oblique impact yields even when normal closing speed is below three metres per second")
	check(rv.get_engine().health == glancing_health, "Direct tree destruction does not bypass unified physical impact damage")
	check(not TreeImpact.hit(rv, glancing_body, 0, Vector3.FORWARD * 8, glancing_normal) and rv.get_engine().health == glancing_health, "Fast oblique contact cannot charge twice")
	world.queue_free()
	await process_frame
	await physics_frame

func observe_crowns(debris: Node, rv: Chassis, forward: Vector3, samples: Dictionary) -> void:
	if debris == null: return
	for fall: TreeFall in debris.get_children():
		var crown: RigidBody3D = fall.crown
		var id := crown.get_instance_id()
		if not samples.has(id):
			samples[id] = {"body": crown, "contacted": false, "first_position": Vector3.ZERO, "max_impulse": 0.0, "max_forward_speed": 0.0}
		var sample: Dictionary = samples[id]
		var state := PhysicsServer3D.body_get_direct_state(crown.get_rid())
		if state == null: continue
		for contact in range(state.get_contact_count()):
			var collider := state.get_contact_collider_object(contact)
			if collider != rv and not ((collider is Item or collider is RVStructurePanel) and collider.get_connected_rv() == rv): continue
			if not sample.contacted:
				sample.contacted = true
				sample.first_position = crown.global_position
			sample.max_impulse = maxf(sample.max_impulse, state.get_contact_impulse(contact).length())
			sample.max_forward_speed = maxf(sample.max_forward_speed, state.linear_velocity.dot(forward))

func debris_lifecycle_scenario() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(120, 0.2, 120)
	floor_shape.shape = floor_box
	ground.add_child(floor_shape)
	ground.position.y = -0.1
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.position = Vector3(25, 12, 25)
	camera.fov = 75
	camera.far = 200
	world.add_child(camera)
	camera.look_at(Vector3(0, 4, 0))
	camera.current = true
	await physics_frame
	var source := MeshInstance3D.new()
	source.mesh = ForestMeshes.tree(0)
	source.scale = Vector3(3, 14, 3)
	world.add_child(source)
	var fall := TreeFall.spawn(source, Vector3.FORWARD * 8)
	fall.set_process(false)
	fall.set_physics_process(false)
	for wood: RigidBody3D in fall.wood_bodies: wood.freeze = true
	check(not fall.leaf_pieces.is_empty(), "Fallen leafy tree retains actual leaf clusters")
	check(fall.wood_bodies.size() >= 4, "Full bare trunk is preserved across physical wood segments")
	var leaf_start: Vector3 = fall.leaf_pieces[0].node.global_position
	for i in range(360): fall._process(1.0 / 60.0)
	var all_settled := fall.leaf_pieces.all(func(piece: Dictionary) -> bool: return piece.settled)
	check(all_settled, "Actual leaf clusters fall under gravity and settle on the ground")
	check(fall.leaf_pieces[0].node.global_position.y < leaf_start.y - 0.5, "Leaf clusters visibly descend from their original canopy positions")
	check(fall._visible_to_camera(camera), "Real camera sees settled tree debris")
	fall.elapsed = 12.0
	fall._process(0)
	check(not fall.is_queued_for_deletion() and fall.canopy.visible, "Visible tree debris remains present before timed wood cleanup")
	check(fall.leaf_pieces.all(func(piece: Dictionary) -> bool: return is_instance_valid(piece.node) and not piece.node.is_queued_for_deletion() and piece.node.visible and piece.node.transparency == 0.0), "Visible leaf geometry stays intact and opaque independently of wood cleanup")
	check(not fall._can_cleanup_wood(camera, 3.0) and not fall._can_cleanup_leaves(camera, 3.0), "Neither visible debris group can be removed by an elapsed timer")
	var wood_refs: Array = fall.wood_bodies.duplicate()
	var stump_ref := fall.stump
	for wood: RigidBody3D in fall.wood_bodies: wood.global_position += Vector3.RIGHT * 1000
	fall.stump.global_position += Vector3.RIGHT * 1000
	fall.leaf_pieces[0].node.global_position = Vector3(0, 1, 0)
	check(fall._visible_to_camera(camera), "Actual leaf geometry remains visible while every wood segment is offscreen")
	fall.elapsed = 7.0
	check(not fall._can_cleanup_wood(camera, 3.0), "Offscreen wood survives its first eight seconds")
	fall.elapsed = 12.0
	check(not fall._can_cleanup_wood(null, 3.0) and not fall._can_cleanup_leaves(null, 3.0), "Missing camera protects both independent debris groups")
	check(not fall._can_cleanup_wood(camera, 1.0), "Wood waits through its first offscreen second despite visible foliage")
	fall.stump.global_position = Vector3(0, 0.75, 0)
	check(not fall._can_cleanup_wood(camera, 0), "Seeing the stump resets the wood offscreen interval")
	fall.stump.global_position += Vector3.RIGHT * 1000
	check(not fall._can_cleanup_wood(camera, 1.0), "Wood offscreen interval starts over after the stump returns to view")
	check(fall._can_cleanup_wood(camera, 1.1), "Wood becomes removable after two continuous offscreen seconds even while foliage stays visible")
	check(not fall._can_cleanup_leaves(camera, 3.0), "Visible foliage survives independently of removable wood")
	fall._process(0)
	check(fall.wood_removed and not fall.leaves_removed and not fall.is_queued_for_deletion(), "Runtime removes only offscreen wood while visible leaves retain their parent")
	check(fall.wood_bodies.is_empty(), "Wood cleanup clears stored physical-body references")
	await process_frame
	check(wood_refs.all(func(body) -> bool: return not is_instance_valid(body)) and not is_instance_valid(stump_ref), "Wood cleanup frees every collision body and the stump")
	check(fall.canopy.visible and not fall.leaf_pieces.is_empty(), "Actual leaf geometry remains present after wood cleanup")
	var leaf_refs: Array = fall.leaf_pieces.map(func(piece: Dictionary): return piece.node)
	for piece: Dictionary in fall.leaf_pieces: piece.node.global_position += Vector3.RIGHT * 1000
	fall.elapsed = 5.0
	check(not fall._can_cleanup_leaves(camera, 3.0), "Offscreen foliage keeps its minimum six-second lifetime")
	fall.elapsed = 30.0
	fall.leaf_pieces[0].settled = false
	check(not fall._can_cleanup_leaves(camera, 3.0), "Foliage cannot be removed while any leaf cluster is still falling")
	fall.leaf_pieces[0].settled = true
	check(not fall._can_cleanup_leaves(null, 3.0), "Missing camera independently protects remaining leaf geometry")
	check(not fall._can_cleanup_leaves(camera, 1.0), "Leaves wait through their first offscreen second")
	fall.leaf_pieces[0].node.global_position = Vector3(0, 1, 0)
	check(not fall._can_cleanup_leaves(camera, 0), "Seeing one leaf cluster resets the foliage offscreen interval")
	fall.leaf_pieces[0].node.global_position += Vector3.RIGHT * 1000
	check(not fall._can_cleanup_leaves(camera, 1.0), "Foliage offscreen interval starts over after a leaf returns to view")
	check(fall._can_cleanup_leaves(camera, 1.1), "Settled leaves become removable after two continuous offscreen seconds")
	fall._process(0)
	check(fall.leaves_removed and fall.leaf_pieces.is_empty() and fall.is_queued_for_deletion(), "Runtime clears leaf references and retires the parent after both groups are removed")
	await process_frame
	check(leaf_refs.all(func(node) -> bool: return not is_instance_valid(node)), "Final leaf cleanup frees the actual leaf meshes")
	# Exercise the reverse order: offscreen foliage cleans up beside visible wood.
	var second_source := MeshInstance3D.new()
	second_source.mesh = ForestMeshes.tree(0)
	second_source.scale = Vector3(3, 14, 3)
	world.add_child(second_source)
	var second := TreeFall.spawn(second_source, Vector3.FORWARD * 8)
	second.set_process(false)
	second.set_physics_process(false)
	for wood: RigidBody3D in second.wood_bodies: wood.freeze = true
	second.elapsed = 12.0
	for piece: Dictionary in second.leaf_pieces:
		piece.settled = true
		piece.node.global_position += Vector3.RIGHT * 1000
	check(not second._can_cleanup_wood(camera, 3.0) and second._can_cleanup_leaves(camera, 2.1), "Offscreen leaves can retire while visible wood remains protected")
	second._process(0)
	check(second.leaves_removed and not second.wood_removed and not second.is_queued_for_deletion(), "Runtime retains visible physical wood after independently cleaning foliage")
	check(not second.wood_bodies.is_empty() and second.leaf_pieces.is_empty(), "Leaf cleanup preserves collision bodies and clears only foliage references")
	camera.look_at(camera.global_position + Vector3.BACK * 100)
	check(second._can_cleanup_wood(camera, 2.1), "Remaining wood becomes removable when the camera finally looks away")
	second._process(0)
	check(second.is_queued_for_deletion(), "Runtime frees a wood-only parent after its own offscreen interval")
	# Timed wood cleanup also works while its geometry stays visible.
	camera.look_at(Vector3(0, 4, 0))
	var timed_source := MeshInstance3D.new()
	timed_source.mesh = ForestMeshes.tree(0)
	timed_source.scale = Vector3(3, 14, 3)
	world.add_child(timed_source)
	var timed := TreeFall.spawn(timed_source, Vector3.FORWARD * 8)
	timed.set_process(false)
	timed.set_physics_process(false)
	for wood: RigidBody3D in timed.wood_bodies: wood.freeze = true
	for piece: Dictionary in timed.leaf_pieces: piece.settled = true
	timed.elapsed = 21.0
	check(not timed._can_cleanup_wood(null, 3.0), "Missing camera protects physical wood until its timed lifetime expires")
	timed._process(0)
	check(not timed.wood_removed and not timed.leaves_removed, "Visible wood remains physical through the middle of its gradual fade")
	check(not timed.crown_materials.is_empty() and timed.crown_materials.all(func(material: ShaderMaterial) -> bool:
		var fade: float = material.get_shader_parameter("fade")
		return fade >= 0.4 and fade <= 0.6), "Wood gradually fades during its final two seconds")
	var timed_body_refs: Array = timed.wood_bodies.duplicate()
	timed.elapsed = 22.0
	check(timed._can_cleanup_wood(null, 0), "Timed wood cleanup works even without a current camera")
	timed._process(0)
	check(timed.wood_removed and timed.wood_bodies.is_empty() and timed.crown == null and timed.stump == null, "Timed cleanup removes visible physical wood and clears its references")
	check(not timed.leaves_removed and timed.canopy.visible and not timed.is_queued_for_deletion(), "Visible settled foliage survives after timed wood cleanup")
	await process_frame
	check(timed_body_refs.all(func(body) -> bool: return not is_instance_valid(body)), "Timed cleanup frees every wood collision body")
	timed.elapsed = 30.0
	timed._process(0)
	check(not timed.leaves_removed and timed.leaf_pieces.all(func(piece: Dictionary) -> bool: return piece.node.visible and piece.node.transparency == 0.0), "Visible foliage remains opaque beyond thirty seconds after wood cleanup")
	print("TREE_DEBRIS_LIFECYCLE settled=%s wood_then_leaves=true leaves_then_wood=true" % all_settled)
	world.queue_free()
	await process_frame
	await physics_frame

func continuous_chain_scenario(with_trees := true) -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(120, 0.2, 200)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	var chunk := ChunkGenerator.new()
	chunk.field = WorldField.new(42)
	var planned: Array[Dictionary] = []
	if with_trees:
		for row in range(8):
			for x in [-0.8, 0.8]:
				planned.append({"point": Vector3(x, 0, -13.0 - row * 6.0), "height": 14.0, "width": 3.0, "angle": 0.0})
	chunk.field.forest_cache = {0: planned, -1: [] as Array[Dictionary], 1: [] as Array[Dictionary]}
	world.add_child(chunk)
	await ForestScenery.build(chunk, false)
	var trunks := chunk.get_node("ForestTrunks") as ForestTrunks
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	var observed := shell.get_node("Chassis")
	observed.set_script(CONTACT_CHASSIS)
	observed.observed_tree = trunks
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.allow_test_controls = true
	var impact_events: Array[Dictionary] = []
	rv.vehicle_impact.connect(func(kind: String, loss: float, damage: float) -> void:
		impact_events.append({"kind": kind, "loss": loss, "damage": damage}))
	for i in range(90): await physics_frame
	check(rv.get_engine().health == 450, "Continuous chain starts with the standard healthy engine")
	check(rv.set_engine_running(true), "Wheel-driven fixture successfully starts its engine")
	rv.gear = 2
	rv.handbrake = false
	rv.observed_tree_steps.clear()
	rv.peak_contacts = 0
	rv.saturated_callbacks = 0
	rv.debris_slowdown_frames = 0
	rv.debris_solver_speed_loss = 0.0
	# Initial entry speed only; all subsequent acceleration comes from wheel power.
	rv.linear_velocity = Vector3.FORWARD * 8.0
	var minimum_speed := INF
	var minimum_chain_speed := TreeImpact.MIN_SPEED + 1.0
	var frames := 0
	var reported_hits := 0
	for i in range(1800):
		var speed := rv.linear_velocity.dot(Vector3.FORWARD)
		var throttle := clampf(0.5 + (8.0 - speed) * 0.5, 0.0, 1.0)
		rv.control_override = {"throttle": throttle, "steering": clampf(rv.global_position.x * 0.12 + rv.rotation.y * 0.8, -0.25, 0.25)}
		await physics_frame
		frames = i + 1
		if not with_trees or not trunks.broken.is_empty(): minimum_speed = minf(minimum_speed, rv.linear_velocity.dot(Vector3.FORWARD))
		if trunks.broken.size() > reported_hits:
			reported_hits = trunks.broken.size()
			print("TREE_CHAIN_ROW broken=%d speed=%.2f force=%.1f brake=%.1f throttle=%.2f gear=%d running=%s blocked=%s position=%s" % [reported_hits, rv.linear_velocity.dot(Vector3.FORWARD), rv.engine_force, rv.brake, rv.throttle_input, rv.gear, rv.energy.engine_running, rv.drive_blocked(), rv.global_position])
		if rv.global_position.z < -65.0: break
	print("TREE_CHAIN trees=%s broken=%d min_speed=%.2f final_speed=%.2f distance=%.2f engine=%.2f peak_contacts=%d saturated=%d seconds=%.2f force=%.1f brake=%.1f" % [with_trees, trunks.broken.size(), minimum_speed, rv.linear_velocity.dot(Vector3.FORWARD), -rv.global_position.z, rv.get_engine().health, rv.peak_contacts, rv.saturated_callbacks, frames / 60.0, rv.engine_force, rv.brake])
	check(trunks.broken.size() == (16 if with_trees else 0), "Wheel-driven RV continuously breaks all planned trees")
	check(rv.global_position.z < -65.0, "Wheel-driven RV passes the last tree row within thirty seconds")
	check(minimum_speed >= minimum_chain_speed, "Continuous ramming stays at least one metre per second above the tree-breaking speed threshold")
	check(rv.get_engine().health > 0, "Continuous ramming preserves a working engine without durability resets")
	if not with_trees:
		check(rv.get_engine().health == 450, "The smooth no-tree driving baseline creates no impact damage")
		if not impact_events.is_empty(): print("TREE_BASELINE_IMPACTS %s" % impact_events)
	check(rv.saturated_callbacks == 0, "Dense chain keeps complete physical contact reports")
	if with_trees and minimum_speed < minimum_chain_speed:
		print("TREE_CHAIN_DEBRIS_LOSS frames=%d sum=%.2f" % [rv.debris_slowdown_frames, rv.debris_solver_speed_loss])
		for sample in rv.observed_tree_steps: print("TREE_CHAIN_SOLVER %s" % sample)
	world.queue_free()
	await process_frame
	await physics_frame

func physical_short_log_scenario() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(120, 0.2, 120)
	floor_shape.shape = floor_box
	ground.add_child(floor_shape)
	ground.position.y = -0.1
	world.add_child(ground)
	var source: Node3D = RoadsideKit.instantiate_module("tree")
	source.position = Vector3(30, 0, 30)
	world.add_child(source)
	var fall := TreeFall.spawn(source, Vector3.FORWARD * 8)
	# Arrange generated physical wood as a loose road obstacle before motion.
	# Its later contacts and movement are entirely solver-driven.
	fall.crown.freeze = true
	fall.crown.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -13))
	fall.crown.linear_velocity = Vector3.ZERO
	fall.crown.angular_velocity = Vector3.ZERO
	fall.crown.freeze = false
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.8
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.allow_test_controls = true
	var impact_kinds: Array[String] = []
	rv.vehicle_impact.connect(func(kind: String, _loss: float, _damage: float) -> void: impact_kinds.append(kind))
	for i in range(90): await physics_frame
	check(rv.set_engine_running(true), "Loose-wood fixture starts its engine")
	rv.gear = 2
	rv.handbrake = false
	rv.linear_velocity = Vector3.FORWARD * 8
	var samples := {}
	for i in range(240):
		rv.control_override = {"throttle": clampf(0.5 + (8 - rv.linear_velocity.dot(Vector3.FORWARD)) * 0.5, 0, 1)}
		await physics_frame
		observe_crowns(world.get_node("TreeDebris"), rv, Vector3.FORWARD, samples)
	var sample: Dictionary = samples[fall.crown.get_instance_id()]
	var displacement := fall.crown.global_position.distance_to(sample.first_position) if sample.contacted else 0.0
	print("TREE_LOOSE_WOOD contact=%s impulse=%.2f speed=%.2f displacement=%.2f" % [sample.contacted, sample.max_impulse, sample.max_forward_speed, displacement])
	check(sample.contacted and sample.max_impulse > 0.01, "RV makes a real solver contact and exchanges impulse with generated short wood")
	check(sample.max_forward_speed > 0.5 and displacement > 0.5, "Physical short wood is pushed onward after RV contact")
	check(not impact_kinds.has("tree"), "Loose broken wood cannot charge standing-tree impact damage")
	world.queue_free()
	await process_frame
	await physics_frame

func persistence_scenario() -> void:
	var world: Node3D = load("res://world/test_world.tscn").instantiate()
	var generator := world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = WorldProfile.new()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 0
	root.add_child(world)
	current_scene = world
	check(await world.wait_for_play(), "Persistence fixture reaches play readiness")
	generator.set_process(false)
	var chunk: ChunkGenerator = generator.active_chunks[0].node
	var body := chunk.get_node("ForestTrunks") as ForestTrunks
	var shape: CollisionShape3D = body.get_child(0)
	var point: Vector3 = shape.get_meta("tree_point")
	var key: String = shape.get_meta("tree_id")
	var map: RID = chunk.navigation.get_navigation_map()
	var before := NavigationServer3D.map_get_closest_point(map, point)
	check(Vector2(before.x - point.x, before.z - point.z).length() > 0.5, "Standing trunk excludes its centre from navigation")
	var rv := world.get_node("NewRv/Chassis") as Chassis
	var surviving: Dictionary = {}
	for child: CollisionShape3D in body.get_children():
		if child != shape:
			var entry: Dictionary = body.visuals[child.get_meta("tree_point")]
			surviving[child.get_meta("tree_id")] = entry.node.global_transform * entry.pose
	check(TreeImpact.hit(rv, body, 0, Vector3.FORWARD * 8, Vector3.BACK), "Generated production tree is destructible")
	await process_frame
	for i in range(30): await physics_frame
	check(await WAIT.navigation_ready(self, [chunk]), "Navigation republishes after destruction")
	check(await WAIT.until(self, func() -> bool:
		var nearest := NavigationServer3D.map_get_closest_point(map, point)
		return Vector2(nearest.x - point.x, nearest.z - point.z).length() < 0.3, 10000, true), "Destroyed trunk's centre becomes navigable")
	check(chunk.find_children("ChunkNavigationRegion", "NavigationRegion3D", false, false).size() == 1, "Rebake reuses the existing region")
	check(shape.disabled and generator.destroyed_trees.has(key), "Generator owns destroyed state after collision")
	var roadside := chunk._place_module("tree", Vector3(170, 0, -70))
	var roadside_key := TreeImpact.roadside_id(roadside.position)
	var roadside_body := roadside.find_children("*", "StaticBody3D", true, false)[0]
	check(TreeImpact.hit(rv, roadside_body, 0, Vector3.FORWARD * 8, Vector3.BACK), "Roadside tree also records a tombstone")
	await process_frame
	for i in range(30): await physics_frame
	check(await WAIT.navigation_ready(self, [chunk]), "Second destruction finishes rebake before saving")
	var checkpoint := root.get_node("Checkpoint")
	check(checkpoint.save_world(world, SAVE_PATH), "Tree destruction saves through real checkpoint")
	var saved: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(saved.get("destroyed_trees", {}).has(key), "Disk checkpoint contains destruction")
	check(saved.get("destroyed_trees", {}).has(roadside_key), "Disk checkpoint includes legacy roadside destruction")
	check(saved.vehicles[0].engine_item.health == rv.get_engine().health, "Collision damage saves with existing engine state")
	var invalid := saved.duplicate(true)
	invalid.destroyed_trees = {key: "true"}
	check(checkpoint.validation_error(invalid) == "destroyed_trees", "Checkpoint rejects malformed destruction before world mutation")
	var legacy := saved.duplicate(true)
	legacy.erase("destroyed_trees")
	check(checkpoint.validation_error(legacy).is_empty(), "Older checkpoints without tree state remain valid")
	# Rebuild with a fresh field, as on checkpoint load, not a retained placement cache.
	var regenerated := ChunkGenerator.new()
	var field := WorldField.new(saved.seed, generator.profile)
	field.destroyed_trees = saved.destroyed_trees.duplicate()
	regenerated.field = field
	regenerated.band = chunk.band
	world.add_child(regenerated)
	await ForestScenery.build(regenerated, false)
	var rebuilt := regenerated.get_node("ForestTrunks") as ForestTrunks
	var restored_roadside := regenerated._place_module("tree", Vector3(170, 0, -70))
	check(not restored_roadside.visible and restored_roadside.find_children("*", "CollisionShape3D", true, false)[0].disabled, "Restored legacy roadside tree is absent before nav parsing")
	check(not rebuilt.visuals.has(point), "Destroyed tree stays absent after fresh-field rebuild")
	for child: CollisionShape3D in rebuilt.get_children():
		var entry: Dictionary = rebuilt.visuals[child.get_meta("tree_point")]
		check(surviving[child.get_meta("tree_id")] == entry.node.global_transform * entry.pose, "Survivors retain original seeded appearance and placement")
	checkpoint.pending = saved
	var candidate: Node3D = load("res://world/test_world.tscn").instantiate()
	checkpoint.prepare_world(candidate)
	check(candidate.get_node("WorldGenerator").destroyed_trees == saved.destroyed_trees, "Load prepares destruction before generator enters the tree")
	checkpoint.pending = {}
	candidate.free()
	world.queue_free()
	await process_frame
	await physics_frame

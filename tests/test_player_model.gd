extends SceneTree
const PLAYER = preload("res://player/player.tscn")
const MODEL = preload("res://assets/models/player_test_v020/player_export_test_v020.glb")
var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	var actor: CharacterBody3D = PLAYER.instantiate()
	arena.add_child(actor)
	var visual: PlayerModelVisual = actor.get_node("Visuals")
	var camera: Camera3D = actor.camera
	var observer := Camera3D.new()
	arena.add_child(observer)
	check(visual.source_meshes.size() == 11 and visual.skeleton.get_bone_count() == 41, "Complete accepted model is in production player")
	check(visual.local_shadows.size() == 6, "Local camera retains complete head/body shadows")
	check((camera.cull_mask & PlayerModelVisual.FULL_BODY_LAYER) == 0, "Local camera hides original head")
	check((camera.cull_mask & PlayerModelVisual.LOCAL_VIEW_LAYER) != 0, "Local body is visible to its camera")
	check((observer.cull_mask & PlayerModelVisual.FULL_BODY_LAYER) != 0 and (observer.cull_mask & PlayerModelVisual.LOCAL_VIEW_LAYER) == 0, "Default observer sees full model without duplicate body")
	check(visual.global_basis.z.dot(-actor.global_basis.z) > .999, "Model +Z front follows player -Z movement")
	var low := INF
	var high := -INF
	var triangles := 0
	for mesh in visual.source_meshes:
		check(mesh.get_node(mesh.skeleton) == visual.skeleton and mesh.skin.get_bind_count() == 41, "Accessory shares original skeleton and all named binds")
		check(mesh.scale.distance_to(Vector3.ONE) < .00001, "No model scaling")
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point := visual.to_local(mesh.to_global(vertex))
				low = minf(low, point.y)
				high = maxf(high, point.y)
	check(triangles == 16222 and absf(high - low - 1.6) < .0001, "Unmodified source triangles and 1.60 m height")
	var original: MeshInstance3D = visual.skeleton.get_node("PLAYER_Mesh")
	var local_triangles := 0
	for surface in visual.local_body.mesh.get_surface_count():
		var local_arrays := visual.local_body.mesh.surface_get_arrays(surface)
		var material := visual.local_body.mesh.surface_get_material(surface)
		var source_surface := -1
		for index in original.mesh.get_surface_count():
			if original.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX] == local_arrays[Mesh.ARRAY_VERTEX]: source_surface = index
		check(source_surface >= 0, "Local body retains materials")
		if source_surface < 0: continue
		check(original.mesh.surface_get_material(source_surface) == material, "Material resource is unchanged")
		var source_arrays := original.mesh.surface_get_arrays(source_surface)
		for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			check(local_arrays[attribute] == source_arrays[attribute], "Local visibility preserves attribute %d on surface %d" % [attribute, source_surface])
		# ArrayMesh packs normals again on GPU upload (octahedral encoding).
		var normal_error := 0.0
		for vertex in local_arrays[Mesh.ARRAY_NORMAL].size():
			normal_error = maxf(normal_error, local_arrays[Mesh.ARRAY_NORMAL][vertex].distance_to(source_arrays[Mesh.ARRAY_NORMAL][vertex]))
		print("LOCAL_NORMAL_ERROR surface=", source_surface, " delta=", normal_error)
		check(normal_error < .0002, "GPU normal repacking stays below 0.012 degrees")
		local_triangles += local_arrays[Mesh.ARRAY_INDEX].size() / 3
	check(local_triangles == 11078, "Only 224 head triangles omitted from local view")
	var animation: AnimationPlayer = visual.model.get_node("AnimationPlayer")
	check(not animation.has_animation("TEST_v020_POSE_SAMPLES") and animation.has_animation("locomotion/idle"), "Production uses authored locomotion instead of TEST clip")
	var untouched: Node3D = MODEL.instantiate()
	check(untouched.get_node("AnimationPlayer").has_animation("TEST_v020_POSE_SAMPLES"), "Imported animation library remains intact for QA")
	untouched.free()
	for frame in 40: await physics_frame
	check(actor.is_on_floor() and absf(visual.global_position.y + low) < .01, "Boot soles align with real ground and unchanged capsule")
	check(absf(camera.global_position.y - 1.53) < .01, "Eye height is 1.53 m above ground")
	# Looking down sideways from the eye used to hit our own capsule first.
	var prop: Prop = load("res://props/scrap.tscn").instantiate()
	prop.freeze = true
	prop.position = Vector3(1.2, .4, 0)
	arena.add_child(prop)
	camera.look_at(prop.global_position)
	for frame in 10: await physics_frame
	var ray: RayCast3D = camera.get_node("InteractRay")
	ray.force_raycast_update()
	check(ray.get_collider() == prop, "Oblique downward pickup ray excludes the player's own capsule")
	Input.action_press("interact")
	for frame in 3: await physics_frame
	Input.action_release("interact")
	for frame in 3: await physics_frame
	check(actor.inventory.items.size() == 1, "Actual E pickup works at the new eye height")
	camera.rotation = Vector3.ZERO
	var start := actor.global_position
	Input.action_press("move_forward")
	for frame in ceili(0.5 * Engine.physics_ticks_per_second): await physics_frame
	Input.action_release("move_forward")
	check(actor.global_position.z < start.z - 2.0, "Production movement carries visible model forward")
	check(visual.position.is_equal_approx(Vector3(0, .25, 0)), "Visual offset does not accumulate during movement")
	Input.action_press("jump")
	for frame in 2: await physics_frame
	Input.action_release("jump")
	check(actor.velocity.y > 0, "Model follows real jump")
	for frame in ceili(1.5 * Engine.physics_ticks_per_second): await physics_frame
	var seat := Node3D.new()
	arena.add_child(seat)
	check(actor.enter_seat_mode(seat), "Existing seat transition succeeds")
	check(not visual.is_visible_in_tree() and not visual.local_body.is_visible_in_tree(), "Seat hides complete model and local proxies together")
	actor.exit_seat_mode(Vector3(2, 0, 2))
	check(visual.is_visible_in_tree() and visual.local_body.is_visible_in_tree(), "Exit seat restores all presentation")
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0, "transform": Transform3D(Basis(Vector3.UP, .7), Vector3(4, 0, 3))})
	check(visual.global_basis.z.dot(-actor.global_basis.z) > .999 and visual.local_shadows.size() == 6, "Checkpoint transform restores facing without duplicate proxies")
	check(actor.camera.current and (actor.camera.cull_mask & PlayerModelVisual.LOCAL_VIEW_LAYER) != 0, "World transition keeps local camera contract")
	var other_world := SubViewport.new()
	other_world.own_world_3d = true
	arena.add_child(other_world)
	actor.reparent(other_world)
	actor.complete_world_transition(Transform3D.IDENTITY)
	await process_frame
	check(visual.get_world_3d() == other_world.find_world_3d() and visual.local_body.get_world_3d() == other_world.find_world_3d(), "POI reparent moves skeleton, model and local view into new World3D")
	check(visual.source_meshes.size() == 11 and visual.local_shadows.size() == 6, "Reparent does not duplicate visual nodes")
	arena.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: production player model, first-person visibility, shadows, movement and lifecycle")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

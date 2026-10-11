extends SceneTree
## Production presentation and actor lifecycle; source provenance lives in the import audit.
const PLAYER = preload("res://player/player.tscn")
const MODEL = preload("res://assets/models/player_test_v020/player_export_test_v020.glb")
var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func wait_until(condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + ceili(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await physics_frame
		await process_frame
	return true

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
	check(not visual.source_meshes.is_empty() and visual.skeleton != null, "Production player has a skinned model")
	check(visual.model.scene_file_path == MODEL.resource_path, "Production uses the accepted imported model")
	for bone_name in ["root", "pelvis", "spine_01", "spine_02", "head"]:
		check(visual.skeleton.find_bone(bone_name) >= 0, "Locomotion and ragdoll bone exists: " + bone_name)
	for side in ["L", "R"]:
		for bone_name in ["upper_arm", "forearm", "hand", "thigh", "shin", "foot"]:
			check(visual.skeleton.find_bone(bone_name + "_" + side) >= 0, "Carry and ragdoll bone exists: " + bone_name + "_" + side)
		for finger in ["thumb", "index", "middle", "ring", "pinky"]:
			for segment in ["01", "02"]:
				check(visual.skeleton.find_bone(finger + "_" + segment + "_" + side) >= 0, "Carry finger bone exists: " + finger + "_" + segment + "_" + side)
	check((camera.cull_mask & PlayerModelVisual.FULL_BODY_LAYER) == 0, "Local camera hides original head")
	check((camera.cull_mask & PlayerModelVisual.LOCAL_VIEW_LAYER) != 0, "Local body is visible to its camera")
	check((observer.cull_mask & PlayerModelVisual.FULL_BODY_LAYER) != 0 and (observer.cull_mask & PlayerModelVisual.LOCAL_VIEW_LAYER) == 0, "Default observer sees full model without duplicate body")
	check(visual.global_basis.z.dot(-actor.global_basis.z) > .999, "Model +Z front follows player -Z movement")
	var source_meshes := visual.source_meshes.duplicate()
	var local_shadows := visual.local_shadows.duplicate()
	var full_body_meshes: Array[MeshInstance3D] = []
	var model_sole_y := INF
	for mesh in visual.source_meshes:
		check(mesh.skin != null and mesh.get_node(mesh.skeleton) == visual.skeleton, "Source mesh shares the production skeleton")
		if mesh.skin != null:
			for bind in mesh.skin.get_bind_count():
				check(visual.skeleton.find_bone(mesh.skin.get_bind_name(bind)) >= 0, "Source skin bind resolves to a production bone")
		if mesh.layers == PlayerModelVisual.FULL_BODY_LAYER:
			full_body_meshes.append(mesh)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				model_sole_y = minf(model_sole_y, visual.to_local(mesh.to_global(vertex)).y)
	check(visual.local_shadows.size() == full_body_meshes.size() and not full_body_meshes.is_empty(), "Every locally hidden source mesh has a full shadow proxy")
	for source in full_body_meshes:
		var proxy_count := 0
		for shadow in visual.local_shadows:
			if shadow.mesh == source.mesh and shadow.skin == source.skin and shadow.transform == source.transform:
				proxy_count += 1
		check(proxy_count == 1, "Locally hidden source mesh has exactly one complete shadow: " + String(source.name))
	for shadow in visual.local_shadows:
		check(shadow.get_node(shadow.skeleton) == visual.skeleton, "Shadow proxy shares the production rig")
		check(shadow.layers == PlayerModelVisual.LOCAL_VIEW_LAYER and shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "Local proxy casts a complete shadow without visible geometry")
	# These double-sided neck accessories can fill the downward crouch view.
	# They must retain their complete observer geometry and local shadows.
	for accessory_name: String in ["PLAYER_Skin_Collar", "PLAYER_Skin_Undershirt"]:
		var accessory := visual.skeleton.get_node(accessory_name) as MeshInstance3D
		check(accessory.visible and accessory.mesh.get_surface_count() > 0, "Complete neck accessory remains present: " + accessory_name)
		check((camera.cull_mask & accessory.layers) == 0, "Local camera excludes neck accessory: " + accessory_name)
		check((observer.cull_mask & accessory.layers) != 0, "Observer retains neck accessory: " + accessory_name)
		var matching_shadows := 0
		for shadow in visual.local_shadows:
			if shadow.mesh == accessory.mesh and shadow.skin == accessory.skin and shadow.transform == accessory.transform:
				matching_shadows += 1
		check(matching_shadows == 1, "Neck accessory retains exactly one complete local shadow: " + accessory_name)
	var original: MeshInstance3D = visual.skeleton.get_node("PLAYER_Mesh")
	check(visual.local_body.skin == original.skin and visual.local_body.get_node(visual.local_body.skeleton) == visual.skeleton, "Local body shares the source skin and skeleton")
	check(visual.local_body.layers == PlayerModelVisual.LOCAL_VIEW_LAYER and visual.local_body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Local body is camera-specific without duplicate shadows")
	var source_triangles := 0
	var local_triangles := 0
	var source_surfaces: Array[Array] = []
	for surface in original.mesh.get_surface_count():
		var arrays := original.mesh.surface_get_arrays(surface)
		source_surfaces.append(arrays)
		source_triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
	for surface in visual.local_body.mesh.get_surface_count():
		var local_arrays := visual.local_body.mesh.surface_get_arrays(surface)
		local_triangles += local_arrays[Mesh.ARRAY_INDEX].size() / 3
		var source_surface := -1
		for index in source_surfaces.size():
			if source_surfaces[index][Mesh.ARRAY_VERTEX] == local_arrays[Mesh.ARRAY_VERTEX]:
				source_surface = index
				break
		check(source_surface >= 0, "Local view retains source surface vertices")
		if source_surface < 0: continue
		check(original.mesh.surface_get_material(source_surface) == visual.local_body.mesh.surface_get_material(surface), "Local view retains the source material resource")
		var source_arrays: Array = source_surfaces[source_surface]
		for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			check(local_arrays[attribute] == source_arrays[attribute], "Local visibility preserves attribute %d on surface %d" % [attribute, source_surface])
		# ArrayMesh packs normals again on GPU upload (octahedral encoding).
		check(local_arrays[Mesh.ARRAY_NORMAL].size() == source_arrays[Mesh.ARRAY_NORMAL].size(), "Local view retains source normal count")
		var normal_error := 0.0
		for vertex in mini(local_arrays[Mesh.ARRAY_NORMAL].size(), source_arrays[Mesh.ARRAY_NORMAL].size()):
			normal_error = maxf(normal_error, local_arrays[Mesh.ARRAY_NORMAL][vertex].distance_to(source_arrays[Mesh.ARRAY_NORMAL][vertex]))
		check(normal_error < .0002, "GPU normal repacking stays below 0.012 degrees")
	check(local_triangles > 0 and local_triangles < source_triangles, "First-person view retains body geometry while omitting head geometry")
	var animation: AnimationPlayer = visual.model.get_node("AnimationPlayer")
	check(not animation.has_animation("TEST_v020_POSE_SAMPLES") and animation.has_animation("locomotion/idle"), "Production uses authored locomotion instead of TEST clip")
	var untouched: Node3D = MODEL.instantiate()
	check(untouched.get_node("AnimationPlayer").has_animation("TEST_v020_POSE_SAMPLES"), "Imported animation library remains intact for QA")
	untouched.free()
	check(await wait_until(func(): return actor.is_on_floor(), 1.0), "Production actor reaches the floor before timeout")
	var capsule: CapsuleShape3D = actor.body_collision_shape.shape
	var capsule_sole_y: float = actor.body_collision_shape.global_position.y - capsule.height * .5
	check(actor.is_on_floor() and absf(capsule_sole_y) < .01, "Visible actor remains grounded on its production capsule")
	check(absf(visual.global_position.y + model_sole_y) < .01, "Imported boot soles align with the actual floor")
	check(absf(camera.global_position.y - 1.53) < .01, "Eye height is 1.53 m above ground")
	# Looking down sideways from the eye used to hit our own capsule first.
	var prop: Item = load("res://props/scrap.tscn").instantiate()
	prop.freeze = true
	prop.position = Vector3(1.2, .4, 0)
	arena.add_child(prop)
	camera.look_at(prop.global_position)
	var ray: RayCast3D = camera.get_node("InteractRay")
	check(await wait_until(func():
		ray.force_raycast_update()
		return ray.get_collider() == prop, 1.0), "Oblique downward pickup ray excludes the player's own capsule")
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
	check(await wait_until(func(): return actor.is_on_floor(), 2.0), "Production jump lands before lifecycle checks")
	var seat := Node3D.new()
	arena.add_child(seat)
	check(actor.enter_seat_mode(seat), "Existing seat transition succeeds")
	check(visual.is_visible_in_tree() and visual.local_body.is_visible_in_tree(), "Seat preserves complete observer model and local body presentation")
	actor.exit_seat_mode(Vector3(2, 0, 2))
	check(visual.is_visible_in_tree() and visual.local_body.is_visible_in_tree(), "Exit seat restores all presentation")
	check(actor.sever_part(&"left_arm", {}), "Arm-loss fixture activates the segmented body")
	for accessory_name: String in ["PLAYER_Skin_Collar", "PLAYER_Skin_Undershirt"]:
		var piece_count := 0
		for piece: Dictionary in visual.dismemberment.pieces:
			if String(piece.full.name) != "Part_torso__" + accessory_name: continue
			piece_count += 1
			check(not piece.local.visible, "Injured local view excludes neck accessory: " + accessory_name)
			check(piece.full.visible and (observer.cull_mask & piece.full.layers) != 0, "Injured observer retains neck accessory: " + accessory_name)
			check(piece.shadow.visible and piece.shadow.mesh == piece.full.mesh and piece.shadow.skin == piece.full.skin, "Injured neck accessory retains its complete shadow: " + accessory_name)
		check(piece_count == 1, "Segmented body contains neck accessory: " + accessory_name)
	var injured_torso_count := 0
	for piece: Dictionary in visual.dismemberment.pieces:
		if String(piece.full.name) != "Part_torso__PLAYER_Mesh": continue
		injured_torso_count += 1
		var full_count := 0
		var view_count := 0
		for surface in piece.full.mesh.get_surface_count():
			full_count += piece.full.mesh.surface_get_array_index_len(surface) / 3
		for surface in piece.local.mesh.get_surface_count():
			view_count += piece.local.mesh.surface_get_array_index_len(surface) / 3
		check(piece.local.visible and view_count > 0 and view_count < full_count, "Injured local torso retains body geometry while omitting its neck ring")
		check(piece.local.skin == piece.full.skin and piece.shadow.mesh == piece.full.mesh, "Injured local torso preserves the source skin and complete shadow geometry")
	check(injured_torso_count == 1, "Segmented body contains the complete main torso")
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0, "transform": Transform3D(Basis(Vector3.UP, .7), Vector3(4, 0, 3))})
	check(visual.local_body.visible and not visual.dismemberment.injured, "Intact checkpoint restores the original local body after arm loss")
	for accessory_name: String in ["PLAYER_Skin_Collar", "PLAYER_Skin_Undershirt"]:
		var accessory := visual.skeleton.get_node(accessory_name) as MeshInstance3D
		check(accessory.visible and (camera.cull_mask & accessory.layers) == 0, "Restored neck accessory remains excluded only from the local camera: " + accessory_name)
	check(visual.global_basis.z.dot(-actor.global_basis.z) > .999 and visual.local_shadows == local_shadows, "Checkpoint transform restores facing without duplicate proxies")
	check(actor.camera.current and (actor.camera.cull_mask & PlayerModelVisual.LOCAL_VIEW_LAYER) != 0, "World transition keeps local camera contract")
	var other_world := SubViewport.new()
	other_world.own_world_3d = true
	arena.add_child(other_world)
	actor.reparent(other_world)
	actor.complete_world_transition(Transform3D.IDENTITY)
	await process_frame
	check(visual.get_world_3d() == other_world.find_world_3d() and visual.local_body.get_world_3d() == other_world.find_world_3d(), "POI reparent moves skeleton, model and local view into new World3D")
	check(visual.source_meshes == source_meshes and visual.local_shadows == local_shadows, "Reparent retains the same source meshes and shadow proxies")
	arena.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: production player model, first-person visibility, shadows, movement and lifecycle")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

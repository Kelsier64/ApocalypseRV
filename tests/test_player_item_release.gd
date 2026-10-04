extends SceneTree
## Full-sized held props and release continuity through the production player.
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(value: bool, note: String) -> void:
	if not value and note not in failures: failures.append(note)

func steps(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func check_size(held: Node3D, source: Node3D, note: String) -> void:
	check(held.scale.is_equal_approx(source.scale), note + " preserves authored root scale")
	for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		var preview := held.get_node_or_null(source.get_path_to(mesh)) as MeshInstance3D
		check(preview != null, note + " preserves mesh " + str(source.get_path_to(mesh)))
		if preview == null: continue
		check(preview.transform.is_equal_approx(mesh.transform), note + " preserves authored mesh transform")
		check(preview.mesh.get_aabb().is_equal_approx(mesh.mesh.get_aabb()), note + " preserves mesh dimensions")

func find_prop(container: Node, persistent_id: String) -> Prop:
	for child in container.get_children():
		if child is Prop and child.persistent_id == persistent_id and not child.is_queued_for_deletion(): return child
	return null

func run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var actor: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.position = Vector3(4, 3, 7)
	var entities := WorldEntities.get_container(actor)
	await steps(2)
	for key in ["flashlight", "scrap", "battery", "oil_barrel", "engine_standard", "engine_upgraded", "engine_repair_kit", "wheel"]:
		for release_pitch in [-.8, 0.0, .8]:
			var scene_path := "res://props/" + key + ".tscn"
			var source: Prop = load(scene_path).instantiate()
			source.freeze = true
			source.position = Vector3(100, 3, 100)
			world.add_child(source) # Run production state initialization (battery/engine IDs).
			var original_scale := source.scale
			var persistent_id := source.persistent_id
			actor.inventory.items.clear()
			actor.inventory.active_slot = 0
			check(actor.add_prop_item(source, scene_path), key + " enters inventory")
			check_size(actor.held_item_node, source, key + " immediately after equip")
			await steps(20)
			check_size(actor.held_item_node, source, key + " after carry overlay")
			for pitch in [-.45, 0.0, .45]:
				actor.camera.rotation.x = pitch
				actor.rotation.y += .7
				actor.velocity = Vector3(4, 0, -2)
				await steps(4)
				check_size(actor.held_item_node, source, key + " while moving/looking")
			# Re-equipping must not accumulate a size change or lose item state.
			actor.camera.rotation.x = release_pitch
			actor.refresh_inventory()
			await steps(20)
			check_size(actor.held_item_node, source, key + " after refresh")
			var held_frame: Transform3D = actor.held_item_node.global_transform
			var expected_velocity: Vector3 = -actor.transform.basis.z * 3.0
			actor.drop_item()
			var dropped := find_prop(entities, persistent_id)
			check(dropped != null, key + " releases one world prop with the same ID")
			if dropped != null:
				# Before another physics tick, compare the complete visible release pose.
				check(dropped.global_transform.is_equal_approx(held_frame), key + " releases from the actual held pose")
				check(dropped.scale.is_equal_approx(original_scale), key + " remains full size after release")
				check(dropped.linear_velocity.is_equal_approx(expected_velocity), key + " preserves existing toss direction and speed")
				check(is_equal_approx(dropped.condition, source.condition), key + " retains condition")
				check(not dropped.freeze and dropped.collision_layer != 0, key + " restores world physics")
				dropped.queue_free()
			check(actor.inventory.items.is_empty(), key + " leaves inventory exactly once")
			source.free()
			await steps(2)
	# Existing no-preview path is required when injury prevents holding an item.
	actor.inventory.add_item("Scrap Metal", false, "res://props/scrap.tscn", {"id": "release-without-hands"})
	actor.held_item_node = null
	var fallback_position: Vector3 = actor.global_position - actor.transform.basis.z * 1.5 + Vector3.UP
	actor.drop_item()
	var fallback := find_prop(entities, "release-without-hands")
	check(fallback != null, "No-preview item can still be dropped")
	if fallback != null: check(fallback.global_position.is_equal_approx(fallback_position), "No-preview release preserves fallback location")
	actor.drop_item()
	check(actor.inventory.items.is_empty(), "Repeated empty drop does not create another item")
	world.queue_free()
	await steps(2)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: full-sized props, equip/refresh/motion, held-pose release, IDs, original toss and no-preview fallback")
	quit(0 if failures.is_empty() else 1)

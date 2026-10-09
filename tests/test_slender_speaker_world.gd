extends SceneTree
const WAIT = preload("res://tests/support/test_wait.gd")
const SAVE_PATH := "res://.godot/test-slender-world.save"
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)
func giants(world: Node) -> Array:
	return get_nodes_in_group("slender_speaker").filter(func(n): return WorldEntities.same_world(world, n) and not n.is_queued_for_deletion())
func freeze_actor(actor: Node) -> void:
	if actor is Monster: actor.process_mode = Node.PROCESS_MODE_DISABLED
func run() -> void:
	var world: Node3D = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 0
	check(generator.profile.generation_version == 10, "New production world explicitly uses v10")
	check(WorldProfile.new().generation_version == 6, "Legacy/default profile remains v6")
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play() or not await WAIT.generator_idle(self, generator):
		check(false, "v10 startup navigation publishes")
		quit(1)
		return
	generator.set_process(false)
	world.get_node("Player").set_physics_process(false)
	WorldEntities.get_container(world).child_entered_tree.connect(freeze_actor)
	check(generator.giant_navigation_map.is_valid(), "Giant has its own navigation map")
	check(generator.giant_navigation_map != world.get_world_3d().navigation_map, "Giant map cannot change normal Raker clearance")
	var initial: ChunkGenerator = generator.active_chunks[0].node
	check(initial.giant_navigation_ready, "Giant navigation completes before startup readiness")
	check(is_equal_approx(initial.giant_navigation.navigation_mesh.agent_height, 15.0) and is_equal_approx(initial.giant_navigation.navigation_mesh.agent_radius, 1.1), "Giant bake uses 15m/1.1m agent")
	var foreign_view := SubViewport.new()
	foreign_view.own_world_3d = true
	foreign_view.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(foreign_view)
	var foreign_domain := Node3D.new()
	foreign_domain.set_meta("entity_domain", true)
	foreign_view.add_child(foreign_domain)
	var foreign_giant: Node3D = load(SlenderSpeakerSpawns.SCENE).instantiate()
	WorldEntities.get_container(foreign_domain).add_child(foreign_giant)
	check(not WorldEntities.same_world(world, foreign_giant), "Other-world giant fixture belongs to a separate World3D")
	var spawned := false
	var chosen_segment := -1
	var chosen_band := -1
	for segment in range(1, 25):
		var plan := SlenderSpeakerSpawns.plan(generator.field, segment)
		if plan.candidates.is_empty(): continue
		var band: int = plan.band
		var anchor: Vector3 = plan.candidates[0] + Vector3(0, 0, 260)
		world.get_node("Player").global_position = anchor
		await generator._spawn_band(band)
		if not await WAIT.generator_idle(self, generator):
			check(false, "Candidate band giant map publishes")
			break
		generator._spawn_giant_segments(anchor)
		check(segment in generator.generated_giant_segments, "Once-ready candidate segment committed exactly once")
		if not giants(world).is_empty():
			spawned = true
			chosen_segment = segment
			chosen_band = band
			break
		for entry in generator.active_chunks.duplicate():
			if entry.index != 0: generator.retire_band(entry)
		await process_frame
	check(spawned, "Actual forest/NavMesh placement spawns a giant")
	check(spawned and foreign_giant.is_in_group("slender_speaker"), "A giant in another World3D cannot consume this world's one-giant slot")
	foreign_view.free()
	if spawned:
		var giant: Node3D = giants(world)[0]
		check(giant.get_parent() == WorldEntities.get_container(world), "Giant belongs to WorldEntities")
		check(giant.global_position.distance_to(world.get_node("Player").global_position) >= 160.0, "Giant spawns at least160m from player")
		check(SlenderSpeakerSpawns.forest_valid(generator.field, giant.global_position), "Real forest placement avoids trunks")
		check(SlenderSpeakerSpawns.static_valid(generator.field, giant.global_position), "Actual projected spawn retains road distance, POI exclusion and traversable slope")
		var record := WorldActorSnapshot.capture(giant)
		check(record.scene == SlenderSpeakerSpawns.SCENE and WorldActorSnapshot.validation_error(record, "giant").is_empty(), "Giant trusted Monster snapshot validates")
		var clone := WorldActorSnapshot.restore(record, WorldEntities.get_container(world))
		check(clone.global_transform.is_equal_approx(giant.global_transform), "Saved giant transform restores")
		clone.free()
		var checkpoint: Node = root.get_node("Checkpoint")
		giant.phase = giant.Phase.GRAB
		check(not checkpoint.save_world(world, SAVE_PATH), "Checkpoint refuses giant grab windup before contact")
		giant.phase = giant.Phase.PATROL
		giant._execution_player = world.get_node("Player")
		check(not checkpoint.save_world(world, SAVE_PATH), "Checkpoint refuses active giant execution")
		giant._execution_player = null
		check(checkpoint.save_world(world, SAVE_PATH), "Living giant v5 checkpoint writes")
		check(await checkpoint.load_world(world, SAVE_PATH), "Living giant checkpoint actually reloads")
		world = current_scene
		generator = world.get_node("WorldGenerator")
		generator.set_process(false)
		world.get_node("Player").set_physics_process(false)
		check(await WAIT.generator_idle(self, generator) and await WAIT.retired_candidates(self, checkpoint), "Restored v10 navigation and old-world retirement settle")
		var restored := giants(world)
		check(restored.size() == 1, "Checkpoint restores exactly one living giant")
		if restored.size() != 1:
			world.free()
			quit(1)
			return
		giant = restored[0]
		giant.process_mode = Node.PROCESS_MODE_DISABLED
		check(giant.global_transform.is_equal_approx(record.transform), "Actual reload preserves giant pose")
		check(giant.giant_navigation_map == generator.giant_navigation_map and giant.nav_agent.get_navigation_map() == generator.giant_navigation_map, "Actual reload rebinds giant and navigation agent to restored dedicated map")
		check(giant.phase == giant.Phase.PATROL and giant.target_player == null, "Reload starts fresh visual perception without saved target")
		check(chosen_segment in generator.generated_giant_segments, "Actual reload keeps spent segment")
		WorldEntities.get_container(world).child_entered_tree.connect(freeze_actor)
		await generator._spawn_band(chosen_band + 1)
		check(await WAIT.generator_idle(self, generator), "Neighbour giant region publishes on same map")
		var road_start: Vector3 = generator.field.road_frame(chosen_band * 150.0 + 145.0).origin
		var road_end: Vector3 = generator.field.road_frame(chosen_band * 150.0 + 155.0).origin
		var path := NavigationServer3D.map_get_path(generator.giant_navigation_map, road_start, road_end, true)
		check(path.size() >= 2 and path[-1].distance_to(road_end) < 2.0, "Giant navigation crosses streaming seam without an eroded gap")
		var skipped_segment := -1
		for segment in range(chosen_segment + 1, chosen_segment + 30):
			var plan := SlenderSpeakerSpawns.plan(generator.field, segment)
			if plan.candidates.is_empty(): continue
			await generator._spawn_band(plan.band)
			check(await WAIT.generator_idle(self, generator), "Second candidate forest/navigation publishes")
			generator._spawn_giant_segments(plan.candidates[0] + Vector3(0, 0, 260))
			check(giants(world).size() == 1, "A ready second encounter cannot exceed one active giant")
			check(segment in generator.generated_giant_segments, "Encounter skipped for an active giant is permanently spent")
			skipped_segment = segment
			break
		# A cleared encounter remains spent after a tree rebake and return.
		giant.free()
		generator._spawn_giant_segments(world.get_node("Player").global_position)
		check(giants(world).is_empty(), "Cleanup cannot respawn the same segment")
		check(skipped_segment > 0 and skipped_segment in generator.generated_giant_segments, "Active-giant skip remains spent after old giant removed")
		for segment in range(skipped_segment + 1, skipped_segment + 30):
			var plan := SlenderSpeakerSpawns.plan(generator.field, segment)
			if plan.candidates.is_empty(): continue
			await generator._spawn_band(plan.band)
			check(await WAIT.generator_idle(self, generator), "Too-close candidate navigation publishes")
			var close_anchor: Vector3 = generator.field.road_frame(plan.band * 150.0 + 75.0).origin
			close_anchor.x = plan.candidates[0].x
			generator._spawn_giant_segments(close_anchor)
			check(giants(world).is_empty() and segment in generator.generated_giant_segments, "Too-close encounter is skipped and committed")
			generator._spawn_giant_segments(close_anchor + Vector3(0, 0, 300))
			check(giants(world).is_empty(), "Moving away cannot defer a previously too-close spawn")
			break
		var chunk: ChunkGenerator
		var neighbour_chunk: ChunkGenerator
		for entry in generator.active_chunks:
			if entry.index == chosen_band: chunk = entry.node
			if entry.index == chosen_band + 1: neighbour_chunk = entry.node
		var trunks: ForestTrunks = chunk.get_node("ForestTrunks")
		var seam_shape: CollisionShape3D
		var seam_shape_index := -1
		for owner_id in trunks.get_shape_owners():
			var shape := trunks.shape_owner_get_owner(owner_id) as CollisionShape3D
			if shape == null or shape.disabled: continue
			var point: Vector3 = shape.get_meta("tree_point")
			if absf(point.z + (chosen_band + 1) * 150.0) <= 5.0:
				seam_shape = shape
				seam_shape_index = trunks.shape_owner_get_shape_index(owner_id, 0)
				break
		check(seam_shape != null, "Actual production forest supplies seam tree for edit test")
		var own_iteration := NavigationServer3D.region_get_iteration_id(chunk.giant_navigation.get_region_rid())
		var neighbour_iteration := NavigationServer3D.region_get_iteration_id(neighbour_chunk.giant_navigation.get_region_rid())
		if seam_shape != null:
			check(trunks.vehicle_tree_impact(seam_shape_index, Vector3.RIGHT), "Production tree impact API accepts seam tree removal")
		await create_timer(0.5).timeout
		check(await WAIT.generator_idle(self, generator), "Giant and ordinary maps both republish after actual tree removal")
		if seam_shape != null:
			check(seam_shape.disabled and generator.destroyed_trees.has(str(seam_shape.get_meta("tree_id"))), "Actual tree removal disables collider and writes shared ledger")
			check(NavigationServer3D.region_get_iteration_id(chunk.giant_navigation.get_region_rid()) > own_iteration and NavigationServer3D.region_get_iteration_id(neighbour_chunk.giant_navigation.get_region_rid()) > neighbour_iteration, "Seam tree removal rebakes both adjacent giant regions")
		generator._spawn_giant_segments(world.get_node("Player").global_position)
		check(giants(world).is_empty(), "Navigation rebake cannot replenish giant")
		check(checkpoint.save_world(world, SAVE_PATH), "v5 checkpoint accepts v10 world and segment ledger")
		var data: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
		check(data.get("generated_giant_segments", []).has(chosen_segment), "Checkpoint stores spent segment")
		check(data.generation_version == 10 and data.version == 5, "Generation changes without checkpoint version change")
		data.generated_giant_segments.append(chosen_segment)
		check(checkpoint.validation_error(data) == "generated_giant_segments", "Duplicate ledger rejected before loading")
		var spent_entry: Dictionary
		for entry in generator.active_chunks:
			if entry.index == chosen_band: spent_entry = entry
		var retiring_rid: RID = spent_entry.node.giant_navigation.get_region_rid()
		generator.retire_band(spent_entry)
		await process_frame
		check(await WAIT.until(self, func(): return not retiring_rid in NavigationServer3D.map_get_regions(generator.giant_navigation_map), 5000, true), "Retiring chunk removes its giant region from dedicated map")
		await generator._spawn_band(chosen_band, true)
		check(await WAIT.generator_idle(self, generator), "Returning band rebuilds dedicated map")
		generator._spawn_giant_segments(world.get_node("Player").global_position)
		check(giants(world).is_empty(), "Returning after actual checkpoint reload cannot respawn spent giant")
	world.free()
	await process_frame
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(SAVE_PATH)
	if failures.is_empty(): print("PASS: v10 forest spawn, dedicated giant navigation, tree rebake/cleanup no replenishment and v5 checkpoint ledger")
	quit(0 if failures.is_empty() else 1)

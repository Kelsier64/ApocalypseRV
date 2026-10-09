extends Node3D
## v5+ streams both directions; indoor coordinates retain the outdoor anchor.
var outdoor_sites: Dictionary = {}
var dormant_items: Dictionary = {}
var destroyed_trees: Dictionary = {}
var generated_bands: Array[int] = []
var generated_giant_segments: Array[int] = []
var giant_navigation_map := RID()
var _giant_plans: Dictionary = {}
var restore_bands: Array[int] = []
var restoring_entities: bool = false
var active_chunks: Array = []
var field: WorldField
var poi_spawner := POISpawner.new()
var next_band: int = 0
var building: bool = false
var horizon: MeshInstance3D
var generation_times: Array[float] = []
var _cleanup_timer := 0.0
@export var player: Node3D
@export var world_seed: int = -1
@export var profile: WorldProfile

func _enter_tree() -> void:
	if giant_navigation_map.is_valid():
		NavigationServer3D.map_set_active(giant_navigation_map, true)
		_bind_giants.call_deferred()

func _exit_tree() -> void:
	if giant_navigation_map.is_valid(): NavigationServer3D.map_set_active(giant_navigation_map, false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and giant_navigation_map.is_valid():
		NavigationServer3D.free_rid(giant_navigation_map)
		giant_navigation_map = RID()

func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(Groups.PLAYER)
	if profile == null:
		profile = WorldProfile.new()
	if world_seed < 0:
		world_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	field = WorldField.new(world_seed, profile)
	if profile.generation_version >= 10:
		giant_navigation_map = NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(giant_navigation_map, 0.275)
		NavigationServer3D.map_set_cell_height(giant_navigation_map, 0.25)
		NavigationServer3D.map_set_merge_rasterizer_cell_scale(giant_navigation_map, 0.1)
		NavigationServer3D.map_set_edge_connection_margin(giant_navigation_map, 0.8)
		NavigationServer3D.map_set_active(giant_navigation_map, true)
	field.destroyed_trees = destroyed_trees
	# Thin scenery and independently baked tile edges must not quantize into
	# the same 25cm merge cell. Keep centimetre-scale matching on this map only.
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(get_world_3d().navigation_map, 0.1)
	print("WORLD v%d seed=%d" % [profile.generation_version, world_seed])
	var initial_bands: Array = range(-profile.chunks_behind, profile.chunks_ahead + 1) if restore_bands.is_empty() else restore_bands
	for index in initial_bands:
		_spawn_band(index)
	next_band = int(initial_bands.back()) + 1
	if not restore_bands.is_empty():
		_refresh_horizon(next_band, false)
	if not get_parent().has_node("OutdoorPresentation"):
		var presentation := OutdoorPresentation.new()
		presentation.name = "OutdoorPresentation"
		get_parent().add_child.call_deferred(presentation)

func tree_navigation_changed(source: ChunkGenerator, point: Vector3) -> void:
	for entry in active_chunks:
		var chunk: ChunkGenerator = entry.node
		if chunk == source: continue
		if point.z <= -chunk.band * 150.0 + 5 and point.z >= -(chunk.band + 1) * 150.0 - 5:
			chunk.request_navigation_rebuild()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var anchor := player.global_position
	var instances := get_parent().get_node_or_null("PoiInstances") as PoiInstanceManager
	if instances != null and not instances.active_id.is_empty():
		anchor = instances.stream_anchor
	var current := floori(-anchor.z / profile.chunk_length)
	if profile.generation_version >= 10:
		_bind_giants()
		if not restoring_entities: _spawn_giant_segments(anchor)
	var pinned := protected_bands(anchor)
	if not building:
		for index in pinned:
			if not active_chunks.any(func(c): return int(c.index) == index):
				_spawn_band(index, true)
				break
	if profile.generation_version >= 5:
		if not building:
			# Fill the closest missing band first, including when returning north.
			var wanted: Array[int] = []
			for index in range(current - profile.chunks_behind, current + profile.chunks_ahead + 1): wanted.append(index)
			wanted.sort_custom(func(a, b): return absi(a - current) < absi(b - current))
			for index in wanted:
				if not active_chunks.any(func(c): return int(c.index) == index):
					_spawn_band(index, true)
					break
		for entry in active_chunks.duplicate():
			if (entry.index < current - profile.chunks_behind or entry.index > current + profile.chunks_ahead) and entry.index not in pinned:
				retire_band(entry)
		_cleanup_timer -= delta
		if _cleanup_timer <= 0.0:
			_cleanup_timer = 0.5
			_despawn_entities_behind(anchor.z)
		return
	if not building and next_band <= current + profile.chunks_ahead:
		if not active_chunks.any(func(c): return int(c.index) == next_band):
			_spawn_band(next_band, true)
		next_band += 1
	if not active_chunks.is_empty() and int(active_chunks[0].index) < current - profile.chunks_behind and int(active_chunks[0].index) not in pinned:
		active_chunks.pop_front().node.queue_free()
	# Remote cleanup does not need to allocate group/child arrays every frame.
	_cleanup_timer -= delta
	if _cleanup_timer <= 0.0:
		_cleanup_timer = 0.5
		_despawn_entities_behind(anchor.z)

func protected_bands(anchor: Vector3) -> Array[int]:
	var result: Array[int] = []
	if profile.generation_version < 3: return result
	for site in field.sites_near_z(anchor.z, 400):
		if not site.has("bounds") or not site.bounds.has_point(anchor): continue
		var box: AABB = site.bounds
		for index in range(floori(-box.end.z / 150.0) - 1, floori(-box.position.z / 150.0) + 2):
			if index not in result: result.append(index)
	return result

func _spawn_band(index: int, gradual: bool = false) -> void:
	building = true
	var chunk := ChunkGenerator.new()
	chunk.name = "Band_%d" % index
	add_child(chunk)
	chunk.set_meta("skip_actors", restoring_entities or index in generated_bands)
	chunk.set_meta("skip_walk_in", restoring_entities)
	if profile.generation_version >= 7 and index == -1:
		# The rear barrier is static chunk geometry, parsed by the same nav bake.
		var roadblock: Node3D = load("res://world/starting_shelter/roadblock.tscn").instantiate()
		chunk.add_child(roadblock)
		roadblock.position = Vector3(0, 0, 20)
	await chunk.generate(field, index, poi_spawner, gradual)
	if profile.generation_version >= 7 and index == 0:
		var start_run := get_parent().get_node_or_null("StartRun")
		if start_run != null and start_run.has_method("bind_shelter"):
			var site := field.stop(0)
			for child in chunk.get_children():
				if child is Node3D and child.get_meta("poi_id", "") == site.id:
					start_run.bind_shelter(child, site)
					break
	_stabilize_support_names(chunk)
	if not restoring_entities: restore_dormant_items(index)
	if index not in generated_bands: generated_bands.append(index)
	active_chunks.append({"node": chunk, "index": index, "start_z": -index * profile.chunk_length, "end_z": -(index + 1) * profile.chunk_length})
	active_chunks.sort_custom(func(a, b): return int(a.index) < int(b.index))
	generation_times.append(chunk.build_ms)
	if generation_times.size() > 64:
		generation_times.pop_front()
	# Pinning may fill a band behind the player. Its horizon must not cover
	# already-loaded roads and sites with a coarse visual-only terrain sheet.
	if (gradual or index == profile.chunks_ahead) and index == int(active_chunks.back().index):
		await _refresh_horizon(index + 1, gradual)
	print("TERRAIN band=%d build_ms=%.1f max_slice_ms=%.1f active=%d" % [index, chunk.build_ms, chunk.max_slice_ms, active_chunks.size()])
	building = false

func _refresh_horizon(index: int, gradual: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(31):
		var z := -index * profile.chunk_length - j * 30.0
		for i in range(71):
			var x := -1050.0 + i * 30.0
			st.set_color(Color(0.36, 0.39, 0.27))
			st.add_vertex(Vector3(x, field.height_at(x, z), z))
		if gradual and j % 5 == 0:
			await get_tree().process_frame
	for j in range(30):
		for i in range(70):
			var a := j * 71 + i
			for v in [a, a + 71, a + 1, a + 1, a + 71, a + 72]:
				st.add_index(v)
	st.generate_normals()
	var next := MeshInstance3D.new()
	next.name = "Horizon"
	next.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	next.material_override = mat
	add_child(next)
	if is_instance_valid(horizon):
		horizon.queue_free()
	horizon = next

func _despawn_entities_behind(player_z: float) -> void:
	var distance := (profile.chunks_behind + 1) * profile.chunk_length
	for node in get_tree().get_nodes_in_group(Groups.MONSTERS):
		if node is Node3D and WorldEntities.same_world(self, node) and (absf(node.global_position.z - player_z) > RoadSpawns.SAFE_DISTANCE if profile.generation_version >= 8 else node.global_position.z - player_z > distance) and not _in_loaded_walk_in(node.global_position):
			node.queue_free()
	var container := WorldEntities.get_container(self)
	if container != null and container.is_inside_tree():
		for child in container.get_children():
			# v8 monsters already use the symmetric current-position policy above.
			if profile.generation_version >= 8 and child is Monster: continue
			if child is Node3D and child.global_position.z - player_z > distance and not _in_loaded_walk_in(child.global_position):
				if child is Item:
					_store_items([child])
				else: child.queue_free()

func _in_loaded_walk_in(point: Vector3) -> bool:
	for entry in active_chunks:
		for site in entry.node.sites:
			if site.kind == "walk_in" and site.bounds.has_point(point): return true
	return false

func activate_walk_in(site: Dictionary, chunk: Node) -> void:
	WalkInSites.activate(self, site, chunk)

func retire_band(entry: Dictionary) -> void:
	# Never retire a region while its asynchronous bake still owns the mesh.
	if not entry.node.navigation_ready: return
	for site in entry.node.sites:
		if site.kind == "walk_in": WalkInSites.deactivate(self, site)
	var retiring: Array = []
	var container := WorldEntities.get_container(self)
	for actor in container.get_children():
		if not actor is Item or _in_loaded_walk_in(actor.global_position): continue
		if floori(-actor.global_position.z / profile.chunk_length) == entry.index or _supported_by_chunk(actor, entry.node): retiring.append(actor)
	_store_items(retiring)
	active_chunks.erase(entry)
	entry.node.queue_free()

func _supported_by_chunk(item: Item, chunk: Node) -> bool:
	var support: Node = item.mount_support
	var visited := {}
	while is_instance_valid(support):
		if chunk.is_ancestor_of(support): return true
		if not support is Item or visited.has(support): return false
		visited[support] = true
		support = support.mount_support
	return false

func _store_items(actors: Array) -> void:
	var accepted: Array[Item] = []
	for actor: Item in actors:
		var saved := WorldActorSnapshot.capture(actor)
		if saved.is_empty(): continue
		var owner_position: Vector3 = actor.global_position
		var support := actor.mount_support
		var visited := {}
		while is_instance_valid(support) and support is Item and not visited.has(support):
			visited[support] = true
			support = support.mount_support
		if actor.is_fixed and support is StaticBody3D: owner_position = support.global_position
		var band := floori(-owner_position.z / profile.chunk_length)
		if not dormant_items.has(band): dormant_items[band] = []
		dormant_items[band].append(saved)
		accepted.append(actor)
	for actor in accepted: actor.begin_world_transfer()
	for actor in accepted: actor.free()

func restore_dormant_items(index: int) -> void:
	if not dormant_items.has(index): return
	var records: Array = dormant_items[index]
	var actors: Array = []
	var container := WorldEntities.get_container(self)
	for saved: Dictionary in records: actors.append(WorldActorSnapshot.restore(saved, container))
	dormant_items.erase(index)
	WorldActorSnapshot.restore_supports(records, actors, WorldActorSnapshot.domain(self))

func _stabilize_support_names(node: Node) -> void:
	for index in range(node.get_child_count()):
		var child := node.get_child(index)
		if str(child.name).begins_with("@"): child.name = "Anchor_%d" % index
		_stabilize_support_names(child)

func _bind_giants() -> void:
	if not giant_navigation_map.is_valid(): return
	for giant in get_tree().get_nodes_in_group("slender_speaker"):
		if WorldEntities.same_world(self, giant) and giant.has_method("set_giant_navigation_map"):
			giant.set_giant_navigation_map(giant_navigation_map)

func _spawn_giant_segments(anchor: Vector3) -> void:
	if not giant_navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(giant_navigation_map) == 0: return
	for entry in active_chunks:
		var segment := floori(int(entry.index) * profile.chunk_length / SlenderSpeakerSpawns.SEGMENT_LENGTH)
		if segment < 1 or segment in generated_giant_segments: continue
		if not _giant_plans.has(segment): _giant_plans[segment] = SlenderSpeakerSpawns.plan(field, segment)
		var plan: Dictionary = _giant_plans[segment]
		if int(plan.get("band", -1)) != int(entry.index) or not entry.node.giant_navigation_ready: continue
		# Commit the encounter before choosing a location. Every failure is final
		# for this segment, including an active giant or a too-close player.
		generated_giant_segments.append(segment)
		_giant_plans.erase(segment)
		if get_tree().get_nodes_in_group("slender_speaker").any(func(n): return WorldEntities.same_world(self, n) and not n.is_queued_for_deletion()): continue
		for candidate: Vector3 in plan.get("candidates", []):
			if candidate.distance_to(anchor) < SlenderSpeakerSpawns.PLAYER_CLEARANCE or not SlenderSpeakerSpawns.forest_valid(field, candidate): continue
			var nav_point := NavigationServer3D.map_get_closest_point(giant_navigation_map, candidate)
			if nav_point.distance_to(candidate) > 1.5: continue
			var spawn_point := nav_point + Vector3.UP * 0.1
			if spawn_point.distance_to(anchor) < SlenderSpeakerSpawns.PLAYER_CLEARANCE or not SlenderSpeakerSpawns.static_valid(field, nav_point) or not SlenderSpeakerSpawns.forest_valid(field, nav_point): continue
			var shape := CapsuleShape3D.new()
			shape.height = SlenderSpeakerSpawns.HEIGHT
			shape.radius = SlenderSpeakerSpawns.RADIUS
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform.origin = nav_point + Vector3.UP * (SlenderSpeakerSpawns.HEIGHT * 0.5 + 0.12)
			query.collision_mask = 1
			if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
			var container := WorldEntities.get_container(self)
			if container == null: break
			var giant: Node3D = load(SlenderSpeakerSpawns.SCENE).instantiate()
			giant.position = container.to_local(spawn_point)
			giant.set_giant_navigation_map(giant_navigation_map)
			container.add_child(giant)
			print("SLENDER_SPAWN segment=%d band=%d point=%s" % [segment, entry.index, giant.global_position])
			break

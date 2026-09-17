extends Node3D
## Monotonic highway streaming; indoor coordinates never move the outdoor anchor.
var restore_bands: Array[int] = []
var restoring_entities: bool = false
var active_chunks: Array = []
var field: WorldField
var poi_spawner := POISpawner.new()
var next_band: int = 0
var building: bool = false
var horizon: MeshInstance3D
var generation_times: Array[float] = []
@export var player: Node3D
@export var world_seed: int = -1
@export var profile: WorldProfile

func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(Groups.PLAYER)
	if profile == null:
		profile = WorldProfile.new()
	if world_seed < 0:
		world_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	field = WorldField.new(world_seed, profile)
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

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var anchor := player.global_position
	var instances := get_parent().get_node_or_null("PoiInstances") as PoiInstanceManager
	if instances != null and not instances.active_id.is_empty():
		anchor = instances.stream_anchor
	var current := floori(-anchor.z / profile.chunk_length)
	var pinned := protected_bands(anchor)
	if not building:
		for index in pinned:
			if not active_chunks.any(func(c): return int(c.index) == index):
				_spawn_band(index, true)
				break
	if not building and next_band <= current + profile.chunks_ahead:
		if not active_chunks.any(func(c): return int(c.index) == next_band):
			_spawn_band(next_band, true)
		next_band += 1
	if not active_chunks.is_empty() and int(active_chunks[0].index) < current - profile.chunks_behind and int(active_chunks[0].index) not in pinned:
		active_chunks.pop_front().node.queue_free()
	_despawn_entities_behind(anchor.z)

func protected_bands(anchor: Vector3) -> Array[int]:
	var result: Array[int] = []
	if profile.generation_version < 3: return result
	var nearest := maxi(0, roundi(-anchor.z / profile.stop_spacing))
	for i in range(maxi(0, nearest - 1), nearest + 2):
		var site := field.stop(i)
		if not site.has("bounds") or not site.bounds.has_point(anchor): continue
		var box: AABB = site.bounds
		for index in range(floori(-box.end.z / 150.0) - 1, floori(-box.position.z / 150.0) + 2):
			if index not in result: result.append(index)
	return result

func _spawn_band(index: int, gradual: bool = false) -> void:
	building = true
	var chunk := ChunkGenerator.new()
	add_child(chunk)
	chunk.set_meta("skip_actors", restoring_entities)
	await chunk.generate(field, index, poi_spawner, gradual)
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
		if node is Node3D and WorldEntities.same_world(self, node) and node.global_position.z - player_z > distance:
			node.queue_free()
	var container := WorldEntities.get_container(self)
	if container != null and container.is_inside_tree():
		for child in container.get_children():
			if child is Node3D and child.global_position.z - player_z > distance:
				child.queue_free()

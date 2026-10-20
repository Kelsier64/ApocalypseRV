extends SceneTree
## Slicing must preserve geometry and collision, including every forest trunk.
const WAIT = preload("res://tests/support/test_wait.gd")
const TERRAIN_CONTRACTS = preload("res://tests/support/terrain_contracts.gd")
var failures: Array[String] = []

class TerrainHost extends Node3D:
	var giant_navigation_map := RID()

	func _init() -> void:
		giant_navigation_map = NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(giant_navigation_map, 0.275)
		NavigationServer3D.map_set_cell_height(giant_navigation_map, 0.25)
		NavigationServer3D.map_set_merge_rasterizer_cell_scale(giant_navigation_map, 0.1)
		NavigationServer3D.map_set_edge_connection_margin(giant_navigation_map, 0.8)
		NavigationServer3D.map_set_active(giant_navigation_map, true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and giant_navigation_map.is_valid():
			NavigationServer3D.free_rid(giant_navigation_map)
			giant_navigation_map = RID()

func _init() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var reference: Dictionary = {}
	var legacy := WorldProfile.new()
	legacy.generation_version = 6
	for gradual: bool in [false, true]:
		var chunk := ChunkGenerator.new()
		chunk.set_meta("skip_actors", true)
		world.add_child(chunk)
		await chunk.generate(WorldField.new(42, legacy), 0, POISpawner.new(), gradual)
		var ground := chunk.get_node("Ground") as MeshInstance3D
		var body := chunk.get_node("ForestTrunks") as StaticBody3D
		var poses: Array[Transform3D] = []
		for shape: CollisionShape3D in body.get_children():
			poses.append(shape.transform)
			check(shape.shape is BoxShape3D and not shape.disabled, "Trunks retain active box collision")
		check(body.is_inside_tree() and body.collision_layer == 1, "Completed forest participates in physics")
		var snapshot := {"faces": ground.mesh.get_faces(), "trunks": poses, "decorations": chunk.decoration_positions.duplicate()}
		if gradual:
			check(snapshot == reference, "Sliced and immediate generation produce identical ground and forest")
		else:
			reference = snapshot
		if not await WAIT.navigation_ready(self, [chunk]):
			check(false, "Navigation bake/publication timed out (gradual=%s)" % gradual)
			quit(1)
			return
		chunk.queue_free()
		await process_frame
	TERRAIN_CONTRACTS.run(check)
	await _check_crossing_chunk(world)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: sliced generation preserves geometry/collision; v13 route and landforms satisfy sampled contracts")
	quit(0 if failures.is_empty() else 1)

func _check_crossing_chunk(world: Node3D) -> void:
	var field := WorldField.new(42, TERRAIN_CONTRACTS.profile())
	var rivers: Array[Dictionary] = field.landforms.rivers_near(-1200.0)
	check(not rivers.is_empty(), "v13 fixture contains a river crossing")
	if rivers.is_empty():
		return
	var crossing: Dictionary = rivers[0]
	var s := float(crossing.s)
	var host := TerrainHost.new()
	world.add_child(host)
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(world.get_world_3d().navigation_map, 0.1)
	var chunk := ChunkGenerator.new()
	chunk.set_meta("skip_actors", true)
	host.add_child(chunk)
	await chunk.generate(field, floori(s / field.profile.chunk_length), POISpawner.new(), true)
	var water := chunk.find_children("*RiverWater*", "MeshInstance3D", true, false)
	check(not water.is_empty(), "v13 crossing chunk builds visible river water")
	for mesh: MeshInstance3D in water:
		check(mesh.mesh != null and mesh.mesh.get_faces().size() >= 6, "River water has real mesh geometry")
		check(mesh.find_children("*", "CollisionShape3D", true, false).is_empty(), "River surface does not become a solid floor")
	check(chunk.has_node("BridgeStructure"), "v13 crossing chunk builds bridge structure")
	check(not chunk.find_children("*BridgeDeck*", "MeshInstance3D", true, false).is_empty(), "v13 crossing chunk builds bridge deck geometry")
	if not await WAIT.navigation_ready(self, [chunk]):
		check(false, "v13 river/bridge navigation bake/publication timed out")
	else:
		await physics_frame
		var frame := field.road_frame(s)
		var space := world.get_world_3d().direct_space_state
		for lateral: float in [-1.6, 0.0, 1.6]:
			var point: Vector3 = frame.origin + frame.basis.x * lateral
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 6.0, point + Vector3.DOWN * 3.0, 1)
			var hit := space.intersect_ray(ray)
			check(not hit.is_empty(), "Bridge supplies physical support across the RV wheel span")
			if not hit.is_empty():
				check(absf(float(hit.position.y) - point.y) < 0.2, "Bridge wheel support matches the drivable road elevation")
			var closest := NavigationServer3D.map_get_closest_point(chunk.navigation.get_navigation_map(), point)
			check(Vector2(closest.x - point.x, closest.z - point.z).length() < 1.0 and absf(closest.y - point.y) < 0.8, "Published navigation crosses the bridge deck above the river")
	host.queue_free()
	await process_frame

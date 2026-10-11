extends SceneTree
## Geometry contracts plus bounded production v10 spawn/acquisition checks.
const WAIT := preload("res://tests/support/test_wait.gd")
class FlatField extends WorldField:
	func road_frame(s: float) -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(0, 0, -s))
	func road_query(x: float, z: float) -> Dictionary: return {"s": -z, "distance": absf(x), "height": 0.0, "width": 15.0, "frame": road_frame(-z)}
	func height_at(_x: float, _z: float) -> float: return 0.0
	func normal_at(_x: float, _z: float) -> Vector3: return Vector3.UP
	func sites_near_z(_z: float, _radius: float = 240.0) -> Array[Dictionary]: return []
class PoiField extends FlatField:
	func sites_near_z(_z: float, _radius: float = 240.0) -> Array[Dictionary]:
		return [{"kind": "entrance", "definition_id": "maintenance_legacy", "building": Transform3D(Basis.IDENTITY, Vector3(60, 0, -1600)), "road": Transform3D(Basis.IDENTITY, Vector3(0, 0, -1700)), "bounds": AABB(Vector3(20, -1, -1750), Vector3(300, 5, 300)), "route": PackedVector3Array([Vector3(50, 0, -1700), Vector3(50, 0, -1500)])}]
	func court_distance(_x: float, _z: float, _site: Dictionary) -> float: return 100.0
var failures: Array[String] = []
var world: Node3D
var generator: Node
var player: CharacterBody3D
var camera: Camera3D
var rng := RandomNumberGenerator.new()

func _init() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
func frames(count := 1) -> void:
	for index in count: await physics_frame

func geometry() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	camera = Camera3D.new()
	holder.add_child(camera)
	camera.current = true
	camera.far = 1000.0
	check(not PressureSpawns.hidden_bounds(camera, AABB(Vector3(-2, 0, -20), Vector3(4, 15, 4)), -1.0), "Visible giant bounds cannot use hidden root shortcut")
	check(PressureSpawns.hidden_bounds(camera, AABB(Vector3(-2, 0, 20), Vector3(4, 15, 4)), -1.0), "Entire bounds behind camera are hidden")
	check(not PressureSpawns.hidden_bounds(camera, AABB(Vector3(-30, -20, -30), Vector3(60, 40, 10)), -1.0), "Frustum-crossing bounds remain visible even when corners leave frustum")
	check(not PressureSpawns.hidden_bounds(camera, AABB(Vector3(-2, 0, -40), Vector3(4, 15, 15)), 20.0), "Nearest model edge must clear effective fog plus ten metres")
	check(PressureSpawns.hidden_bounds(camera, AABB(Vector3(-2, 0, -60), Vector3(4, 15, 4)), 20.0), "Entire bounds beyond effective fog are hidden")
	var profile := WorldProfile.new()
	profile.generation_version = 10
	var field := FlatField.new(42, profile)
	check(PressureSpawns.static_valid(field, Vector3(20, 0, 200), .4), "Pressure can spawn on negative/rear bands before ambient giant threshold")
	check(PressureSpawns.static_valid(field, Vector3(200, 0, -1600), 1.1), "Pressure supports deep forest beyond ambient 100m road exclusion")
	check(not PressureSpawns.static_valid(field, Vector3(0, 0, -1600), .4), "Escape carriageway stays clear")
	var poi := PoiField.new(42, profile)
	check(not PressureSpawns.static_valid(poi, Vector3(70, 0, -1600), .4), "Actual POI bounds have twelve metres clearance")
	check(not PressureSpawns.static_valid(poi, Vector3(40, 0, -1650), .4), "Actual POI trail has twelve metres clearance")
	check(PressureSpawns.static_valid(poi, Vector3(200, 0, -1650), 1.1), "Exploration terrain envelope does not exempt empty deep forest")
	for scene in [PressureSpawns.RAKER_SCENE, PressureSpawns.GIANT_SCENE]:
		var actor: Node3D = scene.instantiate()
		var bounds := PressureSpawns.mesh_bounds(actor)
		check(bounds.size.y > 2.0 and bounds.size.x > .8, "Production visual meshes supply whole-model bounds")
		actor.free()
	holder.free()

func remove_enemies() -> void:
	for actor in get_nodes_in_group(Groups.MONSTERS):
		if WorldEntities.same_world(world, actor): actor.free()

func forest_spawn() -> void:
	var plan := SlenderSpeakerSpawns.plan(generator.field, 11)
	check(not plan.get("candidates", []).is_empty(), "Known v10 forest fixture exists")
	if plan.get("candidates", []).is_empty(): return
	for band in [113, 114, 115]:
		await generator._spawn_band(band, true)
		check(await WAIT.generator_idle(self, generator, 90000), "Production forest and both nav maps publish")
	remove_enemies()
	for map: RID in [world.get_world_3d().navigation_map, generator.giant_navigation_map]:
		var from: Vector3 = NavigationServer3D.map_get_closest_point(map, generator.field.road_frame(17095.0).origin)
		var to: Vector3 = NavigationServer3D.map_get_closest_point(map, generator.field.road_frame(17105.0).origin)
		check(PressureSpawns.connected_path(map, from, [to]), "Actual regular and giant navigation connect across published band seam")
	var anchor: Vector3 = plan.candidates[0]
	player.global_position = anchor + Vector3.UP * .05
	var outward: Vector3 = (anchor - generator.field.road_query(anchor.x, anchor.z).frame.origin).slide(Vector3.UP).normalized()
	camera.global_position = player.global_position + Vector3.UP * 1.7
	camera.look_at(camera.global_position - outward)
	var sample := {"point": player.global_position, "danger_direction": outward}
	var success := false
	for attempt in 12:
		if PressureSpawns.try_spawn(world, "raker", sample, rng):
			success = true
			break
	check(success, "Production forest creates a hidden physically supported connected Raker")
	if success:
		var raker: Raker
		for actor in get_nodes_in_group(Groups.MONSTERS):
			if actor is Raker and actor.get_meta("pressure_spawn", false): raker = actor
		check(raker != null and raker.target_player == null, "Spawn helper does not force Raker target")
		if raker != null:
			check(raker.global_position.distance_to(player.global_position) <= 25.0, "Actual three-dimensional Raker detection range holds")
			check(PressureSpawns.hidden_bounds(camera, raker.global_transform * PressureSpawns.mesh_bounds(raker), -1), "Complete Raker visual starts outside active camera")
			await frames(12)
			check(raker.target_player == player and raker.ai_state != Monster.State.WANDER, "Unmodified Raker AI naturally acquires production player")
	remove_enemies()
	success = false
	for attempt in 16:
		if PressureSpawns.try_spawn(world, "giant", sample, rng):
			success = true
			break
	check(success, "Production forest creates a hidden connected giant at 120–160m")
	if success:
		var giant: SlenderSpeaker
		for actor in get_nodes_in_group("slender_speaker"):
			if WorldEntities.same_world(world, actor): giant = actor
		check(giant != null and giant.target_player == null, "Spawn helper does not force giant encounter")
		check(not PressureSpawns.try_spawn(world, "giant", sample, rng), "Pressure giant shares singleton slot immediately")
		await frames(90)
		check(giant.target_player == player, "Unmodified giant perception and encounter naturally acquire player")
	remove_enemies()
	# A disabled ambient actor still occupies the global giant slot.
	var ambient: Node3D = PressureSpawns.GIANT_SCENE.instantiate()
	ambient.process_mode = Node.PROCESS_MODE_DISABLED
	WorldEntities.get_container(world).add_child(ambient)
	check(PressureSpawns.giant_present(world) and not PressureSpawns.try_spawn(world, "giant", sample, rng), "Disabled ambient giant reserves the shared slot")
	ambient.free()
	for index in PressureSpawns.RAKER_CAP - 1:
		var actor: Raker = PressureSpawns.RAKER_SCENE.instantiate()
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		WorldEntities.get_container(world).add_child(actor)
	var eighth := false
	for attempt in 12:
		if PressureSpawns.try_spawn(world, "raker", sample, rng): eighth = true; break
	check(eighth and PressureSpawns.raker_count(world) == 8 and not PressureSpawns.try_spawn(world, "raker", sample, rng), "Seven live Rakers receive only one additional actor before shared cap")
	remove_enemies()
	var missing := sample.duplicate()
	missing.point = Vector3(200, 0, 10000)
	check(not PressureSpawns.try_spawn(world, "raker", missing, rng), "Unloaded signed rear terrain cannot spawn")
	var road: Transform3D = generator.field.road_frame(-75.0)
	if not generator.active_chunks.any(func(entry): return entry.index == -1): await generator._spawn_band(-1, true)
	check(await WAIT.generator_idle(self, generator, 90000), "Rear collision and navigation publish before pressure candidates")
	player.global_position = road.origin + road.basis.x * 40.0
	player.global_position.y = generator.field.height_at(player.global_position.x, player.global_position.z) + .05
	camera.global_position = player.global_position + Vector3.UP * 1.7
	camera.look_at(camera.global_position - road.basis.z)
	sample = {"point": player.global_position, "danger_direction": road.basis.z}
	success = false
	for attempt in 12:
		if PressureSpawns.try_spawn(world, "raker", sample, rng):
			success = true
			break
	check(success, "Loaded negative rear band permits connected hidden Raker without ambient progress exclusion")
	remove_enemies()
	await generator._spawn_band(-2, true)
	check(await WAIT.until(self, func() -> bool:
		return generator.active_chunks.all(func(entry): return entry.node.giant_navigation_ready), 90000, true), "Rear giant navigation publishes alongside regular navigation")
	success = false
	for attempt in 16:
		if PressureSpawns.try_spawn(world, "giant", sample, rng): success = true; break
	check(success, "Negative rear bands create a giant before 1.5km ambient threshold")
	if success:
		await frames(90)
		var acquired := false
		for actor in get_nodes_in_group("slender_speaker"):
			if WorldEntities.same_world(world, actor) and actor.target_player == player: acquired = true
		check(acquired, "Rear giant naturally acquires player using original visual AI")
	remove_enemies()

func run() -> void:
	rng.seed = 9321
	geometry()
	world = load("res://world/main_world.tscn").instantiate()
	generator = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 0
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play(90000) or not await WAIT.generator_idle(self, generator, 90000):
		check(false, "Production startup completes")
		world.free()
		quit(1)
		return
	generator.set_process(false)
	var controller := world.get_node_or_null("DeviationPressure")
	if controller != null: controller.process_mode = Node.PROCESS_MODE_DISABLED
	player = world.get_node("Player")
	player.set_physics_process(false)
	world.get_node("StartRun").restore({"version": 1, "phase": "sealed"})
	var clock: WorldClock = world.get_node("WorldClock")
	clock.weather_running = false
	clock.running = false
	clock.weather.set_weather(Vector3.ZERO, true)
	clock.environment.fog_enabled = false
	check(PressureSpawns.effective_fog_end(world) < 0, "Disabled low-quality fog cannot hide an on-screen spawn")
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.far = 1000.0
	await forest_spawn()
	world.free()
	await frames(3)
	if failures.is_empty(): print("PASS: pressure whole-model visibility, exclusions, production forest placement/acquisition, shared giant slot and live Raker cap")
	quit(0 if failures.is_empty() else 1)

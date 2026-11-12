extends SceneTree
## Slicing must preserve geometry and collision, including every forest trunk.
const WAIT = preload("res://tests/support/test_wait.gd")
const TERRAIN_CONTRACTS = preload("res://tests/support/terrain_contracts.gd")
const V14_CONTRACTS = preload("res://tests/support/terrain_v14_contracts.gd")
const OFFROAD_CONTRACTS = preload("res://tests/support/offroad_site_contracts.gd")
const MEGASHELTER_CONTRACTS = preload("res://tests/support/megashelter_contracts.gd")
const BUILDING_LOCATOR_CONTRACTS = preload("res://tests/support/building_locator_contracts.gd")
const NAV_SURFACE = preload("res://tests/support/nav_surface_probe.gd")
const STREETLIGHT_SCENE = preload("res://world/roadside_kit/streetlight.tscn")
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
	_check_opening_profiles()
	var world := TerrainHost.new()
	root.add_child(world)
	current_scene = world
	_check_streetlight_placement()
	await _check_streetlight_flicker(world)
	var reference: Dictionary = {}
	var settings := WorldProfile.new()
	for gradual: bool in [false, true]:
		var chunk := ChunkGenerator.new()
		chunk.set_meta("skip_actors", true)
		world.add_child(chunk)
		await chunk.generate(WorldField.new(42, settings), 0, POISpawner.new(), gradual)
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
	await V14_CONTRACTS.run(self, world, check)
	await OFFROAD_CONTRACTS.run(self, world, check)
	BUILDING_LOCATOR_CONTRACTS.run(check)
	await MEGASHELTER_CONTRACTS.run(self, world, check)
	for version: int in [19]:
		await _check_crossing_chunk(world, version)
		await _check_dry_viaduct(world, version)
	await _check_mountain_navigation(world)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: sliced generation preserves geometry/collision; current routes, landforms, crossings and streetlights satisfy sampled contracts")
	quit(0 if failures.is_empty() else 1)

func _check_streetlight_placement() -> void:
	const BAND_COUNT := 36
	var single_count := 0
	var row_spacings: Array[float] = []
	var crosses_seam := false
	for world_seed: int in [6, 42, 99, 733, 1792913777, 1792932659, 1209537593]:
		var field := WorldField.new(world_seed)
		var other := WorldField.new(world_seed)
		var band_length := field.profile.chunk_length
		var plans: Array = []
		var rows: Dictionary = {}
		var singles: Dictionary = {}
		var names: Dictionary = {}
		check(RoadsideStreetlights.plan(field, -1).is_empty(), "Streetlights leave the route behind the origin empty")
		for band in range(BAND_COUNT):
			var plan := RoadsideStreetlights.plan(field, band)
			plans.append(plan)
			for light in plan:
				var s: float = light.s
				var point: Vector3 = light.pose.origin
				var remainder := fposmod(-point.z, band_length)
				var label := "Streetlight seed %d, band %d, s %.1f" % [world_seed, band, s]
				check(s >= 150.0, label + " starts beyond the opening")
				check(floori(-point.z / band_length) == band and remainder >= 5.0 and remainder <= band_length - 5.0, label + " belongs to one band with seam clearance")
				check(not names.has(light.name), label + " has a unique stable name")
				names[light.name] = true
				var cell := floori(s / RoadsideStreetlights.CELL_LENGTH)
				if String(light.name).begins_with("StreetlightV3Row"):
					if not rows.has(cell): rows[cell] = []
					rows[cell].append(light)
				else:
					check(not singles.has(cell), label + " has at most one isolated lamp per cell")
					singles[cell] = s
				var cell_offset := fposmod(s, RoadsideStreetlights.CELL_LENGTH)
				check(cell_offset >= 35.0 and cell_offset <= RoadsideStreetlights.CELL_LENGTH - 35.0, label + " leaves a gap between patterns")
				_check_streetlight_ground(field, s, point, label)
		for band in range(BAND_COUNT - 1, -1, -1):
			check(RoadsideStreetlights.plan(other, band) == plans[band], "Streetlight plans are identical when seed %d streams in reverse (band %d)" % [world_seed, band])
		check(rows.has(0), "Seed %d has a complete row within the opening 900 m" % world_seed)
		check(rows.size() >= 4, "Seed %d has at least four rows in the first 5.4 km" % world_seed)
		single_count += singles.size()
		for cell in rows:
			var lamps: Array = rows[cell]
			check(lamps.size() >= 11 and lamps.size() <= 16, "A streetlight row has 11–16 fixtures")
			if lamps.size() < 2:
				continue
			lamps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s < b.s)
			if singles.has(cell):
				var single_s: float = singles[cell]
				check(single_s <= float(lamps[0].s) - 95.0 + 0.001 or single_s >= float(lamps.back().s) + 95.0 - 0.001, "An isolated lamp is at least 95 m from its cell's row")
			var spacing := _streetlight_road_distance(field, lamps[0].s, lamps[1].s)
			row_spacings.append(spacing)
			check(spacing >= 19.95 and spacing <= 28.05, "Row spacing is between 20 and 28 m (%.2f m)" % spacing)
			var side := _streetlight_side(field, lamps[0])
			for i in range(1, lamps.size()):
				var gap := _streetlight_road_distance(field, lamps[i - 1].s, lamps[i].s)
				check(absf(gap - spacing) < 0.06, "Streetlight row keeps its spacing through bends and across bands")
				check(_streetlight_side(field, lamps[i]) == side, "Streetlight row stays on one shoulder")
			crosses_seam = crosses_seam or floori(-lamps[0].pose.origin.z / band_length) != floori(-lamps.back().pose.origin.z / band_length)
	check(single_count > 0 and row_spacings.size() > 1, "The route has isolated lamps and continuous rows")
	check(crosses_seam, "At least one streetlight row spans multiple bands")
	if not row_spacings.is_empty():
		check(row_spacings.max() - row_spacings.min() > 0.5, "Different rows roll different spacing")

func _streetlight_road_distance(field: WorldField, from: float, to: float) -> float:
	var previous := field.road_frame(from).origin
	var distance := 0.0
	for i in range(1, ceili(to - from) + 1):
		var point := field.road_frame(minf(from + i, to)).origin
		distance += point.distance_to(previous)
		previous = point
	return distance

func _streetlight_side(field: WorldField, lamp: Dictionary) -> float:
	var road := field.road_frame(lamp.s)
	var point: Vector3 = lamp.pose.origin
	return signf((point - road.origin).dot(road.basis.x))

func _check_streetlight_ground(field: WorldField, s: float, point: Vector3, label: String) -> void:
	var surface := field.surface(point.x, point.z)
	var road: Dictionary = surface.road
	var setback := float(road.distance) - float(road.width) * 0.5
	check(setback >= 1.99, label + " sits outside the asphalt")
	check(not is_finite(float(surface.water_height)) and is_equal_approx(point.y, float(surface.height)), label + " sits on dry terrain")
	var slope_limit := 50.0 if setback < 2.5 else 25.0
	check(field.normal_at(point.x, point.z).y >= cos(deg_to_rad(slope_limit)), label + " has ground its footing can support")
	check(not field.landforms.bridge_at(s - 15.0) and not field.landforms.bridge_at(s) and not field.landforms.bridge_at(s + 15.0), label + " stays off bridges and their approaches")
	for site in field.sites_near_z(point.z):
		check(field.court_distance(point.x, point.z, site) >= 20.0, label + " clears POI courts")

func _check_streetlight_flicker(world: Node3D) -> void:
	var clock := WorldClock.new()
	clock.set_time(1, 12.0)
	var chunk := Node3D.new()
	world.add_child(chunk)
	var steady := _add_streetlight(chunk, clock, RoadsideStreetlight.Fault.STEADY)
	var dip := _add_streetlight(chunk, clock, RoadsideStreetlight.Fault.DIP)
	var burst := _add_streetlight(chunk, clock, RoadsideStreetlight.Fault.BURST)
	for lamp in [steady, dip, burst]:
		check(_streetlight_energy(lamp).is_zero_approx() and lamp._flicker == null, "Daytime streetlights have no beam, lens emission or scheduled fault")
	clock.set_time(1, 23.0)
	check(_streetlight_energy(steady).is_equal_approx(Vector2.ONE) and steady._flicker == null, "A steady streetlight switches on at night without a tween")
	var dip_events := _sample_streetlight(dip, 32.0)
	var burst_events := _sample_streetlight(burst, 55.0)
	check(_streetlight_energy(steady).is_equal_approx(Vector2.ONE), "Faulty streetlights do not change another lamp's beam or lens")
	check(dip_events.size() >= 2, "A dip streetlight dims and restores repeatedly")
	if dip_events.size() >= 2:
		check(dip_events[0].x >= 1.95 and dip_events[0].x <= 10.05, "Dip profile starts after its randomized delay")
		for event in dip_events:
			check(event.z >= 0.349 and event.z <= 0.601, "Dip profile dims to 35–60% and restores to full")
		var gap := dip_events[1].x - dip_events[0].y
		check(gap >= 6.95 and gap <= 18.05, "Dip profile waits 7–18 seconds between dips (%.2f s)" % gap)
	_check_streetlight_burst(burst_events)
	check(_advance_streetlight_to_dip(burst), "Dawn test reaches an active burst dip")
	var dusk_tweens: Array[Tween] = [dip._flicker, burst._flicker]
	clock.set_time(2, 6.0)
	for lamp in [steady, dip, burst]:
		check(_streetlight_energy(lamp).is_zero_approx() and lamp._flicker == null, "Dawn cancels pending faults and switches off beam and lens")
	for tween in dusk_tweens:
		check(tween != null and not tween.is_valid(), "Dawn kills the active flicker tween")
	clock.set_time(2, 23.0)
	var unload_tween: Tween = burst._flicker
	check(unload_tween != null and unload_tween.is_valid() and not dusk_tweens.has(unload_tween), "The next dusk starts a fresh fault schedule")
	check(_advance_streetlight_to_dip(burst), "Unload test reaches an active burst dip")
	chunk.queue_free()
	await process_frame
	await process_frame # The scene tree drops bound tweens on the frame after deletion.
	check(not is_instance_valid(burst) and unload_tween != null and not unload_tween.is_valid(), "Unloading a chunk frees its lights and their active flicker tweens")
	check(clock.minute_changed.get_connections().is_empty(), "Unloading streetlights releases their clock signal connections")
	clock.free()

func _add_streetlight(parent: Node3D, clock: WorldClock, fault: int) -> RoadsideStreetlight:
	var lamp := STREETLIGHT_SCENE.instantiate() as RoadsideStreetlight
	lamp.configure(clock, Color("ffd19e"), fault, 42)
	parent.add_child(lamp)
	return lamp

func _streetlight_energy(lamp: RoadsideStreetlight) -> Vector2:
	var light := lamp.get_node("Light") as SpotLight3D
	var lens := lamp.get_node("Lens") as MeshInstance3D
	var material := lens.material_override as StandardMaterial3D
	return Vector2(light.light_energy / 2.5, material.emission_energy_multiplier / 2.2)

func _advance_streetlight_to_dip(lamp: RoadsideStreetlight) -> bool:
	for step in range(1200):
		var tween := lamp._flicker
		if tween == null or not tween.is_valid(): return false
		tween.pause()
		tween.custom_step(0.025)
		var energy := _streetlight_energy(lamp).x
		if energy >= 0.15 and energy <= 0.45: return true
	return false

# Each event records its start, restored time, lowest brightness and blackout duration.
func _sample_streetlight(lamp: RoadsideStreetlight, duration: float) -> Array[Vector4]:
	const STEP := 0.025
	var events: Array[Vector4] = []
	var started := -1.0
	var lowest := 1.0
	var dark_duration := 0.0
	var last_dark := 0.0
	var synchronized := true
	for i in range(1, roundi(duration / STEP) + 1):
		var tween: Tween = lamp._flicker
		if tween == null or not tween.is_valid():
			break
		tween.pause()
		tween.custom_step(STEP)
		var energy := _streetlight_energy(lamp)
		synchronized = synchronized and is_equal_approx(energy.x, energy.y)
		var time := i * STEP
		if energy.x < 0.98:
			if started < 0.0:
				started = time
			lowest = minf(lowest, energy.x)
			if is_zero_approx(energy.x):
				dark_duration += STEP
				last_dark = time
		elif started >= 0.0:
			events.append(Vector4(started, time, lowest, dark_duration))
			if dark_duration > 0.0:
				check(time - last_dark >= 0.45 and time - last_dark <= 0.55, "The lamp restores over about half a second after blackout")
			started = -1.0
			lowest = 1.0
			dark_duration = 0.0
	check(synchronized, "A flickering streetlight keeps its beam and lens in sync")
	return events

func _check_streetlight_burst(events: Array[Vector4]) -> void:
	var blackout := -1
	for i in range(events.size()):
		if is_zero_approx(events[i].z):
			blackout = i
			break
	check(blackout == 3 or blackout == 4, "A burst gives three or four dips before complete blackout (%d)" % blackout)
	if blackout < 0:
		return
	check(events[0].x >= 2.95 and events[0].x <= 12.05, "Burst profile starts after its randomized delay")
	for i in range(blackout):
		check(events[i].z >= 0.149 and events[i].z <= 0.451, "Burst dips reach 15–45% brightness")
		var lit_gap := events[i + 1].x - events[i].y
		check(lit_gap >= 0.33 and lit_gap <= 0.68, "Burst dips are separated by about half a second of full light (%.2f s)" % lit_gap)
	check(events[blackout].w >= 0.975 and events[blackout].w <= 2.025, "The lamp stays completely dark for one to two seconds (%.2f s)" % events[blackout].w)
	check(events.size() > blackout + 1, "Burst profile starts another cycle after cooldown")
	if events.size() > blackout + 1:
		var cooldown := events[blackout + 1].x - events[blackout].y
		check(cooldown >= 13.95 and cooldown <= 28.10, "Burst profile cools down for 14–28 seconds (%.2f s)" % cooldown)

func _check_opening_profiles() -> void:
	var current_profile := WorldProfile.new()
	check(current_profile.generation_version == 19 and WorldField.new(42, current_profile).stop(0).definition_id == "orientation_shelter", "Current default profile selects the orientation shelter")
	var sandbox: WorldProfile = load("res://world/cheat_test_profile.gd").new()
	sandbox.generation_version = 19
	sandbox.max_grade = 0.12
	var production := WorldProfile.new()
	production.generation_version = 19
	production.max_grade = sandbox.max_grade
	var field := WorldField.new(42, sandbox)
	var reference := WorldField.new(42, production)
	var site := field.stop(0)
	check(site.definition_id == "starting_shelter" and field.route != null and field.landforms != null, "Sandbox combines old garage with current route and landform generation")
	for local: Vector3 in [Vector3(0, 0, -6), Vector3(0, 0, 30)]:
		var point: Vector3 = site.building * local
		var sample := field.surface(point.x, point.z)
		check(sample.reserved and is_equal_approx(sample.height, -0.08), "Old garage and apron retain recessed terrain backing on v15")
	for point: Vector2 in [Vector2(0, -900), Vector2(180, -1200), Vector2(-230, -2100)]:
		check(field.surface(point.x, point.y) == reference.surface(point.x, point.y), "Sandbox outdoor terrain and appearance match the v15 production profile")
		check(field.road_frame(-point.y) == reference.road_frame(-point.y), "Sandbox uses the v15 production road route")

func _check_crossing_chunk(world: Node3D, version: int) -> void:
	var field := WorldField.new(42, TERRAIN_CONTRACTS.profile(version))
	var label := "v%d: " % version
	var rivers: Array[Dictionary] = field.landforms.rivers_near(-1200.0)
	check(not rivers.is_empty(), label + "fixture contains a river crossing")
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
	check(not water.is_empty(), label + "crossing chunk builds visible river water")
	for mesh: MeshInstance3D in water:
		check(mesh.mesh != null and mesh.mesh.get_faces().size() >= 6, "River water has real mesh geometry")
		check(mesh.find_children("*", "CollisionShape3D", true, false).is_empty(), "River surface does not become a solid floor")
	_check_terrain_side_seams(chunk)
	_check_rendered_shores(chunk, crossing)
	await _check_water_band_seam(host, chunk)
	check(chunk.has_node("BridgeStructure"), label + "crossing chunk builds bridge structure")
	check(not chunk.find_children("*BridgeDeck*", "MeshInstance3D", true, false).is_empty(), label + "crossing chunk builds bridge deck geometry")
	_check_bridge_supports(chunk)
	if not await WAIT.navigation_ready(self, [chunk]):
		check(false, label + "river/bridge navigation bake/publication timed out")
	else:
		await physics_frame
		var frame := field.road_frame(s)
		var space := world.get_world_3d().direct_space_state
		for side: float in [-1.0, 1.0]:
			var x := side * (field.profile.terrain_half_width - 0.25)
			var z := -chunk.band * field.profile.chunk_length - 75.0
			var height := field.height_at(x, z)
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, height + 6.0, z), Vector3(x, height - 6.0, z), 1)
			var hit := space.intersect_ray(ray)
			check(not hit.is_empty(), "Physical ground supports actors immediately inside both terrain side boundaries")
			if not hit.is_empty():
				check(absf(float(hit.position.y) - height) < 0.3, "Side-boundary collision matches the continuous terrain surface")
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

func _check_mountain_navigation(world: Node3D) -> void:
	var field := WorldField.new(42, TERRAIN_CONTRACTS.profile())
	var peak_s := 0.0
	var peak_height := -INF
	for sample in range(int(TERRAIN_CONTRACTS.LENGTH / 15.0) + 1):
		var s := sample * 15.0
		var height := field.road_height(s)
		if height > peak_height:
			peak_s = s
			peak_height = height
	check(peak_height > 150.0, "Mountain navigation fixture reaches a road summit above the former bake ceiling")
	if peak_height <= 150.0: return
	# The two bands adjoining the nearest summit seam include the highest
	# sampled road point, and exercise independent vertical bake bounds.
	var seam := roundi(peak_s / field.profile.chunk_length)
	var host := TerrainHost.new()
	world.add_child(host)
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(world.get_world_3d().navigation_map, 0.1)
	var chunks: Array[ChunkGenerator] = []
	for band in [seam - 1, seam]:
		var chunk := ChunkGenerator.new()
		chunk.field = field
		chunk.band = band
		chunk.set_meta("skip_actors", true)
		host.add_child(chunk)
		chunks.append(chunk)
		# Use the production terrain/road/crossing/navigation builders; unrelated
		# forest rendering and actor populations are covered by existing fixtures.
		await chunk._build_ground(false)
		chunk._build_road()
		await TerrainCrossings.build(chunk, false)
		await chunk._build_navigation(false)
	if not await WAIT.navigation_ready(self, chunks):
		check(false, "Summit and neighbouring band publish ordinary and giant navigation")
	else:
		var summit := field.road_frame(peak_s).origin
		var start := field.road_frame(seam * field.profile.chunk_length - 20.0).origin
		var finish := field.road_frame(seam * field.profile.chunk_length + 20.0).origin
		for giant: bool in [false, true]:
			var map: RID = host.giant_navigation_map if giant else chunks[0].navigation.get_navigation_map()
			var label := "Giant" if giant else "Ordinary"
			# Navigation retains its established height-detail simplification;
			# grounded actors advance waypoints using their real collider height.
			# This regression checks summit coverage and horizontal connectivity,
			# rather than imposing a new sub-metre vertical bake contract.
			var surface := NAV_SURFACE.point_at(chunks, summit, giant)
			check(surface.is_finite(), label + " baked navigation contains the summit XZ (summit %s at s %.1f)" % [summit, peak_s])
			if surface.is_finite():
				var closest := NavigationServer3D.map_get_closest_point(map, surface)
				check(surface.y > 150.0 and closest.y > 150.0 and Vector2(closest.x, closest.z).distance_to(Vector2(summit.x, summit.z)) < 1.0, label + " published navigation covers the road summit above the former 150m ceiling (summit %s, baked surface %s, closest %s)" % [summit, surface, closest])
			var path := NavigationServer3D.map_get_path(map, start, finish, true)
			check(path.size() >= 2 and Vector2(path[0].x, path[0].z).distance_to(Vector2(start.x, start.z)) < 1.0 and Vector2(path[-1].x, path[-1].z).distance_to(Vector2(finish.x, finish.z)) < 1.0, label + " mountain navigation connects across the summit streaming seam")
	host.queue_free()
	await process_frame

func _check_dry_viaduct(world: Node3D, version: int) -> void:
	var field := WorldField.new(42, TERRAIN_CONTRACTS.profile(version))
	var label := "v%d: " % version
	var band := -1
	var candidates: Array[int] = []
	for index in range(3):
		candidates.append(floori(float(field.landforms.dry_valley(index).s) / field.profile.chunk_length))
	for candidate: int in candidates:
		var eligible := true
		for offset: float in [10.0, 75.0, 140.0]:
			var s := candidate * field.profile.chunk_length + offset
			eligible = eligible and not field.landforms.river_span_at(s) and field.landforms.bridge_gap(s) > 0.95 and field.landforms.natural_clearance(s) > 5.0
		if eligible:
			band = candidate
			break
	check(band >= 0, label + "fixture contains a sustained elevated road over a dry valley")
	if band < 0: return
	var host := TerrainHost.new()
	world.add_child(host)
	var chunk := ChunkGenerator.new()
	chunk.field = field
	chunk.band = band
	chunk.set_meta("skip_actors", true)
	host.add_child(chunk)
	# Exercise the production ground, road, structure and navigation builders
	# without generating an unrelated second forest, scenery or actor population.
	await chunk._build_ground(false)
	chunk._build_road()
	await TerrainCrossings.build(chunk, false)
	_check_bridge_supports(chunk)
	await chunk._build_navigation(false)
	if not await WAIT.navigation_ready(self, [chunk]):
		check(false, label + "dry viaduct navigation bake/publication timed out")
	else:
		await physics_frame
		var space := world.get_world_3d().direct_space_state
		var supported := true
		for offset in range(5, 150, 10):
			var frame := field.road_frame(band * field.profile.chunk_length + offset)
			for lateral: float in [-1.6, 1.6]:
				var point := frame.origin + frame.basis.x * lateral
				var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point + Vector3.DOWN * 2.0, 1)
				var hit := space.intersect_ray(ray)
				supported = supported and not hit.is_empty()
				if not hit.is_empty(): supported = supported and absf(float(hit.position.y) - point.y) < 0.2
		check(supported, "Physical deck supports both RV wheel tracks continuously along the dry viaduct")
		var start := field.road_frame(band * field.profile.chunk_length + 10.0).origin
		var finish := field.road_frame(band * field.profile.chunk_length + 140.0).origin
		var path := NavigationServer3D.map_get_path(chunk.navigation.get_navigation_map(), start, finish, true)
		check(path.size() >= 2 and path[0].distance_to(start) < 1.0 and path[-1].distance_to(finish) < 1.0, "Published navigation connects both ends of the dry viaduct")
		var stays_on_deck := not path.is_empty()
		for point in path:
			var road := field.road_query(point.x, point.z)
			stays_on_deck = stays_on_deck and absf(point.y - float(road.height)) < 0.8
		check(stays_on_deck, "Dry viaduct navigation stays on the deck above the valley floor")
		var middle := field.road_frame(band * field.profile.chunk_length + 77.5)
		var underside_frame := field.road_frame(band * field.profile.chunk_length + 78.1)
		var underside := underside_frame * Vector3(field.road_width(band * field.profile.chunk_length + 78.1) * 0.5 * 0.58, -4.0, 0)
		var girder_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(underside, underside + Vector3.UP * 3.0, 1))
		check(not girder_hit.is_empty() and absf(float(girder_hit.position.y) - (underside_frame.origin.y - 2.11)) < 0.12, "Main girders have physical undersides matching the visible structure: %s" % girder_hit)
		for side: float in [-1.0, 1.0]:
			var inner := middle * Vector3(side * (field.road_width(band * field.profile.chunk_length + 77.5) * 0.5 - 1.0), 0.9, 0.0)
			var outer := inner + middle.basis.x * side * 4.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(inner, outer, 1))
			check(not hit.is_empty(), "Dry viaduct has physical vehicle barriers on both exposed edges")
	host.queue_free()
	await process_frame

func _check_bridge_supports(chunk: ChunkGenerator) -> void:
	var structure := chunk.get_node_or_null("BridgeStructure")
	check(structure != null, "Elevated roadway has modeled supporting structure")
	if structure == null: return
	var piers: Array[MeshInstance3D] = []
	var foundations: Array[MeshInstance3D] = []
	var caps: Array[MeshInstance3D] = []
	for member: MeshInstance3D in structure.find_children("*", "MeshInstance3D", true, false):
		if str(member.name).begins_with("Foundation"): foundations.append(member)
		elif str(member.name).begins_with("PierCap"): caps.append(member)
		elif str(member.name).begins_with("Pier"): piers.append(member)
	check(not piers.is_empty() and not foundations.is_empty() and not caps.is_empty(), "Bridge model includes piers, foundations and supporting caps")
	for pier in piers:
		var box := pier.global_transform * pier.mesh.get_aabb()
		var grounded := false
		var capped := false
		for foundation in foundations:
			var footing := foundation.global_transform * foundation.mesh.get_aabb()
			if not _horizontal_overlap(box, footing): continue
			var ground := chunk.field.height_at(footing.get_center().x, footing.get_center().z)
			grounded = grounded or (footing.position.y <= ground + 0.05 and footing.end.y >= box.position.y - 0.05)
		for cap in caps:
			var cap_box := cap.global_transform * cap.mesh.get_aabb()
			if _horizontal_overlap(box, cap_box): capped = capped or cap_box.position.y <= box.end.y + 0.05
		check(grounded, "Each pier contacts a foundation embedded in the actual valley or river bed")
		check(capped, "Each pier reaches its modeled cap beneath the bridge girders")
	var deck := chunk.get_node_or_null("BridgeDeck") as MeshInstance3D
	check(deck != null and deck.mesh != null and deck.mesh.get_aabb().size.y > 0.25, "Bridge deck is a substantial modeled slab")
	check(not structure.find_children("MainGirder*", "MeshInstance3D", true, false).is_empty(), "Bridge deck has longitudinal load bearing girders")

func _horizontal_overlap(a: AABB, b: AABB) -> bool:
	return a.position.x <= b.end.x and b.position.x <= a.end.x and a.position.z <= b.end.z and b.position.z <= a.end.z

func _check_terrain_side_seams(chunk: ChunkGenerator) -> void:
	var ground := chunk.get_node("Ground") as MeshInstance3D
	var distant := chunk.find_children("DistantTerrain*", "MeshInstance3D", false, false)
	check(distant.size() == 2, "River chunk retains both distant terrain sides")
	for side: float in [-1.0, 1.0]:
		var x := side * chunk.field.profile.terrain_half_width
		var near_edge := _vertices_at(ground.mesh.get_faces(), x, true)
		var far_edge: Dictionary = {}
		for mesh: MeshInstance3D in distant:
			far_edge.merge(_vertices_at(mesh.mesh.get_faces(), x, true))
		check(near_edge.size() >= 51 and near_edge == far_edge, "Physical and distant terrain share every vertex at x=%.0fm without a side gap" % x)

func _vertices_at(faces: PackedVector3Array, coordinate: float, use_x: bool) -> Dictionary:
	var vertices: Dictionary = {}
	for point in faces:
		if absf((point.x if use_x else point.z) - coordinate) < 0.001:
			vertices[Vector2i(roundi((point.z if use_x else point.x) * 1000.0), roundi(point.y * 1000.0))] = true
	return vertices

func _check_water_band_seam(host: Node3D, chunk: ChunkGenerator) -> void:
	var water := chunk.get_node("RiverWater") as MeshInstance3D
	var north := -chunk.band * chunk.field.profile.chunk_length
	var seam := north
	var neighbor_band := chunk.band - 1
	var edge := _vertices_at(water.mesh.get_faces(), seam, false)
	if edge.is_empty():
		seam = north - chunk.field.profile.chunk_length
		neighbor_band = chunk.band + 1
		edge = _vertices_at(water.mesh.get_faces(), seam, false)
	check(not edge.is_empty(), "River fixture exercises a water ribbon crossing a streaming boundary")
	if edge.is_empty(): return
	# Only build the crossing geometry: the existing fixture already covers
	# full generation/navigation, and a second forest adds no seam coverage.
	var neighbor := ChunkGenerator.new()
	neighbor.field = chunk.field
	neighbor.band = neighbor_band
	host.add_child(neighbor)
	await TerrainCrossings.build(neighbor, false)
	var adjacent := neighbor.get_node_or_null("RiverWater") as MeshInstance3D
	check(adjacent != null, "Adjacent band owns the continuing river water mesh")
	if adjacent != null:
		check(edge == _vertices_at(adjacent.mesh.get_faces(), seam, false), "Clipped water meshes have identical intersection vertices across the streaming seam")
	neighbor.queue_free()
	await process_frame

func _check_rendered_shores(chunk: ChunkGenerator, river: Dictionary) -> void:
	var north := -chunk.band * chunk.field.profile.chunk_length
	var south := north - chunk.field.profile.chunk_length
	var terrain: Array[PackedVector3Array] = []
	for mesh: MeshInstance3D in chunk.find_children("DistantTerrain*", "MeshInstance3D", false, false):
		terrain.append(mesh.mesh.get_faces())
	var checked := 0
	var exposed := 0
	var dry_bed := 0
	# Sample actual water-segment midpoints between far-terrain columns,
	# where a coarse mesh could bridge over the carved channel completely.
	for index in range(0, ceili(2.0 * TerrainCrossings.WATER_EXTENT / TerrainCrossings.WATER_STEP), 4):
		var x0 := -TerrainCrossings.WATER_EXTENT + index * TerrainCrossings.WATER_STEP
		var polygon := TerrainCrossings.water_polygon(chunk.field.landforms, river, x0, minf(x0 + TerrainCrossings.WATER_STEP, TerrainCrossings.WATER_EXTENT))
		for side: int in [0, 1]:
			var edge := polygon[0].lerp(polygon[1], 0.5) if side == 0 else polygon[3].lerp(polygon[2], 0.5)
			if absf(edge.x) < 520.0 or edge.z < south + 6.0 or edge.z > north - 6.0: continue
			var inside := edge + Vector3(0.0, 0.0, 5.0 if side == 0 else -5.0)
			var bank_height := INF
			var bed_height := INF
			for faces in terrain:
				bank_height = minf(bank_height, _mesh_height(faces, edge))
				bed_height = minf(bed_height, _mesh_height(faces, inside))
			checked += 1
			if not is_finite(bank_height) or bank_height < edge.y - 0.02: exposed += 1
			if not is_finite(bed_height) or bed_height >= edge.y - 0.02: dry_bed += 1
	check(checked > 0, "River fixture samples rendered shoreline in the distant terrain")
	check(exposed == 0, "Distant terrain covers the outer water ribbon edge (%d exposed samples)" % exposed)
	check(dry_bed == 0, "Distant terrain retains a submerged channel beneath visible water (%d dry samples)" % dry_bed)

func _mesh_height(faces: PackedVector3Array, point: Vector3) -> float:
	for index in range(0, faces.size(), 3):
		var a := faces[index]
		var b := faces[index + 1]
		var c := faces[index + 2]
		if point.x < minf(a.x, minf(b.x, c.x)) - 0.001 or point.x > maxf(a.x, maxf(b.x, c.x)) + 0.001: continue
		if point.z < minf(a.z, minf(b.z, c.z)) - 0.001 or point.z > maxf(a.z, maxf(b.z, c.z)) + 0.001: continue
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var ap := Vector2(point.x - a.x, point.z - a.z)
		var determinant := ab.cross(ac)
		if absf(determinant) < 0.000001: continue
		var u := ap.cross(ac) / determinant
		var v := ab.cross(ap) / determinant
		if u >= -0.0001 and v >= -0.0001 and u + v <= 1.0001:
			return a.y + u * (b.y - a.y) + v * (c.y - a.y)
	return INF

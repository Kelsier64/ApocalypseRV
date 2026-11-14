extends RefCounted
## Generated world detail: planned features, scatter layers, road dressing and
## knock-down props. Runs inside test_streaming_generation.
const CONTRACTS = preload("res://tests/support/terrain_contracts.gd")
const WAIT = preload("res://tests/support/test_wait.gd")
const CELLS := 40

static func run(tree: SceneTree, world: Node3D, check: Callable) -> void:
	_check_catalog(check)
	var built := false
	for seed_value: int in CONTRACTS.SEEDS:
		var field := WorldField.new(seed_value, CONTRACTS.profile())
		# One field planned back to front answers both order-independence checks.
		var reverse := WorldField.new(seed_value, CONTRACTS.profile())
		_check_features(field, reverse, check)
		_check_road_dressing(field, reverse, check)
		if not built: built = await _check_band(tree, world, field, check)
	check.call(built, "At least one sampled seed offers a band with knock-down props to build")

static func _check_catalog(check: Callable) -> void:
	var ids := {}
	var meshes := true
	var bounded := true
	for layer in ScatterCatalog.layers():
		check.call(not ids.has(layer.id), "Scatter layer %s has a unique id (its RNG stream)" % layer.id)
		ids[layer.id] = true
		bounded = bounded and layer.landforms.size() == TerrainLandforms.KINDS.size() and layer.spacing > 0.5 and not layer.variants.is_empty() and layer.scale_min <= layer.scale_max
		# A solid footprint keeps props off the shoulder that road encounters use.
		if layer.solid: bounded = bounded and layer.radius > 0.0 and layer.road_min >= 4.5 and layer.pattern == ScatterLayer.Pattern.GRID
		for variant in layer.variants:
			var mesh := ScatterMeshes.mesh(variant)
			meshes = meshes and mesh != null and mesh.get_surface_count() > 0 and mesh.get_faces().size() >= 3
			if layer.solid: meshes = meshes and ScatterMeshes.solid(variant).size.x > 0.05 and ScatterMeshes.solid(variant).size.y > 0.05
	check.call(ids.size() >= 12, "The catalog carries the natural, verge and carriageway layers")
	check.call(bounded, "Every scatter layer has per-landform weights, variants and a legal footprint")
	check.call(meshes, "Every scatter variant resolves to real geometry, and solids to a collision box")
	for id: StringName in ScatterMeshes.POSTS:
		var mesh := ScatterMeshes.mesh(id)
		check.call(mesh != null and mesh.get_faces().size() >= 12, "Knock-down prop %s has a mesh behind its post collider" % id)

static func _check_features(field: WorldField, reverse: WorldField, check: Callable) -> void:
	var label := "seed %d: " % field.world_seed
	var features := field.features
	for index in range(CELLS - 1, -1, -1): reverse.features.cell(index)
	var deterministic := true
	var contained := true
	var clear := true
	var shaped := true
	var counts := {"ponds": 0, "tracks": 0, "roadside": 0, "pylons": 0}
	var length := field.profile.chunk_length
	for index in range(CELLS):
		var plan := features.cell(index)
		deterministic = deterministic and plan == reverse.features.cell(index)
		var north := -index * WorldFeatures.CELL
		var south := north - WorldFeatures.CELL
		for pond: Dictionary in plan.ponds:
			counts.ponds += 1
			var reach := float(pond.r) * 1.35 + 14.0
			contained = contained and float(pond.z) + reach < north and float(pond.z) - reach > south and absf(float(pond.x)) + reach < 440.0
			contained = contained and fposmod(-float(pond.z), length) > reach and fposmod(-float(pond.z), length) < length - reach
			clear = clear and _clear_of_sites(field, pond.x, pond.z, reach)
			var centre := field.surface(pond.x, pond.z)
			shaped = shaped and is_equal_approx(float(centre.water_height), float(pond.level)) and float(centre.height) < float(pond.level) - 0.5 and centre.reserved
			# Every shoreline sample sits at the waterline, wherever the outline wanders.
			for step in range(8):
				var angle := step * TAU / 8.0
				var shore := WorldFeatures.pond_radius(pond, angle)
				var rim := field.surface(float(pond.x) + cos(angle) * (shore + 6.0), float(pond.z) + sin(angle) * (shore + 6.0))
				shaped = shaped and not is_finite(float(rim.water_height)) and float(rim.height) > float(pond.level)
				var road := field.road_query(float(pond.x) + cos(angle) * shore, float(pond.z) + sin(angle) * shore)
				clear = clear and float(road.distance) - float(road.width) * 0.5 > 14.0
		for track: Dictionary in plan.tracks:
			counts.tracks += 1
			var points: PackedVector3Array = track.points
			var centre: Vector3 = track.centre
			var radius: float = track.radius
			contained = contained and points.size() >= 10 and centre.z < north and centre.z > south
			contained = contained and fposmod(-centre.z, length) > radius and fposmod(-centre.z, length) < length - radius
			clear = clear and _clear_of_sites(field, centre.x, centre.z, radius)
			var pad := field.surface(centre.x, centre.z)
			shaped = shaped and pad.reserved and absf(float(pad.height) - centre.y) < 0.05
			var steepest := 0.0
			for i in range(points.size()):
				contained = contained and points[i].z < north and points[i].z > south and absf(points[i].x) < 440.0
				if i > 0: steepest = maxf(steepest, absf(points[i].y - points[i - 1].y) / WorldFeatures.TRACK_STEP)
				var sample := field.surface(points[i].x, points[i].z)
				shaped = shaped and not is_finite(float(sample.water_height))
				# Past the road's own earthworks the graded bed is the terrain.
				if float(sample.road.distance) - float(sample.road.width) * 0.5 > 20.0 and Vector2(points[i].x - centre.x, points[i].z - centre.z).length() > radius + 8.0:
					shaped = shaped and absf(float(sample.height) - points[i].y) < 0.05 and sample.reserved and float(sample.track) < 0.05
			shaped = shaped and steepest <= WorldFeatures.TRACK_GRADE + 0.001
		for pad: Dictionary in plan.pads:
			if pad.type == "reserve": continue
			if pad.type == "pylon": counts.pylons += 1
			elif pad.has("side"): counts.roadside += 1
			var radius: float = pad.r
			contained = contained and float(pad.z) < north and float(pad.z) > south and fposmod(-float(pad.z), length) > radius and fposmod(-float(pad.z), length) < length - radius
			clear = clear and _clear_of_sites(field, pad.x, pad.z, radius)
			var sample := field.surface(pad.x, pad.z)
			shaped = shaped and sample.reserved and not is_finite(float(sample.water_height))
			# Solid roadside content leaves the shoulder to wrecks, strips and lamps.
			clear = clear and float(sample.road.distance) - float(sample.road.width) * 0.5 - radius > 4.5
	check.call(deterministic, label + "feature cells are independent of planning order")
	check.call(contained, label + "every feature stays inside its cell, its band and the collision strip")
	check.call(clear, label + "ponds, tracks and pads keep clear of POI courts and the carriageway")
	check.call(shaped, label + "the surface carries each pond's waterline, each track's graded bed and each pad's reservation")
	check.call(counts.tracks > 0 and counts.roadside >= 4 and counts.pylons >= 8, label + "12 km offers tracks, roadside traces and a transmission line (%s)" % counts)
	var margins := true
	for station: float in [700.0, 2500.0, 6100.0]:
		var frame := field.road_frame(station)
		for lateral: float in [0.0, field.road_width(station) * 0.5 + 2.0, 60.0]:
			var point := frame * Vector3(lateral, 0, 0)
			var sample := field.surface(point.x, point.z)
			margins = margins and (sample.reserved or not sample.occupied)
		margins = margins and field.surface(frame.origin.x, frame.origin.z).reserved
	check.call(margins, label + "occupied ground is always reserved, and the carriageway margin is reserved on its own")
	var opening := features.cell(0)
	check.call(opening.ponds.is_empty() and opening.tracks.is_empty() and opening.pads.is_empty() and opening.fences.is_empty(), label + "the opening stretch has no generated features")

static func _clear_of_sites(field: WorldField, x: float, z: float, radius: float) -> bool:
	for site: Dictionary in field.sites_near_z(z, 400.0):
		if field.court_distance(x, z, site) < radius + 20.0: return false
	return true

static func _check_road_dressing(field: WorldField, reverse: WorldField, check: Callable) -> void:
	var label := "seed %d: " % field.world_seed
	var signs := 0
	var warnings := 0
	var legal := true
	var deterministic := true
	var bands := int(CONTRACTS.LENGTH / field.profile.chunk_length)
	var plans: Array = []
	for band in range(bands - 1, -1, -1): plans.push_front([RoadDetails.curve_signs(reverse, band), RoadDetails.markers(reverse, band)])
	for band in range(bands):
		var boards := RoadDetails.curve_signs(field, band)
		var posts := RoadDetails.markers(field, band)
		deterministic = deterministic and boards == plans[band][0] and posts == plans[band][1]
		for board: Dictionary in boards:
			signs += 1
			if board.kind == "warning": warnings += 1
			var point: Vector3 = board.point
			var sample := field.surface(point.x, point.z)
			legal = legal and floori(-point.z / field.profile.chunk_length) == band and not field.landforms.bridge_at(float(board.s))
			legal = legal and float(sample.road.distance) - float(sample.road.width) * 0.5 > 4.0 and not is_finite(float(sample.water_height))
			# A warning stands before the bend it announces and bends the right way.
			if board.kind == "warning":
				var ahead := float(board.s) + RoadDetails.WARNING_LEAD * float(board.side)
				legal = legal and absf(field.route.curvature(ahead)) >= 1.0 / RoadDetails.APEX_RADIUS - 0.0001
				legal = legal and is_equal_approx(float(board.bend), signf(field.route.curvature(ahead)) * float(board.side))
		for post: Dictionary in posts:
			legal = legal and floori(-float(post.point.z) / field.profile.chunk_length) == band
	check.call(deterministic, label + "curve signs and marker posts are independent of streaming order")
	check.call(legal, label + "road furniture stays in its band, off bridges and outside the asphalt, and warnings match their bend")
	check.call(signs > 12 and warnings > 4, label + "a winding 12 km carries hazard boards and curve warnings (%d, %d)" % [signs, warnings])
	var poles := 0
	var poles_match := true
	for index in range(0, 240):
		var pose := RoadDetails.pole_pose(field, index)
		poles_match = poles_match and pose == RoadDetails.pole_pose(reverse, index)
		if pose != Transform3D.IDENTITY: poles += 1
	check.call(poles > 60 and poles_match, label + "utility poles are a pure function of the route, so a band can string a line to its neighbour's pole")
	var mesh := RoadDetails.surface_mesh(field, 6)
	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var widths: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var mapped := uvs.size() > 100
	for index in range(uvs.size()):
		mapped = mapped and is_equal_approx(absf(uvs[index].x), widths[index].x) and uvs[index].y >= 0.0 and uvs[index].y <= RoadDetails.UV_WRAP
	check.call(mapped, label + "the asphalt strip carries lateral and route coordinates for its surface shader")

## Builds one real band that owns knock-down props and exercises the chunk-level contracts.
static func _check_band(tree: SceneTree, world: Node3D, field: WorldField, check: Callable) -> bool:
	var band := -1
	for index in range(2, CELLS):
		for fence: Dictionary in field.features.cell(index).fences:
			band = floori(-float(fence.z) / field.profile.chunk_length)
			break
		if band >= 0: break
	if band < 0: return false
	var label := "seed %d band %d: " % [field.world_seed, band]
	var chunk := ChunkGenerator.new()
	chunk.set_meta("skip_actors", true)
	world.add_child(chunk)
	await chunk.generate(field, band, POISpawner.new(), false)
	var planned: Dictionary = await ScatterScenery.plan(chunk, false)
	var other := ChunkGenerator.new()
	other.field = WorldField.new(field.world_seed, CONTRACTS.profile())
	other.band = band
	world.add_child(other)
	await ForestScenery.prepare(other, band, false)
	# The second chunk never built ground: its grid is sampled straight from the field.
	check.call(planned == await ScatterScenery.plan(other, false), label + "scatter placements match between a built chunk and a fresh field")
	other.free()
	var solids := 0
	var legal := true
	var placements := 0
	var length := field.profile.chunk_length
	for layer in ScatterCatalog.layers():
		check.call(planned.has(layer.id), label + "layer %s is planned" % layer.id)
		for placement: Dictionary in planned.get(layer.id, []):
			placements += 1
			var pose: Transform3D = placement.pose
			legal = legal and int(placement.variant) >= 0 and int(placement.variant) < layer.variants.size() and pose.origin.is_finite()
			# Verge rows follow the road frame, which may lean a step across a seam.
			legal = legal and pose.origin.z < -band * length + 3.5 and pose.origin.z > -(band + 1) * length - 3.5
			if not layer.solid: continue
			solids += 1
			var sample := field.surface(pose.origin.x, pose.origin.z)
			var offset := fposmod(-pose.origin.z, length)
			legal = legal and not sample.reserved and not is_finite(float(sample.water_height))
			legal = legal and float(sample.road.distance) - float(sample.road.width) * 0.5 >= layer.road_min - 0.5
			legal = legal and offset >= ScatterScenery.SEAM and offset <= length - ScatterScenery.SEAM
			for site: Dictionary in field.sites_near_z(pose.origin.z): legal = legal and field.court_distance(pose.origin.x, pose.origin.z, site) >= 8.0
	check.call(placements > 200 and legal, label + "scatter stays in its band; solids avoid water, courts, the shoulder and the seams (%d placements)" % placements)
	var body := chunk.get_node_or_null("ScatterSolids") as StaticBody3D
	check.call(body != null and body.get_child_count() == solids and body.collision_layer == 1, label + "every solid placement has one collider on the world layer (%d)" % solids)
	# Between vertices the grid follows the rendered triangles, not the analytic
	# surface, so compare on a vertex near the band's middle.
	var grid := chunk.grid
	var sampled := grid != null
	if sampled:
		var vertex := Vector2(grid.x0 + grid.step_x * floori(grid.columns * 0.5), grid.z0 - grid.step_z * floori(grid.rows * 0.5))
		sampled = grid.probe(vertex.x, vertex.y) and absf(grid.height - field.height_at(vertex.x, vertex.y)) < 0.01
	check.call(sampled, label + "the band keeps its sampled grid for detail placement")
	var props: Array[BreakableProps] = []
	for child in chunk.get_children():
		if child is BreakableProps: props.append(child)
	check.call(props.size() >= 2, label + "road furniture and fence runs are separate knock-down bodies")
	var built := false
	for prop in props:
		check.call(prop.collision_layer == TreeImpact.SHRUB_LAYER and prop.collision_mask == 0 and prop.get_child_count() > 0, label + "%s collides with the RV only" % prop.name)
		check.call(TreeImpact.retained_for(prop) > TreeImpact.SPEED_RETAINED and TreeImpact.retained_for(chunk.get_node("ForestTrunks")) == TreeImpact.SPEED_RETAINED, label + "%s costs the RV less speed than a tree trunk" % prop.name)
		if built: continue
		built = true
		var struck := prop.get_child(0) as CollisionShape3D
		var key: String = struck.get_meta("tree_id")
		var count := prop.get_child_count()
		check.call(prop.vehicle_tree_impact(0, Vector3.FORWARD * 8.0) and not prop.vehicle_tree_impact(0, Vector3.FORWARD * 8.0), label + "a prop yields to exactly one impact")
		await tree.process_frame
		check.call(struck.disabled and prop.vehicle_tree_is_broken(0) and field.destroyed_trees.has(key) and TreeImpact.valid_ledger(field.destroyed_trees), label + "the knocked prop is tombstoned in the saved ledger")
		var title := str(prop.name)
		var items: Array[Dictionary] = []
		for shape: CollisionShape3D in prop.get_children():
			var visual: Dictionary = prop.visuals[shape.get_meta("tree_point")]
			check.call(visual.node is MultiMeshInstance3D, label + "each knock-down collider maps to one batched instance")
			items.append({"mesh": &"marker_0", "pose": Transform3D(Basis.IDENTITY, shape.get_meta("tree_point"))})
		var rebuilt := BreakableProps.build(chunk, title + "Rebuilt", items)
		check.call(rebuilt != null and rebuilt.get_child_count() == count - 1, label + "rebuilding the band omits the tombstoned prop")
	if not await WAIT.navigation_ready(tree, [chunk]): check.call(false, label + "navigation publishes with detail colliders present")
	chunk.queue_free()
	await tree.process_frame
	field.destroyed_trees.clear()
	return true

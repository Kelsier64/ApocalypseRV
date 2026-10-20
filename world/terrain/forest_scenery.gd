extends RefCounted
class_name ForestScenery
## Deterministic forest cells shared by rendering, collision and seam navigation.

static func trees(field: WorldField, band: int) -> Array[Dictionary]:
	return field.forest_cache.get(band, [] as Array[Dictionary])

static func prepare(chunk: ChunkGenerator, band: int, gradual: bool) -> void:
	var field := chunk.field
	if field.forest_cache.has(band): return
	if field.profile.generation_version >= 14:
		await _prepare_v14(chunk, band, gradual)
		return
	var result: Array[Dictionary] = []
	var rng := field.rng_for(band, "dense_forest")
	for row in range(19):
		if gradual: await chunk._pause()
		for column in range(112):
			var x := -444.0 + column * 8.0 + rng.randf_range(-2.5, 2.5)
			var z := -band * 150.0 - (row + 0.5) * 150.0 / 19.0 + rng.randf_range(-1.8, 1.8)
			var chance := rng.randf()
			if chance > clampf(0.79 + field.clusters.get_noise_2d(x, z) * 0.4, 0.55, 0.95): continue
			var sample := field.surface(x, z)
			if sample.reserved or sample.road.distance < sample.road.width * 0.5 + 5.0: continue
			if field.landforms != null and not field.landforms.vegetation(sample, x, z): continue
			var point := Vector3(x, sample.height, z)
			if landmark_slit(field, point): continue
			result.append({"point": point, "height": rng.randf_range(12.0, 21.0), "width": rng.randf_range(2.8, 4.2), "angle": rng.randf_range(-PI, PI), "kind": rng.randi_range(0, 2)})
	field.forest_cache[band] = result
	# Streaming should not retain every visited forest's placement arrays.
	if field.forest_cache.size() > 16:
		field.forest_cache.erase(field.forest_cache.keys()[0])

static func landmark_slit(field: WorldField, point: Vector3) -> bool:
	for site in field.sites_near_z(point.z):
		if not site.has("route"): continue
		var p: Vector3 = site.road.affine_inverse() * point
		var u: float = p.x * float(site.side)
		if u > 38 and u < 350 and absf(p.z) < 5.0: return true
	return false

static func build(chunk: ChunkGenerator, gradual: bool) -> void:
	if chunk.field.profile.generation_version >= 14:
		await _build_v14(chunk, gradual)
		return
	await TreeFall.prepare(chunk)
	# Warm both seam halos in slices before the synchronous nav source parse.
	for band in [chunk.band, chunk.band - 1, chunk.band + 1]:
		await prepare(chunk, band, gradual)
	var tree_poses: Array = [[], [], [], [], [], []]
	var variants := chunk.field.rng_for(chunk.band, "forest_art_variants")
	var shrubs: Array = [[], [], []]
	var body := ForestTrunks.new()
	body.name = "ForestTrunks"
	# Assemble off-tree so each added trunk does not rebuild a live compound body.
	var trunk_shape := BoxShape3D.new()
	trunk_shape.size = Vector3(0.7, 1, 0.7)
	var planned := trees(chunk.field, chunk.band)
	for i in range(planned.size()):
		var tree: Dictionary = planned[i]
		var basis := Basis(Vector3.UP, tree.angle)
		var kind := variants.randi_range(0, 3) if variants.randf() > 0.16 else variants.randi_range(4, 5)
		# Consume appearance RNG even for tombstones, preserving all later trees.
		if chunk.field.destroyed_trees.has(TreeImpact.forest_id(chunk.band, i)): continue
		tree_poses[kind].append(Transform3D(basis.scaled(Vector3(tree.width, tree.height, tree.width)), tree.point))
		var shape := CollisionShape3D.new()
		# Shared geometry; box height is represented by its transform.
		shape.shape = trunk_shape
		shape.position = tree.point + Vector3.UP * tree.height * 0.5
		shape.scale.y = tree.height
		shape.set_meta("tree_id", TreeImpact.forest_id(chunk.band, i))
		shape.set_meta("tree_point", tree.point)
		body.add_child(shape)
		chunk.decoration_positions.append(tree.point)
	if gradual: await chunk._pause()
	# Dense waist/head-high undergrowth; no physical snagging on leaves.
	var rng := chunk.field.rng_for(chunk.band, "undergrowth")
	for i in range(4700):
		if gradual and i % 100 == 0: await chunk._pause()
		var x := rng.randf_range(-440, 440)
		var z := -chunk.band * 150.0 - rng.randf_range(1, 149)
		var sample := chunk.field.surface(x, z)
		if sample.reserved or sample.road.distance < sample.road.width * 0.5 + 4.5: continue
		if chunk.field.landforms != null and not chunk.field.landforms.vegetation(sample, x, z): continue
		var point := Vector3(x, sample.height, z)
		if landmark_slit(chunk.field, point): continue
		var height := rng.randf_range(1.5, 3.0)
		var radius := rng.randf_range(1.0, 2.0)
		shrubs[i % 3].append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(radius, height, radius)), point))
	for kind in range(6):
		body.visuals.merge(batch(chunk, "ForestTree%d" % kind, ForestMeshes.tree(kind), tree_poses[kind]))
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	for kind in range(3):
		batch(chunk, "ForestBrush%d" % kind, ForestMeshes.shrub(kind), shrubs[kind])
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	# Contacts may begin immediately when inserted, so every visual mapping must
	# already exist, including while this chunk is being built over many frames.
	chunk.add_child(body)
	print("FOREST band=%d trees=%d shrubs=%d" % [chunk.band, planned.size(), shrubs[0].size() + shrubs[1].size() + shrubs[2].size()])

static func _prepare_v14(chunk: ChunkGenerator, band: int, gradual: bool) -> void:
	var field := chunk.field
	var result: Array[Dictionary] = []
	var rng := field.rng_for(band, "flora_v14_trees")
	for row in range(19):
		for column in range(112):
			# Query the same float32 coordinates ultimately stored by Node3D.
			var horizontal := Vector2(-444.0 + column * 8.0 + rng.randf_range(-3.4, 3.4), -band * 150.0 - (row + 0.5) * 150.0 / 19.0 + rng.randf_range(-2.5, 2.5))
			var x := horizontal.x
			var z := horizontal.y
			var weights := field.landforms.flora_weights(x, z)
			if rng.randf() > weights.x * field.profile.decoration_density: continue
			var sample := field.surface(x, z)
			if sample.reserved or sample.road.distance < sample.road.width * 0.5 + 7.5 or is_finite(float(sample.water_height)): continue
			var normal := field.normal_at(x, z)
			if normal.y < cos(deg_to_rad(40.0)): continue
			var point := Vector3(x, sample.height, z)
			if landmark_slit(field, point): continue
			var mesh_kind := field.landforms.tree_choice(x, z, rng.randf())
			var appearance: Vector3 = sample.appearance
			var ridge := lerpf(1.0 if int(appearance.x) == 3 else 0.0, 1.0 if int(appearance.y) == 3 else 0.0, appearance.z)
			result.append({"point": point, "normal": normal, "height": rng.randf_range(lerpf(11.0, 7.5, ridge), lerpf(19.0, 13.0, ridge)), "width": rng.randf_range(2.8, 4.2), "angle": rng.randf_range(-PI, PI), "kind": mesh_kind % 3, "mesh_kind": mesh_kind})
			if gradual and chunk.slice_exhausted(): await chunk._pause()
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	field.forest_cache[band] = result
	if field.forest_cache.size() > 16: field.forest_cache.erase(field.forest_cache.keys()[0])

static func _build_v14(chunk: ChunkGenerator, gradual: bool) -> void:
	await TreeFall.prepare(chunk)
	for band in [chunk.band, chunk.band - 1, chunk.band + 1]: await prepare(chunk, band, gradual)
	var tree_poses: Array = [[], [], [], [], [], [], [], []]
	var shrubs: Array = [[], [], [], []]
	var body := ForestTrunks.new()
	body.name = "ForestTrunks"
	var trunk_shape := BoxShape3D.new()
	trunk_shape.size = Vector3(0.7, 1, 0.7)
	var planned := trees(chunk.field, chunk.band)
	for i in range(planned.size()):
		var tree: Dictionary = planned[i]
		if chunk.field.destroyed_trees.has(TreeImpact.forest_id(chunk.band, i)): continue
		var kind: int = tree.mesh_kind
		tree_poses[kind].append(Transform3D(Basis(Vector3.UP, tree.angle).scaled(Vector3(tree.width, tree.height, tree.width)), tree.point))
		var shape := CollisionShape3D.new()
		shape.shape = trunk_shape
		shape.position = tree.point + Vector3.UP * tree.height * 0.5
		shape.scale.y = tree.height
		shape.set_meta("tree_id", TreeImpact.forest_id(chunk.band, i))
		shape.set_meta("tree_point", tree.point)
		body.add_child(shape)
		chunk.decoration_positions.append(tree.point)
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	var rng := chunk.field.rng_for(chunk.band, "flora_v14_ground")
	for i in range(2400):
		if gradual and i % 64 == 0 and chunk.slice_exhausted(): await chunk._pause()
		var horizontal := Vector2(rng.randf_range(-440, 440), -chunk.band * 150.0 - rng.randf_range(1, 149))
		var x := horizontal.x
		var z := horizontal.y
		var weights := chunk.field.landforms.flora_weights(x, z)
		if rng.randf() > weights.y * chunk.field.profile.decoration_density: continue
		var sample := chunk.field.surface(x, z)
		if sample.reserved or sample.road.distance < sample.road.width * 0.5 + 4.5 or is_finite(float(sample.water_height)): continue
		var normal := chunk.field.normal_at(x, z)
		if normal.y < 0.70: continue
		var point := Vector3(x, sample.height, z)
		if landmark_slit(chunk.field, point): continue
		var appearance: Vector3 = sample.appearance
		var biome := int(appearance.y) if rng.randf() < appearance.z else int(appearance.x)
		var kind := 0
		if biome == 2 or float(sample.river_bank) > 0.45: kind = 1
		elif biome in [1, 3, 4]: kind = 2
		elif biome == 5: kind = 3
		var radius := rng.randf_range(0.7, 1.5)
		shrubs[kind].append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * radius), point))
	for kind in range(8):
		body.visuals.merge(batch(chunk, "ForestTree%d" % kind, ForestMeshes.tree(kind), tree_poses[kind]))
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	for kind in range(4):
		batch(chunk, "ForestBrush%d" % kind, FloraMeshes.ground(kind), shrubs[kind])
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	chunk.add_child(body)
	print("FOREST v14 band=%d trees=%d ground=%d" % [chunk.band, planned.size(), shrubs[0].size() + shrubs[1].size() + shrubs[2].size() + shrubs[3].size()])

static func batch(parent: Node3D, title: String, mesh: Mesh, poses: Array) -> Dictionary:
	var instances := {}
	if poses.is_empty(): return instances
	# Cull local cells rather than rendering the entire 900 m band at once.
	var cells: Dictionary = {}
	for pose: Transform3D in poses:
		var cell := Vector2i(floori(pose.origin.x / 48.0), floori(pose.origin.z / 48.0))
		if not cells.has(cell): cells[cell] = []
		cells[cell].append(pose)
	for cell: Vector2i in cells:
		var origin := Vector3(cell.x * 48.0 + 24, 0, cell.y * 48.0 + 24)
		instances.merge(_cell(parent, title, mesh, cells[cell], origin, cell))
	return instances

static func _cell(parent: Node3D, title: String, mesh: Mesh, poses: Array, origin: Vector3, cell: Vector2i) -> Dictionary:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = poses.size()
	for i in range(poses.size()):
		var pose: Transform3D = poses[i]
		pose.origin -= origin
		multi.set_instance_transform(i, pose)
	var node := MultiMeshInstance3D.new()
	node.name = "%s_%d_%d" % [title, cell.x, cell.y]
	node.position = origin
	node.set_meta("forest_kind", title.right(1).to_int())
	node.multimesh = multi
	if title.begins_with("ForestBrush"):
		# Trunks, canopy and terrain provide the large shadows; small undergrowth
		# still receives them without resubmitting every twig to the shadow pass.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Hysteresis suppresses toggling; disappearance is hidden by distant fog.
	node.visibility_range_end = 160 if title.begins_with("ForestBrush") else 340
	node.visibility_range_end_margin = 16
	parent.add_child(node)
	var instances := {}
	for i in range(poses.size()):
		var pose: Transform3D = poses[i]
		pose.origin -= origin
		instances[poses[i].origin] = {"node": node, "index": i, "pose": pose}
	return instances

extends RefCounted
class_name ForestScenery
## Deterministic forest cells shared by rendering, collision and seam navigation.

static func trees(field: WorldField, band: int) -> Array[Dictionary]:
	return field.forest_cache.get(band, [] as Array[Dictionary])

static func prepare(chunk: ChunkGenerator, band: int, gradual: bool) -> void:
	var field := chunk.field
	if field.forest_cache.has(band): return
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
			var point := Vector3(x, sample.height, z)
			if landmark_slit(field, point): continue
			result.append({"point": point, "height": rng.randf_range(12.0, 21.0), "width": rng.randf_range(2.8, 4.2), "angle": rng.randf_range(-PI, PI), "kind": rng.randi_range(0, 2)})
	field.forest_cache[band] = result
	# Streaming should not retain every visited forest's placement arrays.
	if field.forest_cache.size() > 16:
		field.forest_cache.erase(field.forest_cache.keys()[0])

static func landmark_slit(field: WorldField, point: Vector3) -> bool:
	var nearest := maxi(0, roundi(-point.z / field.profile.stop_spacing))
	for index in range(maxi(0, nearest - 1), nearest + 2):
		var site := field.stop(index)
		if not site.has("route"): continue
		var p: Vector3 = site.road.affine_inverse() * point
		var u: float = p.x * float(site.side)
		if u > 38 and u < 350 and absf(p.z) < 5.0: return true
	return false

static func build(chunk: ChunkGenerator, gradual: bool) -> void:
	# Warm both seam halos in slices before the synchronous nav source parse.
	for band in [chunk.band, chunk.band - 1, chunk.band + 1]:
		await prepare(chunk, band, gradual)
	var tree_poses: Array = [[], [], [], [], [], []]
	var variants := chunk.field.rng_for(chunk.band, "forest_art_variants")
	var shrubs: Array = [[], [], []]
	var body := StaticBody3D.new()
	body.name = "ForestTrunks"
	# Assemble off-tree so each added trunk does not rebuild a live compound body.
	var trunk_shape := BoxShape3D.new()
	trunk_shape.size = Vector3(0.7, 1, 0.7)
	var planned := trees(chunk.field, chunk.band)
	for i in range(planned.size()):
		var tree: Dictionary = planned[i]
		var basis := Basis(Vector3.UP, tree.angle)
		var kind := variants.randi_range(0, 3) if variants.randf() > 0.16 else variants.randi_range(4, 5)
		tree_poses[kind].append(Transform3D(basis.scaled(Vector3(tree.width, tree.height, tree.width)), tree.point))
		var shape := CollisionShape3D.new()
		# Shared geometry; box height is represented by its transform.
		shape.shape = trunk_shape
		shape.position = tree.point + Vector3.UP * tree.height * 0.5
		shape.scale.y = tree.height
		body.add_child(shape)
		chunk.decoration_positions.append(tree.point)
	chunk.add_child(body)
	if gradual: await chunk._pause()
	# Dense waist/head-high undergrowth; no physical snagging on leaves.
	var rng := chunk.field.rng_for(chunk.band, "undergrowth")
	for i in range(4700):
		if gradual and i % 100 == 0: await chunk._pause()
		var x := rng.randf_range(-440, 440)
		var z := -chunk.band * 150.0 - rng.randf_range(1, 149)
		var sample := chunk.field.surface(x, z)
		if sample.reserved or sample.road.distance < sample.road.width * 0.5 + 4.5: continue
		var point := Vector3(x, sample.height, z)
		if landmark_slit(chunk.field, point): continue
		var height := rng.randf_range(1.5, 3.0)
		var radius := rng.randf_range(1.0, 2.0)
		shrubs[i % 3].append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(radius, height, radius)), point))
	for kind in range(6):
		batch(chunk, "ForestTree%d" % kind, ForestMeshes.tree(kind), tree_poses[kind])
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	for kind in range(3):
		batch(chunk, "ForestBrush%d" % kind, ForestMeshes.shrub(kind), shrubs[kind])
		if gradual and chunk.slice_exhausted(): await chunk._pause()
	print("FOREST band=%d trees=%d shrubs=%d" % [chunk.band, planned.size(), shrubs[0].size() + shrubs[1].size() + shrubs[2].size()])

static func batch(parent: Node3D, title: String, mesh: Mesh, poses: Array) -> void:
	if poses.is_empty(): return
	# Cull local cells rather than rendering the entire 900 m band at once.
	var cells: Dictionary = {}
	for pose: Transform3D in poses:
		var cell := Vector2i(floori(pose.origin.x / 48.0), floori(pose.origin.z / 48.0))
		if not cells.has(cell): cells[cell] = []
		cells[cell].append(pose)
	for cell: Vector2i in cells:
		var origin := Vector3(cell.x * 48.0 + 24, 0, cell.y * 48.0 + 24)
		_cell(parent, title, mesh, cells[cell], origin, cell)

static func _cell(parent: Node3D, title: String, mesh: Mesh, poses: Array, origin: Vector3, cell: Vector2i) -> void:
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

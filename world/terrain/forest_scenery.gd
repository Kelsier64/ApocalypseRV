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
	var trunks: Array[Transform3D] = []
	var crowns: Array = [[], [], []]
	var shrubs: Array = [[], [], []]
	var body := StaticBody3D.new()
	body.name = "ForestTrunks"
	chunk.add_child(body)
	var trunk_shape := BoxShape3D.new()
	trunk_shape.size = Vector3(0.7, 1, 0.7)
	var planned := trees(chunk.field, chunk.band)
	for i in range(planned.size()):
		if gradual and i % 60 == 0: await chunk._pause()
		var tree: Dictionary = planned[i]
		var basis := Basis(Vector3.UP, tree.angle)
		trunks.append(Transform3D(basis.scaled(Vector3(0.58, tree.height, 0.58)), tree.point + Vector3.UP * tree.height * 0.5))
		var shape := CollisionShape3D.new()
		# Shared geometry; box height is represented by its transform.
		shape.shape = trunk_shape
		shape.position = tree.point + Vector3.UP * tree.height * 0.5
		shape.scale.y = tree.height
		body.add_child(shape)
		for layer in range(3):
			var radius: float = tree.width * (1.0 - layer * 0.22)
			var height: float = tree.height * 0.49
			var center: Vector3 = tree.point + Vector3.UP * (2.0 + height * 0.5 + layer * tree.height * 0.19)
			crowns[tree.kind].append(Transform3D(basis.rotated(Vector3.UP, layer * 0.6).scaled(Vector3(radius, height, radius)), center))
		chunk.decoration_positions.append(tree.point)
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
		shrubs[i % 3].append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(radius, height, radius)), point + Vector3.UP * height * 0.45))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28
	trunk.bottom_radius = 0.5
	trunk.height = 1
	trunk.radial_segments = 6
	trunk.material = RoadsideKit.material(Color("373b32"))
	batch(chunk, "ForestBark", trunk, trunks)
	for kind in range(3):
		var cone := CylinderMesh.new()
		cone.top_radius = 0
		cone.bottom_radius = 1
		cone.height = 1
		cone.radial_segments = 7
		cone.material = RoadsideKit.material([Color("29392e"), Color("354237"), Color("3e4534")][kind])
		batch(chunk, "ForestCanopy%d" % kind, cone, crowns[kind])
		var bush := SphereMesh.new()
		bush.radius = 1
		bush.height = 1
		bush.radial_segments = 5
		bush.rings = 2
		bush.material = RoadsideKit.material([Color("414937"), Color("4a4b38"), Color("343f30")][kind])
		batch(chunk, "ForestBrush%d" % kind, bush, shrubs[kind])
	print("FOREST band=%d trees=%d shrubs=%d" % [chunk.band, planned.size(), shrubs[0].size() + shrubs[1].size() + shrubs[2].size()])

static func batch(parent: Node3D, title: String, mesh: Mesh, poses: Array) -> void:
	if poses.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = poses.size()
	for i in range(poses.size()): multi.set_instance_transform(i, poses[i])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = multi
	# MultiMesh culls as a whole band; its centre can be far from a player
	# standing at the edge of the 900 m strip even with trees beside them.
	node.visibility_range_end = 650
	parent.add_child(node)

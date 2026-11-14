extends RefCounted
class_name ScatterScenery
## Turns ScatterCatalog layers into deterministic placements for one band, then
## into batched visuals and one compound collider. Every layer owns an RNG stream,
## so adding, removing or retuning a layer never moves another layer's props.
const MASK_CELL := 8.0
const HALF_WIDTH := 440.0
const SEAM := 4.0

## Pure plan: layer id -> Array of {"pose": Transform3D, "variant": int}.
## Solid placements stay SEAM metres inside the band, so neighbours never need them.
static func plan(chunk: ChunkGenerator, gradual: bool) -> Dictionary:
	var field := chunk.field
	var band := chunk.band
	var mask := {}
	var grid := chunk.grid
	if grid == null: grid = await TerrainGrid.for_band(chunk, gradual)
	# The forest owns its ground first; solid props fit between the trunks.
	for tree: Dictionary in ForestScenery.trees(field, band): _claim(mask, tree.point.x, tree.point.z, 0.8)
	var result := {}
	for layer in ScatterCatalog.layers():
		var placements: Array[Dictionary] = []
		var rng := field.rng_for(band, "scatter_" + String(layer.id))
		if layer.pattern == ScatterLayer.Pattern.GRID:
			var columns := ceili(HALF_WIDTH * 2.0 / layer.spacing)
			var rows := ceili(field.profile.chunk_length / layer.spacing)
			for row in range(rows):
				for column in range(columns):
					var x := -HALF_WIDTH + (column + 0.5 + rng.randf_range(-0.42, 0.42)) * layer.spacing
					var z := -band * field.profile.chunk_length - (row + 0.5 + rng.randf_range(-0.42, 0.42)) * layer.spacing
					_consider(field, layer, rng, mask, grid, x, z, placements)
				if gradual and chunk.slice_exhausted(): await chunk._pause()
		else:
			var rows := floori(field.profile.chunk_length / layer.spacing)
			for row in range(rows):
				var s := band * field.profile.chunk_length + (row + 0.5) * layer.spacing
				var frame := field.road_frame(s)
				var half := field.road_width(s) * 0.5
				var bridged := field.landforms.bridge_at(s)
				for side: float in [-1.0, 1.0]:
					for slot in range(layer.per_row):
						var along := rng.randf_range(-0.5, 0.5) * layer.spacing
						if layer.pattern == ScatterLayer.Pattern.CARRIAGEWAY:
							var lateral := rng.randf_range(0.0, half - 0.5) * side
							_litter(field, layer, rng, s + along, lateral, placements)
						else:
							var point := frame * Vector3(side * (half + rng.randf_range(layer.road_min, minf(layer.road_max, 400.0))), 0, along)
							# Bridge verges hang over the valley; nothing grows on the deck.
							if not bridged: _consider(field, layer, rng, mask, grid, point.x, point.z, placements)
				if gradual and chunk.slice_exhausted(): await chunk._pause()
		result[layer.id] = placements
	return result

static func build(chunk: ChunkGenerator, gradual: bool) -> void:
	var planned: Dictionary = await plan(chunk, gradual)
	var body := StaticBody3D.new()
	body.name = "ScatterSolids"
	var shapes := {}
	var total := 0
	for layer in ScatterCatalog.layers():
		var placements: Array = planned[layer.id]
		total += placements.size()
		for variant in range(layer.variants.size()):
			var id := layer.variants[variant]
			var poses: Array = []
			for placement: Dictionary in placements:
				if int(placement.variant) != variant: continue
				poses.append(placement.pose)
				if not layer.solid: continue
				if not shapes.has(id):
					var box := BoxShape3D.new()
					box.size = ScatterMeshes.solid(id).size
					shapes[id] = box
				var shape := CollisionShape3D.new()
				shape.shape = shapes[id]
				var pose: Transform3D = placement.pose
				shape.transform = pose.translated_local(ScatterMeshes.solid(id).get_center())
				body.add_child(shape)
			var instances := ForestScenery.batch(chunk, "Scatter_%s_%d" % [layer.id, variant], ScatterMeshes.mesh(id), poses)
			if not layer.shadows:
				var seen := {}
				for entry: Dictionary in instances.values():
					if seen.has(entry.node): continue
					seen[entry.node] = true
					entry.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if gradual and chunk.slice_exhausted(): await chunk._pause()
	chunk.add_child(body)
	print("SCATTER band=%d placements=%d solids=%d" % [chunk.band, total, body.get_child_count()])

static func _consider(field: WorldField, layer: ScatterLayer, rng: RandomNumberGenerator, mask: Dictionary, grid: TerrainGrid, x: float, z: float, placements: Array[Dictionary]) -> void:
	var roll := rng.randf()
	if -z < layer.start: return
	var chance := layer.density * field.profile.decoration_density
	var appearance := field.landforms.appearance_at(-z)
	if layer.bank_min <= 0.0:
		chance *= lerpf(layer.landforms[int(appearance.x)], layer.landforms[int(appearance.y)], appearance.z)
	if layer.cluster > 0.0:
		var noise := field.clusters.get_noise_2d(x + layer.cluster_offset.x, z + layer.cluster_offset.y)
		chance *= lerpf(1.0, clampf((noise + 0.30) * 1.8, 0.0, 1.0), layer.cluster)
	if roll >= chance * (1.0 + layer.steep_bonus): return
	if not grid.probe(x, z) or grid.wet: return
	# Verge layers grow right up to the asphalt, inside the carriageway margin
	# that every other layer treats as reserved.
	if grid.occupied if layer.road_min < 4.0 else grid.reserved: return
	var size := rng.randf_range(layer.scale_min, layer.scale_max)
	var footprint := layer.radius * size
	if grid.edge < layer.road_min + footprint or grid.edge > layer.road_max + 1.0: return
	if grid.bank < layer.bank_min or grid.normal.y < layer.normal_min: return
	if layer.moisture_min > 0.0 and lerpf(TerrainLandforms.MOISTURE[int(appearance.x)], TerrainLandforms.MOISTURE[int(appearance.y)], appearance.z) < layer.moisture_min: return
	if layer.steep_bonus > 0.0 and rng.randf() * (1.0 + layer.steep_bonus) > 1.0 + layer.steep_bonus * smoothstep(0.03, 0.22, 1.0 - grid.normal.y): return
	if layer.solid:
		# Solid props stay inside their own band and outside every POI court.
		var offset := fposmod(-z, field.profile.chunk_length)
		if offset < footprint + SEAM or offset > field.profile.chunk_length - footprint - SEAM or absf(x) > HALF_WIDTH - footprint: return
		for site: Dictionary in field.sites_near_z(z):
			if field.court_distance(x, z, site) < footprint + 8.0: return
	if footprint > 0.0:
		if _blocked(mask, x, z, footprint): return
		_claim(mask, x, z, footprint)
	placements.append({"pose": _pose(layer, rng, Vector3(x, grid.height, z), grid.normal, size), "variant": rng.randi_range(0, layer.variants.size() - 1)})

static func _litter(field: WorldField, layer: ScatterLayer, rng: RandomNumberGenerator, s: float, lateral: float, placements: Array[Dictionary]) -> void:
	var roll := rng.randf()
	if s < layer.start or roll >= layer.density * field.profile.decoration_density: return
	var frame := field.road_frame(s)
	var forward := (field.road_frame(s + 1.0).origin - field.road_frame(s - 1.0).origin).normalized()
	var up := frame.basis.x.cross(forward).normalized()
	# Sits on the asphalt top (road mesh is 7 cm above the graded ground).
	var point := frame * Vector3(lateral, 0.075, 0)
	placements.append({"pose": _pose(layer, rng, point, up, rng.randf_range(layer.scale_min, layer.scale_max)), "variant": rng.randi_range(0, layer.variants.size() - 1)})

static func _pose(layer: ScatterLayer, rng: RandomNumberGenerator, point: Vector3, normal: Vector3, size: float) -> Transform3D:
	var up := Vector3.UP.lerp(normal, layer.align).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	var basis := Basis(right, up, right.cross(up)).rotated(up, rng.randf_range(-PI, PI))
	if layer.tilt > 0.0:
		var axis := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		if axis.length() > 0.01: basis = basis.rotated(axis.normalized(), rng.randf_range(0.0, layer.tilt))
	var stretch := Vector3(size, size * rng.randf_range(layer.height_scale.x, layer.height_scale.y), size)
	return Transform3D(basis.scaled_local(stretch), point - up * layer.sink * size)

static func _claim(mask: Dictionary, x: float, z: float, radius: float) -> void:
	for cx in range(floori((x - radius) / MASK_CELL), floori((x + radius) / MASK_CELL) + 1):
		for cz in range(floori((z - radius) / MASK_CELL), floori((z + radius) / MASK_CELL) + 1):
			var key := Vector2i(cx, cz)
			if not mask.has(key): mask[key] = []
			mask[key].append(Vector3(x, z, radius))

static func _blocked(mask: Dictionary, x: float, z: float, radius: float) -> bool:
	for cx in range(floori((x - radius) / MASK_CELL), floori((x + radius) / MASK_CELL) + 1):
		for cz in range(floori((z - radius) / MASK_CELL), floori((z + radius) / MASK_CELL) + 1):
			for other: Vector3 in mask.get(Vector2i(cx, cz), []):
				if Vector2(x - other.x, z - other.y).length() < radius + other.z: return true
	return false

extends RefCounted
class_name TerrainCrossings
## Water and bridges consume exactly the same plans as terrain and POI clearance.
const WATER = preload("res://world/terrain/river_water.gdshader")
const WATER_STEP := 6.0
const WATER_EXTENT := 1310.0
const SHORE_OVERLAP := 1.5

static func water_polygon(landforms: TerrainLandforms, river: Dictionary, x0: float, x1: float) -> PackedVector3Array:
	var a := landforms.river_z(river, x0)
	var b := landforms.river_z(river, x1)
	# Bury the last 1.5m under the dry bank. This covers the small difference
	# between curved analytical shores and triangulated ground without a gap.
	var half0 := landforms.river_half_width(river, x0) + SHORE_OVERLAP
	var half1 := landforms.river_half_width(river, x1) + SHORE_OVERLAP
	var y: float = river.water_height
	return PackedVector3Array([Vector3(x0, y, a - half0), Vector3(x1, y, b - half1), Vector3(x1, y, b + half1), Vector3(x0, y, a + half0)])

static func _clip(points: PackedVector3Array, z: float, keep_below: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	if points.is_empty(): return result
	var previous := points[-1]
	var previous_in := previous.z <= z if keep_below else previous.z >= z
	for point in points:
		var inside := point.z <= z if keep_below else point.z >= z
		if inside != previous_in:
			result.append(previous.lerp(point, (z - previous.z) / (point.z - previous.z)))
		if inside: result.append(point)
		previous = point
		previous_in = inside
	return result

static func build(chunk: ChunkGenerator, gradual: bool) -> void:
	var field := chunk.field
	if field.landforms == null: return
	var north := -chunk.band * 150.0
	var south := north - 150.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for river in field.landforms.rivers_near((north + south) * 0.5, 75.0):
		for i in range(ceili(WATER_EXTENT * 2.0 / WATER_STEP)):
			var x := -WATER_EXTENT + i * WATER_STEP
			var polygon := _clip(_clip(water_polygon(field.landforms, river, x, minf(x + WATER_STEP, WATER_EXTENT)), north, true), south, false)
			for j in range(1, polygon.size() - 1):
				for vertex in [polygon[0], polygon[j + 1], polygon[j]]:
					st.set_normal(Vector3.UP)
					var half := field.landforms.river_half_width(river, vertex.x)
					st.set_uv(Vector2(vertex.x * 0.04, 0.5 + (vertex.z - field.landforms.river_z(river, vertex.x)) / (half * 2.0)))
					st.add_vertex(vertex)
					count += 1
			if gradual and chunk.slice_exhausted(): await chunk._pause()
	if count > 0:
		var water := chunk._mesh(st.commit(), "RiverWater", false)
		var material := ShaderMaterial.new()
		material.shader = WATER
		water.material_override = material
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await BridgeBuilder.build(chunk, gradual)
	_build_road_edges(chunk)

static func bridge_faces(field: WorldField, band: int, halo: float = 0.0) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in range(-ceili(halo / 2.5), 60 + ceili(halo / 2.5)):
		var s := band * 150.0 + i * 2.5
		if not field.landforms.bridge_at(s + 1.25): continue
		var corners := PackedVector3Array()
		for t in [s, s + 2.5]:
			var frame := field.road_frame(t)
			for side in [-1.0, 1.0]:
				corners.append(frame * Vector3(side * field.road_width(t) * 0.5, 0.07, 0))
		for index in [0, 2, 1, 1, 2, 3]: faces.append(corners[index])
	return faces

static func _build_road_edges(chunk: ChunkGenerator) -> void:
	var root := Node3D.new()
	root.name = "RoadSafety"
	chunk.add_child(root)
	for part in rail_plan(chunk.field, chunk.band):
		if part.get("bridge", false): continue # Modeled Jersey profiles own these colliders.
		RoadsideKit.part(root, part.size, part.pose.origin, part.color, part.solid).basis = part.pose.basis

static func rail_plan(field: WorldField, band: int) -> Array[Dictionary]:
	if field.landforms.rail_cache.has(band): return field.landforms.rail_cache[band]
	var result: Array[Dictionary] = []
	for i in range(30):
		var s := band * 150.0 + i * 5.0 + 2.5
		if s < 400: continue
		var frame := field.road_frame(s)
		var half := field.road_width(s) * 0.5
		var bridge := field.landforms.bridge_at(s)
		for side: float in [-1.0, 1.0]:
			var point := frame * Vector3(side * (half + 0.55), 0, 0)
			if bridge:
				var next := field.road_frame(s + 2.5) * Vector3(side * (field.road_width(s + 2.5) * 0.5 + 0.56), 0.54, 0)
				var previous := field.road_frame(s - 2.5) * Vector3(side * (field.road_width(s - 2.5) * 0.5 + 0.56), 0.54, 0)
				result.append({"size": Vector3(0.80, 1.16, next.distance_to(previous) + 0.12), "pose": Transform3D(Basis.looking_at(next - previous), (next + previous) * 0.5), "color": Color("85877b"), "solid": true, "bridge": true})
				continue
			var near_site := false
			for site in field.sites_near_z(point.z):
				if field.court_distance(point.x, point.z, site) < 20.0:
					near_site = true
					break
			if near_site: continue
			var drop := frame.origin.y - field.height_at(point.x, point.z)
			var far := frame * Vector3(side * (half + 15.0), 0, 0)
			drop = maxf(drop, frame.origin.y - field.height_at(far.x, far.z))
			if bridge or drop > 5.0:
				var next := field.road_frame(s + 2.5) * Vector3(side * (field.road_width(s + 2.5) * 0.5 + 0.55), 1.0, 0)
				var previous := field.road_frame(s - 2.5) * Vector3(side * (field.road_width(s - 2.5) * 0.5 + 0.55), 1.0, 0)
				var center := (next + previous) * 0.5
				result.append({"size": Vector3(0.25, 0.48, next.distance_to(previous) + 0.12), "pose": Transform3D(Basis.looking_at(next - previous), center), "color": Color("747e78"), "solid": true})
				result.append({"size": Vector3(0.20, 1.1, 0.20), "pose": Transform3D(frame.basis, point + Vector3.UP * 0.55), "color": Color("505952"), "solid": true})
				if i % 3 == 0:
					result.append({"size": Vector3(0.12, 0.12, 0.24), "pose": Transform3D(frame.basis, point + Vector3.UP * 1.18), "color": Color("cfb66e"), "solid": false})
	if field.landforms.rail_cache.size() >= 16: field.landforms.rail_cache.clear()
	field.landforms.rail_cache[band] = result
	return result

static func navigation_obstacles(field: WorldField, band: int, source: NavigationMeshSourceGeometryData3D) -> void:
	var north := -band * 150.0
	for river in field.landforms.rivers_near(north - 75.0, 90.0):
		for i in range(168):
			var x := -504.0 + i * WATER_STEP
			var polygon := water_polygon(field.landforms, river, x, x + WATER_STEP)
			if polygon[0].z > north + 15.0 and polygon[1].z > north + 15.0: continue
			if polygon[2].z < north - 165.0 and polygon[3].z < north - 165.0: continue
			# Remove the submerged bed, leaving the bridge overhead navigable.
			source.add_projected_obstruction(polygon, -1000.0, float(river.water_height) + 1002.0, false)
	var deck := bridge_faces(field, band, 5.0)
	if not deck.is_empty(): source.add_faces(deck, Transform3D.IDENTITY)
	# Neighbour rails overlap the seam halo. Include their shared plan even
	# when that neighbour has not been loaded yet.
	for neighbour in [band - 1, band + 1]:
		for part in rail_plan(field, neighbour):
			if not part.solid: continue
			var box: AABB = part.pose * AABB(-part.size * 0.5, part.size)
			if box.position.z > north + 5.0 or box.end.z < north - 155.0: continue
			var outline := PackedVector3Array()
			for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
				outline.append(part.pose * (corner * part.size * 0.5))
			source.add_projected_obstruction(outline, box.position.y, box.size.y, false)

extends RefCounted
class_name TerrainCrossings
## Water and bridges consume exactly the same plans as terrain and POI clearance.
const WATER = preload("res://world/terrain/river_water.gdshader")

static func water_polygon(landforms: TerrainLandforms, river: Dictionary, x0: float, x1: float) -> PackedVector3Array:
	var a := landforms.river_z(river, x0)
	var b := landforms.river_z(river, x1)
	var half: float = river.half_width
	var y: float = river.water_height
	return PackedVector3Array([Vector3(x0, y, a - half), Vector3(x1, y, b - half), Vector3(x1, y, b + half), Vector3(x0, y, a + half)])

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
		for i in range(218):
			var x := -1308.0 + i * 12.0
			var polygon := _clip(_clip(water_polygon(field.landforms, river, x, x + 12.0), north, true), south, false)
			for j in range(1, polygon.size() - 1):
				for vertex in [polygon[0], polygon[j + 1], polygon[j]]:
					st.set_normal(Vector3.UP)
					st.add_vertex(vertex)
					count += 1
			if gradual and chunk.slice_exhausted(): await chunk._pause()
	if count > 0:
		var water := chunk._mesh(st.commit(), "RiverWater", false)
		var material := ShaderMaterial.new()
		material.shader = WATER
		water.material_override = material
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_bridges(chunk)
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

static func _build_bridges(chunk: ChunkGenerator) -> void:
	var field := chunk.field
	var faces := bridge_faces(field, chunk.band)
	if faces.is_empty(): return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in faces:
		st.set_color(Color("64685e"))
		st.add_vertex(point - Vector3.UP * 0.18)
	st.generate_normals()
	chunk._mesh(st.commit(), "BridgeDeck", false)
	var structure := Node3D.new()
	structure.name = "BridgeStructure"
	chunk.add_child(structure)
	# Segment centres use the world lattice, so each pier/beam has one owner.
	for i in range(30):
		var s := chunk.band * 150.0 + i * 5.0 + 2.5
		if not field.landforms.bridge_at(s): continue
		var frame := field.road_frame(s)
		var slope := atan2(field.road_height(s + 0.5) - field.road_height(s - 0.5), 1.0)
		var basis := frame.basis * Basis(Vector3.RIGHT, slope)
		var length := Vector2(field.road_x(s + 2.5) - field.road_x(s - 2.5), 5.0).length() + 0.2
		var half := field.road_width(s) * 0.5
		var slab := RoadsideKit.part(structure, Vector3(half * 2.0, 0.65, length), frame.origin - Vector3.UP * 0.44, Color("6c7167"))
		slab.basis = basis
		for side in [-1.0, 1.0]:
			var beam := RoadsideKit.part(structure, Vector3(0.55, 1.05, length), frame * Vector3(side * (half - 0.8), -0.72, 0), Color("444d4a"))
			beam.basis = basis
		if posmod(roundi(s / 5.0), 6) != 3: continue
		for side in [-1.0, 1.0]:
			var base := frame * Vector3(side * (half - 1.2), 0, 0)
			var bottom := field.height_at(base.x, base.z)
			var height := maxf(0.8, base.y - bottom - 0.9)
			RoadsideKit.part(structure, Vector3(1.25, height, 1.8), Vector3(base.x, bottom + height * 0.5, base.z), Color("71756b"), true).basis = frame.basis
		var cap := RoadsideKit.part(structure, Vector3(field.road_width(s), 0.65, 1.6), frame.origin - Vector3.UP * 1.05, Color("62685e"))
		cap.basis = frame.basis

static func _build_road_edges(chunk: ChunkGenerator) -> void:
	var root := Node3D.new()
	root.name = "RoadSafety"
	chunk.add_child(root)
	for part in rail_plan(chunk.field, chunk.band):
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
		for i in range(84):
			var x := -504.0 + i * 12.0
			var polygon := water_polygon(field.landforms, river, x, x + 12.0)
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

extends RefCounted
## Pure, bounded terrain sampling. Geometry checks use the swept carriageway, not
## only the monotonic centre parameter, so folded or overlapping edges fail too.
const LENGTH := 12000.0
const STEP := 10.0
const SEEDS := [0, 42, 99173, -61]

static func profile(version: int = 17) -> WorldProfile:
	var settings := WorldProfile.new()
	settings.generation_version = version
	settings.max_grade = 0.12
	return settings

static func run(check: Callable, version: int = 17) -> void:
	var signatures: Array = []
	for seed_value: int in SEEDS:
		var field := WorldField.new(seed_value, profile(version))
		var reverse := WorldField.new(seed_value, profile(version))
		# Ask far-first before comparing ascending samples to catch cache/order drift.
		for index in range(24, -1, -1):
			_snapshot(reverse, index * 487.0 + 31.0)
		var signature: Array = []
		for index in range(25):
			var s := index * 487.0 + 31.0
			var sample := _snapshot(field, s)
			check.call(sample == _snapshot(reverse, s), "v%d seed %d: queries are independent of request order at %.0fm" % [version, seed_value, s])
			signature.append(sample)
		signatures.append(signature)
		_check_route(field, check)
		_check_mountain_journey(field, check)
		_check_rivers(field, check)
		_check_elevated_spans(field, reverse, check)
	for index in range(1, signatures.size()):
		check.call(signatures[index] != signatures[0], "v%d different seeds produce different routes and terrain" % version)

static func _snapshot(field: WorldField, s: float) -> Array:
	var x := field.road_x(s)
	return [field.road_frame(s), field.road_width(s), field.surface(x + 65.0, -s), field.landforms.kind_at(s), field.landforms.rivers_near(-s), field.landforms.bridge_at(s), field.landforms.bridge_gap(s)]

static func _check_elevated_spans(field: WorldField, reverse: WorldField, check: Callable) -> void:
	var label := "v%d seed %d: " % [field.profile.generation_version, field.world_seed]
	var dry_valley := false
	var supported := true
	var deterministic := true
	var seam_count := 0
	for index in range(40, int(LENGTH / 15.0)):
		var s := index * 15.0
		var frame := field.road_frame(s)
		var gap := frame.origin.y - field.height_at(frame.origin.x, frame.origin.z)
		if gap > 5.0:
			supported = supported and field.landforms.bridge_at(s)
		if not field.landforms.river_span_at(s) and field.landforms.bridge_gap(s) > 0.95 and field.landforms.natural_clearance(s) > 6.0:
			dry_valley = dry_valley or gap > 3.0
		if index % 10 != 0: continue
		# Probe both sides of streaming boundaries after the other field was
		# queried far-first. A loaded neighbour must not change span ownership.
		for delta: float in [-1.25, 0.0, 1.25]:
			var t := s + delta
			deterministic = deterministic and field.landforms.bridge_at(t) == reverse.landforms.bridge_at(t)
			deterministic = deterministic and field.landforms.bridge_gap(t) == reverse.landforms.bridge_gap(t)
		var band := floori(s / field.profile.chunk_length)
		var before := TerrainCrossings.bridge_faces(field, band - 1)
		var after := TerrainCrossings.bridge_faces(reverse, band)
		var before_edge := _seam_vertices(before, frame)
		var after_edge := _seam_vertices(after, frame)
		if not before_edge.is_empty() and not after_edge.is_empty():
			seam_count += 1
			deterministic = deterministic and before_edge == after_edge
	check.call(dry_valley, label + "dry valleys retain terrain below a planned viaduct instead of a raised earth ribbon")
	check.call(supported, label + "every sampled carriageway more than five metres above terrain has a planned structure")
	check.call(deterministic and seam_count > 0, label + "span classification and deck edges agree across chunk seams and query order")

static func _seam_vertices(faces: PackedVector3Array, frame: Transform3D) -> Dictionary:
	var result: Dictionary = {}
	for point in faces:
		if absf((point - frame.origin).dot(frame.basis.z)) < 0.001:
			result[Vector3i(roundi(point.x * 1000.0), roundi(point.y * 1000.0), roundi(point.z * 1000.0))] = true
	return result

static func _check_route(field: WorldField, check: Callable) -> void:
	var maximum_grade := 0.0
	var maximum_curvature := 0.0
	var minimum_curve := INF
	var maximum_curve := -INF
	var minimum_grade := INF
	var maximum_uphill := -INF
	var minimum_width := INF
	var maximum_width := 0.0
	var maximum_offset := 0.0
	var projection_error := 0.0
	var signed_offset_error := 0.0
	var surface_error := 0.0
	var maximum_relief := 0.0
	var kinds: Dictionary = {}
	var ribbons: Array[PackedVector2Array] = []
	var buckets: Dictionary = {}
	var ribbon_clear := true
	var previous_left := Vector2.ZERO
	var previous_right := Vector2.ZERO
	var previous_origin := Vector3.ZERO
	var forward_only := true
	for index in range(int(LENGTH / STEP) + 1):
		var s := index * STEP
		var frame := field.road_frame(s)
		var width := field.road_width(s)
		var origin := frame.origin
		var before := Vector2(field.road_x(s - 2.0), -s + 2.0)
		var center := Vector2(origin.x, origin.z)
		var after := Vector2(field.road_x(s + 2.0), -s - 2.0)
		var a := center - before
		var b := after - center
		# Circumcircle curvature is independent of the route's parameter speed.
		var curvature := 2.0 * a.cross(b) / maxf(a.length() * b.length() * (after - before).length(), 0.001)
		var grade := (field.road_height(s + 2.0) - field.road_height(s - 2.0)) / before.distance_to(after)
		maximum_grade = maxf(maximum_grade, absf(grade))
		maximum_curvature = maxf(maximum_curvature, absf(curvature))
		minimum_curve = minf(minimum_curve, curvature)
		maximum_curve = maxf(maximum_curve, curvature)
		minimum_grade = minf(minimum_grade, grade)
		maximum_uphill = maxf(maximum_uphill, grade)
		minimum_width = minf(minimum_width, width)
		maximum_width = maxf(maximum_width, width)
		maximum_offset = maxf(maximum_offset, absf(origin.x))
		kinds[field.landforms.kind_at(s)] = true
		if index > 0:
			forward_only = forward_only and origin.z < previous_origin.z
		previous_origin = origin
		var left_3d: Vector3 = origin - frame.basis.x * width * 0.5
		var right_3d: Vector3 = origin + frame.basis.x * width * 0.5
		var left := Vector2(left_3d.x, left_3d.z)
		var right := Vector2(right_3d.x, right_3d.z)
		if index > 0:
			var quad := PackedVector2Array([previous_left, left, right, previous_right])
			if ribbon_clear:
				ribbon_clear = _insert_clear_ribbon(quad, ribbons, buckets)
			ribbons.append(quad)
		previous_left = left
		previous_right = right
		if index % 12 != 0:
			continue
		for lateral: float in [-width * 0.5 - 3.0, -width * 0.4, 0.0, width * 0.4, width * 0.5 + 3.0]:
			var point: Vector3 = origin + frame.basis.x * lateral
			var query := field.road_query(point.x, point.z)
			projection_error = maxf(projection_error, absf(float(query.s) - s))
			projection_error = maxf(projection_error, absf(float(query.distance) - absf(lateral)))
			var queried_frame: Transform3D = query.frame
			signed_offset_error = maxf(signed_offset_error, absf((point - queried_frame.origin).dot(queried_frame.basis.x) - lateral))
		# A bridge is intentionally suspended above the carved river bed.
		if not field.landforms.bridge_at(s) and s > 450.0:
			for lateral: float in [-width * 0.4, 0.0, width * 0.4]:
				var point: Vector3 = origin + frame.basis.x * lateral
				surface_error = maxf(surface_error, absf(float(field.surface(point.x, point.z).height) - origin.y))
			var left_terrain := float(field.surface(origin.x - 150.0, origin.z).height)
			var right_terrain := float(field.surface(origin.x + 150.0, origin.z).height)
			maximum_relief = maxf(maximum_relief, maxf(absf(left_terrain - right_terrain), maxf(absf(left_terrain - origin.y), absf(right_terrain - origin.y))))
	var label := "v%d seed %d: " % [field.profile.generation_version, field.world_seed]
	check.call(forward_only and maximum_offset <= 220.0, label + "route progresses forward inside the terrain corridor")
	check.call(ribbon_clear, label + "finite-width road ribbon neither folds nor intersects earlier road")
	check.call(maximum_grade <= field.profile.max_grade + 0.002, label + "actual road grade respects the configured limit (%.4f)" % maximum_grade)
	check.call(maximum_curvature <= 1.0 / field.profile.min_turn_radius + 0.00015, label + "actual horizontal turning radius respects its configured minimum (curvature %.5f)" % maximum_curvature)
	check.call(minimum_curve < -0.0005 and maximum_curve > 0.0005, label + "route contains substantial bends in both directions")
	check.call(minimum_grade < -0.01 and maximum_uphill > 0.01, label + "route includes climbs and descents")
	check.call(minimum_width >= 7.0 and maximum_width <= 20.0 and maximum_width - minimum_width >= 3.0, label + "carriageway has narrow and wide drivable sections (%.2f–%.2fm)" % [minimum_width, maximum_width])
	check.call(projection_error < 0.08 and signed_offset_error < 0.08, label + "nearest-road projection preserves signed offsets through curves (error %.4f)" % maxf(projection_error, signed_offset_error))
	check.call(surface_error < 0.12, label + "dry carriageway stays level across its usable width (error %.4f)" % surface_error)
	check.call(kinds.size() >= 4, label + "journey visits at least four landform kinds")
	check.call(maximum_relief > 40.0, label + "landforms produce substantial real terrain relief beside the road")

static func _check_mountain_journey(field: WorldField, check: Callable) -> void:
	# Parameter s is forward Z progress, not distance driven: acute bends make
	# the difference large. Measure mountain grades and turn lengths in actual
	# horizontal road distance, independently of the implementation's waves.
	var distances := PackedFloat64Array([0.0])
	var headings := PackedFloat64Array()
	var previous := field.road_frame(600.0).origin
	var rise_start := previous.y
	var fall_start := previous.y
	var rise_distance := 0.0
	var fall_distance := 0.0
	var best_rise := 0.0
	var best_fall := 0.0
	var sharpest := [0.0, 0.0]
	var sharpest_s := [600.0, 600.0]
	var sharp_turn := [0.0, 0.0]
	var turn_start := 0
	var previous_turn := 0.0
	for index in range(int((LENGTH - 600.0) / 2.5) + 1):
		var s := 600.0 + index * 2.5
		var frame := field.road_frame(s)
		var origin := frame.origin
		var before := Vector2(field.road_x(s - 1.0), -s + 1.0)
		var center := Vector2(origin.x, origin.z)
		var after := Vector2(field.road_x(s + 1.0), -s - 1.0)
		var a := center - before
		var b := after - center
		var curvature := 2.0 * a.cross(b) / maxf(a.length() * b.length() * (after - before).length(), 0.001)
		var side := 0 if curvature < 0.0 else 1
		if absf(curvature) > sharpest[side]:
			sharpest[side] = absf(curvature)
			sharpest_s[side] = s
		headings.append(atan2(-frame.basis.z.x, frame.basis.z.z))
		if index == 0: continue
		var distance := Vector2(origin.x, origin.z).distance_to(Vector2(previous.x, previous.z))
		distances.append(distances[-1] + distance)
		var height_change := origin.y - previous.y
		if height_change < 0.0:
			rise_start = origin.y
			rise_distance = 0.0
		else:
			rise_distance += distance
			var rise := origin.y - rise_start
			if rise_distance >= 1000.0 and rise / rise_distance >= 0.06: best_rise = maxf(best_rise, rise)
		if height_change > 0.0:
			fall_start = origin.y
			fall_distance = 0.0
		else:
			fall_distance += distance
			var fall := fall_start - origin.y
			if fall_distance >= 1000.0 and fall / fall_distance >= 0.06: best_fall = maxf(best_fall, fall)
		var turn := headings[index] - headings[index - 1]
		if turn * previous_turn < 0.0: turn_start = index - 1
		while turn_start < index and distances[index] - distances[turn_start] > 250.0:
			turn_start += 1
		side = 0 if turn < 0.0 else 1
		sharp_turn[side] = maxf(sharp_turn[side], absf(headings[index] - headings[turn_start]))
		previous_turn = turn
		previous = origin
	var label := "v%d seed %d: " % [field.profile.generation_version, field.world_seed]
	check.call(best_rise >= 150.0 and best_fall >= 150.0, label + "sustained climbs and descents each change elevation by at least 150m over 1km or more at a mean actual-road grade of at least 6%% (%.1fm up, %.1fm down)" % [best_rise, best_fall])
	for side in range(2):
		check.call(sharp_turn[side] >= deg_to_rad(100.0) and sharpest[side] >= 1.0 / 55.0, label + "direction %d has an acute bend changing heading at least 100 degrees within 250m of actual road and reaching a radius of 55m or less (%.1f degrees, curvature %.5f)" % [side, rad_to_deg(sharp_turn[side]), sharpest[side]])
		_check_sharp_projection(field, float(sharpest_s[side]), check)

static func _check_sharp_projection(field: WorldField, s: float, check: Callable) -> void:
	var maximum_error := 0.0
	# The uniform 120m projection probes can miss the tightest part of a bend.
	# Probe the real positive/negative curvature extrema and their approaches.
	for delta: float in [-10.0, -5.0, -2.5, 0.0, 2.5, 5.0, 10.0]:
		var t := s + delta
		var frame := field.road_frame(t)
		var half := field.road_width(t) * 0.5
		for lateral: float in [-half - 3.0, -half, -half * 0.5, 0.0, half * 0.5, half, half + 3.0]:
			var point := frame * Vector3(lateral, 0.0, 0.0)
			var query := field.road_query(point.x, point.z)
			var queried_frame: Transform3D = query.frame
			maximum_error = maxf(maximum_error, absf(float(query.s) - t))
			maximum_error = maxf(maximum_error, absf(float(query.distance) - absf(lateral)))
			maximum_error = maxf(maximum_error, absf((point - queried_frame.origin).dot(queried_frame.basis.x) - lateral))
	check.call(maximum_error < 0.08, "v%d seed %d: full-width signed projection remains accurate around the sharpest bend at %.1fm (error %.4fm)" % [field.profile.generation_version, field.world_seed, s, maximum_error])
	var outer_error := 0.0
	var apex := field.road_frame(s)
	for lateral: float in [-60.0, -44.0, -40.0, 40.0, 44.0, 60.0]:
		var point: Vector3 = apex * Vector3(lateral, 0, 0)
		var probe := Vector2(point.x, point.z)
		var nearest := INF
		# Independent polyline distance also covers inner-bend terrain beyond
		# the curvature radius, where the apex need not be the closest station.
		var previous := Vector2(field.road_x(s - 220.0), -s + 220.0)
		for step in range(1, 441):
			var t := s - 220.0 + step
			var next := Vector2(field.road_x(t), -t)
			nearest = minf(nearest, probe.distance_to(Geometry2D.get_closest_point_to_segment(probe, previous, next)))
			previous = next
		outer_error = maxf(outer_error, absf(float(field.road_query(point.x, point.z).distance) - nearest))
	check.call(outer_error < 0.03, "v%d seed %d: terrain outside a tight bend selects the nearest road rather than the stationary apex (error %.4fm)" % [field.profile.generation_version, field.world_seed, outer_error])

static func _insert_clear_ribbon(quad: PackedVector2Array, ribbons: Array[PackedVector2Array], buckets: Dictionary) -> bool:
	if Geometry2D.segment_intersects_segment(quad[0], quad[1], quad[2], quad[3]) != null:
		return false
	if Geometry2D.segment_intersects_segment(quad[1], quad[2], quad[3], quad[0]) != null:
		return false
	var bounds := Rect2(quad[0], Vector2.ZERO)
	for point in quad:
		bounds = bounds.expand(point)
	var first := Vector2i(floori(bounds.position.x / 50.0), floori(bounds.position.y / 50.0))
	var last := Vector2i(floori(bounds.end.x / 50.0), floori(bounds.end.y / 50.0))
	var candidates: Dictionary = {}
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var key := Vector2i(x, y)
			for previous: int in buckets.get(key, []):
				candidates[previous] = true
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(ribbons.size())
	for previous: int in candidates:
		# Adjacent quads share a cross-section by construction.
		if previous == ribbons.size() - 1:
			continue
		for overlap: PackedVector2Array in Geometry2D.intersect_polygons(quad, ribbons[previous]):
			var twice_area := 0.0
			for index in range(overlap.size()):
				twice_area += (overlap[index] - overlap[0]).cross(overlap[(index + 1) % overlap.size()] - overlap[0])
			if absf(twice_area) > 0.02:
				return false
	return true

static func _check_rivers(field: WorldField, check: Callable) -> void:
	var rivers: Array[Dictionary] = field.landforms.rivers_near(-LENGTH * 0.5, LENGTH * 0.5)
	var label := "v%d seed %d: " % [field.profile.generation_version, field.world_seed]
	check.call(not rivers.is_empty(), label + "journey contains river crossings")
	for river: Dictionary in rivers:
		var s := float(river.s)
		if s < 450.0 or s > LENGTH:
			continue
		var water := float(river.water_height)
		var x := field.road_x(s)
		check.call(field.landforms.bridge_at(s), label + "river crossing has a bridge")
		check.call(field.road_height(s) > water + 1.0, label + "bridge deck clears the water")
		_check_shoreline(field, river, check)
		_check_crossing_support(field, river, check)
		# Sample the real carved bed away from the bridge and its piers.
		for side: float in [-1.0, 1.0]:
			var bank_x := x + side * 90.0
			var river_z: float = field.landforms.river_z(river, bank_x)
			check.call(float(field.surface(bank_x, river_z).height) < water - 0.3, label + "water is above the carved river bed")
		# Bank transition must finish before the road returns to dry ground.
		for side: float in [-1.0, 1.0]:
			var approach_s := s + side * (float(river.half_width) + 70.0)
			if field.landforms.bridge_at(approach_s):
				continue
			var point := field.road_frame(approach_s).origin
			check.call(absf(float(field.surface(point.x, point.z).height) - point.y) < 0.12, label + "bridge approaches meet dry carriageway")
		for side: float in [-1.0, 1.0]:
			var approach_s := s + side * 87.5
			# A river bridge can continue as a dry viaduct beyond the bank.
			if field.landforms.bridge_at(approach_s): continue
			var approach := field.road_frame(approach_s)
			for lateral: float in [-0.4, 0.0, 0.4]:
				var point := approach.origin + approach.basis.x * field.road_width(s + side * 87.5) * lateral
				check.call(absf(float(field.surface(point.x, point.z).height) - point.y) < 0.12, label + "both bridge ends have dry terrain support across the carriageway")

static func _check_crossing_support(field: WorldField, river: Dictionary, check: Callable) -> void:
	var deck_cache: Dictionary = {}
	var wet_samples := 0
	var grounded_samples := 0
	var supported := true
	var water_clear := true
	var maximum_ground_error := 0.0
	# World-aligned 5m stations coincide with the real deck mesh's 2.5m
	# cross-sections. Cover both banks and the full width, including the edge
	# that can cross an oblique river before the road centre reaches it.
	var first := floori((float(river.s) - 170.0) / 5.0)
	var last := ceili((float(river.s) + 170.0) / 5.0)
	for index in range(first, last + 1):
		var s := index * 5.0
		var frame := field.road_frame(s)
		var half := field.road_width(s) * 0.5
		var bridge := field.landforms.bridge_at(s)
		for lateral: float in [-half + 0.01, -half * 0.5, 0.0, half * 0.5, half - 0.01]:
			var point := frame * Vector3(lateral, 0.0, 0.0)
			var sample := field.surface(point.x, point.z)
			if is_finite(float(sample.water_height)):
				wet_samples += 1
				water_clear = water_clear and point.y > float(sample.water_height) + 1.0
				supported = supported and bridge
			if bridge:
				var band := floori(s / 150.0)
				if not deck_cache.has(band): deck_cache[band] = TerrainCrossings.bridge_faces(field, band, 2.5)
				supported = supported and _deck_covers(deck_cache[band], point)
			if not bridge:
				grounded_samples += 1
				maximum_ground_error = maxf(maximum_ground_error, absf(float(sample.height) - point.y))
	var label := "v%d seed %d river %.0fm: " % [field.profile.generation_version, field.world_seed, float(river.s)]
	check.call(wet_samples > 0 and supported and water_clear, label + "every wet full-width carriageway sample has a physical deck clearing water, including oblique bank edges")
	check.call(maximum_ground_error < 0.12, label + "all grounded river approaches retain terrain support across the complete road width (%d samples, error %.4fm)" % [grounded_samples, maximum_ground_error])

static func _deck_covers(faces: PackedVector3Array, point: Vector3) -> bool:
	# Vector2/Vector3 store float32 coordinates. A point made from the same
	# cross-section can round just outside its triangle's boundary kilometres
	# from the origin. Admit only that coordinate-sized rounding distance;
	# the independent vertical support tolerance remains unchanged.
	var rounding := maxf(1.0, maxf(absf(point.x), absf(point.z))) * 0.00000012
	for index in range(0, faces.size(), 3):
		var a := faces[index]
		var b := faces[index + 1]
		var c := faces[index + 2]
		var triangle := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
		var inside := Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), triangle)
		if not inside:
			for edge in range(3):
				var closest := Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), triangle[edge], triangle[(edge + 1) % 3])
				inside = inside or closest.distance_to(Vector2(point.x, point.z)) <= rounding
		if not inside: continue
		var normal := (b - a).cross(c - a)
		if absf(normal.y) < 0.0001: continue
		var height := a.y - (normal.x * (point.x - a.x) + normal.z * (point.z - a.z)) / normal.y
		if absf(height - (point.y + 0.07)) < 0.12: return true
	return false

static func _check_shoreline(field: WorldField, river: Dictionary, check: Callable) -> void:
	var label := "v%d seed %d river %.0fm: " % [field.profile.generation_version, field.world_seed, float(river.s)]
	var level := float(river.water_height)
	var waterline_error := 0.0
	var inside_wet := true
	var outside_dry := true
	var mesh_edges_buried := true
	# Cover the physical strip and both distant sides. These checks catch a
	# water ribbon ending on a still-submerged bank even when its centre is wet.
	for x: float in [-1250.0, -1010.0, -750.0, -500.0, float(river.center_x) - 90.0, float(river.center_x) + 90.0, 500.0, 750.0, 1010.0, 1250.0]:
		var center := field.landforms.river_z(river, x)
		var half := field.landforms.river_half_width(river, x)
		for side: float in [-1.0, 1.0]:
			waterline_error = maxf(waterline_error, absf(float(field.surface(x, center + side * half).height) - level))
			inside_wet = inside_wet and float(field.surface(x, center + side * (half - 3.0)).height) < level - 0.05
			outside_dry = outside_dry and float(field.surface(x, center + side * (half + 3.0)).height) > level + 0.05
		var x0 := -TerrainCrossings.WATER_EXTENT + floorf((x + TerrainCrossings.WATER_EXTENT) / TerrainCrossings.WATER_STEP) * TerrainCrossings.WATER_STEP
		var polygon := TerrainCrossings.water_polygon(field.landforms, river, x0, x0 + TerrainCrossings.WATER_STEP)
		# Test the actual straight bank segments between water vertices too.
		for t: float in [0.0, 0.5, 1.0]:
			for edge: Vector3 in [polygon[0].lerp(polygon[1], t), polygon[3].lerp(polygon[2], t)]:
				mesh_edges_buried = mesh_edges_buried and float(field.surface(edge.x, edge.z).height) > level
	check.call(waterline_error < 0.02, label + "shared shoreline reaches water level across near and distant terrain (error %.4f)" % waterline_error)
	check.call(inside_wet and outside_dry, label + "both shores transition from submerged bed to dry bank")
	check.call(mesh_edges_buried, label + "rendered water bank edges and their midpoints overlap dry terrain")

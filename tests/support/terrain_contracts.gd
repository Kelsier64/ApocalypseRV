extends RefCounted
## Pure, bounded v13 sampling. Geometry checks use the swept carriageway, not
## only the monotonic centre parameter, so folded or overlapping edges fail too.
const LENGTH := 12000.0
const STEP := 10.0
const SEEDS := [0, 42, 99173, -61]

static func profile() -> WorldProfile:
	var settings := WorldProfile.new()
	settings.generation_version = 13
	settings.max_grade = 0.12
	return settings

static func run(check: Callable) -> void:
	var signatures: Array = []
	for seed_value: int in SEEDS:
		var field := WorldField.new(seed_value, profile())
		var reverse := WorldField.new(seed_value, profile())
		# Ask far-first before comparing ascending samples to catch cache/order drift.
		for index in range(24, -1, -1):
			_snapshot(reverse, index * 487.0 + 31.0)
		var signature: Array = []
		for index in range(25):
			var s := index * 487.0 + 31.0
			var sample := _snapshot(field, s)
			check.call(sample == _snapshot(reverse, s), "v13 seed %d: queries are independent of request order at %.0fm" % [seed_value, s])
			signature.append(sample)
		signatures.append(signature)
		_check_route(field, check)
		_check_rivers(field, check)
	for index in range(1, signatures.size()):
		check.call(signatures[index] != signatures[0], "v13 different seeds produce different routes and terrain")

static func _snapshot(field: WorldField, s: float) -> Array:
	var x := field.road_x(s)
	return [field.road_frame(s), field.road_width(s), field.surface(x + 65.0, -s), field.landforms.kind_at(s), field.landforms.rivers_near(-s)]

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
	var label := "v13 seed %d: " % field.world_seed
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
	var label := "v13 seed %d: " % field.world_seed
	check.call(not rivers.is_empty(), label + "journey contains river crossings")
	for river: Dictionary in rivers:
		var s := float(river.s)
		if s < 450.0 or s > LENGTH:
			continue
		var water := float(river.water_height)
		var x := field.road_x(s)
		check.call(field.landforms.bridge_at(s), label + "river crossing has a bridge")
		check.call(field.road_height(s) > water + 1.0, label + "bridge deck clears the water")
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

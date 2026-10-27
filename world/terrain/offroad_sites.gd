extends RefCounted
class_name OffroadSites
## World-coordinate cells keep independent off-road sites separated by construction.
## WorldField owns the cache; this planner never queries the blended surface.
const CELL_LENGTH := 900.0
const CELL_WIDTH := 300.0
const COLUMNS := 3
const WALK_MARGIN := 3.0
const BLEND_MARGIN := 16.0
const ROAD_CLEARANCE := 25.0
const MEGASHELTER_CHANCE := 0.02

static func plan(field: WorldField, row: int, column: int) -> Dictionary:
	if row < 0 or column < 0 or column >= COLUMNS: return {}
	var cell_index := row * COLUMNS + column
	if field.rng_for(cell_index, "offroad_presence").randf() >= 0.55: return {}
	var seed_value := field.seed_for(cell_index, "offroad_content")
	var exterior_plan: Dictionary = {}
	var definition_id: String
	if field.profile.generation_version >= 18 and field.rng_for(cell_index, "offroad_megashelter").randf() < MEGASHELTER_CHANCE:
		definition_id = "modular_megashelter"
		exterior_plan = MegashelterPlan.generate(seed_value)
	else:
		var category := field.rng_for(cell_index, "offroad_category")
		var theme := field.rng_for(cell_index, "offroad_theme")
		var layout := field.rng_for(cell_index, "offroad_layout")
		# Existing category and layout draws retain their independent streams.
		var category_roll := category.randf()
		if category_roll < 0.4:
			definition_id = POIConfig.GENERATION_IDS[theme.randi_range(0, POIConfig.GENERATION_IDS.size() - 1)]
		elif category_roll < 0.6:
			definition_id = "civilian_shelter" if theme.randf() < 0.5 else "courtyard_shelter"
		else:
			definition_id = "roadside_%s_%d" % ["camp" if theme.randf() < 0.5 else "shed", layout.randi_range(0, 2)]
	var definition := POIConfig.definition(StringName(definition_id))
	if definition == null or not definition.supports_placement(PoiDefinition.Placement.OFF_ROAD): return {}
	var local_site_bounds: AABB = exterior_plan.get("site_bounds", definition.site_bounds)
	var placement := field.rng_for(cell_index, "offroad_placement")
	var x_min := -450.0 + column * CELL_WIDTH
	var s_min := row * CELL_LENGTH
	for attempt in range(8):
		var position := Vector3(placement.randf_range(x_min + 65.0, x_min + CELL_WIDTH - 65.0), 0.0,
			-placement.randf_range(s_min + 100.0, s_min + CELL_LENGTH - 100.0))
		if -position.z < 450.0: continue
		var building := Transform3D(Basis(Vector3.UP, placement.randf_range(-PI, PI)), position)
		# The complete terrain blend stays inside its cell and the collision strip.
		var influence := local_site_bounds.grow(WALK_MARGIN + BLEND_MARGIN + 1.0)
		var envelope: AABB = building * influence
		if envelope.position.x < maxf(-440.0, x_min) or envelope.end.x > minf(440.0, x_min + CELL_WIDTH): continue
		if envelope.position.z < -s_min - CELL_LENGTH or envelope.end.z > -s_min: continue
		if not _environment_clear(field, building, influence): continue
		if not _terrain_clear(field, building, local_site_bounds.grow(4.0)): continue
		position.y = field.raw_height(position.x, position.z)
		building.origin = position
		var site := {"index": cell_index,
			"id": "v%d:%d:offroad:%d:%d" % [field.profile.generation_version, field.world_seed, row, column],
			"s": -position.z, "building": building, "frame": building,
			"bounds": (building * local_site_bounds).grow(5.0),
			"placement": "off_road", "definition_id": definition_id,
			"kind": "entrance" if definition.kind == PoiDefinition.Kind.INSTANCE_ENTRANCE else "walk_in",
			"title": definition.display_name, "seed": seed_value, "walls": []}
		if not exterior_plan.is_empty():
			site.exterior_plan = exterior_plan
			site.local_site_bounds = local_site_bounds
			site.local_building_bounds = exterior_plan.building_bounds
		if definition.kind == PoiDefinition.Kind.WALK_IN: site.minor = true
		if _occupied(field, building * influence): continue
		return site
	return {}

static func court_distance(point: Vector3, site: Dictionary) -> float:
	var local: Vector3 = site.building.affine_inverse() * point
	var bounds: AABB = site.get("local_site_bounds", POIConfig.definition_for_site(site).site_bounds)
	var center := bounds.get_center()
	var q := Vector2(absf(local.x - center.x) - bounds.size.x * 0.5 - WALK_MARGIN,
		absf(local.z - center.z) - bounds.size.z * 0.5 - WALK_MARGIN)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()

static func _environment_clear(field: WorldField, building: Transform3D, bounds: AABB) -> bool:
	# channel().wet and water_height only describe the waterline. Its valley
	# earthworks extend another 115m and run after the POI pad is flattened.
	# Exclude that complete interval across the world envelope, with 4m spare
	# for river meander between the 8m transverse samples.
	var envelope: AABB = building * bounds
	var river_columns := maxi(1, ceili(envelope.size.x / 8.0))
	for river in field.landforms.rivers_near(envelope.get_center().z, envelope.size.z * 0.5):
		for index in range(river_columns + 1):
			var x := lerpf(envelope.position.x, envelope.end.x, float(index) / river_columns)
			var river_z := field.landforms.river_z(river, x)
			var half := field.landforms.river_half_width(river, x) + 119.0
			if river_z + half >= envelope.position.z and river_z - half <= envelope.end.z: return false
	# Corners, edge midpoints and centre include the whole rotated blend envelope.
	# The tighter grid also catches a road bend or river crossing its interior.
	var columns := maxi(2, ceili(bounds.size.x / 24.0) * 2)
	var rows := maxi(2, ceili(bounds.size.z / 24.0) * 2)
	for x_index in range(columns + 1):
		for z_index in range(rows + 1):
			var point := building * Vector3(lerpf(bounds.position.x, bounds.end.x, float(x_index) / columns), 0.0,
				lerpf(bounds.position.z, bounds.end.z, float(z_index) / rows))
			var road := field.road_query(point.x, point.z)
			if float(road.distance) - float(road.width) * 0.5 < ROAD_CLEARANCE: return false
			var raw_height := field.landforms.height(point.x, point.z, road)
			var channel := field.landforms.channel(point.x, point.z, raw_height)
			# Channel shaping runs after POI flattening: avoid its entire bank/valley
			# influence, not just wet water, so entrances cannot be cut away later.
			if channel.wet or is_finite(float(channel.water_height)): return false
	return true

static func _terrain_clear(field: WorldField, building: Transform3D, bounds: AABB) -> bool:
	var low := INF
	var high := -INF
	for x_index in range(3):
		for z_index in range(3):
			var point := building * Vector3(lerpf(bounds.position.x, bounds.end.x, x_index * 0.5), 0.0,
				lerpf(bounds.position.z, bounds.end.z, z_index * 0.5))
			var height := field.raw_height(point.x, point.z)
			low = minf(low, height)
			high = maxf(high, height)
			if high - low > 6.0: return false
	var center := building.origin
	var dx := (field.raw_height(center.x + 2.0, center.z) - field.raw_height(center.x - 2.0, center.z)) / 4.0
	var dz := (field.raw_height(center.x, center.z + 2.0) - field.raw_height(center.x, center.z - 2.0)) / 4.0
	return Vector2(dx, dz).length() <= 0.65

static func _occupied(field: WorldField, envelope: AABB) -> bool:
	# The dependency direction is intentional: stop/minor_site must never query
	# OffroadSites or sites_near_z, otherwise surface planning would recurse.
	var first := maxi(0, floori((-envelope.end.z - field.profile.stop_jitter - 160.0) / field.profile.stop_spacing))
	var last := maxi(0, ceili((-envelope.position.z + field.profile.stop_jitter + 160.0) / field.profile.stop_spacing))
	for index in range(first, last + 1):
		var site := field.stop(index)
		if not site.is_empty() and _intersects_xz(envelope, site.bounds.grow(20.0)): return true
	first = maxi(0, floori((-envelope.end.z - 160.0) / MinorSites.CELL_LENGTH))
	last = maxi(0, floori((-envelope.position.z + 160.0) / MinorSites.CELL_LENGTH))
	for cell in range(first, last + 1):
		var site := field.minor_site(cell)
		if not site.is_empty() and _intersects_xz(envelope, site.bounds.grow(20.0)): return true
	return false

static func _intersects_xz(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x and a.end.x > b.position.x and a.position.z < b.end.z and a.end.z > b.position.z

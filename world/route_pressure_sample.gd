extends RefCounted
class_name RoutePressureSample
## XZ-only route policy; terrain-course AABBs deliberately confer no immunity.
const ROUTE_CLEARANCE := 12.0
const SAFE_FOREST_OFFSET := 70.0

static func sample(field: WorldField, point: Vector3) -> Dictionary:
	if field == null or not point.is_finite(): return {}
	var road := field.road_query(point.x, point.z)
	var frame: Transform3D = road.frame
	var offset := maxf(0.0, float(road.distance) - float(road.width) * 0.5)
	var forest_direction := point - frame.origin
	forest_direction.y = 0.0
	forest_direction = forest_direction.normalized()
	var backward_direction := frame.basis.z
	backward_direction.y = 0.0
	backward_direction = backward_direction.normalized()
	var result := {"progress": float(road.s), "forest_offset": offset,
		"exempt": false, "progress_valid": offset <= SAFE_FOREST_OFFSET,
		"danger_direction": forest_direction if offset > 100.0 else backward_direction,
		"forest_direction": forest_direction, "backward_direction": backward_direction,
		"reason": "forest" if offset > 100.0 else ""}
	var nearest := INF
	for site: Dictionary in field.sites_near_z(point.z, 400.0):
		if not _site_exempt(point, site): continue
		# Overlapping approach strips use the closest site's longitudinal anchor.
		var distance := absf(float(site.s) - float(road.s))
		if distance >= nearest: continue
		nearest = distance
		result.exempt = true
		result.progress_valid = true
		result.progress = float(site.s)
		result.reason = ""
	return result

static func _site_exempt(point: Vector3, site: Dictionary) -> bool:
	var kind: String = site.get("kind", "")
	if kind not in ["entrance", "walk_in"] and not site.has("definition_id"): return false
	var definition := POIConfig.definition_for_site(site)
	if definition == null or not site.get("building") is Transform3D: return false
	var building: Transform3D = site.building
	var local: Vector3 = building.affine_inverse() * Vector3(point.x, building.origin.y, point.z)
	var bounds := definition.site_bounds
	if local.x >= bounds.position.x and local.x <= bounds.end.x and local.z >= bounds.position.z and local.z <= bounds.end.z:
		return true
	if not site.get("road") is Transform3D: return false
	var road: Transform3D = site.road
	if site.get("route") is PackedVector3Array:
		var route: PackedVector3Array = site.route
		if ExplorationSite.route_distance(point, route) <= ROUTE_CLEARANCE: return true
		if not route.is_empty() and _segment_distance(point, road.origin, route[0]) <= ROUTE_CLEARANCE: return true
	elif site.get("frame") is Transform3D:
		var frame: Transform3D = site.frame
		if _segment_distance(point, road.origin, frame.origin) <= ROUTE_CLEARANCE: return true
		if _segment_distance(point, frame.origin, building.origin) <= ROUTE_CLEARANCE: return true
	return false

static func _segment_distance(point: Vector3, start: Vector3, end: Vector3) -> float:
	var p := Vector2(point.x, point.z)
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, Vector2(start.x, start.z), Vector2(end.x, end.z)))

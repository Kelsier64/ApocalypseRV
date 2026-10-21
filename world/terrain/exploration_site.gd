extends RefCounted
class_name ExplorationSite
## Road-local templates. All consumers use the same route, gates and enclosure.
static var NAMES: Array[String] = POIConfig.instance_titles()
const TYPES = POIConfig.GENERATION_IDS

static func configure(site: Dictionary, field: WorldField) -> void:
	var index: int = site.index
	site.kind = "entrance"
	site.side = select_side(site.road, float(site.side), field)
	var side: float = site.side
	var road: Transform3D = site.road
	site.frame = Transform3D(road.basis, road * Vector3(side * 33, 0, 0))
	var type_index := 0 if index == 0 else field.rng_for(index, "exterior").randi_range(0, 3)
	site.exterior = TYPES[type_index]
	site.title = NAMES[type_index]
	site.mirror = 1.0 if field.rng_for(index, "route").randf() > 0.5 else -1.0
	site.building = Transform3D(Basis.looking_at(road.basis.x * side), Vector3.ZERO)
	configure_forest(site)

## Major stops share the established side choice, including walk-in sites.
## Only the clearance envelope is needed; no forest route or walls are built.
static func select_side(road: Transform3D, side: float, field: WorldField) -> float:
	# Face inward when near a world edge, rather than expanding the terrain.
	if absf(road.origin.x) > 25.0:
		side = -signf(road.origin.x)
	# Bounded candidate check; mirror to the opposite side if the requested
	# side cannot contain the full apron/perimeter in the collision strip.
	if not fits_strip(road, side, field.profile.terrain_half_width):
		side = -side
	if not _road_clear(road, side, _forest_bounds(road, side), field):
		side = -side
	return side

static func road_clear(site: Dictionary, field: WorldField) -> bool:
	if not site.has("route"): return true
	return _road_clear(site.road, float(site.side), site.bounds, field)

static func _road_clear(road: Transform3D, side: float, site_bounds: AABB, field: WorldField) -> bool:
	if not fits_strip(road, side, field.profile.terrain_half_width): return false
	var inverse := road.affine_inverse()
	var bounds := site_bounds.grow(14.0)
	for station in range(maxi(0, floori(-bounds.end.z)), ceili(-bounds.position.z) + 1, 5):
		var frame := field.road_frame(float(station))
		var half := field.road_width(float(station)) * 0.5 + 2.0
		for lateral: float in [-half, 0.0, half]:
			var point: Vector3 = inverse * (frame * Vector3(lateral, 0, 0))
			var u := point.x * side
			if u > 18.0 and u < 362.0 and absf(point.z) < 60.0: return false
	return true

static func configure_forest(site: Dictionary) -> void:
	# Keep the parking/first RV barrier, then weave through a deeper forest.
	site.deep_forest = true
	site.route = PackedVector3Array()
	for p in [Vector2(33, 0), Vector2(52, 0), Vector2(52, 24), Vector2(102, 24), Vector2(102, -24), Vector2(162, -24), Vector2(162, 24), Vector2(222, 24), Vector2(222, -24), Vector2(282, -24), Vector2(282, 0), Vector2(328.9, 0)]:
		site.route.append(site.road * Vector3(p.x * float(site.side), site_rise(site, p.x), p.y * float(site.mirror)))
	site.building.origin = site.road * Vector3(335.2 * float(site.side), 6, 0)
	site.landmark = site.building * Vector3(0, 14, 0)
	site.bounds = _forest_bounds(site.road, float(site.side))
	site.walls = []
	for gate in [Vector2(44, 0), Vector2(77, 24), Vector2(137, -24), Vector2(197, 24), Vector2(257, -24), Vector2(310, 0)]:
		var gap: float = gate.y * float(site.mirror)
		for interval in [Vector2(-44, gap - 0.9), Vector2(gap + 0.9, 44)]:
			site.walls.append({"position": Vector3(gate.x * float(site.side), 0, (interval.x + interval.y) * 0.5), "size": Vector3(0.6, 1.4 if gate.x == 44 else 3.2, interval.y - interval.x)})
	for v in [-44.0, 44.0]:
		site.walls.append({"position": Vector3(199.5 * float(site.side), 0, v), "size": Vector3(311.6, 3.2, 0.6)})
	site.walls.append({"position": Vector3(355 * float(site.side), 0, 0), "size": Vector3(0.6, 3.2, 88)})

static func _forest_bounds(road: Transform3D, side: float) -> AABB:
	var bounds := AABB(road * Vector3(20 * side, -15, -58), Vector3.ZERO)
	for u in [20.0, 360.0]:
		for v in [-58.0, 58.0]:
			bounds = bounds.expand(road * Vector3(u * side, 38, v))
	return bounds

static func site_rise(_site: Dictionary, u: float) -> float:
	return smoothstep(40.0, 310.0, u) * 6.0

static func route_distance(point: Vector3, route: PackedVector3Array) -> float:
	var p := Vector2(point.x, point.z)
	var result := INF
	for i in range(1, route.size()):
		var a := Vector2(route[i - 1].x, route[i - 1].z)
		var b := Vector2(route[i].x, route[i].z)
		result = minf(result, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return result

static func wall_parts(site: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for wall: Dictionary in site.walls:
		var along_z: bool = wall.size.z > wall.size.x
		var length: float = maxf(wall.size.x, wall.size.z)
		var count := ceili(length / 3.0)
		for i in range(count):
			var center: Vector3 = wall.position + (Vector3.BACK if along_z else Vector3.RIGHT) * (-length * 0.5 + length / count * (i + 0.5))
			var point: Vector3 = site.road * center
			point.y += site_rise(site, center.x * float(site.side))
			var size := Vector3(0.6, wall.size.y, length / count + 0.01) if along_z else Vector3(length / count + 0.01, wall.size.y, 0.6)
			result.append({"base": point, "size": size, "transform": Transform3D(site.road.basis, point + Vector3.UP * size.y * 0.5)})
	return result

static func route_length(site: Dictionary) -> float:
	var result := 0.0
	for i in range(1, site.route.size()):
		result += site.route[i].distance_to(site.route[i - 1])
	return result

static func local_point(site: Dictionary, x: float, z: float) -> Vector3:
	return site.road * Vector3(float(site.side) * x, 0, z)

static func fits_strip(road: Transform3D, side: float, half_width: float) -> bool:
	for u in [20.0, 360.0]:
		for v in [-58.0, 58.0]:
			if absf((road * Vector3(side * u, 0, v)).x) > half_width - 8: return false
	return true

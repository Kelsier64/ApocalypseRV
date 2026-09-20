extends RefCounted
class_name ExplorationSite
## Road-local templates. All consumers use the same route, gates and enclosure.
static var NAMES: Array[String] = POIConfig.instance_titles()
const TYPES = POIConfig.GENERATION_IDS

static func configure(site: Dictionary, field: WorldField) -> void:
	var index: int = site.index
	site.kind = "entrance" if index % 3 != 2 else ["wreck", "camp", "shed"][field.rng_for(index, "exterior").randi_range(0, 2)]
	if site.kind != "entrance":
		return
	# Face inward when near a world edge, rather than expanding the terrain.
	if absf(site.road.origin.x) > 25.0:
		site.side = -signf(site.road.origin.x)
	# Bounded candidate check; mirror to the opposite side if the requested
	# side cannot contain the full apron/perimeter in the collision strip.
	if not fits_strip(site.road, float(site.side), field.profile.terrain_half_width):
		site.side = -float(site.side)
	var side: float = site.side
	var road: Transform3D = site.road
	site.frame = Transform3D(road.basis, road * Vector3(side * 33, 0, 0))
	var type_index := 0 if index == 0 else field.rng_for(index, "exterior").randi_range(0, 3)
	site.exterior = TYPES[type_index]
	site.title = NAMES[type_index]
	var mirror := 1.0 if field.rng_for(index, "route").randf() > 0.5 else -1.0
	var route := PackedVector3Array()
	for p in [Vector2(33, 0), Vector2(50, 0), Vector2(50, 24), Vector2(78, 24), Vector2(78, -24), Vector2(108, -24), Vector2(108, 0), Vector2(128.7, 0)]:
		route.append(road * Vector3(p.x * side, rise(p.x), p.y * mirror))
	site.route = route
	site.mirror = mirror
	var building_pos: Vector3 = road * Vector3(side * 135, rise(135), 0)
	site.building = Transform3D(Basis.looking_at(road.basis.x * side), building_pos)
	site.landmark = site.building * Vector3(0, 14, 0)
	site.bounds = AABB(road * Vector3(side * 20, -15, -45), Vector3.ZERO)
	for u in [20.0, 160.0]:
		for v in [-45.0, 45.0]:
			site.bounds = site.bounds.expand(road * Vector3(side * u, 30, v))
	site.walls = []
	# Continuous perimeter and two staggered baffles. 1.8 m pedestrian gaps.
	for gate in [Vector2(44, 0), Vector2(68, 24 * mirror), Vector2(92, -24 * mirror)]:
		for interval in [Vector2(-38, gate.y - 0.9), Vector2(gate.y + 0.9, 38)]:
			site.walls.append({"position": Vector3(gate.x * side, 0, (interval.x + interval.y) * 0.5), "size": Vector3(0.6, 1.4 if gate.x == 44 else 3.8, interval.y - interval.x)})
	for v in [-38.0, 38.0]:
		site.walls.append({"position": Vector3(99.5 * side, 0, v), "size": Vector3(111.6, 3.8, 0.6)})
	site.walls.append({"position": Vector3(155 * side, 0, 0), "size": Vector3(0.6, 3.8, 76)})
	if field.profile.generation_version >= 4:
		configure_forest(site)

static func configure_forest(site: Dictionary) -> void:
	# Keep the parking/first RV barrier, then weave through a deeper forest.
	site.deep_forest = true
	site.route = PackedVector3Array()
	for p in [Vector2(33, 0), Vector2(52, 0), Vector2(52, 24), Vector2(102, 24), Vector2(102, -24), Vector2(162, -24), Vector2(162, 24), Vector2(222, 24), Vector2(222, -24), Vector2(282, -24), Vector2(282, 0), Vector2(328.9, 0)]:
		site.route.append(site.road * Vector3(p.x * float(site.side), site_rise(site, p.x), p.y * float(site.mirror)))
	site.building.origin = site.road * Vector3(335.2 * float(site.side), 6, 0)
	site.landmark = site.building * Vector3(0, 14, 0)
	site.bounds = AABB(site.road * Vector3(20 * float(site.side), -15, -58), Vector3.ZERO)
	for u in [20.0, 360.0]:
		for v in [-58.0, 58.0]:
			site.bounds = site.bounds.expand(site.road * Vector3(u * float(site.side), 38, v))
	site.walls = []
	for gate in [Vector2(44, 0), Vector2(77, 24), Vector2(137, -24), Vector2(197, 24), Vector2(257, -24), Vector2(310, 0)]:
		var gap: float = gate.y * float(site.mirror)
		for interval in [Vector2(-44, gap - 0.9), Vector2(gap + 0.9, 44)]:
			site.walls.append({"position": Vector3(gate.x * float(site.side), 0, (interval.x + interval.y) * 0.5), "size": Vector3(0.6, 1.4 if gate.x == 44 else 3.2, interval.y - interval.x)})
	for v in [-44.0, 44.0]:
		site.walls.append({"position": Vector3(199.5 * float(site.side), 0, v), "size": Vector3(311.6, 3.2, 0.6)})
	site.walls.append({"position": Vector3(355 * float(site.side), 0, 0), "size": Vector3(0.6, 3.2, 88)})

static func site_rise(site: Dictionary, u: float) -> float:
	return smoothstep(40.0, 310.0, u) * 6.0 if site.get("deep_forest", false) else rise(u)

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

static func rise(u: float) -> float:
	# Six-metre rise reveals the roof over foreground occluders; apron is level.
	return smoothstep(40.0, 122.0, u) * 6.0

static func fits_strip(road: Transform3D, side: float, half_width: float) -> bool:
	for u in [20.0, 360.0 if half_width > 300 else 160.0]:
		for v in [-58.0, 58.0] if half_width > 300 else [-45.0, 45.0]:
			if absf((road * Vector3(side * u, 0, v)).x) > half_width - 8: return false
	return true

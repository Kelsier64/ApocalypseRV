extends RefCounted
class_name ExplorationSite
## Standalone roadside entrances. Off-road copies use the independent grid plan.
const TYPES = POIConfig.GENERATION_IDS

static func configure(site: Dictionary, field: WorldField) -> void:
	site.kind = "entrance"
	site.side = select_side(site.road, float(site.side), field)
	var selected := field.rng_for(int(site.index), "exterior").randi_range(0, TYPES.size() - 1)
	var definition := POIConfig.definition(StringName(TYPES[selected]))
	site.definition_id = str(definition.definition_id)
	site.title = definition.display_name
	site.building = Transform3D(Basis.looking_at(site.road.basis.x * float(site.side)), site.road * Vector3(float(site.side) * 49, 0, 0))
	site.frame = site.building
	site.bounds = (site.building * definition.site_bounds).grow(5.0)

static func select_side(road: Transform3D, side: float, field: WorldField) -> float:
	if absf(road.origin.x) > 25.0:
		side = -signf(road.origin.x)
	if absf((road * Vector3(side * 100, 0, 0)).x) > field.profile.terrain_half_width - 20:
		side = -side
	return side

## Shared by pressure-spawn exclusion for arbitrary polylines.
static func route_distance(point: Vector3, route: PackedVector3Array) -> float:
	var p := Vector2(point.x, point.z)
	var result := INF
	for i in range(1, route.size()):
		var a := Vector2(route[i - 1].x, route[i - 1].z)
		var b := Vector2(route[i].x, route[i].z)
		result = minf(result, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return result

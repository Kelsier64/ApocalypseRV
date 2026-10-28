extends RefCounted
class_name BuildingLocator
## Finds planned large buildings even when their chunks are not loaded.
## Callers cache the result; a cold query may plan several surrounding cells.
const SIGNAL_RANGE := 2000.0
const DEFINITION_ID := "modular_megashelter"

var field: WorldField

func _init(world_field: WorldField = null) -> void:
	field = world_field

func nearest(origin: Vector3, radius: float = SIGNAL_RANGE) -> Dictionary:
	if field == null or not origin.is_finite() or not is_finite(radius) or radius < 0.0:
		return {}
	# Most targets are nearby. Once a circle contains a target, sites outside
	# that circle cannot be nearer; cached rows make expansion inexpensive.
	var search_radius := minf(450.0, radius)
	while true:
		var found := _nearest_within(origin, search_radius)
		if not found.is_empty() or search_radius >= radius: return found
		search_radius = minf(search_radius * 2.0, radius)
	return {}

func _nearest_within(origin: Vector3, radius: float) -> Dictionary:
	var candidates: Array[Dictionary] = []
	# Both ordinary off-road cells and the denser v18 pool can contain a
	# megashelter. Site roots stay inside their longitudinal cell, so these
	# rows include every possible root within the horizontal signal radius.
	var first := maxi(0, floori((-origin.z - radius) / OffroadSites.CELL_LENGTH))
	var last := maxi(0, floori((-origin.z + radius) / OffroadSites.CELL_LENGTH))
	for row in range(first, last + 1):
		for column in range(OffroadSites.COLUMNS):
			candidates.append(field.offroad_site(row, column))
	first = maxi(1, floori((-origin.z - radius) / OffroadSites.MEGASHELTER_CELL_LENGTH))
	last = maxi(0, floori((-origin.z + radius) / OffroadSites.MEGASHELTER_CELL_LENGTH))
	for row in range(first, last + 1):
		candidates.append(field.megashelter_site(row))
	return nearest_site(candidates, origin, radius)

## Read-only selection by X/Z distance to the building root, including behind.
static func nearest_site(sites: Array[Dictionary], origin: Vector3, radius: float = SIGNAL_RANGE) -> Dictionary:
	if not origin.is_finite() or not is_finite(radius) or radius < 0.0:
		return {}
	var result: Dictionary = {}
	var best_squared := radius * radius
	for site in sites:
		if site.get("definition_id", "") != DEFINITION_ID or not site.get("building") is Transform3D:
			continue
		var pose: Transform3D = site.building
		if not pose.origin.is_finite(): continue
		var offset := Vector2(pose.origin.x - origin.x, pose.origin.z - origin.z)
		var distance_squared := offset.length_squared()
		if distance_squared > best_squared: continue
		# Stable ties keep a cached compass from changing with candidate order.
		if not result.is_empty() and distance_squared == best_squared and str(site.get("id", "")) >= str(result.get("id", "")):
			continue
		best_squared = distance_squared
		result = site
	return result

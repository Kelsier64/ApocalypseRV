extends RefCounted
const LOCATOR = preload("res://core/building_locator.gd")

class PoolField extends WorldField:
	var ordinary: Dictionary
	var dense: Dictionary

	func offroad_site(row: int, column: int) -> Dictionary:
		return ordinary if row == 3 and column == 1 else {}

	func megashelter_site(row: int) -> Dictionary:
		return dense if row == 12 else {}

static func run(check: Callable) -> void:
	_check_selection(check)
	_check_pools(check)
	_check_world(check)

static func _check_selection(check: Callable) -> void:
	var behind := _site("behind", Vector3(3.0, 900.0, 4.0))
	var ahead := _site("ahead", Vector3(0.0, 0.0, -6.0))
	var other := _site("other", Vector3.ZERO)
	other.definition_id = "gas_station"
	var sites: Array[Dictionary] = [other, ahead, behind]
	check.call(LOCATOR.nearest_site(sites, Vector3.ZERO, 10.0) == behind, "Building locator includes buildings behind and ignores height and other POI kinds")
	check.call(LOCATOR.nearest_site(sites, Vector3.ZERO, 5.0) == behind, "Building locator includes the exact signal radius")
	check.call(LOCATOR.nearest_site(sites, Vector3.ZERO, 4.9).is_empty(), "Building locator reports no signal outside the horizontal radius")
	check.call(LOCATOR.nearest_site(sites, Vector3(0.0, 200.0, -5.0), 10.0) == ahead, "Building locator selects a different nearest target after movement")
	var tie := _site("a_tie", Vector3(-3.0, 0.0, -4.0))
	var ties: Array[Dictionary] = [behind, tie]
	var selected: Dictionary = LOCATOR.nearest_site(ties, Vector3.ZERO, 5.0)
	ties.reverse()
	check.call(selected == tie and LOCATOR.nearest_site(ties, Vector3.ZERO, 5.0) == tie, "Building locator resolves equal distances independently of candidate order")
	check.call(LOCATOR.new().nearest(Vector3.ZERO).is_empty(), "Unbound building locator reports no signal")
	check.call(LOCATOR.nearest_site(sites, Vector3.ZERO, -1.0).is_empty(), "Building locator rejects an invalid signal radius")

static func _check_pools(check: Callable) -> void:
	var field := PoolField.new()
	field.ordinary = _site("ordinary", Vector3(0.0, 0.0, -3590.0))
	field.dense = _site("dense", Vector3(0.0, 0.0, -3615.0))
	var locator := LOCATOR.new(field)
	check.call(locator.nearest(Vector3(0.0, 0.0, -3600.0), 25.0) == field.ordinary, "Building locator includes rare ordinary-pool megashelters across a row boundary")
	check.call(locator.nearest(Vector3(0.0, 0.0, -3610.0), 25.0) == field.dense, "Building locator includes the dedicated megashelter pool")

static func _check_world(check: Callable) -> void:
	var field := WorldField.new(6)
	var locator := LOCATOR.new(field)
	var origin := Vector3(0.0, 1000.0, -1600.0)
	seed(37191)
	var expected_random := randi()
	seed(37191)
	var started := Time.get_ticks_usec()
	var found: Dictionary = locator.nearest(origin)
	var cold_usec := Time.get_ticks_usec() - started
	check.call(randi() == expected_random, "Cold building planning does not consume global RNG")
	check.call(not found.is_empty(), "Building locator finds an unloaded deterministic seed-6 megashelter without scene nodes")
	var expected := _nearest_reference(field.sites_near_z(origin.z, LOCATOR.SIGNAL_RANGE), origin, LOCATOR.SIGNAL_RANGE)
	check.call(found == expected, "Building locator agrees with an exhaustive mixed-pool WorldField query")
	check.call(locator.nearest(origin) == found, "Repeated building queries preserve the deterministic target")
	if not found.is_empty():
		var pose: Transform3D = found.building
		check.call(locator.nearest(pose.origin + Vector3(0.0, 500.0, 0.0), 0.0) == found, "Zero-radius locator finds the exact building root despite elevation")
	check.call(locator.nearest(Vector3(10000.0, 0.0, origin.z)).is_empty(), "Building locator reports no signal when all planned buildings are too far across the terrain")
	print("BUILDING_LOCATOR cold_ms=", cold_usec / 1000.0, " target=", found.get("id", "none"))

static func _nearest_reference(sites: Array[Dictionary], origin: Vector3, radius: float) -> Dictionary:
	var result: Dictionary = {}
	var best := radius
	for site in sites:
		if site.get("definition_id", "") != "modular_megashelter": continue
		var pose: Transform3D = site.building
		var distance := Vector2(pose.origin.x - origin.x, pose.origin.z - origin.z).length()
		if distance <= best:
			best = distance
			result = site
	return result

static func _site(id: String, origin: Vector3) -> Dictionary:
	return {"id": id, "definition_id": "modular_megashelter", "building": Transform3D(Basis.IDENTITY, origin)}

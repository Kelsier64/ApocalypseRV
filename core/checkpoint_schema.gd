extends RefCounted
class_name CheckpointSchema
## Limits bound decoding and traversal, not inventory capacity (legacy overflow survives).
const MAX_BYTES := 256 * 1024 * 1024
const MAX_ENTRIES := 1000000

static func valid_transform(value: Variant) -> bool:
	return value is Transform3D and value.is_finite() and is_finite(value.basis.determinant()) and absf(value.basis.determinant()) > 0.000001

static func vector(value: Variant) -> bool:
	return value is Vector3 and value.is_finite()

static func physics(value: Variant, require_freeze := false) -> bool:
	if not value is Dictionary or not value.has_all(["mode", "layer", "mask", "linear", "angular"]): return false
	return value.mode is int and value.mode in [0, 1] and value.layer is int and value.layer >= 0 and value.layer <= 0xffffffff and value.mask is int and value.mask >= 0 and value.mask <= 0xffffffff and vector(value.linear) and vector(value.angular) and (not require_freeze or value.get("freeze") is bool)

static func bounded(value: Variant, depth := 0, budget: Array = [MAX_ENTRIES]) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 32: return false
	if value is Object: return false
	if value is Array or value is Dictionary:
		if value.size() > MAX_ENTRIES: return false
		for key in value:
			if value is Dictionary:
				# GDScript dot assignment creates StringName keys in legacy fixtures.
				if not key is String and not key is StringName and not key is int: return false
				if not bounded(value[key], depth + 1, budget): return false
			elif not bounded(key, depth + 1, budget): return false
	return true

static func profile_error(data: Dictionary) -> String:
	var defaults := WorldProfile.new()
	var constants := ["chunk_length", "terrain_step", "max_crossfall", "parking_size"]
	var ranges := {"road_width": Vector2(1, 100), "narrow_width": Vector2(1, 100), "road_shoulder": Vector2(0, 100), "max_grade": Vector2(0, 0.5), "min_turn_radius": Vector2(1, 10000), "region_length": Vector2(1, 100000), "region_transition": Vector2(0, 100000), "stop_spacing": Vector2(1, 100000), "stop_jitter": Vector2(0, 100000), "decoration_density": Vector2(0, 10)}
	for key in data:
		var value: Variant = data[key]
		if key == "terrain_half_width":
			# Historical captures include this derived, read-only field.
			if not VehicleSnapshot._number(value) or value not in [225.0, 450.0]: return "profile." + key
		elif key == "generation_version":
			if not value is int or value not in [2, 3, 4, 5]: return "profile." + key
		elif key in constants:
			if value != defaults.get(key): return "profile." + key
		elif key in ["chunks_ahead", "chunks_behind"]:
			if not value is int or value < 0 or value > 32: return "profile." + key
		elif ranges.has(key):
			if not VehicleSnapshot._number(value) or value < ranges[key].x or value > ranges[key].y: return "profile." + key
		else: return "profile." + str(key)
	if data.get("narrow_width", defaults.narrow_width) > data.get("road_width", defaults.road_width): return "profile.narrow_width"
	if data.get("region_transition", defaults.region_transition) > data.get("region_length", defaults.region_length): return "profile.region_transition"
	if data.get("stop_jitter", defaults.stop_jitter) * 2 >= data.get("stop_spacing", defaults.stop_spacing): return "profile.stop_jitter"
	return ""

static func poi_error(value: Variant, path := "poi") -> String:
	if not value is Dictionary: return path
	for id in value:
		var entry: Variant = value[id]
		var prefix: String = path + "." + str(id)
		if not id is String or not entry is Dictionary or not entry.get("actors") is Array: return prefix
		if entry.has("layout"):
			var layout_error := InteriorLayout.validate(entry.layout)
			if not layout_error.is_empty(): return prefix + "." + layout_error
			if not entry.get("explored") is Array: return prefix + ".progress"
			var seen: Array[String] = []
			for room_id in entry.explored:
				if not room_id is String or room_id in seen: return prefix + ".explored"
				var found := false
				for room: Dictionary in entry.layout.rooms:
					if room.id == room_id: found = true
				if not found: return prefix + ".explored"
				seen.append(room_id)
		else:
			return prefix + ".missing_layout"
		for i in range(entry.actors.size()):
			var actor: Variant = entry.actors[i]
			var field := prefix + ".actors[%d]" % i
			if not actor is Dictionary or not valid_transform(actor.get("transform")): return field + ".transform"
			if actor.has("health"):
				if SaveSceneCatalog.resolve(actor.get("scene"), "monster") == null or not VehicleSnapshot._number(actor.health) or actor.health < 0: return field + ".health/scene"
			else:
				if SaveSceneCatalog.resolve(actor.get("scene"), "prop") == null: return field + ".scene"
				if not actor.get("name") is String or not actor.get("large") is bool or not actor.get("frozen") is bool or not yields_valid(actor.get("yields")): return field
				if not actor.get("state", {}) is Dictionary or not VehicleSnapshot.valid_prop_state(actor.scene, actor.get("state", {})): return field + ".state"
	return ""

static func yields_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not key is String or not value[key] is Vector2 or not value[key].is_finite() or value[key].x < 0 or value[key].y < value[key].x: return false
	return true

static func legacy_poi(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("actors") is Array: return false
	if not entry.has("layout"):
		return entry.size() == 1
	var layout: Variant = entry.layout
	return layout is Dictionary and layout.get("version") == 2 and layout.get("profile") == "maintenance_v2"

static func discard_legacy_poi(data: Dictionary) -> void:
	if not data.get("poi") is Dictionary: return
	for id in data.poi.keys():
		if legacy_poi(data.poi[id]): data.poi.erase(id)

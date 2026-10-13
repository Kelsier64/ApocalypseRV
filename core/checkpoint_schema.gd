extends RefCounted
class_name CheckpointSchema
## Limits bound decoding and traversal, not inventory capacity (legacy overflow survives).
const MAX_BYTES := 256 * 1024 * 1024
const MAX_ENTRIES := 1000000

static func valid_transform(value: Variant) -> bool:
	return value is Transform3D and value.is_finite() and is_finite(value.basis.determinant()) and absf(value.basis.determinant()) > 0.000001

static func vector(value: Variant) -> bool:
	return value is Vector3 and value.is_finite()

static func player_body_error(player: Dictionary) -> String:
	# Older v1/v2/v3 checkpoints have an intact body when this field is absent.
	if not player.has("body"): return ""
	if not PlayerBodyState.valid_state(player.body): return "player.body"
	if player.get("health", 0.0) > 0.0 and not player.body.present[&"head"]:
		return "player.body.head"
	return ""

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
			if not VehicleSnapshot._number(value) or (value not in [225.0, 450.0] and not (value == 500.0 and data.get("generation_version", 2) == 11)): return "profile." + key
		elif key == "generation_version":
			if not value is int or value not in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]: return "profile." + key
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

static func tutorial_error(value: Variant) -> String:
	if not value is Dictionary: return "state"
	var fields := ["version", "stage", "status", "terminal_id", "rv_id", "flashlight_id", "flags"]
	if not value.has_all(fields): return "fields"
	if not value.version is int or value.version not in [1, 2, 3]: return "version"
	if value.version >= 2: fields.append("workshop")
	if value.version == 3: fields.append("service")
	if not value.has_all(fields): return "fields"
	for key in value:
		if key not in fields and key != "entry_snapshot": return "fields"
	var last_stage := 2 if value.version == 1 else (7 if value.version == 2 else 9)
	if not value.stage is int or value.stage < 1 or value.stage > last_stage: return "stage"
	if not value.status is String or value.status not in ["active", "completed", "skipped"]: return "status"
	for key in ["terminal_id", "rv_id", "flashlight_id"]:
		if not value[key] is String or value[key].is_empty(): return key
	var flags: Variant = value.flags
	var flag_fields := ["viewed", "flashlight", "marker_index", "reversed", "parked"]
	if not flags is Dictionary or flags.size() != flag_fields.size() or not flags.has_all(flag_fields): return "flags"
	for key in ["viewed", "flashlight", "reversed", "parked"]:
		if not flags[key] is bool: return "flags." + key
	if not flags.marker_index is int or flags.marker_index < 0 or flags.marker_index > 2: return "flags.marker_index"
	if value.version >= 2:
		var workshop_state_error := workshop_error(value.workshop)
		if not workshop_state_error.is_empty(): return "workshop." + workshop_state_error
		for identity in value.workshop.output_ids:
			if identity in [value.terminal_id, value.rv_id, value.flashlight_id]: return "workshop.output_ids"
	if value.version == 3:
		var service_state_error := service_error(value.service)
		if not service_state_error.is_empty(): return "service." + service_state_error
		if value.service.flags.departure and value.stage != 9: return "service.flags.departure"
		if value.status == "completed" and (value.stage != 9 or not value.service.flags.departure): return "status"
	return ""

static func service_error(value: Variant) -> String:
	if not value is Dictionary: return "state"
	var identity_fields := ["engine_id", "wheel_id", "spare_id", "kit_id", "fuel_port_id", "fuel_can_id", "empty_can_id"]
	var fields := ["version", "configured", "wall_slot", "wheel_slot", "flags", "fuel_amount"] + identity_fields
	if value.size() != fields.size() or not value.has_all(fields): return "fields"
	if not value.version is int or value.version != 1: return "version"
	if not value.configured is bool: return "configured"
	if not value.wall_slot is String or value.wall_slot != "left_0": return "wall_slot"
	if not value.wheel_slot is int or value.wheel_slot != 0: return "wheel_slot"
	var flag_fields := ["wall", "engine", "removed", "wheel", "refueled", "departure"]
	if not value.flags is Dictionary or value.flags.size() != flag_fields.size() or not value.flags.has_all(flag_fields): return "flags"
	for field in flag_fields:
		if not value.flags[field] is bool: return "flags." + field
		if not value.configured and value.flags[field]: return "flags." + field
	var seen: Dictionary = {}
	for field in identity_fields:
		var identity: Variant = value[field]
		if not identity is String: return field
		if not value.configured and not identity.is_empty(): return field
		if value.configured and field not in ["fuel_can_id", "empty_can_id"] and identity.is_empty(): return field
		if not identity.is_empty():
			if seen.has(identity): return field
			seen[identity] = true
	if not VehicleSnapshot._number(value.fuel_amount) or value.fuel_amount < 0.0: return "fuel_amount"
	if not value.configured and value.fuel_amount != 0.0: return "fuel_amount"
	if value.flags.wheel and not value.flags.removed: return "flags.wheel"
	if value.flags.refueled and (value.fuel_amount <= 0.0 or value.fuel_can_id.is_empty() or value.empty_can_id.is_empty()): return "flags.refueled"
	return ""

static func workshop_error(value: Variant) -> String:
	if not value is Dictionary: return "state"
	var fields := ["version", "targets", "flags", "placed_ids", "unmounted_ids", "recycled_ids", "output_ids", "gasoline_id"]
	if value.size() != fields.size() or not value.has_all(fields): return "fields"
	if not value.version is int or value.version != 1: return "version"
	var target_fields := ["battery", "original_battery", "socket", "tablet", "scrapper", "workbench", "scrap_a", "scrap_b", "barrel"]
	var targets: Variant = value.targets
	if not targets is Dictionary or targets.size() != target_fields.size() or not targets.has_all(target_fields): return "targets"
	for key in target_fields:
		if not targets[key] is String or targets[key].is_empty(): return "targets." + key
	var flag_fields := ["battery", "overview", "energy", "equipment", "lights_off", "lights_on", "cancelled", "scrapper_placed", "workbench_placed", "remounted"]
	var flags: Variant = value.flags
	if not flags is Dictionary or flags.size() != flag_fields.size() or not flags.has_all(flag_fields): return "flags"
	for key in flag_fields:
		if not flags[key] is bool: return "flags." + key
	for key in ["placed_ids", "unmounted_ids", "recycled_ids", "output_ids"]:
		var identities: Variant = value[key]
		var maximum := 64 if key == "output_ids" else (3 if key == "recycled_ids" else 2)
		if not identities is Array or identities.size() > maximum: return key
		var allowed: Array = [targets.scrap_a, targets.scrap_b, targets.barrel] if key == "recycled_ids" else [targets.scrapper, targets.workbench]
		var seen: Dictionary = {}
		for identity in identities:
			if not identity is String or identity.is_empty() or seen.has(identity): return key
			if key == "output_ids":
				if identity in targets.values(): return key
			elif identity not in allowed: return key
			seen[identity] = true
	if not value.gasoline_id is String or (not value.gasoline_id.is_empty() and value.gasoline_id not in value.output_ids): return "gasoline_id"
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
		var content_error := _bunker_content_error(entry)
		if not content_error.is_empty(): return prefix + "." + content_error
		for i in range(entry.actors.size()):
			var actor_error := WorldActorSnapshot.validation_error(entry.actors[i], prefix + ".actors[%d]" % i)
			if not actor_error.is_empty(): return actor_error
		var graph_error := WorldActorSnapshot.graph_error(entry.actors)
		if not graph_error.is_empty(): return prefix + "." + graph_error
		if not ItemState.unique_ids(entry, {}): return prefix + ".duplicate_id"
	return ""

static func _bunker_content_error(entry: Dictionary) -> String:
	# Content-free v3 saves remain valid and never receive newly rolled supplies.
	if not entry.has("content"):
		return "missing_content" if entry.has("caches") else ""
	var content: Variant = entry.content
	if not content is Dictionary or content.get("version") != 1 or not content.get("version") is int: return "content.version"
	if not content.get("cargo_id") is String or not content.get("cargo_room") is String: return "content.cargo"
	var room_exists := false
	for room: Dictionary in entry.layout.rooms:
		if room.id == content.cargo_room: room_exists = true
	if content.cargo_id.is_empty() != content.cargo_room.is_empty() or (not content.cargo_id.is_empty() and not room_exists): return "content.room"
	var caches: Variant = entry.get("caches", [])
	if not caches is Array or caches.size() > 60: return "caches"
	var seen: Dictionary = {}
	for cache in caches:
		if not cache is Dictionary or not cache.get("id") is String or cache.id.is_empty() or seen.has(cache.id): return "cache.id"
		seen[cache.id] = true
		if not valid_transform(cache.get("transform")) or not cache.get("searched") is bool or not cache.get("remaining") is Array or cache.remaining.size() > PlayerInventory.MAX_SLOTS: return "cache.state"
		for item in cache.remaining:
			if not item is Dictionary or SaveSceneCatalog.resolve(item.get("scene"), "item") == null or not item.get("name") is String or not item.get("large") is bool: return "cache.item"
			if not item.get("state") is Dictionary or not VehicleSnapshot.valid_prop_state(item.scene, item.state): return "cache.item_state"
			if not item.state.get("id") is String or item.state.id.is_empty(): return "cache.item_id"
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

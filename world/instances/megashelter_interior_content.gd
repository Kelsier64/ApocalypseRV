extends RefCounted
class_name MegashelterInteriorContent
## Sparse abandoned supplies are created once; revisits restore their exact state.
const VERSION := 1
const CACHE: PackedScene = preload("res://world/instances/bunker_cache.tscn")

static func populate(inside: Node3D) -> Dictionary:
	var scope := "%s:%d" % [inside.instance_id, int(inside.layout.seed)]
	var prefix := "megashelter:%s:" % scope
	var supplies := RandomNumberGenerator.new()
	supplies.seed = ("megashelter-supplies-v1:" + scope).sha256_text().substr(0, 15).hex_to_int()
	var positions := RandomNumberGenerator.new()
	positions.seed = ("megashelter-positions-v1:" + scope).sha256_text().substr(0, 15).hex_to_int()
	var eligible: Array[int] = []
	var area := 0.0
	for i in inside.rooms.size():
		var definition := InteriorLayout.definition(inside.layout, i, inside.profile)
		if definition.role != &"ordinary" or definition.selection_group in [&"hall", &"passage", &"corridor"]: continue
		var footprint: Vector2 = inside.rooms[i].footprint
		area += footprint.x * footprint.y
		eligible.append(i)
	# Shuffle with our own stream, independently of layout and global randomness.
	for i in range(eligible.size() - 1, 0, -1):
		var j := positions.randi_range(0, i)
		var swap := eligible[i]
		eligible[i] = eligible[j]
		eligible[j] = swap
	var reserved: Array[Vector3] = []
	# A single chest, with one food item and one small scrap opportunity.
	for index in eligible:
		var location := BunkerContent._position(inside, index, positions, reserved)
		if location.is_empty(): continue
		var cache := CACHE.instantiate() as BunkerCache
		cache.cache_id = prefix + "cache:0"
		cache.remaining.append(_supply(supplies, cache.cache_id + ":item:0", true))
		cache.remaining.append(_supply(supplies, cache.cache_id + ":item:1", false))
		inside.navigation.add_child(cache)
		cache.global_position = location.point
		inside.caches.append(cache)
		break
	var loose_budget := clampi(roundi(area / 120.0), 2, 4)
	var loose_count := 0
	# Multiple passes support compact layouts with only three functional rooms.
	for _pass_index in loose_budget:
		for index in eligible:
			if loose_count >= loose_budget: break
			var location := BunkerContent._position(inside, index, positions, reserved)
			if location.is_empty(): continue
			var entry := _supply(supplies, prefix + "supply:%d" % loose_count, loose_count % 2 == 0)
			var item := load(entry.scene).instantiate() as Item
			item.freeze = true
			inside.entities.add_child(item)
			item.restore_item_state(entry.state)
			item.item_name = entry.name
			item.global_position = location.point + Vector3.UP * (-item.get_placement_bounds().position.y + 0.02)
			loose_count += 1
		if loose_count >= loose_budget: break
	return {"version": VERSION, "cargo_id": "", "cargo_room": ""}

static func _supply(rng: RandomNumberGenerator, identity: String, food: bool) -> Dictionary:
	if food:
		var scene: String = FoodCatalog.SCENES[rng.randi_range(0, FoodCatalog.SCENES.size() - 1)]
		var definition := FoodCatalog.definition_for(scene)
		return {"scene": scene, "name": definition.display_name, "large": false,
			"state": {"id": identity, "condition": 100.0, "scrap_yields": definition.scrap_yields.duplicate(true), "recycle_result": {}}}
	var scene := ScavengeLoot.scene_for(identity)
	var metal := rng.randi_range(1, 3)
	return {"scene": scene, "name": ScavengeLoot.item_name(scene), "large": false,
		"state": {"id": identity, "condition": 100.0, "scrap_yields": {"Metal Parts": Vector2(metal, metal)}, "recycle_result": {}}}

static func validate_content(entry: Dictionary) -> String:
	# Shared cache/item validation does not dispatch back through poi_error.
	var error := CheckpointSchema._bunker_content_error(entry)
	if not error.is_empty(): return error
	if not entry.content.cargo_id.is_empty() or not entry.content.cargo_room.is_empty(): return "content.cargo"
	if entry.caches.size() > 1: return "caches"
	for cache: Dictionary in entry.caches:
		if cache.remaining.size() > 2: return "cache.remaining"
	for actor in entry.get("actors", []):
		if actor is Dictionary and actor.get("kind") == "monster": return "actors.monster"
	return ""

static func reachable(inside: Node3D, first_visit := true) -> bool:
	var map := inside.get_world_3d().navigation_map
	var start: Vector3 = inside.navigation_anchor(0)
	var targets: Array[Vector3] = []
	for cache in inside.caches: targets.append(cache.global_position)
	# Restored player drops can legitimately be off the floor navigation mesh.
	if first_visit:
		for actor in inside.entities.get_children():
			if actor is Item: targets.append(actor.global_position)
	for target in targets:
		var nearest := NavigationServer3D.map_get_closest_point(map, target)
		if nearest.distance_to(target) > 1.5: return false
		var path := NavigationServer3D.map_get_path(map, start, nearest, true)
		if path.size() < 2 or path[-1].distance_to(nearest) > 0.5: return false
	return true

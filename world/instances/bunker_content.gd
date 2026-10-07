extends RefCounted
class_name BunkerContent
## Initial content is rolled once using its own RNG, then only snapshots are restored.
const VERSION := 1
const SCRAP: PackedScene = preload("res://props/scrap.tscn")
const CARGO: PackedScene = preload("res://props/engine_upgraded.tscn")
const CACHE: PackedScene = preload("res://world/instances/bunker_cache.tscn")
const ENCOUNTER_CHANCE := 0.3
# Add entries here to introduce new bunker species; the weights only select
# among the species after an encounter opportunity succeeds its chance roll.
const ENEMY_TYPES := [
	{"scene": preload("res://enemies/raker.tscn"), "weight": 1},
]

static func populate(inside: Node3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(inside.layout.seed) ^ 0x4b554e4b
	var species := RandomNumberGenerator.new()
	species.seed = int(inside.layout.seed) ^ 0x42415252
	var scope: String = inside.instance_id if not inside.instance_id.is_empty() else "seed:%d" % inside.layout.seed
	var prefix := "bunker:%s:" % scope
	var distances := InteriorLayout.distances(inside.layout)
	var eligible: Array[int] = []
	for i in range(1, inside.rooms.size()):
		var definition := InteriorLayout.definition(inside.layout, i)
		if definition.role == &"ordinary" and definition.describe().bounds.size.x >= 5.0 and definition.describe().bounds.size.z >= 5.0:
			eligible.append(i)
	eligible.sort_custom(func(a: int, b: int) -> bool: return distances[a] > distances[b])
	var reserved: Array[Vector3] = []
	var result := {"version": VERSION, "cargo_id": "", "cargo_room": ""}
	# Prefer the most distant usable room, measured along the connection graph.
	for i in eligible:
		var position := _position(inside, i, rng, reserved)
		if position.is_empty(): continue
		var cargo := CARGO.instantiate() as Item
		var identity := prefix + "cargo"
		cargo.restore_item_state({"id": identity, "engine": {"id": identity, "model": "upgraded", "health": EngineState.definition_for("upgraded").max_health * 0.7}})
		cargo.position = position.point + Vector3.UP * 0.45
		cargo.freeze = true
		cargo.set_meta("bunker_actor_id", identity)
		inside.entities.add_child(cargo)
		result.cargo_id = identity
		result.cargo_room = inside.layout.rooms[i].id
		break
	# Sparse supplies leave room for return trips and future content variants.
	var loose_budget := clampi(inside.rooms.size() / 5, 2, 12)
	var cache_budget := clampi(inside.rooms.size() / 12, 1, 5)
	var enemy_opportunities := clampi(inside.rooms.size() / 15, 1, 4)
	var loose_count := 0
	var cache_count := 0
	var enemy_count := 0
	var enemy_rolls := 0
	# Shuffle only with the content RNG; global AI randomness never changes layout/loot.
	var order := eligible.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	for i in order:
		if cache_count < cache_budget:
			var location := _position(inside, i, rng, reserved)
			if not location.is_empty():
				var cache = CACHE.instantiate()
				cache.cache_id = prefix + "cache:%d" % cache_count
				cache.position = location.point
				for item_index in 2:
					cache.remaining.append(_supply(rng, cache.cache_id + ":item:%d" % item_index, true))
				inside.navigation.add_child(cache)
				inside.caches.append(cache)
				cache_count += 1
		if loose_count < loose_budget:
			var location := _position(inside, i, rng, reserved)
			if not location.is_empty():
				var item := _supply(rng, prefix + "supply:%d" % loose_count, false)
				var prop := SCRAP.instantiate() as Item
				prop.restore_item_state(item.state)
				prop.item_name = item.name
				prop.position = location.point + Vector3.UP * 0.35
				prop.freeze = true
				inside.entities.add_child(prop)
				loose_count += 1
		# Entry and the nearest rooms are safe from initial enemy spawns.
		if enemy_rolls < enemy_opportunities and distances[i] >= 24.0:
			# Each suitable room supplies at most one independent encounter roll.
			# A successful roll may still be skipped when there is no safe position.
			enemy_rolls += 1
			if rng.randf() < ENCOUNTER_CHANCE:
				var location := _position(inside, i, rng, reserved)
				if not location.is_empty() and location.point.distance_to(inside.spawn_transform().origin) >= 18.0:
					# Preserve the original selector's RNG draw so later loot and
					# positions stay identical; species uses a separate stream.
					var scene := _choose_enemy_scene(rng)
					if species.randf() < BarrelManSettings.BUNKER_CHANCE: scene = load(RoadSpawns.BARREL_MAN_SCENE)
					if scene != null:
						var enemy := scene.instantiate() as Monster
						configure_monster(enemy)
						enemy.process_mode = Node.PROCESS_MODE_DISABLED
						enemy.position = location.point
						enemy.set_meta("bunker_actor_id", prefix + "enemy:%d" % enemy_count)
						inside.entities.add_child(enemy)
						enemy_count += 1
	return result

static func _choose_enemy_scene(rng: RandomNumberGenerator) -> PackedScene:
	var total := 0
	for entry: Dictionary in ENEMY_TYPES: total += maxi(0, int(entry.weight))
	if total <= 0: return null
	var roll := rng.randi_range(1, total)
	for entry: Dictionary in ENEMY_TYPES:
		roll -= maxi(0, int(entry.weight))
		if roll <= 0: return entry.scene
	return null

static func _supply(rng: RandomNumberGenerator, identity: String, rich: bool) -> Dictionary:
	var metal := rng.randi_range(2, 4) if rich else rng.randi_range(1, 3)
	var electronics := rng.randi_range(1, 2) if rich else 0
	var yields := {"Metal Parts": Vector2(metal, metal)}
	if electronics > 0: yields["Electronic Scrap"] = Vector2(electronics, electronics)
	return {"scene": "res://props/scrap.tscn", "name": "地堡備用零件" if rich else "地堡廢料", "large": false,
		"state": {"id": identity, "condition": 100.0, "scrap_yields": yields, "recycle_result": {}}}

static func configure_monster(enemy: Monster) -> void:
	if enemy is BarrelMan: return
	enemy.detection_range = 10.0
	enemy.lose_interest_range = 16.0
	enemy.wander_min_distance = 2.0
	enemy.wander_max_distance = 4.0

static func _position(inside: Node3D, index: int, rng: RandomNumberGenerator, reserved: Array[Vector3]) -> Dictionary:
	var room: PoiRoom = inside.rooms[index]
	var points: Array[Vector3] = []
	# Derive candidate locations from the actual footprint, including future sizes.
	var half := room.footprint * 0.5 - Vector2.ONE * 1.2
	var x := -half.x
	while x <= half.x:
		var z := -half.y
		while z <= half.y:
			var point := Vector3(x, 0.0, z)
			if point.length() >= 1.5 and _clear_of_doors(room, point): points.append(room.to_global(point))
			z += 1.5
		x += 1.5
	var shape := CapsuleShape3D.new()
	shape.radius = 0.85
	shape.height = 2.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var map := inside.get_world_3d().navigation_map
	var space := inside.get_world_3d().direct_space_state
	while not points.is_empty():
		var pick := rng.randi_range(0, points.size() - 1)
		var point := points[pick]
		points.remove_at(pick)
		if reserved.any(func(other: Vector3) -> bool: return absf(other.y - point.y) < 2.5 and Vector2(other.x - point.x, other.z - point.z).length() < 2.1): continue
		var nav_point := NavigationServer3D.map_get_closest_point(map, point)
		# Recast voxelization raises this project's flat-floor mesh by 0.5 m.
		# Check planar alignment separately so supplies stay on the real floor.
		if absf(nav_point.y - point.y) > 0.65 or Vector2(nav_point.x - point.x, nav_point.z - point.z).length() > 0.3: continue
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 1.25)
		if not space.intersect_shape(query, 1).is_empty(): continue
		reserved.append(point)
		return {"point": point}
	return {}

static func _clear_of_doors(room: PoiRoom, point: Vector3) -> bool:
	for socket: PoiDoorSocket in room.get_node("DoorSockets").get_children():
		var local := room.socket_transform(socket).affine_inverse() * point
		if absf(local.x) < socket.opening.x / 2.0 + 0.7 and local.z > -0.3 and local.z < 2.8: return false
	return true

static func reachable(inside: Node3D, check_cargo := true) -> bool:
	var map := inside.get_world_3d().navigation_map
	var start: Vector3 = inside.navigation_anchor(0)
	var targets: Array[Vector3] = []
	for cache in inside.caches: targets.append(cache.global_position)
	if check_cargo:
		for actor in inside.entities.get_children():
			if actor is Item and actor.persistent_id == inside.content.get("cargo_id", ""): targets.append(actor.global_position)
	for target in targets:
		var nearest := NavigationServer3D.map_get_closest_point(map, target)
		if nearest.distance_to(target) > 1.5: return false
		var path := NavigationServer3D.map_get_path(map, start, nearest, true)
		if path.size() < 2 or path[-1].distance_to(nearest) > 0.5: return false
	return true

static func objective_text(inside: Node3D, player: Node3D) -> String:
	var identity: String = inside.content.get("cargo_id", "")
	if identity.is_empty(): return "搜尋補給箱與零件，返回 B1 ENTRY 離開"
	for item: Dictionary in player.inventory.items:
		if item.get("state", {}).get("id", "") == identity: return "已攜帶強化引擎：返回 B1 ENTRY 帶回 RV"
	for actor in inside.entities.get_children():
		if actor is Item and not actor.is_queued_for_deletion() and actor.persistent_id == identity:
			var floor_number := 1
			for room: Dictionary in inside.layout.rooms:
				if room.id == inside.content.cargo_room: floor_number = 1 + roundi(-room.transform.origin.y / inside.layout.floor_spacing)
			return "回收目標：B%d / %s 強化引擎｜補給箱長按 E 搜尋" % [floor_number, str(inside.content.cargo_room).to_upper()]
	return "強化引擎已移出地堡｜剩餘物資不會補充"

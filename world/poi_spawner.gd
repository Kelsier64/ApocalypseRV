extends RefCounted
class_name POISpawner

var _scene_cache: Dictionary = {}


func pick_poi() -> Dictionary:
	var total := 0
	for entry in POIConfig.POI_TABLE:
		total += entry["weight"]
	var roll := randi_range(0, total - 1)
	var acc := 0
	for entry in POIConfig.POI_TABLE:
		acc += entry["weight"]
		if roll < acc:
			return entry
	return POIConfig.POI_TABLE[-1]


func spawn_building(poi: Dictionary, parent_node: Node3D, local_pos: Vector3) -> Node3D:
	var building: Node3D = null

	if poi["type"] == "procedural":
		building = _create_procedural(poi)
	else:
		building = _create_gridmap(poi)

	if building:
		building.position = local_pos
		building.rotation.y = randf_range(0, TAU)
		parent_node.add_child(building)
	return building


func spawn_loot(poi: Dictionary, parent_node: Node3D, center: Vector3) -> void:
	var loot_cfg: Dictionary = poi.get("loot", {})
	if loot_cfg.is_empty():
		return

	var count_range: Vector2i = loot_cfg.get("count", Vector2i(1, 3))
	var radius: float = loot_cfg.get("radius", 4.0)
	var table: Array = loot_cfg.get("table", [])
	if table.is_empty():
		return

	var num_items := randi_range(count_range.x, count_range.y)
	for i in num_items:
		var scene_path := _pick_from_loot_table(table)
		var scene := _load_cached(scene_path)
		if not scene:
			continue
		var item := scene.instantiate()
		item.position = Vector3(
			center.x + randf_range(-radius, radius),
			center.y + 1.0,
			center.z + randf_range(-radius, radius),
		)
		parent_node.add_child(item)


func spawn_enemies(poi: Dictionary, parent_node: Node3D, center: Vector3,
		get_height: Callable) -> void:
	var enemy_cfg: Dictionary = poi.get("enemies", {})
	if enemy_cfg.is_empty():
		return

	var count_range: Vector2i = enemy_cfg.get("count", Vector2i(1, 3))
	var radius: float = enemy_cfg.get("radius", 15.0)
	var scene_path: String = enemy_cfg.get("scene", "res://enemies/zombie.tscn")

	var scene := _load_cached(scene_path)
	if not scene:
		return

	var num := randi_range(count_range.x, count_range.y)
	for i in range(num):
		var enemy := scene.instantiate()
		var local_x := center.x + randf_range(-radius, radius)
		var local_z := center.z + randf_range(-radius, radius)
		var local_y: float = get_height.call(local_x, local_z) + 2.0
		enemy.position = Vector3(local_x, local_y, local_z)
		parent_node.add_child(enemy)


# --- Internal ---

func _create_gridmap(poi: Dictionary) -> Node3D:
	var scene := _load_cached(poi["scene"])
	if not scene:
		push_warning("POISpawner: Failed to load " + poi["scene"])
		return null
	return scene.instantiate()


func _create_procedural(poi: Dictionary) -> Node3D:
	var script := load("res://world/building/building_generator.gd")
	if not script:
		return null
	var building := Node3D.new()
	building.set_script(script)
	building.name = "ProceduralBuilding"
	var cfg: Dictionary = poi.get("procedural_config", {})
	building.set("max_rooms", randi_range(
		cfg.get("min_rooms", 10),
		cfg.get("max_rooms", 20)
	))
	return building


func _pick_from_loot_table(table: Array) -> String:
	var total := 0.0
	for entry in table:
		total += entry["weight"]
	var roll := randf() * total
	var acc := 0.0
	for entry in table:
		acc += entry["weight"]
		if roll < acc:
			return entry["scene"]
	return table[-1]["scene"]


func _load_cached(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scene_cache.has(path):
		return _scene_cache[path]
	var scene := load(path) as PackedScene
	if scene:
		_scene_cache[path] = scene
	return scene

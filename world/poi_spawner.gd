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


func spawn_loot(poi: Dictionary, parent_node: Node3D, center: Vector3, building: Node3D = null) -> void:
	var loot_cfg: Dictionary = poi.get("loot", {})
	if loot_cfg.is_empty():
		return

	var count_range: Vector2i = loot_cfg.get("count", Vector2i(1, 3))
	var radius: float = loot_cfg.get("radius", 4.0)
	var table: Array = loot_cfg.get("table", [])
	if table.is_empty():
		return

	var spawn_points: Array[Marker3D] = _collect_loot_spawn_points(building)

	var num_items := randi_range(count_range.x, count_range.y)
	for i in range(num_items):
		var scene_path := _pick_from_loot_table(table)
		var scene := _load_cached(scene_path)
		if not scene:
			continue
		var item := scene.instantiate()
		if i < spawn_points.size():
			parent_node.add_child(item)
			item.global_transform = spawn_points[i].global_transform
		else:
			item.position = Vector3(
				center.x + randf_range(-radius, radius),
				center.y + 1.0,
				center.z + randf_range(-radius, radius),
			)
			parent_node.add_child(item)
		if i < spawn_points.size() and item is RigidBody3D:
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO


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


func _collect_loot_spawn_points(building: Node3D) -> Array[Marker3D]:
	var result: Array[Marker3D] = []
	if building == null:
		return result

	for loot_spawns_root in _find_nodes_named(building, "LootSpawns"):
		for child in loot_spawns_root.get_children():
			if child is Marker3D:
				result.append(child)

	if result.is_empty():
		for marker in _find_markers_recursive(building):
			if marker.name.begins_with("LootSpawn"):
				result.append(marker)

	result.shuffle()
	return result


func _find_nodes_named(root: Node, target_name: String) -> Array[Node]:
	var nodes: Array[Node] = []
	for child in root.get_children():
		if child.name == target_name:
			nodes.append(child)
		nodes.append_array(_find_nodes_named(child, target_name))
	return nodes


func _find_markers_recursive(root: Node) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for child in root.get_children():
		if child is Marker3D:
			markers.append(child)
		markers.append_array(_find_markers_recursive(child))
	return markers

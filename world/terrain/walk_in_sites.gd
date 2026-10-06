extends RefCounted
class_name WalkInSites
## Generation v5+: roadside forecourt, authored footprint and dormant loose actors.
static func configure(site: Dictionary, definition_id: String = "gas_station") -> void:
	for key in ["route", "deep_forest", "mirror", "exterior"]: site.erase(key)
	site.kind = "walk_in"
	site.definition_id = definition_id
	var definition := POIConfig.definition(StringName(definition_id))
	site.title = definition.display_name
	var side: float = site.side
	# Front (+Z) faces the road. The RV parks across the open forecourt.
	site.building = Transform3D(Basis.looking_at(site.road.basis.x * side), site.road * Vector3(side * 49, 0, 0))
	site.frame = Transform3D(site.road.basis, site.road * Vector3(side * 33, 0, 0))
	site.bounds = (site.building * definition.site_bounds).grow(5.0)
	site.bounds = site.bounds.expand(site.road * Vector3(side * 8, -3, -23))
	site.bounds = site.bounds.expand(site.road * Vector3(side * 8, 12, 23))
	site.walls = []
	site.landmark = site.building * Vector3(-14, 8, 13)

static func court_distance(point: Vector3, site: Dictionary) -> float:
	var local: Vector3 = site.building.affine_inverse() * point
	var bounds: AABB = POIConfig.definition(site.definition_id).site_bounds
	# Three metres beyond the asset specification support rear/side circulation.
	var center := bounds.get_center()
	var q := Vector2(absf(local.x - center.x) - bounds.size.x * 0.5 - 3, absf(local.z - center.z) - bounds.size.z * 0.5 - 3)
	var yard := Vector2(maxf(q.x, 0), maxf(q.y, 0)).length()
	var road_local: Vector3 = site.road.affine_inverse() * point
	var drive := Vector2(absf(road_local.x - float(site.side) * 16.5) - 16.5, absf(road_local.z) - 20)
	return minf(yard, Vector2(maxf(drive.x, 0), maxf(drive.y, 0)).length())

static func activate(generator: Node, site: Dictionary, chunk: Node) -> void:
	var container := WorldEntities.get_container(generator)
	if generator.outdoor_sites.has(site.id):
		var saved: Dictionary = generator.outdoor_sites[site.id]
		if saved.loaded: return
		var restored: Array = []
		for actor in saved.actors: restored.append(WorldActorSnapshot.restore(actor, container))
		WorldActorSnapshot.restore_supports(saved.actors, restored, WorldActorSnapshot.domain(generator))
		saved.actors = []
		saved.loaded = true
		return
	var definition := POIConfig.definition_for_site(site)
	var building: Node3D
	for child in chunk.get_children():
		if child.get_meta("poi_id", "") == site.id: building = child
	if building == null: return
	if definition.definition_id == &"starting_shelter":
		_spawn_starter_actors(building, container)
	var rng: RandomNumberGenerator = generator.field.rng_for(site.index, "minor_loot" if site.get("minor", false) else "walk_in_loot")
	for point in building.find_children("*", "Marker3D", true, false):
		if definition.definition_id == &"starting_shelter": continue
		if not point is PoiLootPoint: continue
		var scene: PackedScene = point.roll_scene(rng)
		if scene == null: continue
		var item: Item = scene.instantiate()
		container.add_child(item)
		item.global_transform = point.global_transform
	if definition.enemy_count_range.y > 0:
		var enemies: RandomNumberGenerator = generator.field.rng_for(site.index, "minor_enemies")
		var points := building.get_node("EnemySpawns").get_children()
		var count := enemies.randi_range(definition.enemy_count_range.x, definition.enemy_count_range.y)
		for i in range(count):
			var selected := enemies.randi_range(0, points.size() - 1)
			var point: Marker3D = points.pop_at(selected)
			var monster: Node3D = preload("res://enemies/raker.tscn").instantiate()
			container.add_child(monster)
			monster.global_transform = point.global_transform
	generator.outdoor_sites[site.id] = {"definition_id": str(definition.definition_id), "content_version": definition.content_version, "loaded": true, "actors": []}

## The authored opening has a fixed inventory. Markers carry placement only;
## loose actors use the same owner/snapshot lifecycle as every other walk-in.
static func _spawn_starter_actors(building: Node3D, container: Node) -> void:
	var scenes := {
		"StarterEquipment/Generator": "res://equipment/generator.tscn",
		"StarterEquipment/CraftingStation": "res://equipment/crafting_station.tscn",
		"StarterEquipment/Scrapper": "res://equipment/scrapper.tscn",
		"StarterLoot/Flashlight": "res://props/flashlight.tscn",
		"StarterLoot/Battery": "res://props/battery.tscn",
		"StarterLoot/GasCan1": "res://props/gas_can.tscn",
		"StarterLoot/GasCan2": "res://props/gas_can.tscn",
		"StarterLoot/OilBarrel": "res://props/oil_barrel.tscn",
		"StarterLoot/Wheel": "res://props/wheel.tscn",
	}
	for i in range(1, 7): scenes["StarterLoot/Scrap%d" % i] = "res://props/scrap.tscn"
	for path in scenes:
		var point := building.get_node_or_null(NodePath(path)) as Marker3D
		if point == null:
			push_error("Starting shelter is missing marker: " + path)
			continue
		var actor: Node3D = load(scenes[path]).instantiate()
		container.add_child(actor)
		actor.global_transform = point.global_transform
		if actor is Item:
			actor.freeze = true
			actor.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC

static func deactivate(generator: Node, site: Dictionary) -> void:
	if not generator.outdoor_sites.has(site.id): return
	var saved: Dictionary = generator.outdoor_sites[site.id]
	if not saved.loaded: return
	saved.actors = []
	# Spatial ownership includes items brought here and dropped by the player.
	# Mounted equipment/vehicle cargo remain owned by their vehicle.
	var container := WorldEntities.get_container(generator)
	var retiring: Array[Node] = []
	for actor in container.get_children() + generator.get_parent().get_children():
		if not actor is Node3D or not site.bounds.has_point(actor.global_position): continue
		var snapshot := WorldActorSnapshot.capture(actor)
		if snapshot.is_empty(): continue
		saved.actors.append(snapshot)
		retiring.append(actor)
	for actor in retiring:
		if actor is Item: actor.begin_world_transfer()
	for actor in retiring: actor.free()
	saved.loaded = false

static func validation_error(data: Dictionary) -> String:
	var sites: Variant = data.get("outdoor_sites", {})
	var bands: Variant = data.get("generated_bands", [])
	if data.get("generation_version", 2) >= 5 and not data.has_all(["outdoor_sites", "generated_bands"]): return "outdoor_sites.missing"
	if not sites is Dictionary: return "outdoor_sites"
	if not bands is Array: return "generated_bands"
	var seen := {}
	for band in bands:
		if not band is int or seen.has(band): return "generated_bands"
		seen[band] = true
	for id in sites:
		var entry: Variant = sites[id]
		if not id is String or not entry is Dictionary: return "outdoor_sites.id"
		if not entry.get("definition_id") is String: return "outdoor_sites.definition"
		var definition := POIConfig.definition(StringName(entry.get("definition_id", "")))
		if definition == null or definition.kind != PoiDefinition.Kind.WALK_IN: return "outdoor_sites.definition"
		if not entry.get("content_version") is int or entry.content_version != definition.content_version: return "outdoor_sites.content_version"
		if not entry.get("loaded") is bool or not entry.get("actors") is Array: return "outdoor_sites.actors"
		if entry.loaded and not entry.actors.is_empty(): return "outdoor_sites.loaded"
		for actor in entry.actors:
			var error := WorldActorSnapshot.validation_error(actor, "outdoor_sites.actor")
			if not error.is_empty(): return error
		var graph_error := WorldActorSnapshot.graph_error(entry.actors)
		if not graph_error.is_empty(): return "outdoor_sites." + graph_error
	return ""

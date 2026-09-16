extends RefCounted
class_name POISpawner
## Exterior transform and stable identity come from the shared world plan.
func pick_poi() -> Dictionary:
	return POIConfig.POI_TABLE[0]

func spawn_site(site: Dictionary, parent_node: Node3D) -> Node3D:
	var path := "res://world/poi_kit/exteriors/%s.tscn" % site.exterior if site.has("exterior") else str(pick_poi().scene)
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var building := scene.instantiate() as Node3D
	building.set_meta("poi_title", site.get("title", "MAINTENANCE"))
	building.transform = site.building
	parent_node.add_child(building)
	var ancestor: Node = parent_node
	var manager: PoiInstanceManager
	while ancestor != null and manager == null:
		manager = ancestor.get_node_or_null("PoiInstances") as PoiInstanceManager
		ancestor = ancestor.get_parent()
	if manager != null:
		manager.register_entrance(building, int(site.seed), str(site.id))
	return building

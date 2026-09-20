extends RefCounted
class_name POISpawner
## Exterior transform and stable identity come from the shared world plan.
func spawn_site(site: Dictionary, parent_node: Node3D) -> Node3D:
	var definition := POIConfig.definition_for_site(site)
	if definition == null:
		push_warning("Unknown POI definition: " + str(site.get("definition_id", site.get("exterior", ""))))
		return null
	var errors := definition.validate()
	if not errors.is_empty():
		push_warning("Invalid POI %s: %s" % [definition.definition_id, errors])
		return null
	if definition.kind == PoiDefinition.Kind.INSTANCE_ENTRANCE and not POIConfig.supported_interior(definition.interior_profile):
		push_warning("Unsupported POI interior profile: " + str(definition.interior_profile))
		return null
	var scene := POIConfig.scene_for_site(site)
	if scene == null:
		return null
	var instance := scene.instantiate()
	var building := instance as Node3D
	if building == null:
		instance.free()
		push_warning("POI scene root must be Node3D: " + definition.scene_path)
		return null
	errors = definition.validate_scene(building)
	if not errors.is_empty():
		push_warning("Invalid POI scene %s: %s" % [definition.definition_id, errors])
		building.free()
		return null
	building.set_meta("poi_definition_id", definition.definition_id)
	building.set_meta("poi_content_version", definition.content_version)
	building.set_meta("poi_title", site.get("title", definition.display_name))
	building.set_meta("poi_id", str(site.id))
	building.set_meta("poi_seed", int(site.seed))
	building.set_meta("poi_interior_profile", definition.interior_profile)
	building.set_meta("poi_entrance_path", definition.entrance_path)
	building.set_meta("poi_return_path", definition.return_path)
	building.transform = site.building
	parent_node.add_child(building)
	var ancestor: Node = parent_node
	var manager: PoiInstanceManager
	while ancestor != null and manager == null:
		manager = ancestor.get_node_or_null("PoiInstances") as PoiInstanceManager
		ancestor = ancestor.get_parent()
	if manager != null and definition.kind == PoiDefinition.Kind.INSTANCE_ENTRANCE:
		manager.register_entrance(building, int(site.seed), str(site.id))
	return building

extends RefCounted
class_name POISpawner
## Exterior transform and stable identity come from the shared world plan.
func spawn_site(site: Dictionary, parent_node: Node3D, include_visuals: bool = true) -> Node3D:
	var definition := POIConfig.definition_for_site(site)
	if definition == null:
		push_warning("Unknown POI definition: " + str(site.get("definition_id", site.get("exterior", ""))))
		return null
	var placement: String = site.get("placement", "roadside")
	if placement not in ["roadside", "off_road"]:
		push_warning("Unknown POI placement: " + placement)
		return null
	var mode := PoiDefinition.Placement.OFF_ROAD if placement == "off_road" else PoiDefinition.Placement.ROADSIDE
	if not definition.supports_placement(mode):
		push_warning("POI does not support placement: " + str(definition.definition_id))
		return null
	var errors := definition.validate()
	if not errors.is_empty():
		push_warning("Invalid POI %s: %s" % [definition.definition_id, errors])
		return null
	if definition.kind == PoiDefinition.Kind.INSTANCE_ENTRANCE and not POIConfig.supported_interior(definition.interior_profile):
		push_warning("Unsupported POI interior profile: " + str(definition.interior_profile))
		return null
	var building := POIConfig.instantiate_site(site, include_visuals)
	if building == null:
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

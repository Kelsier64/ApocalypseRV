@tool
extends Node3D
## Basic bunker entrance dress on the existing footprint and transition markers.
@export_enum("maintenance", "warehouse", "pump", "research") var exterior: String = "maintenance"
func _ready() -> void:
	if has_node("Visuals/BunkerFacade"): return
	for sign_node in find_children("*", "Label3D", true, false): sign_node.visible = false
	for mesh in get_node("Visuals").get_children():
		if mesh is MeshInstance3D:
			mesh.material_override = preload("res://world/poi_kit/materials/bunker/concrete.tres")
	var art := Node3D.new()
	art.name = "BunkerFacade"
	get_node("Visuals").add_child(art)
	# Decorative reinforcement stays outside the door and within the old shell footprint.
	for x in [-3.7,3.7]:
		RoadsideKit.part(art,Vector3(0.7,4.8,0.5),Vector3(x,2.4,4.55),Color("55594e"))
	RoadsideKit.part(art,Vector3(9.3,0.45,9.3),Vector3(0,5.5,0),Color("55594e"))
	for x in [-1.65,1.65]:
		RoadsideKit.part(art,Vector3(0.18,3.6,0.3),Vector3(x,1.8,4.7),Color("272f28"))
	RoadsideKit.part(art,Vector3(3.4,0.18,0.3),Vector3(0,3.5,4.7),Color("272f28"))
	var leaf := get_node_or_null("Visuals/DoorVisual") as MeshInstance3D
	if leaf != null: leaf.material_override = preload("res://world/poi_kit/materials/bunker/steel.tres")
	RoadsideKit.part(art,Vector3(3.3,0.65,0.08),Vector3(0,4.25,4.7),Color("252c24"))
	var index := maxi(0, ExplorationSite.TYPES.find(exterior))
	RoadsideKit.label(art,"BUNKER / %02d" % (index+1),Vector3(0,4.25,4.76),20)
	RoadsideKit.label(art,"MILITARY RESERVE\nAUTHORIZED ACCESS",Vector3(0,3.0,4.9),10)
	for x in [-4.1,4.1]:
		RoadsideKit.part(art,Vector3(0.12,4.2,0.15),Vector3(x,2.1,4.68),Color("474d3d"))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0,3.7,5.1)
	lamp.light_color = Color("e1d6a8")
	lamp.light_energy = 1.6
	lamp.omni_range = 7
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 28
	lamp.distance_fade_length = 12
	art.add_child(lamp)
	var bulb := RoadsideKit.part(art,Vector3(0.7,0.12,0.2),lamp.position,Color.WHITE)
	bulb.material_override = preload("res://world/poi_kit/materials/bunker/lamp.tres")

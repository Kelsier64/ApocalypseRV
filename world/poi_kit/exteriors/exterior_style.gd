@tool
extends Node3D
## Original native-mesh silhouettes on the shared, tested entrance shell.
@export_enum("maintenance", "warehouse", "pump", "research") var exterior: String = "maintenance"

func _ready() -> void:
	if has_node("Silhouette"): return
	for sign_node in find_children("*", "Label3D", true, false):
		sign_node.visible = false
	var art := Node3D.new()
	art.name = "Silhouette"
	add_child(art)
	var rust := Color("514437")
	var concrete := Color("555b54")
	var steel := Color("303d3b")
	match exterior:
		"maintenance":
			for x in [-3.0, 0.0, 3.0]:
				var roof := RoadsideKit.part(art, Vector3(3.3, 0.25, 9), Vector3(x, 6.2, 0), rust)
				roof.rotation.z = 0.28
			RoadsideKit.part(art, Vector3(3, 17, 3), Vector3(2.5, 8.5, -2), steel, true, "trunk")
			RoadsideKit.part(art, Vector3(4, 3.5, 0.3), Vector3(-5.7, 1.75, 2), steel, true)
			RoadsideKit.part(art, Vector3(5.5, 0.25, 4), Vector3(-6.7, 3.7, 0), rust)
		"warehouse":
			RoadsideKit.part(art, Vector3(13, 8, 7), Vector3(0, 4, -6), concrete, true)
			for x in [-4.0, 4.0]:
				RoadsideKit.part(art, Vector3(0.35, 12, 0.35), Vector3(x, 6, -3), steel, true)
			RoadsideKit.part(art, Vector3(7, 3, 7), Vector3(0, 12.5, -3), rust, true, "trunk")
			for x in [-7.0, 7.0]:
				RoadsideKit.part(art, Vector3(2.5, 2, 2.5), Vector3(x, 1, 2), rust, true)
			var wire := ShaderMaterial.new()
			wire.shader = preload("res://world/terrain/wire_fence.gdshader")
			for x in [-10.6, 10.6]:
				var fence := RoadsideKit.part(art, Vector3(0.08, 2.4, 7), Vector3(x, 1.2, 0), steel, true)
				fence.material_override = wire
				for z in [-3.5, 0.0, 3.5]:
					RoadsideKit.part(art, Vector3(0.15, 2.6, 0.15), Vector3(x, 1.3, z), steel)
				RoadsideKit.part(art, Vector3(0.15, 0.15, 7), Vector3(x, 2.5, 0), steel)
		"pump":
			for x in [-7.0, 7.0]:
				RoadsideKit.part(art, Vector3(4.5, 10, 4.5), Vector3(x, 5, -1), concrete, true, "trunk")
			RoadsideKit.part(art, Vector3(17, 0.65, 0.65), Vector3(0, 11, -1), rust, true)
			RoadsideKit.part(art, Vector3(0.8, 14, 0.8), Vector3(3, 7, -3), steel, true)
		"research":
			for x in [-2.7, 2.7]:
				var roof := RoadsideKit.part(art, Vector3(6.1, 0.3, 11), Vector3(x, 6.5, 0), steel)
				roof.rotation.z = -signf(x) * 0.32
			RoadsideKit.part(art, Vector3(0.4, 16, 0.4), Vector3(2, 8, -2), steel, true)
			for y in [10.0, 12.0, 14.0]:
				RoadsideKit.part(art, Vector3(4, 0.12, 0.12), Vector3(2, y, -2), rust)
			RoadsideKit.part(art, Vector3(7, 0.4, 0.4), Vector3(-7, 2.7, -2), rust, true)
	var type_index := ExplorationSite.TYPES.find(exterior)
	RoadsideKit.label(art, ExplorationSite.NAMES[maxi(0, type_index)], Vector3(0, 3.95, 6), 24)
	RoadsideKit.label(art, "[E] ENTER", Vector3(0, 2.25, 4.65), 24)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.6, 5.3)
	lamp.light_color = Color("ffcb7a")
	lamp.light_energy = 1.3
	lamp.omni_range = 8.0
	lamp.shadow_enabled = false
	art.add_child(lamp)
	var bulb := RoadsideKit.part(art, Vector3(0.65, 0.12, 0.2), lamp.position, Color("ead19a"))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ead19a")
	glow.emission_enabled = true
	glow.emission = Color("b99451")
	bulb.material_override = glow

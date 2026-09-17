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
	IndustrialArt.dress_exterior(self)
	_add_facade_detail(art, maxi(0, type_index))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.6, 5.3)
	lamp.light_color = Color("efd09b")
	lamp.light_energy = 2.0
	lamp.omni_range = 7.0
	lamp.shadow_enabled = true
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 28.0
	lamp.distance_fade_length = 12.0
	art.add_child(lamp)
	var bulb := RoadsideKit.part(art, Vector3(0.65, 0.12, 0.2), lamp.position, Color("ead19a"))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ead19a")
	glow.emission_enabled = true
	glow.emission = Color("b99451")
	bulb.material_override = glow

func _add_facade_detail(art: Node3D, index: int) -> void:
	# All details sit on existing walls or above head height; no new collision.
	var dark := IndustrialArt.material("steel", Color("303638"))
	var rust := IndustrialArt.material("paint", Color("77614a"))
	for x in [-1.65, 1.65]:
		var jamb := RoadsideKit.part(art, Vector3(0.16, 3.6, 0.24), Vector3(x, 1.8, 4.67), Color.WHITE)
		jamb.material_override = dark
		for y in [0.3, 1.8, 3.3]:
			RoadsideKit.part(art, Vector3(0.06, 0.06, 0.03), Vector3(x, y, 4.81), Color("99917c"))
	var sign := RoadsideKit.part(art, Vector3(3.1, 0.55, 0.045), Vector3(0, 3.64, 4.72), Color.WHITE)
	sign.material_override = dark
	RoadsideKit.label(art, "%02d / %s" % [index + 1, ["SERVICE", "STORAGE", "PUMP CONTROL", "FIELD LAB"][index]], Vector3(0, 3.64, 4.75), 17)
	for x in [-3.8, 3.8]:
		var pipe := RoadsideKit.part(art, Vector3(0.13, 4.3, 0.15), Vector3(x, 2.2, 4.67), Color.WHITE)
		pipe.material_override = rust
		for y in [0.6, 2.0, 3.4]:
			RoadsideKit.part(art, Vector3(0.25, 0.08, 0.18), Vector3(x, y, 4.69), Color("3d4141"))
	# Flush repairs and grime collect at joints, not across every square metre.
	for side in [-1, 1]:
		for i in range(3):
			var patch := RoadsideKit.part(art, Vector3(0.32 + i * 0.13, 0.38 + i * 0.15, 0.022), Vector3(side * (2.4 + i * 0.46), 0.3 + i * 0.23, 4.62), Color.WHITE)
			patch.material_override = rust
		var sill := RoadsideKit.part(art, Vector3(2.1, 0.19, 0.03), Vector3(side * 3.0, 0.16, 4.62), Color.WHITE)
		sill.material_override = dark
	var notice := RoadsideKit.part(art, Vector3(0.65, 0.45, 0.025), Vector3(2.1, 2.0, 4.65), Color("918169"))
	notice.material_override = IndustrialArt.material("paint", Color("b4a47f"))
	RoadsideKit.label(art, "CAUTION\nAUTHORIZED ENTRY", Vector3(2.1, 2.0, 4.68), 8)

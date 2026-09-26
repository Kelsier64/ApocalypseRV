@tool
extends Node3D
## Appearance only. Never move collision, access or actor markers.
func _ready() -> void:
	if Engine.is_editor_hint(): return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_meta("poi_seed", 0))
	var tint := Color.from_hsv(rng.randf_range(0.08, 0.18), rng.randf_range(0.12, 0.24), rng.randf_range(0.70, 0.95))
	var tinted: Dictionary = {}
	for mesh in $Visuals.find_children("*", "MeshInstance3D", true, false):
		var source: Material = mesh.material_override
		if source is StandardMaterial3D and source.resource_name == "RoadsidePaint":
			if not tinted.has(source):
				var material: StandardMaterial3D = source.duplicate()
				material.albedo_color *= tint
				tinted[source] = material
			mesh.material_override = tinted[source]
	for slot in $Visuals.get_children():
		if str(slot.name).begins_with("DecorSlot"): slot.visible = rng.randf() > 0.3

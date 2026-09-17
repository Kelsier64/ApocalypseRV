extends Node
## Presentation only: damage never adds new collision holes or HP owners.
var panel: Equipment
var level: int = -1
var surfaces: Array[Dictionary] = []
func _ready() -> void:
	panel = get_parent()
	for node in panel.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		var source: Material = node.material_override if node.material_override else node.mesh.surface_get_material(0)
		if source is StandardMaterial3D:
			surfaces.append({"mesh": node, "source": source, "glass": "window" in str(node.name).to_lower() or "glass" in str(node.name).to_lower()})
func _process(_delta: float) -> void:
	if panel.is_being_placed: return
	var ratio := panel.current_health / maxf(panel.max_health, 1.0)
	var next := 2 if ratio < 0.3 else (1 if ratio < 0.7 else 0)
	if next == level: return
	level = next
	for entry in surfaces:
		var material := entry.source.duplicate() as StandardMaterial3D
		if level > 0:
			material.albedo_color = material.albedo_color.lerp(Color(0.25, 0.17, 0.1, material.albedo_color.a), 0.25 if level == 1 else 0.5)
			material.roughness = 0.95
			if entry.glass:
				material.albedo_texture = preload("res://assets/rv_status/cracked_glass.svg")
			else:
				# Preserve the original paint texture under the extra damage layer.
				material.detail_enabled = true
				material.detail_albedo = preload("res://assets/rv_status/scuffed_panel.svg")
				material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		entry.mesh.material_override = material

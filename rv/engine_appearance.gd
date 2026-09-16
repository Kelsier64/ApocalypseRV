extends RefCounted
class_name EngineAppearance
## Shared item/bay appearance: never changes engine state or collision.
static func apply(visual: Node3D, engine: EngineState) -> void:
	if engine == null: return
	var wear := 2 if engine.health <= 0.0 else (1 if engine.health / engine.definition().max_health < 0.3 else 0)
	var key := engine.model_id + str(wear)
	if visual.get_meta("engine_appearance", "") == key: return
	visual.set_meta("engine_appearance", key)
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		if not mesh.has_meta("engine_material"):
			var source: Material = mesh.material_override if mesh.material_override else mesh.mesh.surface_get_material(0)
			if not source is StandardMaterial3D: continue
			mesh.set_meta("engine_material", source)
		var material: StandardMaterial3D = mesh.get_meta("engine_material").duplicate()
		if mesh.name == "ValveCover" and engine.model_id == "upgraded":
			material.albedo_color = Color(0.68, 0.29, 0.06)
		if wear > 0:
			material.albedo_color = material.albedo_color.lerp(Color(0.12, 0.07, 0.04), 0.45 if wear == 1 else 0.8)
			material.roughness = 1.0
			material.albedo_texture = preload("res://assets/rv_status/scuffed_panel.svg")
		mesh.material_override = material

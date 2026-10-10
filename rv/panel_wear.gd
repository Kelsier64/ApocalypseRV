extends Node
## Presentation only. Health/restore drive appearance; only real hits emit debris.
const DAMAGE_SHADER := preload("res://rv/panel_damage.gdshader")
const BURST := preload("res://rv/panel_damage_effect.gd")
var panel: RVStructurePanel
var level: int = -1
var severity := 0.0
var surfaces: Array[Dictionary] = []
var _last_hit_ms := -1000

func _ready() -> void:
	panel = get_parent()
	for node: MeshInstance3D in panel.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		for index in range(node.mesh.get_surface_count()):
			var source := node.get_active_material(index)
			if not source is StandardMaterial3D: continue
			var material := source.duplicate() as StandardMaterial3D
			var overlay := ShaderMaterial.new()
			overlay.shader = DAMAGE_SHADER
			var glass: bool = source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			overlay.set_shader_parameter("glass", glass)
			overlay.set_shader_parameter("pattern_offset", float(str(panel.get_path()).hash() % 997) * 0.13)
			surfaces.append({"mesh": node, "surface": index, "source": source,
				"original_override": node.get_surface_override_material(index),
				"material": material, "overlay": overlay, "glass": glass})
	panel.availability_changed.connect(_refresh)
	panel.damage_applied.connect(_hit)
	_refresh()

func _refresh() -> void:
	severity = 1.0 - clampf(panel.current_health / maxf(panel.max_health, 1.0), 0.0, 1.0)
	level = 2 if severity > 0.7 else (1 if severity > 0.3 else 0)
	for entry in surfaces:
		var mesh: MeshInstance3D = entry.mesh
		var material: StandardMaterial3D = entry.material
		entry.overlay.set_shader_parameter("damage", severity)
		material.next_pass = entry.overlay
		material.albedo_color = entry.source.albedo_color.lerp(Color(0.22, 0.19, 0.16, entry.source.albedo_color.a), severity * 0.22)
		material.roughness = lerpf(entry.source.roughness, 0.95, severity)
		if mesh.material_override != null:
			mesh.material_override = material if severity > 0.001 else entry.source
		else:
			mesh.set_surface_override_material(entry.surface, material if severity > 0.001 else entry.original_override)

func _hit(amount: float) -> void:
	if amount <= 0.0: return
	var now := Time.get_ticks_msec()
	if not panel.is_destroyed and now - _last_hit_ms < 100: return
	_last_hit_ms = now
	BURST.spawn(panel, panel.is_destroyed)

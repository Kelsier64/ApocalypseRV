@tool
extends EditorScenePostImport
## Preserve the baked oil coating which this Godot glTF import drops.
## Runs at import time; the resulting scene needs no runtime material overrides.
const OIL_MATERIALS := ["SS_Oil_Stained_Cabinets", "SS_Blackened_Steel"]

func _post_import(scene: Node) -> Object:
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null or material.resource_name not in OIL_MATERIALS:
				continue
			material.clearcoat_enabled = true
			material.clearcoat = 1.0
			material.clearcoat_roughness = 1.0
			# Packed map: R = oil mask, G = roughness, B = metallic.
			# Godot multiplies clearcoat roughness by G: retain the authored wet/dry
			# variation, reusing the texture to keep six atlases and six materials.
			material.clearcoat_texture = material.roughness_texture
	return scene

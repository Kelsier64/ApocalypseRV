extends RefCounted
## Disposable camera view; the imported mesh, Skin and all bone weights stay intact.
## Layer 1: shared accessories/ground; 2: full observer body/head; 3: local body.
const HEADS := ["PLAYER_Skin_Hood", "PLAYER_Skin_Hood_Lining", "PLAYER_Skin_Hood_Seams", "PLAYER_Skin_Mask", "PLAYER_Skin_MaskStrap"]

static func configure(model: Node3D) -> Dictionary:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 2 if String(mesh.name) in HEADS else 1
	var original: MeshInstance3D = model.get_node("PLAYER_Rig/Skeleton3D/PLAYER_Mesh")
	original.layers = 2
	var local_mesh := ArrayMesh.new()
	var hidden_triangles := 0
	var visible_triangles := 0
	for surface in original.mesh.get_surface_count():
		var arrays := original.mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var body_indices := PackedInt32Array()
		for triangle in range(0, indices.size(), 3):
			var head_triangle := false
			for corner in 3:
				var vertex: int = indices[triangle + corner]
				var head_weight := 0.0
				for k in 4:
					if original.skin.get_bind_name(bones[vertex * 4 + k]) == &"head":
						head_weight += weights[vertex * 4 + k]
				head_triangle = head_triangle or head_weight > 0.5
			if head_triangle:
				hidden_triangles += 1
			else:
				body_indices.append_array(indices.slice(triangle, triangle + 3))
				visible_triangles += 1
		if not body_indices.is_empty():
			# Only this disposable index list changes; vertex/normal/UV/skin arrays are copied verbatim.
			arrays[Mesh.ARRAY_INDEX] = body_indices
			local_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			local_mesh.surface_set_material(local_mesh.get_surface_count() - 1, original.mesh.surface_get_material(surface))
	var local := MeshInstance3D.new()
	local.name = "TEST_LocalBodyView"
	local.mesh = local_mesh
	local.skin = original.skin
	local.skeleton = original.skeleton
	local.transform = original.transform
	local.layers = 4
	local.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	original.get_parent().add_child(local)
	var shadow_count := 0
	# Camera culling also affects Godot's shadow collection. Add shared-resource,
	# shadow-only instances on the local layer, without displaying the head.
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.layers != 2:
			continue
		var shadow := MeshInstance3D.new()
		shadow.name = "TEST_LocalShadow_" + mesh.name
		shadow.mesh = mesh.mesh
		shadow.skin = mesh.skin
		shadow.skeleton = mesh.skeleton
		shadow.transform = mesh.transform
		shadow.layers = 4
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mesh.get_parent().add_child(shadow)
		shadow_count += 1
	return {"local_hidden_head_triangles": hidden_triangles, "local_visible_body_triangles": visible_triangles, "original_mesh_retained": true, "original_shadow_retained": true, "local_shadow_proxies": shadow_count}

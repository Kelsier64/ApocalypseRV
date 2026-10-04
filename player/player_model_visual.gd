class_name PlayerModelVisual
extends Node3D
## Presentation only: the controller, imported rig and source resources stay intact.
## Layer 18 is the complete local head/body; layer 21 is a script-only view layer.
## Default cameras (including mirrors) see the complete model, never the local copy.
const FULL_BODY_LAYER := 1 << 17
const LOCAL_VIEW_LAYER := 1 << 20
const HEAD_MESHES := [&"PLAYER_Skin_Hood", &"PLAYER_Skin_Hood_Lining", &"PLAYER_Skin_Hood_Seams", &"PLAYER_Skin_Mask", &"PLAYER_Skin_MaskStrap"]
static var _local_body_mesh: ArrayMesh

@export var local_camera_path := NodePath("../Camera3D")
var source_meshes: Array[MeshInstance3D] = []
var local_body: MeshInstance3D
var local_shadows: Array[MeshInstance3D] = []
var death_shadows: Array[MeshInstance3D] = []
var death_accessory_layers: Dictionary = {}
var dismemberment: Node
@onready var model: Node3D = $Model
@onready var skeleton: Skeleton3D = $Model/PLAYER_Rig/Skeleton3D

func _ready() -> void:
	# The delivered clip is QA data, not an idle animation. Remove only this
	# AnimationPlayer's library references; the imported resource is unchanged.
	var animation: AnimationPlayer = model.get_node("AnimationPlayer")
	animation.stop()
	animation.active = false
	for library in animation.get_animation_library_list():
		animation.remove_animation_library(library)
	skeleton.reset_bone_poses()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		source_meshes.append(mesh)
	var locomotion := preload("res://player/player_locomotion_visual.gd").new()
	locomotion.name = "Locomotion"
	add_child(locomotion)
	var carry := preload("res://player/player_carry_visual.gd").new()
	carry.name = "Carry"
	add_child(carry)
	var camera := get_node_or_null(local_camera_path) as Camera3D if not local_camera_path.is_empty() else null
	if camera == null:
		return # Complete model for a future observer-only actor.
	camera.cull_mask = (camera.cull_mask & ~FULL_BODY_LAYER) | LOCAL_VIEW_LAYER
	for mesh in source_meshes:
		if mesh.name == &"PLAYER_Mesh" or mesh.name in HEAD_MESHES:
			mesh.layers = FULL_BODY_LAYER
			var shadow := _copy_instance(mesh, "LocalShadow_" + mesh.name)
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			local_shadows.append(shadow)
	var original: MeshInstance3D = skeleton.get_node("PLAYER_Mesh")
	if _local_body_mesh == null:
		_local_body_mesh = _build_local_body(original)
	local_body = _copy_instance(original, "LocalBody")
	local_body.mesh = _local_body_mesh
	local_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dismemberment = preload("res://player/player_dismemberment_visual.gd").new()
	dismemberment.name = "Dismemberment"
	add_child(dismemberment)

func detach_part(part: StringName, context: Dictionary = {}) -> Node3D:
	return dismemberment.detach_part(part, context) if dismemberment != null else null

func apply_body_state() -> void:
	if dismemberment != null: dismemberment.apply_body_state()

func bite_contact(part: StringName) -> Transform3D:
	var roots := {"left_arm": "upper_arm_L", "right_arm": "upper_arm_R", "left_leg": "thigh_L", "right_leg": "thigh_R", "head": "head"}
	var bone := skeleton.find_bone(roots.get(String(part), "head"))
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	# The surface lies forward of the bone axis, under the collar/shoulder cloth.
	pose.origin += -get_parent().global_basis.z * .065
	if part == &"head": pose.origin -= Vector3.UP * .025
	return pose

func set_death_view(enabled: bool) -> void:
	if local_body == null: return
	# A tumbling torso can cover a non-rolling eye even with the head culled.
	# Hide it only from the local view; observers and complete shadows remain.
	local_body.visible = not enabled
	if enabled and death_shadows.is_empty():
		for mesh in source_meshes:
			if mesh.layers == FULL_BODY_LAYER: continue
			death_accessory_layers[mesh] = mesh.layers
			var shadow := _copy_instance(mesh, "DeathShadow_" + mesh.name)
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			death_shadows.append(shadow)
	for mesh: MeshInstance3D in death_accessory_layers:
		mesh.layers = FULL_BODY_LAYER if enabled else death_accessory_layers[mesh]
	for shadow in death_shadows: shadow.visible = enabled
	apply_body_state()

func _copy_instance(source: MeshInstance3D, node_name: String) -> MeshInstance3D:
	var copy := MeshInstance3D.new()
	copy.name = node_name
	copy.mesh = source.mesh
	copy.skin = source.skin
	copy.skeleton = source.skeleton
	copy.transform = source.transform
	copy.layers = LOCAL_VIEW_LAYER
	copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	source.get_parent().add_child(copy)
	return copy

static func _build_local_body(original: MeshInstance3D) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in original.mesh.get_surface_count():
		var arrays := original.mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var body_indices := PackedInt32Array()
		for triangle in range(0, indices.size(), 3):
			var head_triangle := false
			for corner in 3:
				var vertex := indices[triangle + corner]
				var head_weight := 0.0
				for influence in 4:
					var offset := vertex * 4 + influence
					if original.skin.get_bind_name(bones[offset]) == &"head":
						head_weight += weights[offset]
				head_triangle = head_triangle or head_weight > 0.5
			if not head_triangle:
				body_indices.append_array(indices.slice(triangle, triangle + 3))
		if body_indices.is_empty():
			continue
		# Only the temporary index list changes. Vertices, UVs, normals and
		# weights are copied verbatim; full geometry remains in source_meshes.
		arrays[Mesh.ARRAY_INDEX] = body_indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(result.get_surface_count() - 1, original.mesh.surface_get_material(surface))
	return result

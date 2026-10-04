extends Node
## Immutable mesh donor; preserve the accepted production skeleton, skin and clips.
const DONOR = preload("res://assets/models/player_dismemberment/player_dismemberment.glb")
const ROOTS := {"head": "head", "left_arm": "upper_arm_L", "right_arm": "upper_arm_R", "left_leg": "thigh_L", "right_leg": "thigh_R"}
static var mesh_cache: Dictionary = {}
var visual: Node3D
var actor: CharacterBody3D
var skeleton: Skeleton3D
var pieces: Array[Dictionary] = []
var templates: Array[Dictionary] = []
var injured := false

func _ready() -> void:
	visual = get_parent()
	actor = visual.get_parent()
	skeleton = visual.skeleton
	var original: MeshInstance3D = skeleton.get_node("PLAYER_Mesh")
	var donor := DONOR.instantiate()
	for source: MeshInstance3D in donor.find_children("*", "MeshInstance3D", true, false):
		var label := String(source.name)
		if not label.begins_with("Part_") and not label.begins_with("Wound_") and not label.begins_with("Cap_"): continue
		var role := label.get_slice("_", 0)
		var part := "torso"
		for key: String in ROOTS:
			if label.begins_with(role + "_" + key): part = key; break
		if not mesh_cache.has(label): mesh_cache[label] = _remap_mesh(source, original.skin)
		var template := {"mesh": mesh_cache[label], "skin": original.skin, "transform": original.transform, "part": part, "role": role}
		templates.append(template)
		if role == "Cap": continue
		var full := _instance(template, skeleton, label, 1 << 17)
		var local := _instance(template, skeleton, "Local_" + label, 1 << 20)
		local.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow := _instance(template, skeleton, "Shadow_" + label, 1 << 20)
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		pieces.append({"part": part, "role": role, "full": full, "local": local, "shadow": shadow})
	donor.free()
	apply_body_state()

static func _instance(data: Dictionary, parent: Skeleton3D, label: String, layers: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = data.mesh
	node.skin = data.skin
	node.skeleton = NodePath("..")
	node.transform = data.transform
	node.layers = layers
	parent.add_child(node)
	return node

static func _remap_mesh(source: MeshInstance3D, target_skin: Skin) -> ArrayMesh:
	var binds: Dictionary = {}
	for i in target_skin.get_bind_count(): binds[target_skin.get_bind_name(i)] = i
	var mapping: Array[int] = []
	for i in source.skin.get_bind_count(): mapping.append(int(binds.get(source.skin.get_bind_name(i), 0)))
	var result := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for i in bones.size(): bones[i] = mapping[bones[i]]
		arrays[Mesh.ARRAY_BONES] = bones
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.mesh.surface_get_material(surface))
	return result

func apply_body_state() -> void:
	injured = false
	for part: String in ROOTS: injured = injured or not actor.body_state.has_part(part)
	for source: MeshInstance3D in visual.source_meshes: source.visible = not injured
	for shadow: MeshInstance3D in visual.local_shadows: shadow.visible = not injured
	for shadow: MeshInstance3D in visual.death_shadows: shadow.visible = not injured and actor.is_player_dead
	if visual.local_body != null: visual.local_body.visible = not injured and not actor.is_player_dead
	for piece in pieces:
		var exists: bool = piece.part == "torso" or actor.body_state.has_part(piece.part)
		var show_piece: bool = injured and (exists if piece.role == "Part" else not exists)
		piece.full.visible = show_piece
		piece.local.visible = show_piece and piece.part != "head" and not actor.is_player_dead
		piece.shadow.visible = show_piece

func detach_part(part: StringName, context: Dictionary) -> Node3D:
	var effect := preload("res://player/player_detached_part.gd").new()
	effect.name = "Detached_" + String(part)
	effect.set_meta("player_detached_part", part)
	effect.add_to_group("player_detached_parts")
	var container: Node = WorldEntities.get_container(actor)
	if not WorldEntities.same_world(actor, container): container = actor.get_parent()
	container.add_child(effect)
	var selections: Array[Dictionary] = []
	for template in templates:
		if template.part == String(part) and template.role in ["Part", "Cap"]: selections.append(template)
	effect.setup(actor, skeleton, String(ROOTS[String(part)]), selections, context)
	preload("res://player/player_gore.gd").spawn(actor, visual.bite_contact(part).origin, context)
	var existing := get_tree().get_nodes_in_group("player_detached_parts")
	while existing.size() > 16:
		var oldest: Node = existing.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()
	return effect

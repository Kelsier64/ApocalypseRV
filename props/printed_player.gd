class_name PrintedPlayerBody
extends Item
## Persistent idle body; consciousness keeps the one production controller and inventory.
const SCENE := "res://props/printed_player.tscn"
var body_state := PlayerBodyState.new()
var stamina := 100.0
var stamina_exhausted := false
var recovery_delay := 0.0
var last_transfer_error := ""
static var _injury_templates: Array[Dictionary] = []
var _injury_nodes: Array[Dictionary] = []

func _ready() -> void:
	super._ready()
	_apply_body_visual()

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 5 or data.get("version") != 1 or not data.version is int: return false
	if not PlayerBodyState.valid_state(data.get("body")): return false
	if not VehicleSnapshot._number(data.get("stamina")) or data.stamina < 0 or data.stamina > 100: return false
	if not data.get("exhausted") is bool: return false
	return VehicleSnapshot._number(data.get("recovery_delay")) and data.recovery_delay >= 0 and data.recovery_delay <= 60

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	state["printed_body"] = {"version": 1, "body": body_state.capture(), "stamina": stamina,
		"exhausted": stamina_exhausted, "recovery_delay": recovery_delay}
	return state

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	var data: Dictionary = state.get("printed_body", {})
	if not valid_state(data): return
	body_state.restore(data.body)
	stamina = float(data.stamina)
	stamina_exhausted = data.exhausted
	recovery_delay = float(data.recovery_delay)
	if is_node_ready(): _apply_body_visual()

func can_pickup(_player: Node3D) -> bool:
	return false

func pickup(_player: Node3D) -> String:
	return "身體無法放入背包"

func get_interaction_prompt(_player: Node3D) -> String:
	return "列印身體｜E 切換控制" if current_health > 0 and body_state.has_part(&"head") else "列印身體｜已死亡"

func interact(player: Node3D) -> String:
	return "已切換身體；裝備隨意識移動" if transfer_control(player) else last_transfer_error

func transfer_control(player: Node3D) -> bool:
	last_transfer_error = "目前無法切換身體"
	if not player is CharacterBody3D or not player.has_method("restore_checkpoint_state"): return false
	if not WorldEntities.same_world(self, player) or presentation_only or is_being_placed or is_queued_for_deletion(): return false
	if is_fixed or is_instance_valid(processing_owner) or current_health <= 0 or not body_state.has_part(&"head"): return false
	if player.is_gameplay_input_blocked() or player.get_player_mode() != player.PlayerMode.NORMAL or player.is_executing(): return false
	if player.locomotion_state == player.LocomotionState.CLIMBING: return false
	if global_basis.y.normalized().dot(Vector3.UP) < .98: return false
	# The production controller origin is 0.25 m above its standing boot sole.
	var sole_offset: float = player.standing_collision_transform.origin.y - (player.standing_collision_shape as CapsuleShape3D).height * .5
	var target := Transform3D(Basis(Vector3.UP, rotation.y), global_position - Vector3.UP * sole_offset)
	var old_body := Transform3D(Basis(Vector3.UP, player.global_rotation.y), player.global_position + Vector3.UP * sole_offset)
	if not _destination_clear(player, target) or not _old_body_clear(player, old_body):
		last_transfer_error = "身體周圍空間不足"
		return false
	var old_health: float = player.current_player_health
	var old_parts: Dictionary = player.body_state.capture()
	var old_stamina: float = player.current_stamina
	var old_exhausted: bool = player.stamina_exhausted
	var old_delay: float = player.stamina_recovery_delay_remaining
	var old_velocity: Vector3 = player._barrel_release_velocity(old_body.origin)
	var target_velocity := linear_velocity
	var target_parts := body_state.capture()
	var target_health := current_health
	var target_stamina := stamina
	var target_exhausted := stamina_exhausted
	var target_delay := recovery_delay
	# Flush held ammunition/charge before refreshing the same inventory ownership.
	player._sync_held_item_state()
	var items: Array = player.inventory.items.duplicate(true)
	var slot: int = player.inventory.active_slot
	global_transform = old_body
	linear_velocity = old_velocity
	angular_velocity = Vector3.ZERO
	current_health = old_health
	body_state.restore(old_parts)
	stamina = old_stamina
	stamina_exhausted = old_exhausted
	recovery_delay = old_delay
	_apply_body_visual()
	reset_physics_interpolation()
	player.restore_checkpoint_state({"items": items, "slot": slot, "health": target_health,
		"body": target_parts, "stamina": target_stamina, "stamina_exhausted": target_exhausted, "transform": target})
	player.stamina_recovery_delay_remaining = target_delay
	player._apply_body_collision()
	# Establish the destination carrier explicitly; old floor contacts refer to
	# the abandoned body until the next move_and_slide call.
	var ray := PhysicsRayQueryParameters3D.create(target.origin + Vector3.UP * (sole_offset + .05), target.origin + Vector3.UP * (sole_offset - .15), player.collision_mask, [player.get_rid(), get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var carrier: Node3D = ClimbMath.find_rv_ancestor(hit.collider) if not hit.is_empty() else null
	if is_instance_valid(carrier):
		player.rv_support.surface = hit.collider
		player.rv_support.rv = carrier
		player.rv_support.previous = carrier.global_transform
		player.rv_support.carrier_velocity = ClimbMath.point_velocity(carrier, target.origin)
		player.velocity = target_velocity - player.rv_support.carrier_velocity
	else:
		player.velocity = target_velocity
		player.released_carrier_velocity = Vector3(target_velocity.x, 0, target_velocity.z)
	player.body_state_changed.emit()
	availability_changed.emit()
	last_transfer_error = ""
	return true

func _destination_clear(player: CharacterBody3D, target: Transform3D) -> bool:
	var shape: Shape3D = player.standing_collision_shape
	var local: Transform3D = player.standing_collision_transform
	if not body_state.has_part(&"left_leg") or not body_state.has_part(&"right_leg"):
		var capsule := CapsuleShape3D.new()
		capsule.radius = player.CRAWL_RADIUS
		capsule.height = player.CRAWL_ONE_LEG_LENGTH if body_state.has_part(&"left_leg") or body_state.has_part(&"right_leg") else player.CRAWL_NO_LEGS_LENGTH
		var standing := player.standing_collision_shape as CapsuleShape3D
		var sole: float = local.origin.y - standing.height * .5
		local = Transform3D(Basis(Vector3.RIGHT, PI * .5), Vector3(0, sole + capsule.radius, 0))
		shape = capsule
	return _volume_clear(shape, target * local, player.collision_mask, player)

func _old_body_clear(player: CharacterBody3D, at: Transform3D) -> bool:
	var collider: CollisionShape3D = $CollisionShape3D
	return _volume_clear(collider.shape, at * collider.transform, player.collision_mask, player)

func _volume_clear(shape: Shape3D, at: Transform3D, mask: int, player: CollisionObject3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	# Ignore resting contact tolerance while still rejecting occupied volume.
	var volume := shape.duplicate() as CapsuleShape3D
	if volume != null:
		volume.radius = maxf(.01, volume.radius - .005)
		volume.height = maxf(volume.radius * 2, volume.height - .01)
	query.shape = volume if volume != null else shape
	query.transform = at
	query.collision_mask = mask
	query.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()



func _apply_body_visual() -> void:
	var injured := false
	for part in PlayerBodyState.PARTS: injured = injured or not body_state.has_part(part)
	$Model.visible = not injured
	if injured and _injury_nodes.is_empty():
		if _injury_templates.is_empty(): _build_injury_templates()
		for template in _injury_templates:
			var mesh := MeshInstance3D.new()
			mesh.name = template.name
			mesh.mesh = template.mesh
			mesh.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * template.transform
			add_child(mesh)
			_injury_nodes.append({"node": mesh, "part": template.part, "role": template.role})
	for piece in _injury_nodes:
		var exists: bool = piece.part == "torso" or body_state.has_part(piece.part)
		piece.node.visible = injured and (exists if piece.role == "Part" else not exists)

static func _build_injury_templates() -> void:
	# Use the same accepted anatomical donor as the playable character, baked
	# into independent meshes at its authored standing idle. No live rig remains.
	var source: Node3D = load("res://assets/models/player_test_v020/player_export_test_v020.glb").instantiate()
	var clips: Node3D = load("res://assets/models/player_animations_v021/player_animations_v021.glb").instantiate()
	var donor: Node3D = load("res://assets/models/player_dismemberment/player_dismemberment.glb").instantiate()
	var animation: AnimationPlayer = source.get_node("AnimationPlayer")
	var library := AnimationLibrary.new()
	library.add_animation("idle", clips.get_node("AnimationPlayer").get_animation("idle"))
	animation.add_animation_library("print", library)
	animation.play("print/idle")
	animation.seek(0.0, true)
	var skeleton: Skeleton3D = source.get_node("PLAYER_Rig/Skeleton3D")
	skeleton.force_update_all_bone_transforms()
	var target_skin: Skin = skeleton.get_node("PLAYER_Mesh").skin
	var binds: Array[Transform3D] = []
	for bind in target_skin.get_bind_count():
		binds.append(skeleton.get_bone_global_pose(skeleton.find_bone(target_skin.get_bind_name(bind))) * target_skin.get_bind_pose(bind))
	var anatomy = load("res://player/player_dismemberment_visual.gd")
	for piece: MeshInstance3D in donor.find_children("*", "MeshInstance3D", true, false):
		var label := String(piece.name)
		if not label.begins_with("Part_") and not label.begins_with("Wound_"): continue
		var role := label.get_slice("_", 0)
		var part := "torso"
		for key: String in anatomy.ROOTS:
			if label.begins_with(role + "_" + key): part = key; break
		var skinned: ArrayMesh = anatomy._remap_mesh(piece, target_skin)
		var baked := ArrayMesh.new()
		for surface in skinned.get_surface_count():
			var arrays := skinned.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for vertex in vertices.size():
				var position := Vector3.ZERO
				var normal := Vector3.ZERO
				for influence in 4:
					var offset := vertex * 4 + influence
					position += (binds[bones[offset]] * vertices[vertex]) * weights[offset]
					normal += (binds[bones[offset]].basis * normals[vertex]) * weights[offset]
				vertices[vertex] = position
				normals[vertex] = normal.normalized()
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			arrays[Mesh.ARRAY_TANGENT] = null
			baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			baked.surface_set_material(surface, skinned.surface_get_material(surface))
		_injury_templates.append({"name": label, "mesh": baked, "part": part, "role": role, "transform": Transform3D.IDENTITY})
	source.free()
	clips.free()
	donor.free()

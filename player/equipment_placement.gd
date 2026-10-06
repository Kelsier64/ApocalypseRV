extends RefCounted
class_name EquipmentPlacement
## Owns preview state and placement input; the player authorizes mode entry.

enum PlacementMode { SURFACE, UPRIGHT }
var placing_equipment: Node3D = null
var max_place_distance: float = 4.0
var can_place_equipment: bool = false
var target_support: Node3D = null
var message: String = ""
var preview_scale: Vector3 = Vector3.ONE
var placement_mode: PlacementMode = PlacementMode.SURFACE
var rotation_offset: float = 0.0
var surface_offset := Vector2.ZERO
var surface_marker: MeshInstance3D
var previous_support: WeakRef
var previous_normal := Vector3.ZERO
var inventory_slot := -1
var inventory_id := ""
var hidden_held_item: WeakRef
var held_was_visible := false

func begin_from_inventory(player: Node) -> bool:
	var data: Dictionary = player.inventory.active_item()
	if data.is_empty(): return false
	var scene := load(str(data.get("scene_path", ""))) as PackedScene
	if scene == null: return false
	var instance := scene.instantiate()
	if not instance is Item:
		instance.free()
		return false
	var ghost := instance as Item
	ghost.presentation_only = true
	ghost.restore_item_state(data.get("state", {}))
	ghost.is_being_placed = true
	ghost.freeze = true
	ghost.collision_layer = 0
	ghost.collision_mask = 0
	var container := WorldEntities.get_container(player)
	if container == null: container = player.get_tree().current_scene
	container.add_child(ghost)
	ghost.global_transform = Transform3D(player.global_basis.scaled_local(ghost.basis.get_scale()), player.global_position)
	for node in ghost.find_children("*", "CollisionObject3D", true, false):
		node.collision_layer = 0
		node.collision_mask = 0
	for mesh in ghost.find_children("*", "GeometryInstance3D", true, false):
		mesh.material_override = ghost.ghost_material
	for label in ghost.find_children("*", "Label3D", true, false): label.hide()
	begin(ghost)
	inventory_slot = player.inventory.active_slot
	inventory_id = str(data.get("state", {}).get("id", ""))
	if is_instance_valid(player.held_item_node):
		hidden_held_item = weakref(player.held_item_node)
		held_was_visible = player.held_item_node.visible
		player.held_item_node.hide()
	return true

func begin(equipment: Node3D) -> void:
	rotation_offset = 0.0
	surface_offset = Vector2.ZERO
	previous_support = null
	_clear_marker()
	placing_equipment = equipment
	preview_scale = equipment.global_basis.get_scale()
	can_place_equipment = false
	message = "瞄準安裝位置"
	placement_mode = PlacementMode.SURFACE

func handle_input(player: CharacterBody3D, event: InputEvent) -> void:
	if player.is_gameplay_input_blocked() or not player.can_use_hands(2 if player.inventory.active_item().get("is_large", false) else 1): return
	# Item Placement confirmation
	if is_instance_valid(placing_equipment):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			cancel(player)
			return
		if event is InputEventKey and event.pressed:
			var increment := deg_to_rad(5.0 if event.shift_pressed else 15.0)
			match event.physical_keycode:
				KEY_Q: rotation_offset -= increment
				KEY_E: rotation_offset += increment
				KEY_LEFT: surface_offset.x -= 0.05
				KEY_RIGHT: surface_offset.x += 0.05
				KEY_UP: surface_offset.y += 0.05
				KEY_DOWN: surface_offset.y -= 0.05
		if event.is_action_pressed("toggle_placement_mode"):
			if placement_mode == PlacementMode.SURFACE:
				placement_mode = PlacementMode.UPRIGHT
			else:
				placement_mode = PlacementMode.SURFACE
		if event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_LEFT:
				update_ghost(player)
				if can_place_equipment and is_instance_valid(target_support):
					commit(player)

			elif event.button_index == MOUSE_BUTTON_RIGHT:
				cancel(player)

func commit(player: Node) -> bool:
	if not is_instance_valid(placing_equipment) or not can_place_equipment or not is_instance_valid(target_support): return false
	var data: Dictionary = player.inventory.active_item()
	if player.inventory.active_slot != inventory_slot or str(data.get("state", {}).get("id", "")) != inventory_id or data.is_empty():
		cancel(player)
		return false
	if not player.can_use_hands(2 if data.get("is_large", false) else 1): return false
	var bounds: AABB = placing_equipment.get_placement_bounds()
	if player.camera.global_position.distance_to(placing_equipment.global_position) > max_place_distance + bounds.size.length() * .5: return false
	if not PlacementRules.rejection_reason(placing_equipment, target_support, placing_equipment.global_transform).is_empty(): return false
	player._sync_held_item_state()
	data = player.inventory.active_item()
	var scene := load(str(data.get("scene_path", ""))) as PackedScene
	if scene == null: return false
	var instance := scene.instantiate()
	if not instance is Item:
		instance.free()
		return false
	var item := instance as Item
	player._restore_prop_state(item, data)
	var container := WorldEntities.get_container(player)
	if container == null: container = player.get_tree().current_scene
	container.add_child(item)
	item.global_transform = placing_equipment.global_transform
	var rv := RVConnection.resolve(target_support)
	item.confirm_placement(item.global_transform, rv if rv else container, target_support)
	if not item.is_fixed:
		item.queue_free()
		return false
	cancel(player)
	player.consume_active_item()
	return true

func cancel(_player: Node) -> void:
	if is_instance_valid(placing_equipment): placing_equipment.queue_free()
	var held := hidden_held_item.get_ref() as Node3D if hidden_held_item != null else null
	if is_instance_valid(held): held.visible = held_was_visible
	hidden_held_item = null
	held_was_visible = false
	placing_equipment = null
	can_place_equipment = false
	target_support = null
	previous_support = null
	previous_normal = Vector3.ZERO
	message = ""
	inventory_slot = -1
	inventory_id = ""
	_clear_marker()

func update_ghost(player: CharacterBody3D) -> void:
	if not is_instance_valid(placing_equipment):
		return
	if not player.can_use_hands(2 if player.inventory.active_item().get("is_large", false) else 1):
		can_place_equipment = false
		return

	var space_state = player.get_world_3d().direct_space_state
	var from = player.camera.global_position
	var to = from + -player.camera.global_transform.basis.z * max_place_distance

	# Ignore ourselves and the equipment
	var query = PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player.get_rid(), placing_equipment.get_rid()])
	var result = space_state.intersect_ray(query)

	if result and PlacementRules.valid_target(placing_equipment, result.collider):
		target_support = result.collider
		can_place_equipment = true
		placing_equipment.visible = true

		var equip = placing_equipment
		var normal: Vector3 = result.normal
		if previous_support == null or previous_support.get_ref() != target_support or normal.dot(previous_normal) < 0.95:
			surface_offset = Vector2.ZERO
		previous_support = weakref(target_support)
		previous_normal = normal
		var base_basis: Basis

		# Use RV's local up if placing on RV, so equipment aligns with the RV when it's tilted
		var up_ref: Vector3 = Vector3.UP
		var hit_node: Node = result.collider
		while hit_node != null:
			if hit_node.is_in_group(Groups.RV):
				up_ref = (hit_node as Node3D).global_transform.basis.y.normalized()
				break
			hit_node = hit_node.get_parent()

		if equip is RVLadder:
			# Both modes keep the ladder plane parallel to the actual wall.
			# Local -Z mounts against it, and +Z faces the climber.
			if absf(normal.dot(up_ref)) < 0.95:
				base_basis = Basis.looking_at(-normal, up_ref)
			else:
				base_basis = Basis.IDENTITY
		elif placement_mode == PlacementMode.SURFACE:
			# Mode 1: bottom_face sticks to the placement surface
			if abs(normal.dot(up_ref)) > 0.5:
				var cam_dir = -player.camera.global_transform.basis.z
				cam_dir = (cam_dir - normal * cam_dir.dot(normal)).normalized()
				if cam_dir.length_squared() < 0.001:
					cam_dir = Vector3.FORWARD.cross(normal).normalized()
					if cam_dir.length_squared() < 0.001:
						cam_dir = Vector3.RIGHT.cross(normal).normalized()
				base_basis = Basis.looking_at(cam_dir, normal)
			else:
				var tangent = normal.cross(up_ref).normalized()
				if tangent.length_squared() < 0.001:
					tangent = Vector3.FORWARD
				base_basis = Basis.looking_at(tangent, normal)

			if equip and equip is Item:
				base_basis = base_basis * equip.get_bottom_face_correction()
		else:
			# Mode 2: bottom faces up_ref-down, closest face contacts surface
			var cam_dir = -player.camera.global_transform.basis.z
			cam_dir = (cam_dir - up_ref * cam_dir.dot(up_ref)).normalized()
			if cam_dir.length_squared() < 0.001:
				# Camera pointing along up_ref axis - use RV's forward as fallback
				var rv_forward := -up_ref.cross(Vector3.RIGHT).normalized()
				if rv_forward.length_squared() < 0.001:
					rv_forward = Vector3.FORWARD
				cam_dir = rv_forward

			if abs(normal.dot(up_ref)) > 0.5:
				# Horizontal surface: standard upright, facing camera direction
				base_basis = Basis.looking_at(cam_dir, up_ref)
			else:
				# Vertical surface: upright, back face against wall
				base_basis = Basis.looking_at(normal, up_ref)

		base_basis = (Basis(normal, rotation_offset) * base_basis).scaled_local(preview_scale)
		placing_equipment.global_transform.basis = base_basis

		var tangent: Vector3 = player.camera.global_basis.x.slide(normal).normalized()
		if tangent.length_squared() < 0.01: tangent = normal.cross(Vector3.FORWARD).normalized()
		var other := normal.cross(tangent).normalized()
		result.position += tangent * surface_offset.x + other * surface_offset.y
		_show_marker(equip, result.position, normal, tangent)
		var bounds: AABB = equip.get_placement_bounds()
		var scaled_half: Vector3 = bounds.size * 0.5
		var offset := 0.0
		for axis in range(3):
			offset += absf(normal.dot(base_basis[axis])) * scaled_half[axis]
		placing_equipment.global_position = result.position + normal * (offset + 0.012) - base_basis * bounds.get_center()
		var reason := PlacementRules.rejection_reason(equip, target_support, placing_equipment.global_transform, result.position, normal)
		var contact_check := space_state.intersect_ray(PhysicsRayQueryParameters3D.create(result.position + normal * 0.1, result.position - normal * 0.15, 0xFFFFFFFF, [equip.get_rid(), player.get_rid()]))
		if contact_check.get("collider") != target_support: reason = "細調位置已離開安裝面"
		if from.distance_to(placing_equipment.global_position) > max_place_distance + bounds.size.length() * 0.5: reason = "超過安裝距離"
		can_place_equipment = reason.is_empty()
		message = ("左鍵安裝｜右鍵取消｜R 貼面／直立\nQ/E 旋轉15°（Shift 5°）｜方向鍵細移5cm" if can_place_equipment else "無法安裝：" + reason)
		if can_place_equipment and equip is RVLadder: message = "左鍵貼牆安裝｜右鍵取消\nQ/E 旋轉15°（Shift 5°）｜方向鍵細移5cm"
		if equip.ghost_material is StandardMaterial3D:
			equip.ghost_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5) if can_place_equipment else Color(0.9, 0.15, 0.1, 0.5)

	else:
		can_place_equipment = false
		target_support = null
		message = "請瞄準牆面｜右鍵／Esc 取消" if placing_equipment is RVLadder else "請瞄準有效支撐｜右鍵／Esc 取消"
		_clear_marker()
		# Hide it when looking at the sky so they know they can't place
		placing_equipment.visible = false




func _clear_marker() -> void:
	if is_instance_valid(surface_marker): surface_marker.queue_free()
	surface_marker = null
func _show_marker(equipment: Node3D, point: Vector3, normal: Vector3, tangent: Vector3) -> void:
	if not is_instance_valid(surface_marker):
		surface_marker = MeshInstance3D.new()
		equipment.add_child(surface_marker)
		surface_marker.top_level = true
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.2, 0.9, 1.0)
		material.no_depth_test = true
		surface_marker.material_override = material
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for segment in [[point, point + normal * 0.35], [point - tangent * 0.18, point + tangent * 0.18], [point + normal * 0.35, point + normal * 0.25 + tangent * 0.07], [point + normal * 0.35, point + normal * 0.25 - tangent * 0.07]]:
		mesh.surface_add_vertex(segment[0])
		mesh.surface_add_vertex(segment[1])
	mesh.surface_end()
	surface_marker.global_transform = Transform3D.IDENTITY
	surface_marker.mesh = mesh

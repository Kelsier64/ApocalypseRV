extends RefCounted
class_name EquipmentPlacement
## Owns preview state and placement input; the player authorizes mode entry.

const EquipmentScript = preload("res://equipment/equipment.gd")
enum PlacementMode { SURFACE, UPRIGHT }
var placing_equipment: Node3D = null
var max_place_distance: float = 4.0
var can_place_equipment: bool = false
var snap_enabled: bool = true
var target_support: Node3D = null
var preview_scale: Vector3 = Vector3.ONE
var placement_mode: PlacementMode = PlacementMode.SURFACE

func begin(equipment: Node3D) -> void:
	placing_equipment = equipment
	preview_scale = equipment.global_basis.get_scale()
	can_place_equipment = false
	placement_mode = PlacementMode.SURFACE

func handle_input(player: CharacterBody3D, event: InputEvent) -> void:
	# Equipment Placement confirmation
	if is_instance_valid(placing_equipment):
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
			snap_enabled = not snap_enabled
		if event.is_action_pressed("toggle_placement_mode"):
			if placement_mode == PlacementMode.SURFACE:
				placement_mode = PlacementMode.UPRIGHT
			else:
				placement_mode = PlacementMode.SURFACE
		if event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_LEFT:
				update_ghost(player)
				if can_place_equipment and is_instance_valid(target_support):
					var rv := RVConnection.resolve(target_support)
					placing_equipment.confirm_placement(placing_equipment.global_transform, rv if rv else target_support, target_support)
					placing_equipment = null

			elif event.button_index == MOUSE_BUTTON_RIGHT:
				placing_equipment.cancel_placement()
				placing_equipment = null

func update_ghost(player: CharacterBody3D) -> void:
	if not is_instance_valid(placing_equipment):
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
		var normal = result.normal
		var base_basis: Basis

		# Use RV's local up if placing on RV, so equipment aligns with the RV when it's tilted
		var up_ref: Vector3 = Vector3.UP
		var hit_node: Node = result.collider
		while hit_node != null:
			if hit_node.is_in_group(Groups.RV):
				up_ref = (hit_node as Node3D).global_transform.basis.y.normalized()
				break
			hit_node = hit_node.get_parent()

		if placement_mode == PlacementMode.SURFACE:
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

			if equip and equip is EquipmentScript:
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

		base_basis = base_basis.scaled_local(preview_scale)
		placing_equipment.global_transform.basis = base_basis

		if snap_enabled and target_support.has_method("get_mount_snap_points"):
			for point in target_support.get_mount_snap_points():
				if point.distance_to(result.position) < 0.3:
					result.position = point
					break
		var bounds: AABB = equip.get_placement_bounds()
		var scaled_half: Vector3 = bounds.size * 0.5
		var offset := 0.0
		for axis in range(3):
			offset += absf(normal.dot(base_basis[axis])) * scaled_half[axis]
		placing_equipment.global_position = result.position + normal * (offset + 0.012) - base_basis * bounds.get_center()
		can_place_equipment = PlacementRules.can_place(equip, target_support, placing_equipment.global_transform)
		if equip.ghost_material is StandardMaterial3D:
			equip.ghost_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5) if can_place_equipment else Color(0.9, 0.15, 0.1, 0.5)

	else:
		can_place_equipment = false
		target_support = null
		# Hide it when looking at the sky so they know they can't place
		placing_equipment.visible = false




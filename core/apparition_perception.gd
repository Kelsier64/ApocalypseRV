extends RefCounted

static func player_camera(actor: Node3D, player: Node3D) -> Camera3D:
	if player.get("in_ui_mode") == true or player.is_gameplay_input_blocked() or player.is_grabbed(): return null
	var camera := actor.get_viewport().get_camera_3d()
	var seat := player.get("seated_in") as Node3D
	var expected := (seat.get("seat_camera") if is_instance_valid(seat) else player.get("camera")) as Camera3D
	if camera != expected or not WorldEntities.same_world(actor, camera): return null
	return camera

static func point_in_frame(camera: Camera3D, point: Vector3, frame: Rect2) -> bool:
	if not camera.is_position_in_frustum(point): return false
	var viewport_rect := camera.get_viewport().get_visible_rect()
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0: return false
	return frame.has_point((camera.unproject_position(point) - viewport_rect.position) / viewport_rect.size)

static func clear_sight(camera: Camera3D, player: Node3D, point: Vector3) -> bool:
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.get_camera_transform().origin, point)
	query.hit_from_inside = true
	if player is CollisionObject3D: query.exclude = [player.get_rid()]
	return space.intersect_ray(query).is_empty()

static func touching_seated_player(actor: CharacterBody3D, player: Node3D, capsule: CapsuleShape3D) -> bool:
	if not is_instance_valid(player.get("seated_in")): return false
	var torso: Vector3 = player.execution_contact_position()
	var base := actor.global_position
	var axis_point := Vector3(base.x, clampf(torso.y, base.y + capsule.radius,
		base.y + capsule.height - capsule.radius), base.z)
	if axis_point.distance_to(torso) > capsule.radius + 0.22: return false
	# The seated player's capsule is disabled. Solid vehicle parts still block contact.
	var query := PhysicsRayQueryParameters3D.create(axis_point, torso, actor.collision_mask)
	query.hit_from_inside = true
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

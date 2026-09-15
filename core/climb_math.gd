extends RefCounted
class_name ClimbMath
## Shared climb-locomotion geometry for the player and monster climbing state
## machines. Tuning constants (speeds, grace windows, gravity) stay on each
## actor; the math lives here so the two implementations cannot drift apart.
## The actors keep thin instance wrappers because the tests pin those method
## names as behavior contracts.

static func is_rv_wall_normal(hit_normal: Vector3, rv_up: Vector3, min_dot: float, max_dot: float) -> bool:
	var d := absf(hit_normal.normalized().dot(rv_up.normalized()))
	return d >= min_dot and d <= max_dot

static func is_valid_hit_height(local_hit_y: float, min_y: float, max_y: float) -> bool:
	return local_hit_y >= min_y and local_hit_y <= max_y

static func rv_position_delta(prev_rv_transform: Transform3D, next_rv_transform: Transform3D) -> Vector3:
	return next_rv_transform.origin - prev_rv_transform.origin

## Carry the attachment point, including rotation about the vehicle's origin.
static func attachment_delta(previous: Transform3D, current: Transform3D, point: Vector3) -> Vector3:
	return current * (previous.affine_inverse() * point) - point

static func point_velocity(rv: Node3D, point: Vector3) -> Vector3:
	if rv is RigidBody3D:
		return rv.linear_velocity + rv.angular_velocity.cross(point - rv.global_position)
	return Vector3.ZERO

## Only transfer over an actual roof with enough room for the complete capsule.
## A clear ray alone is insufficient: the body sweep must also fit.
static func try_roof_transfer(body: CharacterBody3D, shape: CollisionShape3D, rv: Node3D, normal: Vector3) -> bool:
	if not is_instance_valid(rv) or shape == null or not (shape.shape is CapsuleShape3D):
		return false
	var up := Vector3.UP
	var inward := -normal.slide(up).normalized()
	if inward.is_zero_approx():
		return false
	var capsule := shape.shape as CapsuleShape3D
	var foot := shape.global_position - up * capsule.height * 0.5
	var destination := foot + inward * (capsule.radius * 2.0 + 0.15)
	var query := PhysicsRayQueryParameters3D.create(destination + up * 0.1, destination - up * 0.45, body.collision_mask, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or find_rv_ancestor(hit.collider) != rv or hit.normal.dot(up) < 0.85:
		return false
	var step := inward * (capsule.radius * 2.0 + 0.15)
	if body.move_and_collide(step, true) != null:
		return false
	body.move_and_collide(step)
	body.move_and_collide(-up * 0.45)
	return true

static func sanitize_velocity_after_climb(v: Vector3, max_up_velocity: float) -> Vector3:
	var out := v
	if out.y > max_up_velocity:
		out.y = 0.0
	return out

static func build_climb_motion(rv_up: Vector3, wall_normal: Vector3, vertical_input: float, horizontal_input: float, delta: float,
		vertical_speed: float, side_speed: float, stick_speed: float, max_frame_delta: float, fallback_tangent: Vector3) -> Vector3:
	var wall_tangent := rv_up.cross(wall_normal).normalized()
	if wall_tangent.length_squared() < 0.001:
		wall_tangent = fallback_tangent.normalized()

	var motion := (rv_up * vertical_input * vertical_speed)
	motion += wall_tangent * horizontal_input * side_speed
	motion += (-wall_normal) * stick_speed
	var inward_mag := motion.dot(-wall_normal)
	if inward_mag > 0.0:
		motion += wall_normal * inward_mag
	motion *= delta
	if motion.length() > max_frame_delta:
		motion = motion.normalized() * max_frame_delta
	return motion

static func find_rv_ancestor(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current is Node3D and current.is_in_group(Groups.RV):
			return current as Node3D
		current = current.get_parent()
	return null

## Nearest blocking hit along [from -> to] using the actor's upward probe plus
## a direct-space ray as fallback (covers RayCast3D config/layer misses).
## Returns {} when nothing blocks; otherwise
## {"distance": float, "position": Vector3, "source": String, "node_label": String}.
static func nearest_ceiling_hit(probe: RayCast3D, body: PhysicsBody3D, from: Vector3, to: Vector3) -> Dictionary:
	var result := {}
	var min_hit_distance := INF

	if probe != null:
		var local_from: Vector3 = body.to_local(from)
		var local_to: Vector3 = body.to_local(to)
		probe.position = local_from
		probe.target_position = local_to - local_from
		probe.force_raycast_update()
		if probe.is_colliding():
			var probe_hit_position: Vector3 = probe.get_collision_point()
			var probe_hit_distance := from.distance_to(probe_hit_position)
			if probe_hit_distance < min_hit_distance:
				min_hit_distance = probe_hit_distance
				result = {
					"distance": probe_hit_distance,
					"position": probe_hit_position,
					"source": "upward_probe",
					"node_label": format_node_name(probe.get_collider() as Node),
				}

	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [body.get_rid()])
	query.hit_from_inside = true
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		var hit_position: Vector3 = hit.get("position", from) as Vector3
		var hit_distance := from.distance_to(hit_position)
		if hit_distance < min_hit_distance:
			result = {
				"distance": hit_distance,
				"position": hit_position,
				"source": "intersect_ray",
				"node_label": format_node_name(hit.get("collider", null) as Node),
			}

	return result

# --- Debug formatting shared by both actors' climb logs ---

static func format_v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

static func format_node_name(node: Node) -> String:
	if node == null:
		return "null"
	return "%s:%s" % [node.name, node.get_class()]

static func climb_side_label(rv: Node3D, wall_normal: Vector3) -> String:
	if rv == null:
		return "rv_unknown"
	var local_normal := rv.global_transform.basis.inverse() * wall_normal.normalized()
	if absf(local_normal.x) >= absf(local_normal.z):
		return "rv_right" if local_normal.x >= 0.0 else "rv_left"
	return "rv_back" if local_normal.z >= 0.0 else "rv_front"

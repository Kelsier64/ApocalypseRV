class_name RVSupport
extends RefCounted
## RV panels are frozen child bodies, so Godot reports zero platform velocity.
## Track their owning RV explicitly; retain the exact support to detect removal.

var surface: Node3D
var rv: Node3D
var previous := Transform3D.IDENTITY
var carrier_velocity := Vector3.ZERO

func clear() -> void:
	surface = null
	rv = null
	carrier_velocity = Vector3.ZERO

func follow(body: CharacterBody3D, delta: float) -> bool:
	if not is_instance_valid(surface) or not is_instance_valid(rv) or not surface.is_inside_tree():
		clear()
		return false
	if ClimbMath.find_rv_ancestor(surface) != rv:
		clear()
		return false
	var current := rv.global_transform
	var motion := ClimbMath.attachment_delta(previous, current, body.global_position)
	if motion.length() > 1.5:
		clear()
		return false
	carrier_velocity = motion / maxf(delta, 0.0001)
	var rotation_delta := current.basis * previous.basis.inverse()
	body.rotate_y(rotation_delta.get_euler().y)
	if not motion.is_zero_approx():
		body.move_and_collide(motion)
	previous = current
	return true

func capture(body: CharacterBody3D) -> bool:
	if body.is_on_floor():
		for i in range(body.get_slide_collision_count()):
			var collision := body.get_slide_collision(i)
			if collision.get_normal().dot(body.up_direction) < 0.85:
				continue
			var collider := collision.get_collider() as Node3D
			var vehicle := ClimbMath.find_rv_ancestor(collider)
			if vehicle != null:
				surface = collider
				rv = vehicle
				previous = rv.global_transform
				return true
		# Floor snapping may report is_on_floor without a slide collision. Verify
		# the real surface immediately below the capsule instead of losing the RV
		# every other tick while walking across a flat moving roof.
		var shape := body.get("body_collision_shape") as CollisionShape3D
		if shape != null and shape.shape is CapsuleShape3D:
			var foot: Vector3 = shape.global_position - body.up_direction * (shape.shape.height * 0.5)
			var query := PhysicsRayQueryParameters3D.create(foot + body.up_direction * 0.04, foot - body.up_direction * 0.12, body.collision_mask, [body.get_rid()])
			var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.normal.dot(body.up_direction) >= 0.85:
				var vehicle := ClimbMath.find_rv_ancestor(hit.collider)
				if vehicle != null:
					surface = hit.collider
					rv = vehicle
					previous = rv.global_transform
					return true
	clear()
	return false

extends RefCounted
## Local rotational mass for the ragdoll's simplified collision volumes.
## Thin limb collision capsules otherwise rotate too easily under contact impulses.
static func configure(body: PhysicalBone3D, shape: Shape3D) -> void:
	var size: Vector3
	if shape is BoxShape3D:
		size = shape.size
	else:
		size = Vector3(shape.radius * 2.0, shape.height, shape.radius * 2.0)
	var squared := size * size
	# Feet take the first impact in airborne handoffs. Their larger rotational
	# mass keeps that contact impulse from separating the ankle at 60 Hz.
	var multiplier := 6.0 if String(body.get("bone_name")).begins_with("foot") else 3.0
	var inertia := Vector3(squared.y + squared.z, squared.x + squared.z, squared.x + squared.y) * body.mass / 12.0 * multiplier
	PhysicsServer3D.body_set_param(body.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA, inertia)

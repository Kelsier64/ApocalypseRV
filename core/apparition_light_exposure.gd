extends RefCounted
class_name ApparitionLightExposure
## Detects direct exposure from local, native lights in the observer's World3D.
## Callers should throttle this query; it enumerates scene lights and casts rays.

const MIN_EFFECTIVE_ILLUMINATION := 0.08
static func active_lights(observer: Node3D) -> Array[Light3D]:
	var lights: Array[Light3D] = []
	var domain := WorldActorSnapshot.domain(observer)
	if domain == null: domain = observer.get_tree().root
	for node in domain.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if not (light is SpotLight3D or light is OmniLight3D) or not light.is_visible_in_tree(): continue
		if light.light_energy > 0.0 and not light.light_negative and WorldEntities.same_world(observer, light):
			lights.append(light)
	return lights

static func is_exposed(observer: Node3D, points: PackedVector3Array, lights: Array[Light3D]) -> bool:
	var space := observer.get_world_3d().direct_space_state
	for light in lights:
		var reach: float = light.spot_range if light is SpotLight3D else light.omni_range
		var attenuation: float = light.spot_attenuation if light is SpotLight3D else light.omni_attenuation
		var strength := light.light_energy * light.light_color.get_luminance()
		for point in points:
			var offset := point - light.global_position
			var distance := offset.length()
			if distance <= 0.001 or distance >= reach: continue
			var cone_factor := _cone_factor(light, offset / distance)
			if cone_factor <= 0.0: continue
			var range_factor := 1.0 - distance / reach
			var illumination := strength * cone_factor * pow(range_factor, maxf(0.25, attenuation))
			if illumination >= MIN_EFFECTIVE_ILLUMINATION and _unoccluded(space, light, observer, point):
				return true
	return false

static func _cone_factor(light: Light3D, direction_to_point: Vector3) -> float:
	if not light is SpotLight3D:
		return 1.0
	var spot := light as SpotLight3D
	var forward := -spot.global_basis.z.normalized()
	var cosine := forward.dot(direction_to_point)
	var outer_cosine := cos(deg_to_rad(spot.spot_angle))
	if cosine <= outer_cosine:
		return 0.0
	# Softly approximate Godot's spot attenuation between the cone edge and axis.
	var inner_cosine := lerpf(outer_cosine, 1.0, 0.35)
	return pow(smoothstep(outer_cosine, inner_cosine, cosine), maxf(0.25, spot.spot_angle_attenuation))

static func _unoccluded(space: PhysicsDirectSpaceState3D, light: Light3D, observer: Node3D, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(light.global_position, point)
	query.hit_from_inside = true
	var excluded: Array[RID] = []
	if observer is CollisionObject3D:
		excluded.append((observer as CollisionObject3D).get_rid())
	# A held light can sit inside both its item collider and the player capsule.
	var ancestor := light.get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D:
			excluded.append((ancestor as CollisionObject3D).get_rid())
		ancestor = ancestor.get_parent()
	query.exclude = excluded
	return space.intersect_ray(query).is_empty()

extends RefCounted
class_name BarrelExplosion
## Resolve the complete pre-blast scene before destroying any shield/support.
## A source already marked dead is valid; only the blast's own latch deduplicates.

static func explode(source: Node3D, origin: Vector3, contacted_rv: Node3D = null, settings: BarrelManSettings = null) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree() or not origin.is_finite(): return
	if source.has_meta("barrel_blast_resolved"): return
	source.set_meta("barrel_blast_resolved", true)
	if settings == null: settings = BarrelManSettings.new()
	var excluded: Array[RID] = []
	_collect_rids(source, excluded)
	# Items retain their immunity and never transfer a hit to their RV ancestor.
	# Decorative limbs/other monsters cannot absorb the blast or trigger a chain.
	for group in [Groups.ITEMS, Groups.MONSTERS, "player_detached_parts"]:
		for node: Node in source.get_tree().get_nodes_in_group(group):
			if node is Node3D and WorldEntities.same_world(source, node): _collect_rids(node, excluded)
	var players: Array[Dictionary] = []
	var panels: Array[Dictionary] = []
	var engines: Dictionary = {}
	for node: Node in source.get_tree().get_nodes_in_group(Groups.PLAYER):
		if not node is Node3D or not WorldEntities.same_world(source, node) or not node.has_method("apply_explosion_hit"): continue
		var sample := _visible_surface(source, node, origin, excluded, true)
		var distance: float = sample.get("distance", INF)
		if distance >= settings.blast_radius: continue
		var amount := falloff(distance, settings.player_full_damage_radius, settings.blast_radius, settings.player_damage)
		# Shape/world transforms use float32; include exact tuned boundaries.
		var cuts := 2 if distance <= settings.double_limb_radius + 0.00001 else 1 if distance <= settings.player_full_damage_radius + 0.00001 else 0
		var outward: Vector3 = (sample.point - origin).normalized()
		if outward.is_zero_approx(): outward = Vector3.UP
		players.append({"node": node, "damage": amount, "cuts": cuts, "impulse": (outward + Vector3.UP * 0.35) * 7.0 * amount / maxf(settings.player_damage, 0.001)})
	for node: Node in source.get_tree().get_nodes_in_group(Groups.MONSTER_DAMAGEABLE):
		# This deliberately is not a generic take_damage dispatch: Item immunity,
		# wheel health, unrelated equipment and other monsters stay untouched.
		if not node is RVStructurePanel or node.is_destroyed or not WorldEntities.same_world(source, node): continue
		var sample := _visible_surface(source, node, origin, excluded)
		var distance: float = sample.get("distance", INF)
		if distance >= settings.blast_radius: continue
		panels.append({"node": node, "damage": falloff(distance, settings.shell_full_damage_radius, settings.blast_radius, settings.shell_damage)})
		var rv: Node3D = node.get_connected_rv()
		if is_instance_valid(rv) and WorldEntities.same_world(source, rv): _record_engine(engines, rv, distance)
	for node: Node in source.get_tree().get_nodes_in_group(Groups.CHASSIS):
		if not node is Chassis or not WorldEntities.same_world(source, node): continue
		# Include actual chassis and wheel-slot surfaces, stopping at Item/panels.
		var sample := _visible_surface(source, node, origin, excluded)
		if sample.get("distance", INF) < settings.blast_radius: _record_engine(engines, node, sample.distance)
	if is_instance_valid(contacted_rv) and not _belongs_to_item(contacted_rv) and WorldEntities.same_world(source, contacted_rv):
		var rv: Node3D = contacted_rv if contacted_rv is Chassis else RVConnection.resolve(contacted_rv)
		if rv is Chassis and WorldEntities.same_world(source, rv):
			# The physical-contact caller is stronger evidence than a center ray.
			# Rear/side/wheel contact always pays the engine once, at contact range.
			_record_engine(engines, rv, 0.0)
	# All distances, visibility and affected targets above belong to one snapshot.
	for hit in players:
		if is_instance_valid(hit.node): hit.node.apply_explosion_hit(hit.damage, hit.cuts, hit.impulse)
	for hit in panels:
		if is_instance_valid(hit.node): hit.node.take_damage(hit.damage)
	for hit in engines.values():
		if is_instance_valid(hit.node): hit.node.take_damage(falloff(hit.distance, settings.shell_full_damage_radius, settings.blast_radius, settings.engine_damage))
	var container := WorldEntities.get_container(source)
	if container != null:
		var effect := preload("res://enemies/barrel_explosion_effect.gd").new()
		container.add_child(effect)
		effect.global_position = origin

static func falloff(distance: float, full_radius: float, radius: float, amount: float) -> float:
	if distance >= radius: return 0.0
	if distance <= full_radius: return amount
	return amount * clampf((radius - distance) / maxf(radius - full_radius, 0.001), 0.0, 1.0)

static func _record_engine(result: Dictionary, rv: Node3D, distance: float) -> void:
	var id := rv.get_instance_id()
	if not result.has(id) or result[id].distance > distance: result[id] = {"node": rv, "distance": distance}

static func _belongs_to_item(node: Node) -> bool:
	# An Item may own separate collision bodies (for example a screen/handle).
	# Those contacts inherit its immunity before any RV ancestor is resolved.
	var cursor := node
	while cursor != null:
		if cursor is Item: return true
		cursor = cursor.get_parent()
	return false

static func _collect_rids(node: Node, result: Array[RID]) -> void:
	if node is CollisionObject3D and not result.has(node.get_rid()): result.append(node.get_rid())
	for child in node.get_children(): _collect_rids(child, result)

static func _bodies(node: Node, result: Array[CollisionObject3D], include_disabled: bool, root: bool = true) -> void:
	if node is Item or node is RVStructurePanel and not root: return
	if node is CollisionObject3D and (include_disabled or node.collision_layer != 0): result.append(node)
	for child in node.get_children(): _bodies(child, result, include_disabled, false)

## Proximity arming requires an enabled physical body, not child trigger Areas.
static func has_visible_body_surface_in_range(source: CollisionObject3D, target: CollisionObject3D, origin: Vector3, radius: float) -> bool:
	var excluded: Array[RID] = [source.get_rid()]
	return not _visible_surface(source, target, origin, excluded, false, true, radius + 0.00001).is_empty()

static func _visible_surface(source: Node3D, target: Node3D, origin: Vector3, excluded: Array[RID], include_disabled: bool = false, body_only: bool = false, max_distance: float = INF) -> Dictionary:
	var bodies: Array[CollisionObject3D] = []
	if (include_disabled or body_only) and target is CollisionObject3D:
		# Seated players disable their controller shape, which still defines the
		# victim volume. Dormant visual ragdoll bodies are not living hitboxes.
		bodies.append(target)
	else:
		_bodies(target, bodies, include_disabled)
	var result: Dictionary = {}
	for body in bodies:
		for owner in body.get_shape_owners():
			if body.is_shape_owner_disabled(owner) and not include_disabled: continue
			var transform: Transform3D = body.global_transform * body.shape_owner_get_transform(owner)
			for index in body.shape_owner_get_shape_count(owner):
				var shape: Shape3D = body.shape_owner_get_shape(owner, index)
				var nearest := closest_shape_point(shape, transform, origin)
				if nearest.is_empty(): continue
				# The nearest point can be behind a wall while the head/edge is
				# exposed through an existing opening. Sample actual shape surfaces.
				for point: Vector3 in _surface_samples(shape, transform, origin, nearest.point):
					var distance := origin.distance_to(point)
					if distance > max_distance: continue
					if (result.is_empty() or distance < result.distance) and _clear(source, body, origin, point, excluded):
						result = {"distance": distance, "point": point}
	return result

static func _surface_samples(shape: Shape3D, transform: Transform3D, origin: Vector3, nearest: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = [nearest]
	var local := transform.affine_inverse() * origin
	if shape is CapsuleShape3D or shape is CylinderShape3D:
		var radial := Vector3(local.x, 0, local.z).normalized()
		if radial.is_zero_approx(): radial = Vector3.RIGHT
		var half: float = shape.height * 0.5
		var end: float = maxf(0, half - shape.radius) if shape is CapsuleShape3D else half
		for y: float in [-end, 0.0, end]: result.append(transform * (Vector3.UP * y + radial * shape.radius))
		result.append(transform * Vector3.UP * half)
		result.append(transform * Vector3.DOWN * half)
	elif shape is BoxShape3D:
		var half: Vector3 = shape.size * 0.5
		for axis: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]: result.append(transform * (axis * half))
		for x: float in [-half.x, half.x]:
			for y: float in [-half.y, half.y]:
				for z: float in [-half.z, half.z]: result.append(transform * Vector3(x, y, z))
	return result

static func _clear(source: Node3D, target_body: CollisionObject3D, origin: Vector3, point: Vector3, excluded: Array[RID]) -> bool:
	if origin.distance_squared_to(point) < 0.000001: return true
	var omit: Array[RID] = excluded.duplicate()
	# Query all solid layers; a seated player's physical shape may be disabled.
	# The destination body's own surface is the target, not an occluder.
	omit.append(target_body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, point, 0xFFFFFFFF, omit)
	query.hit_from_inside = true
	query.collide_with_areas = false
	var hit := source.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

## Primitive projections use the shape owner's transform, never an actor center.
## Unknown bounded collision geometry uses its debug triangles, not a made-up
## actor radius. Unbounded planes/rays are not damage-bearing victim surfaces.
static func closest_shape_point(shape: Shape3D, transform: Transform3D, origin: Vector3) -> Dictionary:
	if shape == null or absf(transform.basis.determinant()) < 0.000001: return {}
	var local := transform.affine_inverse() * origin
	var nearest := local
	if shape is BoxShape3D:
		var half: Vector3 = shape.size * 0.5
		nearest = local.clamp(-half, half)
	elif shape is SphereShape3D:
		if local.length() > shape.radius: nearest = local.normalized() * shape.radius
	elif shape is CapsuleShape3D:
		var half_segment := maxf(0.0, shape.height * 0.5 - shape.radius)
		var axis := Vector3(0, clampf(local.y, -half_segment, half_segment), 0)
		var delta := local - axis
		if delta.length() > shape.radius: nearest = axis + delta.normalized() * shape.radius
	elif shape is CylinderShape3D:
		nearest.y = clampf(local.y, -shape.height * 0.5, shape.height * 0.5)
		var horizontal := Vector2(local.x, local.z)
		if horizontal.length() > shape.radius:
			horizontal = horizontal.normalized() * shape.radius
			nearest.x = horizontal.x; nearest.z = horizontal.y
	elif shape is ConvexPolygonShape3D or shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = shape.get_debug_mesh().get_faces()
		var best := INF
		for i in range(0, faces.size() - 2, 3):
			var candidate := _triangle_point(origin, transform * faces[i], transform * faces[i + 1], transform * faces[i + 2])
			var distance := origin.distance_squared_to(candidate)
			if distance < best: best = distance; nearest = candidate
		return {} if best == INF else {"point": nearest}
	else:
		return {}
	return {"point": transform * nearest}

static func _triangle_point(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var normal := (b - a).cross(c - a)
	if not normal.is_zero_approx():
		var projected := point - normal * normal.dot(point - a) / normal.length_squared()
		if normal.dot((b - a).cross(projected - a)) >= 0 and normal.dot((c - b).cross(projected - b)) >= 0 and normal.dot((a - c).cross(projected - c)) >= 0: return projected
	var best := a
	var distance := INF
	for edge in [[a, b], [b, c], [c, a]]:
		var candidate := Geometry3D.get_closest_point_to_segment(point, edge[0], edge[1])
		var next := point.distance_squared_to(candidate)
		if next < distance: best = candidate; distance = next
	return best

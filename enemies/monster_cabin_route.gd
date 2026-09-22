class_name MonsterCabinRoute
extends RefCounted
## A small RV-local walking graph. Queries use the actor's actual capsule;
## waypoints follow the vehicle, and moving/removing equipment invalidates on refresh.
const STEP := 0.2
const ROOT_Y := 0.28 # Deck top 0.5; zombie capsule foot is root + 0.25.
var active: bool = false
var vehicle: Node3D
var _timer: float = 0.0
var _path: PackedVector3Array = []
var _goal := Vector3.INF

func request_repath() -> void:
	_timer = 0.0

func tick(delta: float) -> void:
	_timer = maxf(0.0, _timer - delta)
	active = false

func inside(actor, rv: Node3D) -> bool:
	if not is_instance_valid(rv): return false
	var point: Vector3 = rv.to_local(actor.global_position)
	return absf(point.x) < 1.85 and absf(point.z) < 5.85 and point.y > -0.1 and point.y < 2.0

func _query(actor, rv: Node3D, point: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.body_collision_shape.shape
	query.transform = Transform3D(rv.global_basis, rv.to_global(point + actor.body_collision_shape.position))
	query.collision_mask = actor.collision_mask
	var excluded: Array[RID] = [actor.get_rid()]
	if is_instance_valid(actor.target_player): excluded.append(actor.target_player.get_rid())
	query.exclude = excluded
	return query

func clear_segment(actor, rv: Node3D, from: Vector3, to: Vector3) -> bool:
	var query := _query(actor, rv, from)
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	query.motion = rv.global_basis * (to - from)
	var fractions := space.cast_motion(query)
	return fractions[0] >= 0.999

func openings(rv: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var slots := rv.get_node_or_null("StructureSlots")
	if slots == null: return result
	for slot in RVStructureSlots.layout():
		if slot.kind == "roof" or slot.kind == "front": continue
		var device: Equipment = slots.occupant(slot.id)
		var normal: Vector3 = slot.pose.basis.z
		if device == null:
			var point: Vector3 = slot.pose.origin
			point.y = ROOT_Y
			result.append({"point": point, "normal": normal})
		elif device.has_method("boarding_entry_point"):
			for index in range(device.leaf_count):
				if absf(device.angles[index]) < deg_to_rad(70): continue
				var point: Vector3 = rv.to_local(device.boarding_entry_point(index))
				point.y = ROOT_Y
				result.append({"point": point, "normal": normal})
	return result

func destination(actor, rv: Node3D, target: Vector3) -> Vector3:
	if not is_instance_valid(rv): return target
	var origin: Vector3 = rv.to_local(actor.global_position)
	var goal: Vector3 = rv.to_local(target)
	var in_cabin := inside(actor, rv)
	var target_inside := absf(goal.x) < 1.85 and absf(goal.z) < 5.85 and goal.y > -0.1 and goal.y < 2.0
	if not in_cabin and not target_inside: return target
	var route_goal := goal
	route_goal.y = ROOT_Y
	if in_cabin and not target_inside:
		var best := INF
		var selected: Dictionary = {}
		for opening in openings(rv):
			var inner: Vector3 = opening.point - opening.normal * 0.8
			var outer: Vector3 = opening.point + opening.normal * 1.1
			if not clear_segment(actor, rv, inner, outer): continue
			var score: float = origin.distance_to(inner) + outer.distance_to(goal)
			if score < best:
				best = score
				selected = opening
		if selected.is_empty():
			active = true
			return actor.global_position # Enclosed cabin: wait, never walk through a wall.
		var point: Vector3 = selected.point
		var normal: Vector3 = selected.normal
		var inner: Vector3 = point - normal * 0.8
		if Vector2(origin.x - inner.x, origin.z - inner.z).length() < 0.4 or (origin - point).dot(normal) > -0.75:
			active = true
			return rv.to_global(point + normal * 1.1)
		route_goal = inner
	elif not in_cabin:
		var best := 5.0
		var selected: Dictionary = {}
		for opening in openings(rv):
			if (origin - opening.point).dot(opening.normal) < -0.3: continue
			var distance: float = origin.distance_to(opening.point)
			if distance < best and clear_segment(actor, rv, opening.point + opening.normal * 0.8, opening.point - opening.normal * 0.8):
				best = distance
				selected = opening
		if selected.is_empty(): return target
		active = true
		return rv.to_global(selected.point - selected.normal * 0.85)
	active = true
	if vehicle != rv or _timer <= 0.0 or _goal.distance_to(route_goal) > 0.5:
		vehicle = rv
		_goal = route_goal
		_timer = 0.65
		_path = _build_path(actor, rv, origin, route_goal, target_inside)
	while not _path.is_empty() and Vector2(origin.x - _path[0].x, origin.z - _path[0].z).length() < (0.01 if _path.size() == 1 else 0.12):
		_path.remove_at(0)
	if _path.is_empty(): return actor.global_position
	return rv.to_global(_path[0])

func _build_path(actor, rv: Node3D, origin: Vector3, goal: Vector3, melee: bool) -> PackedVector3Array:
	var graph := AStar3D.new()
	var cells: Dictionary = {}
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	for x in range(-7, 8):
		for z in range(-27, 28):
			var point := Vector3(x * STEP, ROOT_Y, z * STEP)
			if not space.intersect_shape(_query(actor, rv, point), 1).is_empty(): continue
			var id := graph.get_available_point_id()
			graph.add_point(id, point)
			cells[Vector2i(x, z)] = id
	for cell: Vector2i in cells:
		for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var next: Vector2i = cell + offset
			if cells.has(next) and clear_segment(actor, rv, graph.get_point_position(cells[cell]), graph.get_point_position(cells[next])):
				graph.connect_points(cells[cell], cells[next])
	var start := -1
	var best := INF
	var flat_origin := Vector3(origin.x, ROOT_Y, origin.z)
	var departure := Vector3(origin.x, maxf(ROOT_Y, origin.y + 0.02), origin.z)
	for id in graph.get_point_ids():
		var point := graph.get_point_position(id)
		var distance := point.distance_to(flat_origin)
		# A roof breach can land on furniture. Walk off its edge at actual
		# height; gravity handles descent to the already-checked deck waypoint.
		var arrival := Vector3(point.x, departure.y, point.z)
		if distance < best and clear_segment(actor, rv, departure, arrival):
			best = distance
			start = id
	if start < 0: return PackedVector3Array()
	var end := graph.get_closest_point(goal)
	if end < 0: return PackedVector3Array()
	if melee and is_instance_valid(actor.target_player):
		# Stopping at the closest side of a seat can leave its backrest between
		# the monster and driver. Prefer a reachable position with real melee LOS.
		var best_path := PackedVector3Array()
		var best_cost := INF
		for id in graph.get_point_ids():
			var point := graph.get_point_position(id)
			var to_player: Vector3 = actor.target_player.global_position - rv.to_global(point)
			if absf(to_player.y) > actor.attack_max_vertical_gap: continue
			to_player.y = 0
			if to_player.length() > actor.attack_range * 0.9: continue
			# Query clearance floats 3 cm above the deck. Melee LOS must use
			# the actual grounded root height, or seat edges create unreachable goals.
			var ray := PhysicsRayQueryParameters3D.create(rv.to_global(point - Vector3.UP * 0.03) + Vector3.UP, actor.target_player.global_position + Vector3.UP, actor.collision_mask, [actor.get_rid()])
			var hit := space.intersect_ray(ray)
			if not hit.is_empty() and hit.collider != actor.target_player: continue
			if actor.has_method("can_grab_from") and not actor.can_grab_from(rv.to_global(point - Vector3.UP * .03), actor.target_player): continue
			var route := graph.get_point_path(start, id)
			if route.is_empty(): continue
			var cost := float(route.size()) * STEP + to_player.length() * 0.1
			if cost < best_cost:
				best_cost = cost
				best_path = route
		if not best_path.is_empty(): return best_path
	return graph.get_point_path(start, end)

extends RefCounted
## Plans lateral roof removal / occupant grabs. Navigation and real hand
## contact remain owned by SlenderSpeaker; a selected roof is never a hit.
const VehicleFollow := preload("res://enemies/slender_speaker/slender_speaker_vehicle_follow.gd")
const SMASH_CLEARANCE := 2.8
const GRAB_CLEARANCE := 1.24 # Keep the bent hand arc outside the cab frame before closing.
const GRAB_BODY_MARGIN := 1.1 # Actual giant capsule radius; hand arcs use GRAB_CLEARANCE.
const ROUTE_CLEARANCE := 1.15
const STANCE_TOLERANCE := 0.12
const STANCE_RELEASE := 0.24
const STANCE_LONGITUDINAL := 0.04
# A handbraked RV still settles/slides on its live suspension. Keep an
# arrived stance while turning through 90 degrees; hand contact decides hits.
const STANCE_LONGITUDINAL_RELEASE := 0.20
const CONTACT_DRIFT := 0.75
const REPLAN_DELAY := 0.5
const ATTACK_FACING := 0.9993908 # Two degrees; real hand sweeps still decide contact.
# The long arms can reach across the cabin from the same exterior stance.
# This is a planning bound only; authored arm lengths, palm sweeps and full
# player extraction still decide whether a particular reach can succeed.
const GRAB_REACH := 5.5
const ROOF_TURN_ENTRY := 0.25
const ROOF_TURN_RELEASE := 0.35

var _vehicle_id := 0
var _side := 0.0
var has_roof := false
var _geometry := VehicleFollow.new()
var _roof_id := 0
var _committed_stance := Vector3.INF
var _committed_surface := Vector3.ZERO
var _committed_contact := Vector3.ZERO
var _committed_smash := false
var _outside_seconds := 0.0
var _side_seconds := 0.0
var _traversing := false
var _plan_generation := 0
var _recovery_offset := 0.0
var _roof_turning := false

func reset() -> void:
	_vehicle_id = 0
	_side = 0.0
	has_roof = false
	_geometry.reset()
	_roof_id = 0
	_committed_stance = Vector3.INF
	_committed_surface = Vector3.ZERO
	_committed_contact = Vector3.ZERO
	_committed_smash = false
	_outside_seconds = 0.0
	_side_seconds = 0.0
	_traversing = false
	_plan_generation = 0
	_recovery_offset = 0.0
	_roof_turning = false

func invalidate_approach(clear_side := false) -> void:
	# A detected physical stall permits a new exterior approach. Normal target
	# motion never calls this and cannot reverse an ongoing side traversal.
	_committed_stance = Vector3.INF
	_outside_seconds = 0.0
	_side_seconds = 0.0
	_traversing = false
	_recovery_offset = -0.35 if _recovery_offset > 0.0 else 0.35
	_roof_turning = false
	if clear_side: _side = 0.0

func update(actor: SlenderSpeaker, vehicle: Node3D, delta: float, occupant: Node3D = null, search_point := Vector3.INF) -> Dictionary:
	if not is_instance_valid(actor) or not is_instance_valid(vehicle) or not vehicle.is_inside_tree() or not WorldEntities.same_world(actor, vehicle):
		reset()
		return {"status": "invalid"}
	if _vehicle_id != vehicle.get_instance_id():
		reset()
		_vehicle_id = vehicle.get_instance_id()
	# Refresh after each panel removal; no stale shell or roof collision bounds.
	_geometry._refresh_shapes(vehicle)
	var right := vehicle.global_basis.x.slide(Vector3.UP).normalized()
	if right.length_squared() < 0.5: return {"status": "invalid"}
	var frame := Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)), vehicle.global_position)
	var shell: AABB = _geometry._footprint(frame, true)
	if shell.size.x <= 0.0 or shell.size.z <= 0.0: return {"status": "invalid"}
	var roofs := _roof_bounds(vehicle, frame)
	var all_roofs := roofs
	has_roof = not roofs.is_empty()
	if search_point != Vector3.INF:
		# A remembered cabin point selects only its covering, currently visible
		# roof. It is never substituted for an occupant or used to aim a grab.
		var remembered := frame.affine_inverse() * search_point
		var observed_roofs: Array[Dictionary] = []
		for entry in roofs:
			var box: AABB = entry.box
			var top := box.get_center()
			top.y = box.end.y
			if _covers_horizontal(box, remembered) and box.position.y > remembered.y + .05 and actor.can_see(entry.panel, frame * top):
				observed_roofs.append(entry)
		roofs = observed_roofs
	var point_speed := float(vehicle.road_speed()) if vehicle.has_method("road_speed") else 0.0
	var local_actor := frame.affine_inverse() * actor.global_position
	local_actor.y = 0.0
	# Start on the nearest side; retain it while the visible torso is reachable.
	# The cab's front/back bend paths intersect its glass/frame: use a side.
	if _side == 0.0:
		_side = 1.0 if absf(local_actor.x - shell.end.x) <= absf(local_actor.x - shell.position.x) else -1.0
	if not is_instance_valid(occupant) or not actor.can_see_player(occupant): occupant = null
	var remembered_attack := search_point != Vector3.INF and occupant == null
	var contact := actor._player_contact(occupant) if occupant != null else (search_point if remembered_attack else Vector3.ZERO)
	var local_contact := frame.affine_inverse() * contact
	if occupant != null and _roof_id == 0:
		var current_edge := shell.end.x if _side > 0.0 else shell.position.x
		var other_edge := shell.position.x if _side > 0.0 else shell.end.x
		var current_reach := absf(current_edge + _side * GRAB_CLEARANCE - local_contact.x)
		var other_reach := absf(other_edge - _side * GRAB_CLEARANCE - local_contact.x)
		# A survivor can walk across the cabin after the approach begins. The
		# opposite side may then be the only stance within the grab envelope.
		# Change only from an unreachable side to a reachable one, so movement
		# near the centreline cannot oscillate the route or reveal hidden players.
		var wants_other := current_reach > GRAB_REACH and other_reach <= GRAB_REACH
		_side_seconds = _side_seconds + maxf(delta, 0.0) if wants_other and not _traversing else 0.0
		if _side_seconds >= REPLAN_DELAY:
			_side = -_side
			_committed_stance = Vector3.INF
			_side_seconds = 0.0
	var selected: Dictionary = {}
	# Keep the chosen physical panel while the survivor is hidden or remains
	# beneath it. Fresh sight through an existing opening must release a roof
	# chosen while hidden; that unrelated panel no longer blocks the grab.
	for entry in roofs:
		if entry.panel.get_instance_id() != _roof_id: continue
		var box: AABB = entry.box
		var covering_occupant := occupant != null and _covers_horizontal(box, local_contact) and box.position.y > local_contact.y + 0.05
		if occupant == null or covering_occupant:
			selected = entry
			break
	if selected.is_empty() and _roof_id != 0:
		_roof_id = 0
		_committed_stance = Vector3.INF
	if selected.is_empty() and occupant != null:
		# Only a roof vertically above the visible torso covers its grab path.
		# A roof walker is above their support and must not lose that support.
		for entry in roofs:
			var box: AABB = entry.box
			if _covers_horizontal(box, local_contact) and box.position.y > local_contact.y + 0.05:
				if selected.is_empty() or box.position.y < selected.box.position.y: selected = entry
	elif selected.is_empty():
		# Inspect the closest reachable, visible solid roof surface first. The
		# last observed cabin point already filters these candidates when known.
		var nearest := INF
		for entry in roofs:
			var surface := _roof_surface(entry.panel, all_roofs, shell, local_contact.z if remembered_attack else local_actor.z)
			if surface == Vector3.INF or not actor.can_see(entry.panel, frame * surface): continue
			var distance := local_actor.distance_squared_to(surface.slide(Vector3.UP))
			if distance < nearest:
				nearest = distance
				selected = entry
	# Only a last observed cabin point permits a strike with no covering roof.
	# Unknown inspection never substitutes the vehicle's centre for a survivor.
	if selected.is_empty() and occupant == null and not remembered_attack: return {"status": "waiting"}
	var roof: RVStructurePanel = selected.get("panel")
	var smash := roof != null or remembered_attack
	if roof != null: _roof_id = roof.get_instance_id()
	var local_surface := local_contact
	if roof != null:
		# Coverage authorizes a panel, not just its one shape above the torso.
		# A hatch is several disjoint shapes: the covering shape can be across
		# its opening and unreachable from this side. Strike a reachable solid
		# part of that SAME panel; never aim into the union's empty hatch hole.
		# Keep the original longitudinal area fixed. Feeding the projected top
		# face back into itself shifts the target on every tick of a pitched RV.
		var preferred_z := local_contact.z if remembered_attack else (_committed_stance.z - _recovery_offset if _committed_stance != Vector3.INF and _committed_smash \
			else (local_contact.z if occupant != null else local_actor.z))
		local_surface = _roof_surface(roof, all_roofs, shell, preferred_z)
		if local_surface == Vector3.INF:
			return {"status": "waiting", "reason": "roof_surface_out_of_reach"}
	var memory_smash := remembered_attack and roof == null
	# A low cabin strike approaches within the real body margin. Roof strikes
	# keep their wider authored stance; choose the other side only if needed.
	if memory_smash:
		var current_edge := shell.end.x if _side > 0.0 else shell.position.x
		var other_edge := shell.position.x if _side > 0.0 else shell.end.x
		if absf(current_edge + _side * GRAB_CLEARANCE - local_contact.x) > SMASH_CLEARANCE + .7 \
			and absf(other_edge - _side * GRAB_CLEARANCE - local_contact.x) <= SMASH_CLEARANCE + .7:
			_side = -_side
			_committed_stance = Vector3.INF
	var edge_x := shell.end.x if _side > 0.0 else shell.position.x
	var clearance := SMASH_CLEARANCE if roof != null else GRAB_CLEARANCE
	if remembered_attack and _committed_stance != Vector3.INF \
		and local_contact.distance_to(_committed_contact) > CONTACT_DRIFT:
		_committed_stance = Vector3.INF
	if _committed_stance != Vector3.INF and _committed_smash != smash:
		_committed_stance = Vector3.INF
	# Replacement geometry may expand the live shell into an old stance.
	# Treat that physical change as an invalid plan, rather than aiming inside it.
	if _committed_stance != Vector3.INF and (_committed_stance.x - edge_x) * _side < clearance - 0.05:
		_committed_stance = Vector3.INF
	# Suspension roll can also contract the observed shell after planning.
	# A stale exterior stance/roof height then makes every physical swing miss
	# the same intact panel. Replan from that visible panel's current geometry.
	if _committed_stance != Vector3.INF and smash:
		var shell_shifted := absf(_committed_stance.x - (edge_x + _side * clearance)) > 0.20
		var roof_shifted := absf(local_surface.y - _committed_surface.y) > 0.20
		var surface_shifted := absf(local_surface.x - _committed_surface.x) > 0.20
		if shell_shifted or roof_shifted or surface_shifted: _committed_stance = Vector3.INF
	# Only sustained movement outside the attack area changes a grab stance.
	# Compare the live, visible torso to the original observation; never read
	# an invisible survivor to keep the area current.
	if _committed_stance != Vector3.INF and not smash and occupant != null:
		var drifted := absf(local_contact.z - _committed_contact.z) > CONTACT_DRIFT
		var unreachable := _committed_stance.distance_to(local_contact.slide(Vector3.UP)) > GRAB_REACH
		_outside_seconds = _outside_seconds + maxf(delta, 0.0) if drifted or unreachable else 0.0
		if _outside_seconds >= REPLAN_DELAY and not _traversing:
			_committed_stance = Vector3.INF
	if _committed_stance == Vector3.INF:
		_roof_turning = false
		_committed_stance = Vector3(edge_x + _side * clearance, 0.0, clampf(local_surface.z + _recovery_offset, shell.position.z + 0.25, shell.end.z - 0.25))
		_committed_surface = local_surface
		_committed_contact = local_contact
		_committed_smash = smash
		_outside_seconds = 0.0
		_plan_generation += 1
	var local_stance := _committed_stance
	# Retain the body stance/longitudinal aim, but follow the actual solid roof
	# surface as suspension roll changes it, even by less than the replan band.
	if smash: _committed_surface = local_surface
	var route := _route_point(local_actor, local_stance, shell)
	var routing := route.distance_squared_to(local_stance) > 0.01
	_traversing = routing
	var navigation_point := frame * route
	navigation_point.y = actor.global_position.y
	var standoff_point := frame * local_stance
	standoff_point.y = actor.global_position.y
	var surface_point := frame * local_surface if smash else contact
	# Feet and body yaw share the committed attack area. The hands retain the
	# current visible contact so a survivor moving inside it need not restart
	# the body's turn every frame.
	var stance_gap := actor.global_position.slide(Vector3.UP).distance_to(standoff_point.slide(Vector3.UP))
	var gap := actor.global_position.slide(Vector3.UP).distance_to(surface_point.slide(Vector3.UP))
	var lateral_clearance := (local_actor.x - edge_x) * _side
	# A released handbrake can keep this observed stance moving slowly along
	# the RV. The visible torso is already physically reachable from its side;
	# chasing centimetre arrival forever prevents the body from facing it.
	# Stop and face the live contact inside this bounded grab envelope. Actual
	# hand/player sweeps still decide capture, including a survivor rolling away.
	var rolling_grab := not smash and point_speed > 0.05 and lateral_clearance >= GRAB_BODY_MARGIN \
		and gap <= GRAB_REACH and absf(local_actor.z - local_contact.z) <= 1.5
	# Roof strikes have a physical reach area too. A slowly rolling RV never
	# holds a four-centimetre waypoint still long enough for an approach/turn.
	# Finish facing its observed roof once safely alongside it, without chasing
	# that moving point. Keep the authored smash standoff and reject corners,
	# excessive reach and longitudinal drift; the actual sweep still owns hits.
	# Once turning starts, suspension motion at the entry edge must not send
	# the feet back toward the stance on alternating ticks. A separate release
	# band preserves the turn only while the same roof remains within reach.
	var roof_turn_band := ROOF_TURN_RELEASE if _roof_turning else ROOF_TURN_ENTRY
	var roof_reach := smash and not routing \
		and absf(lateral_clearance - clearance) <= roof_turn_band \
		and gap <= SMASH_CLEARANCE + 0.7 and absf(local_actor.z - local_surface.z) <= 1.0
	_roof_turning = roof_reach
	var turn_in_place := rolling_grab or roof_reach
	var facing_point := surface_point if turn_in_place else frame * _committed_surface
	var settled := actor._parked_facing_waypoint != Vector3.INF and actor._parked_facing_waypoint.slide(Vector3.UP).distance_to(standoff_point.slide(Vector3.UP)) <= STANCE_RELEASE
	var attack_radius := STANCE_RELEASE if settled else STANCE_TOLERANCE
	var longitudinal_radius := STANCE_LONGITUDINAL_RELEASE if settled else STANCE_LONGITUDINAL
	var lateral_stance := lateral_clearance >= GRAB_CLEARANCE - 0.05 and absf(local_actor.z - local_stance.z) <= longitudinal_radius
	var map_ready := actor.giant_navigation_map.is_valid() and actor.nav_agent != null
	if map_ready: map_ready = NavigationServer3D.map_get_iteration_id(actor.giant_navigation_map) > 0
	# The capsule must remain outside the shell even within the arrival area.
	# Alignment is explicit and the authored hand sweep retains final authority.
	var arrived := turn_in_place or (lateral_stance and stance_gap <= attack_radius)
	var ready := map_ready and (turn_in_place or not routing) and arrived and actor._facing_dot(facing_point) >= ATTACK_FACING
	ready = ready and gap <= (SMASH_CLEARANCE + 0.7 if smash else GRAB_REACH)
	if not smash:
		ready = ready and occupant.has_method("can_be_executed") and occupant.can_be_executed()
	var action := "smash" if ready and smash else ("grab" if ready else "approach")
	return {
		"status": "ready" if ready else "approach",
		"vehicle": vehicle, "roof": roof, "occupant": occupant,
		"surface_point": surface_point, "grab_point": contact if occupant != null else Vector3.ZERO,
		"facing_point": facing_point,
		"rolling_grab": rolling_grab,
		"turn_in_place": turn_in_place,
		"navigation_point": navigation_point, "standoff_point": standoff_point,
		"route_frame": frame, "route_shell": shell,
		"body_margin": VehicleFollow.BODY_MARGIN if roof != null else GRAB_BODY_MARGIN,
		"arrival_radius": STANCE_TOLERANCE, "release_radius": STANCE_RELEASE,
		"arrival_longitudinal": STANCE_LONGITUDINAL, "release_longitudinal": STANCE_LONGITUDINAL_RELEASE,
		"facing_dot": ATTACK_FACING, "plan_generation": _plan_generation,
		"action": action, "smash_kind": "roof" if roof != null else ("cabin_memory" if remembered_attack else ""),
		"can_attack": ready, "gap": gap, "clearance": lateral_clearance,
		"speed": minf(actor.settings.patrol_speed, stance_gap * 1.5) if map_ready else 0.0,
	}

func _roof_surface(roof: RVStructurePanel, shapes: Array[Dictionary], shell: AABB, preferred_z: float) -> Vector3:
	var edge := shell.end.x if _side > 0.0 else shell.position.x
	var best := Vector3.INF
	var cost := INF
	for entry in shapes:
		if entry.panel != roof: continue
		var box: AABB = entry.box
		# Thin hatch rims still need an interior point. A fixed inset can fall
		# outside a narrow shape or invert its longitudinal clamp interval.
		var inset_x := minf(.12, box.size.x * .25)
		var inset_z := minf(.25, box.size.z * .25)
		var point := Vector3(box.end.x - inset_x if _side > 0.0 else box.position.x + inset_x,
			box.end.y, clampf(preferred_z, box.position.z + inset_z, box.end.z - inset_z))
		# The upright planning AABB can extend above/outside a thin rim when
		# the suspension rolls. Project onto the actual shape's top face before
		# accepting reach, so the chosen point stays on solid roof geometry.
		var shape_frame: Transform3D = entry.shape_frame
		var shape_box: AABB = entry.shape_box
		var shape_point := shape_frame.affine_inverse() * point
		inset_x = minf(.12, shape_box.size.x * .25)
		inset_z = minf(.25, shape_box.size.z * .25)
		shape_point.x = clampf(shape_point.x, shape_box.position.x + inset_x, shape_box.end.x - inset_x)
		shape_point.y = shape_box.end.y
		shape_point.z = clampf(shape_point.z, shape_box.position.z + inset_z, shape_box.end.z - inset_z)
		point = shape_frame * shape_point
		var stance := Vector3(edge + _side * SMASH_CLEARANCE, 0.0,
			clampf(point.z + _recovery_offset, shell.position.z + .25, shell.end.z - .25))
		if stance.distance_to(point.slide(Vector3.UP)) > SMASH_CLEARANCE + .7: continue
		var candidate_cost := absf(point.x - edge) + absf(point.z - preferred_z)
		if candidate_cost < cost:
			cost = candidate_cost
			best = point
	return best

func _route_point(actor: Vector3, goal: Vector3, shell: AABB) -> Vector3:
	# The vehicle follower's 1.25m route envelope keeps a 1.2m grab stance
	# unreachable. Use the real capsule's radius plus a small physical margin;
	# still route outside the shell and let NavigationAgent own every move.
	var blocked := shell.grow(ROUTE_CLEARANCE)
	blocked.position.y = -1.0
	blocked.size.y = 2.0
	if blocked.intersects_segment(actor, goal) == null: return goal
	var corners := shell.grow(VehicleFollow.ROUTE_MARGIN)
	var points: Array[Vector3] = []
	for x in [corners.position.x, corners.end.x]:
		for z in [corners.position.z, corners.end.z]: points.append(Vector3(x, 0.0, z))
	var distances: Array[float] = []
	for corner in points:
		distances.append(corner.distance_to(goal) if blocked.intersects_segment(corner, goal) == null else INF)
	# A side change needs two corners. Include the remaining exterior route
	# in each waypoint's cost instead of treating a diagonal through the RV
	# as a valid shortcut and repeatedly returning to the previous corner.
	for step in points.size():
		for index in points.size():
			for next in points.size():
				if index == next or blocked.intersects_segment(points[index], points[next]) != null: continue
				distances[index] = minf(distances[index], points[index].distance_to(points[next]) + distances[next])
	var best := actor
	var cost := INF
	for index in points.size():
		var corner := points[index]
		if actor.distance_to(corner) < 1.6 or blocked.intersects_segment(actor, corner) != null: continue
		var length := actor.distance_to(corner) + distances[index]
		if length < cost:
			best = corner
			cost = length
	if cost < INF: return best
	var nearest: Dictionary = _geometry._nearest_footprint(actor, shell)
	var normal: Vector3 = (actor - nearest.point).normalized()
	if float(nearest.clearance) <= 0.0: normal = -normal
	if normal.length_squared() < 0.5: normal = Vector3.RIGHT
	return nearest.point + normal * VehicleFollow.ROOT_CLEARANCE

func _roof_bounds(vehicle: Node3D, frame: Transform3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var inverse := frame.affine_inverse()
	var slots := vehicle.get_node_or_null("StructureSlots") as RVStructureSlots
	if slots == null: return result
	for slot in RVStructureSlots.layout():
		if slot.kind != "roof": continue
		var panel := slots.occupant(slot.id)
		if panel == null: continue
		for child in panel.find_children("*", "CollisionShape3D", true, false):
			var shape := child as CollisionShape3D
			if shape.disabled or shape.shape == null: continue
			var shape_box: AABB = _geometry._shape_box(shape.shape)
			var box := AABB(inverse * (shape.global_transform * shape_box.get_endpoint(0)), Vector3.ZERO)
			for index in range(1, 8): box = box.expand(inverse * (shape.global_transform * shape_box.get_endpoint(index)))
			result.append({"panel": panel, "box": box,
				"shape_frame": inverse * shape.global_transform, "shape_box": shape_box})
	return result

func _covers_horizontal(box: AABB, point: Vector3) -> bool:
	return point.x >= box.position.x - 0.03 and point.x <= box.end.x + 0.03 and point.z >= box.position.z - 0.03 and point.z <= box.end.z + 0.03

func vehicle_for_visible_player(actor: SlenderSpeaker, player: Node3D) -> Node3D:
	# Association is evaluated only after actual sight. Remembered or hidden
	# occupants never disclose their current position to the vehicle planner.
	if not is_instance_valid(player) or not WorldEntities.same_world(actor, player): return null
	if not actor.can_see_player(player): return null
	for candidate in actor.get_tree().get_nodes_in_group(Groups.RV):
		if not candidate is Node3D or not WorldEntities.same_world(actor, candidate): continue
		if _player_belongs_to_vehicle(player, candidate): return candidate
	return null

func player_in_cabin(player: Node3D, vehicle: Node3D) -> bool:
	# Called only for a sight-confirmed, associated survivor. Roof support and
	# exterior climbing are not cabin evidence, even though they belong to RV.
	if not is_instance_valid(player) or not is_instance_valid(vehicle): return false
	if is_instance_valid(player.get("active_climb_rv")): return false
	var support: RefCounted = player.get("rv_support")
	var surface: Node3D = support.get("surface") if support != null else null
	if surface is RVStructurePanel and surface.structure_kind == "roof": return false
	if vehicle.get_node_or_null("StructureSlots") == null: return false
	# Slot frames retain the observed cabin boundary after roof removal. Do
	# not misclassify a survivor standing over an open roof as an occupant.
	var local: Vector3 = vehicle.to_local(player.global_position)
	for slot in RVStructureSlots.layout():
		if slot.kind == "roof" and local.y >= slot.pose.origin.y - .05: return false
	return true

func _player_belongs_to_vehicle(player: Node3D, vehicle: Node3D) -> bool:
	var seat: Node = player.get("seated_in")
	if is_instance_valid(seat) and RVConnection.resolve(seat) == vehicle: return true
	var support: RefCounted = player.get("rv_support")
	if support != null and support.get("rv") == vehicle: return true
	var climb: Node = player.get("active_climb_rv")
	if is_instance_valid(climb) and RVConnection.resolve(climb) == vehicle: return true
	# The unseated interior has no seat owner. Derive its current volume from
	# live chassis/shell shapes, including replacement panels and openings.
	# Feet below the deck and nearby ground players fall outside this volume.
	var geometry := VehicleFollow.new()
	geometry._refresh_shapes(vehicle)
	var bounds := AABB()
	var have_bounds := false
	var shapes: Array[CollisionShape3D] = []
	shapes.append_array(geometry._chassis_shapes)
	shapes.append_array(geometry._panel_shapes)
	for shape in shapes:
		if not is_instance_valid(shape) or shape.disabled or shape.shape == null: continue
		var owner: Node = shape.get_parent()
		while owner != null and not owner is CollisionObject3D: owner = owner.get_parent()
		if owner is RVStructurePanel and owner.is_destroyed: continue
		var box: AABB = geometry._shape_box(shape.shape)
		for index in 8:
			var point: Vector3 = vehicle.to_local(shape.global_transform * box.get_endpoint(index))
			if not have_bounds:
				bounds = AABB(point, Vector3.ZERO)
				have_bounds = true
			else: bounds = bounds.expand(point)
	if not have_bounds: return false
	var local: Vector3 = vehicle.to_local(player.global_position)
	return _covers_horizontal(bounds, local) and local.y >= bounds.position.y - .05 and local.y <= bounds.end.y + .15

extends "res://tests/test_orientation_workshop_journey.gd"
## Authored search approaches must remain physically reachable and expose real stock.
const ROLES := ["scrapper", "workbench", "scrap_a", "scrap_b", "scrap_c", "scrap_d", "scrap_e", "scrap_f", "scrap_g", "scrap_h", "barrel", "barrel_b", "spare", "battery", "engine_kit_a", "engine_kit_b"]
const OLD_STOCK := {
	"scrapper": Vector3(7.5, 0, -17), "workbench": Vector3(-7.5, 0, -17),
	"scrap_a": Vector3(8.45, 0.975, -10), "scrap_b": Vector3(9.25, 0.975, -10),
	"scrap_c": Vector3(8.45, 0.975, -6), "scrap_d": Vector3(9.25, 0.975, -6),
	"scrap_e": Vector3(8.45, 0.975, -2), "scrap_f": Vector3(9.25, 0.975, -2),
	"scrap_g": Vector3(8.45, 0.975, 2), "scrap_h": Vector3(9.25, 0.975, 2),
	"barrel": Vector3(10.7, 0.5, -10), "barrel_b": Vector3(10.7, 0.5, -5),
	"spare": Vector3(-8, 0, -9), "battery": Vector3(-9.5, 0.975, -4),
	"engine_kit_a": Vector3(-8.7, 0.945, -4), "engine_kit_b": Vector3(-8.1, 0.945, -4)}
var building: Node3D
var geometry_exclusions: Array[RID] = []

func run() -> void:
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = 12
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not check(await world.wait_for_play() and await WAIT.generator_idle(self, generator), "Warehouse production world becomes playable"):
		await finish(); return
	run_owner = world.get_node("StartRun")
	tutorial = run_owner.get_node("Tutorial")
	vehicle = tutorial.designated_rv()
	player = world.get_node("Player")
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	player.set_physics_process(false)
	if not await reception(): await finish(); return
	workshop = tutorial.workshop
	building = run_owner.shelter
	for actor in [vehicle, player]:
		geometry_exclusions.append(actor.get_rid())
		for body: CollisionObject3D in actor.find_children("*", "CollisionObject3D", true, false): geometry_exclusions.append(body.get_rid())
	for item in get_nodes_in_group(Groups.ITEMS):
		if WorldEntities.same_world(world, item):
			geometry_exclusions.append(item.get_rid())
			for body: CollisionObject3D in item.find_children("*", "CollisionObject3D", true, false): geometry_exclusions.append(body.get_rid())
	check(building.has_node("Visuals/Warehouse") and building.has_node("Collision/Warehouse"), "Warehouse has visual clutter and physical collision")
	var approaches := building.get_node_or_null("WarehouseApproaches")
	if not check(approaches != null and approaches.get_child_count() == ROLES.size(), "All sixteen stock roles have authored floor approaches"):
		await finish(); return
	var identities := WalkInSites.orientation_workshop_ids(building)
	var actual := get_nodes_in_group(Groups.ITEMS).filter(func(item): return WorldEntities.same_world(world, item) and item.persistent_id in identities.values())
	check(actual.size() == ROLES.size(), "Warehouse retains exactly sixteen designated stock Items")
	for role: String in ROLES:
		var item: Item = workshop.item(role)
		var approach := approaches.get_node_or_null(NodePath(role)) as Marker3D
		if not check(item != null and item.persistent_id == identities[role] and workshop.targets[role] == identities[role] and approach != null, "Original %s identity and search approach exist" % role): continue
		check(absf(approach.position.y) < 0.01, "%s approach is a floor location" % role)
		check(Vector2(approach.position.x - building.to_local(item.global_position).x, approach.position.z - building.to_local(item.global_position).z).length() <= 2.2, "%s is within reach of its aisle" % role)
		var route_z := float(approach.get_meta("route_z", approach.position.z))
		var route_x := float(approach.get_meta("route_x", signf(approach.position.x) * 14.75))
		check(route_z in [-24.0, -18.0, -12.0, -6.0, 0.0, 6.0, 12.0], "%s connects through an authored cross-aisle" % role)
		var route := [Vector3(0, 0, route_z), Vector3(route_x, 0, route_z), Vector3(route_x, 0, approach.position.z), approach.position]
		for index in route.size() - 1: aisle_segment(route[index], route[index + 1], role)
		stock_visible(item, approach, role)
		legacy_stock_clear(item, role)
	var lane := BoxShape3D.new()
	var scrapper: Item = workshop.item("scrapper")
	var entry_eye := building.to_global(Vector3(0, 1.5, -30))
	var entry_aim := scrapper.to_global(scrapper.get_placement_bounds().get_center())
	var entry_query := PhysicsRayQueryParameters3D.create(entry_eye, entry_aim, 3, [player.get_rid(), vehicle.get_rid()])
	var entry_hit := world.get_world_3d().direct_space_state.intersect_ray(entry_query)
	check(not entry_hit.is_empty() and (entry_hit.collider == scrapper or scrapper.is_ancestor_of(entry_hit.collider)), "Scrapper is visible through the open inner doorway before entering the warehouse")
	lane.size = Vector3(8, 4.9, 36)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = lane
	query.transform = building.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 2.5, -6))
	query.collision_mask = 3
	query.exclude = geometry_exclusions
	check(world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "Warehouse preserves the full eight-metre vehicle lane from z=-24 to12")
	journey_completed = failures.is_empty()
	if journey_completed: print("PASS: warehouse sixteen stock identities, capsule-connected search aisles, first-hit pickup sightlines, legacy stock clearance and eight-metre RV lane")
	await finish()

func aisle_segment(first: Vector3, last: Vector3, role: String) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = building.global_transform * Transform3D(Basis.IDENTITY, first + Vector3.UP * 0.8)
	query.motion = building.global_basis * (last - first)
	query.collision_mask = 3
	query.exclude = geometry_exclusions
	var space := world.get_world_3d().direct_space_state
	check(space.intersect_shape(query).is_empty(), "%s aisle segment starts with a clear standing capsule" % role)
	var sweep := space.cast_motion(query)
	if not check(sweep[0] >= 0.999, "%s has a continuous player-width aisle from %s to %s" % [role, first, last]):
		print("WAREHOUSE_AISLE_BLOCKED: role=", role, " from=", first, " to=", last, " safe_fraction=", sweep[0])
	query.transform.origin += query.motion
	query.motion = Vector3.ZERO
	check(space.intersect_shape(query).is_empty(), "%s aisle segment ends with a clear standing capsule" % role)

func stock_visible(item: Item, approach: Marker3D, role: String) -> void:
	var eye := approach.global_position + building.global_basis.y * 1.5
	var aim := item.to_global(item.get_placement_bounds().get_center())
	check(eye.distance_to(aim) <= 3.0, "%s fits the production interaction-ray reach" % role)
	var query := PhysicsRayQueryParameters3D.create(eye, aim, 3, [player.get_rid(), vehicle.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if not check(not hit.is_empty() and (hit.collider == item or item.is_ancestor_of(hit.collider)), "%s is the first physical target seen from its aisle" % role):
		print("WAREHOUSE_SIGHTLINE: role=", role, " eye=", building.to_local(eye), " aim=", building.to_local(aim), " hit=", hit.collider.get_path() if not hit.is_empty() else "none")

func legacy_stock_clear(item: Item, role: String) -> void:
	var bounds := item.get_placement_bounds()
	var shape := BoxShape3D.new()
	shape.size = bounds.size * 0.98
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = building.global_transform * Transform3D(Basis.IDENTITY, OLD_STOCK[role] + bounds.get_center())
	query.collision_mask = 3
	query.exclude = geometry_exclusions
	var warehouse := building.get_node_or_null("Collision/Warehouse")
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query, 64):
		if not check(warehouse == null or (hit.collider != warehouse and not warehouse.is_ancestor_of(hit.collider)), "New warehouse collision preserves %s at its saved legacy position" % role):
			print("WAREHOUSE_LEGACY_BLOCKED: role=", role, " body=", hit.collider.get_path())

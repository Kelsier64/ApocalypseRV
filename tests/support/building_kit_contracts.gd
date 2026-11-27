extends RefCounted
## BuildingKit contracts: the reference building composes cleanly and
## deterministically, validation catches misfit openings, floating pieces,
## pieces passing through walls and z-fighting faces, collision-only builds
## match, and the player capsule fits through doors while windows, walls and
## the stair flight's sides block it.

const SAMPLE = preload("res://world/building_kit/samples/service_block.gd")
const LIFT := Vector3(0, 400, 0)


static func run(tree: SceneTree, world: Node3D, check: Callable) -> void:
	var kit: BuildingKit = SAMPLE.compose(7)
	check.call(kit.validate().is_empty(), "Kit sample validates: %s" % [kit.validate()])
	check.call(_surface_data(SAMPLE.compose(7)) == _surface_data(kit), "Kit sample geometry and shading are deterministic per seed")
	check.call(_surface_data(SAMPLE.compose(8)) != _surface_data(kit), "Another seed varies the kit's shading and damage")
	_validation_catches(check)
	var live := Node3D.new()
	live.position = LIFT
	world.add_child(live)
	kit.build(live, true, true)
	var nav := Node3D.new()
	SAMPLE.compose(7).build(nav, false, true)
	check.call(nav.find_children("*", "VisualInstance3D", true, false).is_empty(), "Collision-only kit build has no visuals")
	check.call(_shape_plan(nav) == _shape_plan(live), "Kit collision matches with and without visuals")
	nav.free()
	for i in 3:
		await tree.physics_frame
	var capsule := _player_capsule()
	var space := world.get_world_3d().direct_space_state
	var stand := 0.05 + capsule.height * 0.5
	var front_door := SAMPLE.STORE.position.x + 6.0
	check.call(_walk(space, capsule, Vector3(front_door, stand, 7), Vector3(front_door, stand, -3)), "Player walks through the store's wide front door")
	var side_door_z := SAMPLE.STORE.end.y - 6.5
	check.call(_walk(space, capsule, Vector3(4, stand, side_door_z), Vector3(6.9, stand, side_door_z)), "Player walks out of the store's side door")
	check.call(not _walk(space, capsule, Vector3(SAMPLE.STORE.position.x + 2.0, stand, 7), Vector3(SAMPLE.STORE.position.x + 2.0, stand, 0)), "Window and its sill wall block the player")
	check.call(not _walk(space, capsule, Vector3(2.0, stand, 7), Vector3(2.0, stand, 0)), "Solid wall blocks the player")
	var upper := SAMPLE.ANNEX_STOREY + BuildingKit.SLAB
	var landing_z := SAMPLE.ANNEX.end.y - 2.5
	check.call(_walk(space, capsule, Vector3(14.3, upper + stand, landing_z), Vector3(11.5, upper + stand, landing_z)), "Player walks from the landing through the upper door")
	# The ramp under the stair stays within one step of the visible treads.
	var run := BuildingKit.STEP_RUN * ceili(upper / BuildingKit.STEP_RISE)
	var middle := Vector3(14.25, 10, SAMPLE.ANNEX.end.y - 1.7 + run * 0.5)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(middle + LIFT, middle + LIFT + Vector3.DOWN * 20))
	check.call(not hit.is_empty() and absf(hit.position.y - LIFT.y - upper * 0.5) < BuildingKit.STEP_RISE, "Stair ramp follows the treads: %s" % [hit.get("position")])
	# Near the top the ramp passes above the capsule; the flight below it must still be solid.
	var high_z := SAMPLE.ANNEX.end.y - 1.7 + 4.0 * BuildingKit.STEP_RUN
	check.call(not _walk(space, capsule, Vector3(16.5, stand, high_z), Vector3(14.3, stand, high_z)), "Player cannot walk into the stair flight from the side")
	live.queue_free()
	await tree.process_frame


static func _validation_catches(check: Callable) -> void:
	var wide := BuildingKit.new()
	wide.wall(Vector2.ZERO, Vector2(2, 0), 3.0, &"block", {"openings": [BuildingKit.window(1.0, Vector2(2.5, 1.0))]})
	check.call(not wide.validate().is_empty(), "Kit rejects an opening wider than its wall")
	var crowded := BuildingKit.new()
	crowded.wall(Vector2.ZERO, Vector2(6, 0), 3.0, &"block", {"openings": [BuildingKit.door(2.0), BuildingKit.door(2.6)]})
	check.call(not crowded.validate().is_empty(), "Kit rejects overlapping openings")
	var low := BuildingKit.new()
	low.wall(Vector2.ZERO, Vector2(6, 0), 2.2, &"block", {"openings": [BuildingKit.door(3.0)]})
	check.call(not low.validate().is_empty(), "Kit rejects a door with no lintel")
	var floating := BuildingKit.new()
	floating.box(Vector3(0, 0.5, 0), Vector3.ONE, &"block")
	floating.box(Vector3(5, 3, 0), Vector3.ONE, &"block")
	check.call(floating.validate().size() == 1, "Kit flags exactly the floating piece")
	var hung := BuildingKit.new()
	hung.box(Vector3(5, 3, 0), Vector3.ONE, &"block", {"hung": true})
	check.call(hung.validate().is_empty(), "Kit accepts a piece marked as hung")
	var crossing := BuildingKit.new()
	crossing.wall(Vector2(0, 0), Vector2(6, 0), 3.0, &"block")
	crossing.wall(Vector2(3, -2), Vector2(3, 2), 3.0, &"block")
	var crossed := crossing.validate()
	check.call(crossed.size() == 1 and "pass through" in crossed[0], "Kit flags walls that pass through each other: %s" % [crossed])
	var doubled := BuildingKit.new()
	for i in 2:
		doubled.wall(Vector2(0, 0), Vector2(4, 0), 3.0, &"block")
	var fighting := doubled.validate()
	check.call(fighting.size() == 1 and "z-fight" in fighting[0], "Kit flags coinciding faces: %s" % [fighting])
	var flush := BuildingKit.new()
	flush.slab(Rect2(0, 0, 4, 4), flush.ground, &"slab")
	var grounded := flush.validate()
	check.call(grounded.size() == 1 and "ground plane" in grounded[0], "Kit flags a top face lying on the ground: %s" % [grounded])
	var threaded := BuildingKit.new()
	threaded.wall(Vector2(0, 0), Vector2(6, 0), 3.0, &"block")
	threaded.box(Vector3(3, 1, 0), Vector3(0.1, 0.1, 1.0), &"steel", {"embedded": true})
	check.call(threaded.validate().is_empty(), "Kit accepts an embedded piece through a wall: %s" % [threaded.validate()])


## Vertices and vertex colours of every surface, built without materials' effect.
static func _surface_data(source: BuildingKit) -> Array:
	var holder := Node3D.new()
	source.build(holder, true, false)
	var mesh: ArrayMesh = (holder.get_node("KitMesh") as MeshInstance3D).mesh
	var data := []
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		data.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR]])
	holder.free()
	return data


static func _player_capsule() -> CapsuleShape3D:
	var player: Node = load("res://player/player.tscn").instantiate()
	var result: CapsuleShape3D
	for collider: CollisionShape3D in player.find_children("*", "CollisionShape3D", true, false):
		if collider.shape is CapsuleShape3D:
			result = collider.shape.duplicate()
			break
	player.free()
	return result


static func _walk(space: PhysicsDirectSpaceState3D, capsule: CapsuleShape3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform.origin = from + LIFT
	query.motion = to - from
	return space.cast_motion(query)[0] >= 0.999


static func _shape_plan(building: Node3D) -> Array:
	var plan := []
	for collider: CollisionShape3D in building.find_children("*", "CollisionShape3D", true, false):
		plan.append([collider.transform, collider.shape.size])
	return plan

extends SceneTree
## Actual v11 chunk collision/navigation plus the manual stage-one gate controls.
const WAIT = preload("res://tests/support/test_wait.gd")
const LENGTHS := [60.0, 20.0, 20.0, 28.0, 20.0, 20.0, 20.0, 20.0, 28.0]
const GATE_Z := [-162.0, -142.0, -122.0, -94.0, -74.0, -54.0, -34.0, -14.0]
var failures: Array[String] = []

class NavigationHost extends Node3D:
	var giant_navigation_map := NavigationServer3D.map_create()
	func _init() -> void:
		NavigationServer3D.map_set_cell_size(giant_navigation_map, 0.275)
		NavigationServer3D.map_set_cell_height(giant_navigation_map, 0.25)
		NavigationServer3D.map_set_active(giant_navigation_map, true)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE: NavigationServer3D.free_rid(giant_navigation_map)

func _init() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func ray(building: Node3D, start: Vector3, end: Vector3) -> Dictionary:
	return building.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(building.to_global(start), building.to_global(end), 1))

func traverses(probe: CharacterBody3D, building: Node3D, start: Vector3, end: Vector3) -> bool:
	probe.global_transform = building.global_transform * Transform3D(Basis.IDENTITY, start)
	var destination := building.to_global(end)
	probe.move_and_collide(destination - probe.global_position)
	return probe.global_position.distance_to(destination) < 0.05

func run() -> void:
	var world := NavigationHost.new()
	root.add_child(world)
	current_scene = world
	var profile := WorldProfile.new()
	profile.generation_version = 11
	var field := WorldField.new(42, profile)
	var chunk := ChunkGenerator.new()
	chunk.set_meta("skip_actors", true)
	chunk.set_meta("skip_walk_in", true)
	world.add_child(chunk)
	await chunk.generate(field, 0, POISpawner.new(), false)
	if not await WAIT.navigation_ready(self, [chunk]):
		check(false, "Tutorial chunk collision and navigation finish within 60 seconds")
		world.free(); quit(1); return
	var building: Node3D
	for child in chunk.get_children():
		if child is Node3D and child.get_meta("poi_definition_id", "") == &"tutorial_shelter": building = child
	check(building != null, "Actual v11 chunk spawns the dedicated tutorial shelter")
	if building == null: world.free(); quit(1); return
	var definition := POIConfig.definition(&"tutorial_shelter")
	check(definition.validate_scene(building).is_empty(), "Tutorial satisfies the production POI scene contract")
	for path in ["RVSpawn", "PlayerSpawn", "AccessPoints/Front", "AccessPoints/Apron", "StarterEquipment/CraftingStation", "StarterEquipment/Scrapper", "StarterLoot/Flashlight", "StarterLoot/Pistol", "StarterLoot/PistolAmmo1", "StarterLoot/PistolAmmo2"]:
		check(building.get_node_or_null(path) is Marker3D, "Established spawn/inventory contract exists: " + path)
	check(building.get_node_or_null("GarageGate") is Node3D and building.get_node_or_null("GarageButton") is StaticBody3D, "Final exit keeps the StartRun physical gate/button interface")
	check(building.find_children("*", "RigidBody3D", true, false).is_empty(), "Scene contains no embedded dynamic loot actors")
	var triangle_count := 0
	for mesh: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null: triangle_count += mesh.mesh.get_faces().size() / 3
	print("TUTORIAL_STATIC_TRIANGLES: ", triangle_count)
	check(triangle_count <= 200000, "Authored structural mesh instances stay within the 200k triangle budget")
	var bays := building.get_node_or_null("Bays")
	check(bays != null and bays.get_child_count() == 9, "Tutorial has exactly nine authored bays")
	var start_z := -222.0
	for index in range(LENGTHS.size()):
		var bay := building.get_node_or_null("Bays/Bay%02d" % (index + 1)) as Node3D
		check(bay != null, "Bay %d exists" % (index + 1))
		if bay == null: continue
		var end_z: float = start_z + LENGTHS[index]
		check(bay.get_meta("stage_number", 0) == index + 1 and is_equal_approx(float(bay.get_meta("length", 0)), LENGTHS[index]) and is_equal_approx(float(bay.get_meta("start_z", 0)), start_z) and is_equal_approx(float(bay.get_meta("end_z", 0)), end_z), "Bay %d has the correct stage, length and contiguous local interval" % (index + 1))
		for marker_name in ["Parking", "WorkArea"]:
			var marker := bay.get_node_or_null(marker_name) as Marker3D
			check(marker != null, "Bay %d owns its %s marker" % [index + 1, marker_name])
			if marker != null:
				var point := building.to_local(marker.global_position)
				check(absf(point.x) < 20 and point.z > start_z and point.z < end_z, "Bay marker lies within its own 40 m wide interior")
		var mid_z := (start_z + end_z) * 0.5
		for x in [-19.0, 0.0, 19.0]:
			var floor_hit := ray(building, Vector3(x, 0.8, mid_z), Vector3(x, -0.6, mid_z))
			check(not floor_hit.is_empty() and absf(building.to_local(floor_hit.position).y) < 0.03, "Bay %d has a real level floor across its interior width" % (index + 1))
		for side in [-1.0, 1.0]:
			check(not ray(building, Vector3(side * 19, 1, mid_z), Vector3(side * 22, 1, mid_z)).is_empty(), "Bay %d has a solid outer side wall" % (index + 1))
		check(not ray(building, Vector3(10, 1, mid_z), Vector3(10, 12, mid_z)).is_empty(), "Bay %d has a solid overhead enclosure" % (index + 1))
		start_z = end_z
	check(is_equal_approx(start_z, 14), "Nine bays total exactly 236 m from -222 to 14")
	check(not ray(building, Vector3(0, 1, -220), Vector3(0, 1, -225)).is_empty(), "Tutorial rear wall blocks exit behind Bay01")
	var spawn := building.to_local(building.get_node("RVSpawn").global_position)
	check(absf(spawn.x) < 15 and spawn.z > -215 and spawn.z < -169, "Initial RV fits inside the 60 m first bay")
	var probe := CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	probe.add_child(shape)
	world.add_child(probe)
	probe.global_position = building.to_global(Vector3(10, 1, -190))
	await physics_frame
	var gates: Array[ShelterGarageGate] = []
	for index in range(GATE_Z.size()):
		var name := "Gate%02d" % (index + 1)
		var gate := building.get_node_or_null("Gates/" + name) as ShelterGarageGate
		check(gate != null, "Inner gate uses the movable physical gate contract: " + name)
		if gate == null: continue
		gates.append(gate)
		check(gate.left != null and gate.right != null and gate.stable() and gate.progress == 0.0, "Gate configures itself and starts fully closed: " + name)
		check(is_equal_approx(building.to_local(gate.global_position).z, GATE_Z[index]), "Gate is on the correct bay boundary: " + name)
		for leaf in [gate.left, gate.right]:
			if leaf == null: continue
			var collisions: Array = leaf.find_children("*", "CollisionShape3D", true, false)
			check(collisions.size() == 1 and collisions[0].shape is BoxShape3D and collisions[0].shape.size.is_equal_approx(Vector3(3.5, 5, collisions[0].shape.size.z)) and not collisions[0].disabled and leaf.collision_layer & 1, "Gate leaves have active 3.5 m by 5 m physical collision: " + name)
		for x in [-3.5, 0.0, 3.5]:
			check(not traverses(probe, building, Vector3(x, 1, GATE_Z[index] - 2), Vector3(x, 1, GATE_Z[index] + 2)), "Closed gate stops a full player-sized sweep: " + name)
		for x in [-12.0, 12.0]:
			check(not traverses(probe, building, Vector3(x, 1, GATE_Z[index] - 2), Vector3(x, 1, GATE_Z[index] + 2)), "Partition blocks walking around the gate: " + name)
		var inside := building.get_node_or_null("Switches/" + name + "Inside")
		var outside := building.get_node_or_null("Switches/" + name + "Outside")
		check(inside is StaticBody3D and outside is StaticBody3D and inside.has_method("interact") and outside.has_method("interact"), "Gate has physical switches on both sides: " + name)
		if inside != null and inside.has_method("interact"): inside.interact(probe)
	probe.global_position = building.to_global(Vector3(10, 1, -190))
	check(await WAIT.until(self, func() -> bool: return gates.all(func(gate): return gate.is_open()), 10000, true), "All eight switch-driven gates complete their real opening movement")
	for index in range(GATE_Z.size()):
		for x in [-2.8, 0.0, 2.8]:
			check(traverses(probe, building, Vector3(x, 1, GATE_Z[index] - 2), Vector3(x, 1, GATE_Z[index] + 2)), "Opened gate admits full player-sized sweeps across its doorway")
		var from := building.to_global(Vector3(0, 0.1, GATE_Z[index] - 4))
		var to := building.to_global(Vector3(0, 0.1, GATE_Z[index] + 4))
		var path := NavigationServer3D.map_get_path(world.get_world_3d().navigation_map, from, to, true)
		check(not path.is_empty() and path[path.size() - 1].distance_to(to) < 1.0 and path[0].distance_to(from) < 1.0, "Production navigation reaches both sides of every opened inner gate")
	var from := building.to_global(Vector3(0, 0.1, -192))
	var to := building.to_global(Vector3(0, 0.1, 0))
	var through_path := NavigationServer3D.map_get_path(world.get_world_3d().navigation_map, from, to, true)
	check(not through_path.is_empty() and through_path[through_path.size() - 1].distance_to(to) < 1.0 and through_path[0].distance_to(from) < 1.0, "Production navigation connects Bay01 through all eight gates to Bay09")
	# The other side's physical switch closes each gate after the probe departs.
	probe.global_position = building.to_global(Vector3(10, 1, -190))
	for index in range(GATE_Z.size()):
		var button := building.get_node_or_null("Switches/Gate%02dOutside" % (index + 1))
		if button != null and button.has_method("interact"): button.interact(probe)
	check(await WAIT.until(self, func() -> bool: return gates.all(func(gate): return gate.stable() and gate.progress == 0.0), 10000, true), "Opposite-side switches close all gates through the physical controller")
	world.free()
	if failures.is_empty(): print("PASS: v11 nine-bay layout, physical enclosure, eight manual sliding gates and production navigation passage")
	quit(0 if failures.is_empty() else 1)

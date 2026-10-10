extends SceneTree
## Autonomous visual acquisition, navigation and real hand contact against an
## unseated production survivor. No target or occupant is supplied to the AI.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const VEHICLE := preload("res://rv/starter_rv.tscn")
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var player: CharacterBody3D
var vehicle: Node3D
var chassis: Chassis
var map: RID

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func frames(count := 1) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func track_parked_travel(previous: Vector3, stats: Dictionary) -> void:
	# Body displacement includes the real NavigationAgent route and collision
	# response. Ignore near-zero stance adjustment when judging locomotion.
	var movement := (giant.global_position - previous).slide(Vector3.UP) * 60.0
	var lateral_speed := absf(movement.dot(giant.global_basis.x.slide(Vector3.UP).normalized()))
	var moving := movement.length() >= 1.2 and (not giant._parked_plan.is_empty() or not giant._parked_approach_memory.is_empty())
	if moving:
		stats.samples += 1
		stats.peak_lateral = maxf(stats.peak_lateral, lateral_speed)
	stats.lateral_ticks = int(stats.lateral_ticks) + 1 if moving and lateral_speed > .8 else 0
	stats.longest_lateral_ticks = maxi(stats.longest_lateral_ticks, stats.lateral_ticks)

func reset_fixture(start: Vector3, occupant_x: float) -> void:
	if is_instance_valid(giant):
		giant._cancel_execution("fixture_reset")
		giant.queue_free()
	if is_instance_valid(player): player.queue_free()
	if is_instance_valid(vehicle): vehicle.queue_free()
	for part in get_nodes_in_group("player_detached_parts"): part.queue_free()
	await frames(3)
	# Roof equipment becomes an independent world entity when support is
	# removed. It stays physical during its encounter, then leaves with this
	# fixture so a later survivor cannot collide with an earlier RV's debris.
	var previous_drops := world.get_node_or_null(WorldEntities.CONTAINER_NAME)
	if previous_drops != null:
		previous_drops.queue_free()
		await frames(3)
	vehicle = VEHICLE.instantiate()
	vehicle.position.y = 1.226
	world.add_child(vehicle)
	chassis = vehicle.get_node("Chassis")
	chassis.freeze = true
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.global_position = chassis.to_global(Vector3(occupant_x, .55, 4.8))
	player.grab_control.immunity = 0.0
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	giant.set_giant_navigation_map(map)
	giant.global_position = start
	var direction := (chassis.global_position - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z)
	giant._sample("idle_play", 0.0)
	await frames(5)
	var locomotion: Node = player.get_node("Visuals/Locomotion")
	locomotion.animation.play("locomotion/idle", 0.0)
	locomotion.animation.advance(0.0)
	player.get_node("Visuals").skeleton.force_update_all_bone_transforms()
	check(player.seated_in == null and player.can_be_executed(), "Standing fixture uses an unseated production survivor")

func check_standing(start: Vector3, occupant_x: float, label: String, walk_across := false, driver_exit := false) -> void:
	await reset_fixture(start, occupant_x)
	if driver_exit:
		var seat: Node3D = chassis.get_node("DriverSeat")
		seat.interact_hold(player)
		player._physics_process(1.0 / 60.0)
		await frames(3)
		check(player.seated_in == seat, label + " enters the real production driver seat")
		var exit_action := InputEventAction.new()
		exit_action.action = "interact"
		exit_action.pressed = true
		seat._unhandled_input(exit_action)
		await frames(3)
		var locomotion: Node = player.get_node("Visuals/Locomotion")
		locomotion.animation.play("locomotion/idle", 0.0)
		locomotion.animation.advance(0.0)
		player.get_node("Visuals").skeleton.force_update_all_bone_transforms()
		check(player.seated_in == null and seat.current_driver == null, label + " exits through the real interact handler to the supported cabin aisle")
		print("STANDING_DRIVER_EXIT local=", chassis.to_local(player.global_position), " contact=", player.execution_contact_position())
	var roof: RVStructurePanel = chassis.get_node("StructureSlots").panel("roof_0" if driver_exit else "roof_2")
	var smashed: Array[Node] = []
	giant.attack_landed.connect(func(target: Node, kind: String):
		if kind == "slender_speaker_smash": smashed.append(target))
	var acquired := false
	var occupant_seen := false
	var roof_time := -1.0
	var grab_time := -1.0
	var held := false
	var moved := false
	var side_changes := 0
	var previous_side := 0.0
	var min_gap := INF
	var travel := {"samples": 0, "peak_lateral": 0.0, "lateral_ticks": 0, "longest_lateral_ticks": 0}
	for tick in 3600:
		await frames()
		var giant_before := giant.global_position
		giant._physics_process(1.0 / 60.0)
		track_parked_travel(giant_before, travel)
		acquired = acquired or giant.phase == SlenderSpeaker.Phase.CHASE
		occupant_seen = occupant_seen or giant.target_player == player
		if roof.is_destroyed and roof_time < 0.0: roof_time = float(tick) / 60.0
		if walk_across and not moved and roof_time >= 0.0 and giant.phase == SlenderSpeaker.Phase.CHASE \
			and giant._parked_plan.get("occupant") == player and giant._parked_plan.get("roof") == null:
			# Change only the survivor's real transform after the roof opens;
			# perception must observe the new location before adjusting the reach.
			player.global_position.x = chassis.to_global(Vector3(.5, .55, 4.8)).x
			moved = true
		if not giant._parked_plan.is_empty() and giant._parked_plan.get("occupant") == player:
			min_gap = minf(min_gap, float(giant._parked_plan.gap))
			var side := signf(chassis.to_local(giant._parked_plan.standoff_point).x)
			if previous_side != 0.0 and side != previous_side: side_changes += 1
			previous_side = side
		if player.is_executing():
			if grab_time < 0.0: grab_time = float(tick) / 60.0
			player._physics_process(1.0 / 60.0)
			held = held or giant.phase == SlenderSpeaker.Phase.HOLD
		if player.is_player_dead: break
	print("STANDING_ATTACK ", label, " acquired=", acquired, " occupant_seen=", occupant_seen,
		" roof_seconds=", roof_time, " grab_seconds=", grab_time, " min_gap=", min_gap,
		" giant=", giant.global_position, " phase=", giant.phase, " plan=", giant._parked_plan,
		" side_changes=", side_changes, " blocked=", giant._grab_blocking_hits,
		" travel_samples=", travel.samples, " peak_lateral=", travel.peak_lateral,
		" longest_lateral_seconds=", float(travel.longest_lateral_ticks) / 60.0)
	check(acquired and occupant_seen, label + " autonomously acquires stopped RV and standing survivor through actual sight")
	check(roof_time >= 0.0 and smashed.has(roof), label + " physically smashes the roof over the standing survivor")
	check(grab_time > roof_time, label + " routes from CHASE to actual hand capture after roof removal")
	check(held and player.is_player_dead, label + " extracts the standing full body through the opening and completes execution")
	check(side_changes <= 1, label + " retains a stable side while routing around the shell")
	check(travel.samples > 30, label + " checks real parked movement at walking speed")
	check(travel.longest_lateral_ticks < 30, label + " never sustains sideways travel above 0.8m/s for half a second")
	if walk_across: check(moved and side_changes == 0, label + " adjusts the observed reach while retaining the same side after the survivor crosses the cabin")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100, 0, -100), Vector3(-100, 0, 100), Vector3(100, 0, 100), Vector3(100, 0, -100)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	await frames(3)
	NavigationServer3D.map_force_update(map)
	await check_standing(Vector3(-9, 0, 4), 0.0, "left_center")
	await check_standing(Vector3(-9, 0, 4), .5, "left_far_side")
	await check_standing(Vector3(9, 0, 4), -.5, "right_far_side")
	await check_standing(Vector3(-9, 0, 4), -.5, "walk_across", true)
	await check_standing(Vector3(-9, 0, -4), 0.0, "driver_exit", false, true)
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
	world.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: autonomous standing production RV roof attack and physical execution from multiple sides")
	quit(0 if failures.is_empty() else 1)

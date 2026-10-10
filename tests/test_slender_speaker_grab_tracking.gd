extends SceneTree
## Real rig/contact points; only the windup aim is exercised here. Full hand
## ownership, cabin movement and misses are covered by integration suites.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
class PostureTarget extends CharacterBody3D:
	var is_player_dead := false
	var active_climb_rv: Node3D
	var crawling := false
	var posture_reads := 0
	func is_crawling() -> bool:
		posture_reads += 1
		return crawling
	func execution_contact_position() -> Vector3:
		return global_position + Vector3.UP

func posture_observation(world: Node3D, giant: SlenderSpeaker) -> void:
	var target := PostureTarget.new()
	world.add_child(target)
	target.position = Vector3(0, .05, -3)
	giant.reset_after_restore()
	giant.position = Vector3.ZERO
	giant.rotation = Vector3.ZERO
	giant.target_player = target
	giant._sample("idle_play", 0.0)
	await physics_frame
	await process_frame
	check(giant.can_see_player(target), "Posture regression begins from a visible target")
	giant._begin_grab()
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 30, .2)
	collision.shape = box
	wall.add_child(collision)
	var eye: Vector3 = giant.visual.bone_world("socket_focus").origin
	wall.position = Vector3(0, 10, (eye.z + target.global_position.z) * .5)
	world.add_child(wall)
	await physics_frame
	await process_frame
	check(not giant.can_see_player(target), "Real wall occludes posture changes before aim lock")
	target.crawling = true
	target.active_climb_rv = world
	target.posture_reads = 0
	giant.phase_elapsed = .6
	giant._pose_grab_reach(1.0 / 60.0)
	check(target.posture_reads == 0 and not giant._action_context.crawling and not giant._action_context.climbing, "Hidden crawl/climb changes cannot alter recorded grab posture")
	wall.queue_free()
	await physics_frame
	await process_frame
	giant.phase_elapsed = .7
	giant._sample("idle_play", 0.0)
	check(giant.can_see_player(target), "Removing the wall restores actual posture sight before lock")
	giant._pose_grab_reach(1.0 / 60.0)
	check(giant._action_context.crawling and giant._action_context.climbing, "Visible permitted tracking may refresh grab posture")
	giant.phase_elapsed = .9
	giant._pose_grab_reach(1.0 / 60.0)
	var right := giant._bone_position("hand.R")
	var left := giant._bone_position("hand.L")
	target.crawling = false
	target.active_climb_rv = null
	target.posture_reads = 0
	giant._pose_grab_reach(1.0 / 60.0)
	check(giant._grab_locked and target.posture_reads == 0 and giant._action_context.crawling and giant._action_context.climbing, "Final aim lock ignores even visible live crawl/climb state changes")
	check(giant._bone_position("hand.R").is_equal_approx(right) and giant._bone_position("hand.L").is_equal_approx(left), "Locked posture changes preserve both actual wrist endpoints")
	target.queue_free()
	giant.reset_after_restore()
	await process_frame
var failures: Array[String] = []
class FixtureRV extends StaticBody3D:
	func add_item(_item): pass
	func deduct_materials(_cost): pass
	func road_speed() -> float: return 0.0
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func recovery(world: Node3D, giant: SlenderSpeaker) -> void:
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100, 0, -100), Vector3(-100, 0, 100), Vector3(100, 0, 100), Vector3(100, 0, -100)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	giant.set_giant_navigation_map(map)
	var vehicle := FixtureRV.new()
	var vehicle_collision := CollisionShape3D.new()
	var vehicle_shape := BoxShape3D.new()
	vehicle_shape.size = Vector3(2, 3, 6)
	vehicle_collision.shape = vehicle_shape
	vehicle_collision.position.y = 1.5
	vehicle.add_child(vehicle_collision)
	world.add_child(vehicle)
	vehicle.add_to_group(Groups.RV)
	giant.reset_after_restore()
	giant.position = Vector3(-5, .02, 0)
	giant.rotation.y = -PI / 2
	giant.velocity = Vector3.ZERO
	giant._sample("idle_play", 0.0)
	await physics_frame
	await process_frame
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	check(giant.target_vehicle == vehicle and giant._encounter_decision.get("vehicle_visible", false),
		"Recovery fixture acquires its actual RV shell before the route is obstructed")
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.2, 30, 5)
	collision.shape = box
	blocker.add_child(collision)
	blocker.position = Vector3(-3.5, 10, 0)
	world.add_child(blocker)
	await physics_frame
	await process_frame
	NavigationServer3D.map_force_update(map)
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	check(not giant._encounter_decision.get("vehicle_visible", false)
		and giant.target_vehicle == vehicle, "Real route obstruction hides the shell while retaining encounter ownership")
	giant._set_phase(SlenderSpeaker.Phase.SEARCH)
	giant._sense_remaining = 100.0
	giant._parked_approach_remaining = 8.0
	giant._parked_approach_memory = {
		"vehicle_id": vehicle.get_instance_id(), "occupant_id": 0,
		"navigation_point": Vector3(-2.24, .02, 0), "standoff_point": Vector3(-2.24, .02, 0),
		"surface_point": Vector3(0, 1, 0), "route_frame": Transform3D.IDENTITY,
		"route_shell": AABB(Vector3(-1, 0, -3), Vector3(2, 3, 6)),
		"body_margin": 1.1, "arrival_radius": .12, "release_radius": .24,
	}
	var blocked_at := Vector3.INF
	var escaped := false
	for tick in 420:
		await physics_frame
		await process_frame
		giant._physics_process(1.0 / 60.0)
		if giant._parked_recoveries > 0 and blocked_at == Vector3.INF:
			blocked_at = giant.global_position
		if blocked_at != Vector3.INF and giant.global_position.x < blocked_at.x - .45:
			escaped = true
			break
	check(giant._parked_recoveries == 1 and escaped, "A physically blocked remembered approach turns and walks outward instead of staying stuck")
	check(giant.global_position.x < -4.5, "Recovery never crosses the actual blocking wall")
	print("CABIN_RECOVERY count=", giant._parked_recoveries, " escaped=", escaped, " position=", giant.global_position)
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var giant: SlenderSpeaker = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	var player: CharacterBody3D = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0, .05, -3)
	player.grab_control.immunity = 0.0
	await physics_frame
	await process_frame
	giant.target_player = player
	check(giant.can_see_player(player), "Windup starts with an actually visible survivor")
	giant._begin_grab()
	var initial := giant._grab_correction
	var visible_ticks := 0
	for tick in 35:
		player.position.x += .012
		giant.phase_elapsed = float(tick + 1) / 60.0
		if giant.can_see_player(player): visible_ticks += 1
		var before := giant._grab_correction
		giant._pose_grab_reach(1.0 / 60.0)
		check(before.distance_to(giant._grab_correction) <= 2.0 / 60.0 + .0001, "Aim correction obeys its 2m/s bound")
		check(giant._grab_contact.distance_to(giant._grab_tracking_origin) <= .751, "Windup cannot chase beyond the .75m initial reach area")
	check(visible_ticks > 0 and giant._grab_correction.distance_to(initial) > .05, "Visible early motion adjusts the actual reach correction")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, 30, .2)
	collision.shape = shape
	wall.add_child(collision)
	var eye: Vector3 = giant.visual.bone_world("socket_focus").origin
	wall.position = Vector3(0, 10, (eye.z + player.global_position.z) * .5)
	world.add_child(wall)
	await physics_frame
	await process_frame
	check(not giant.can_see_player(player), "Real wall occludes the survivor during early reach")
	var hidden_aim := giant._grab_correction
	player.position.x += .4
	giant.phase_elapsed = .6
	giant._pose_grab_reach(1.0 / 60.0)
	check(giant._grab_correction.is_equal_approx(hidden_aim), "Hidden movement cannot update the early grab aim")
	wall.queue_free()
	await physics_frame
	await process_frame
	giant.phase_elapsed = .8
	giant._pose_grab_reach(1.0 / 60.0)
	var locked := giant._grab_correction
	player.position.x -= 1.0
	giant.phase_elapsed = .9
	giant._pose_grab_reach(1.0 / 60.0)
	check(giant._grab_locked and giant._grab_correction.is_equal_approx(locked), "Final quarter second preserves its locked landing point")
	player.global_position = Vector3(1000, 0, 1000)
	await posture_observation(world, giant)
	await recovery(world, giant)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: visible bounded early grab aim, real occlusion, late lock and physical stall recovery")
	quit(0 if failures.is_empty() else 1)

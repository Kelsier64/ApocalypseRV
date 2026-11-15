extends RefCounted
## Runs the production giant on a small baked giant map and proves that each
## situation either makes progress or ends. Budgets come from its own settings.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const VEHICLE := preload("res://rv/new_rv.tscn")
## Far from every other fixture, beyond the giant's sight range.
const ORIGIN := Vector3(3000, 0, 3000)
const HALF := 35.0

var tree: SceneTree
var check: Callable
var stage: Node3D
var map: RID
var giant: SlenderSpeaker
var player: CharacterBody3D

func run(scene_tree: SceneTree, world: Node3D, checker: Callable) -> void:
	tree = scene_tree
	check = checker
	stage = Node3D.new()
	world.add_child(stage)
	stage.global_position = ORIGIN
	if not await _build_navigation():
		check.call(false, "Liveness fixture bakes its giant navigation floor")
		stage.queue_free()
		return
	player = PLAYER.instantiate()
	stage.add_child(player)
	player.set_physics_process(false)
	giant = GIANT.instantiate()
	stage.add_child(giant)
	giant.set_giant_navigation_map(map)
	giant.set_physics_process(false)
	await tree.physics_frame
	await _patrol_past_unreachable_points()
	await _patrol_rehomes_from_unreachable_territory()
	await _reachable_survivor_is_attacked()
	await _unreachable_survivor_ends_in_disengage()
	await _unreachable_vehicle_ends_in_disengage()
	giant.set_physics_process(false)
	stage.queue_free()
	await tree.physics_frame
	NavigationServer3D.free_rid(map)

func _build_navigation() -> bool:
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(map, .275)
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.agent_height = 15.0
	mesh.agent_radius = 1.1
	mesh.agent_max_climb = .5
	mesh.cell_size = .275
	mesh.cell_height = .25
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	region.navigation_mesh = mesh
	stage.add_child(region)
	region.set_navigation_map(map)
	# Only this slab is navigable. The surrounding ground stays physical and
	# visible, so anything standing beyond its edge can be seen but not reached.
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF * 2.0, .3, HALF * 2.0)
	collision.shape = shape
	floor_body.add_child(collision)
	region.add_child(floor_body)
	floor_body.position = Vector3(0, -.15, 0)
	region.bake_navigation_mesh(false)
	for frame in 120:
		await tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0: return true
	return false

func _place_giant(offset: Vector3, yaw := 0.0) -> void:
	giant.set_physics_process(false)
	giant._cancel_execution("fixture_reset")
	giant.global_position = ORIGIN + offset + Vector3.UP * .02
	giant.rotation = Vector3(0, yaw, 0)
	giant.velocity = Vector3.ZERO
	giant.reset_after_restore()
	giant.set_physics_process(true)

func _hide_player() -> void:
	player.global_position = ORIGIN + Vector3(0, 0, giant.settings.sight_range * 3.0)

func _inside_floor(point: Vector3) -> bool:
	var local := point - ORIGIN
	return absf(local.x) <= HALF and absf(local.z) <= HALF

## Steps real physics frames. "Idle" is a tick with neither travel nor turning.
func _simulate(seconds: float, stop := Callable()) -> Dictionary:
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	var previous := giant.global_position
	var previous_yaw := giant.rotation.y
	var idle := 0.0
	var result := {"elapsed": 0.0, "travel": 0.0, "longest_idle": 0.0, "stopped": false}
	for tick in int(ceil(seconds / step)):
		await tree.physics_frame
		var moved := (giant.global_position - previous).slide(Vector3.UP).length()
		var turned := absf(angle_difference(previous_yaw, giant.rotation.y))
		previous = giant.global_position
		previous_yaw = giant.rotation.y
		result.travel += moved
		result.elapsed += step
		idle = idle + step if moved < .05 * step and turned < deg_to_rad(1.0) * step else 0.0
		result.longest_idle = maxf(result.longest_idle, idle)
		if stop.is_valid() and stop.call():
			result.stopped = true
			break
	return result

func _engagement_budget() -> float:
	var settings := giant.settings
	var attempts := int(settings.get("liveness_attempts")) if settings.get("liveness_attempts") != null else 2
	var stall := float(settings.get("liveness_stall_seconds")) if settings.get("liveness_stall_seconds") != null else 3.0
	var reposition := float(settings.get("liveness_reposition_seconds")) if settings.get("liveness_reposition_seconds") != null else 6.0
	var drought := float(settings.get("liveness_drought_seconds")) if settings.get("liveness_drought_seconds") != null else 25.0
	# Approach, every recovery attempt with its walk, then the final stall.
	return 15.0 + maxf(drought, float(attempts + 1) * stall + float(attempts) * reposition)

func _idle_limit() -> float:
	var stall = giant.settings.get("liveness_stall_seconds")
	return (float(stall) if stall != null else 3.0) + 1.0

func _patrol_past_unreachable_points() -> void:
	_hide_player()
	_place_giant(Vector3(HALF - 10.0, 0, 0))
	# Centre the patrol ring on the navigation edge: about half its points lie
	# beyond the slab whatever the ring's radius is.
	giant.home_position = ORIGIN + Vector3(HALF, 0, 0)
	var start_index := giant._patrol_index
	var stats := await _simulate(40.0)
	check.call(giant.phase == SlenderSpeaker.Phase.PATROL, "Unobserved giant stays on patrol")
	check.call(giant._patrol_index - start_index >= 3, "Patrol moves on past destinations beyond its navigation instead of waiting at the edge (advanced %d)" % (giant._patrol_index - start_index))
	check.call(stats.longest_idle <= _idle_limit(), "Patrol near unreachable destinations never stands idle (%.1fs)" % stats.longest_idle)
	check.call(stats.travel >= giant.settings.patrol_speed * stats.elapsed * .3, "Patrol near unreachable destinations keeps walking (%.1fm)" % stats.travel)

func _patrol_rehomes_from_unreachable_territory() -> void:
	_hide_player()
	_place_giant(Vector3.ZERO)
	# A chase can end far from a home whose navigation is no longer loaded.
	giant.home_position = ORIGIN + Vector3(HALF * 12.0, 0, 0)
	# It first walks the edge nearest that home, one unreachable point at a time.
	var stats := await _simulate(60.0, func() -> bool: return _inside_floor(giant.home_position))
	check.call(stats.stopped, "Patrol adopts reachable territory when its old home has no navigation")
	check.call(stats.longest_idle <= _idle_limit(), "Returning toward a lost home never stands idle (%.1fs)" % stats.longest_idle)
	stats = await _simulate(15.0)
	check.call(stats.travel >= giant.settings.patrol_speed * stats.elapsed * .3, "Re-homed patrol keeps walking (%.1fm)" % stats.travel)

func _reachable_survivor_is_attacked() -> void:
	player.global_position = ORIGIN + Vector3(0, 0, -20)
	_place_giant(Vector3.ZERO)
	var stats := await _simulate(20.0, func() -> bool: return giant.phase == SlenderSpeaker.Phase.GRAB)
	check.call(stats.stopped, "Visible reachable survivor is approached and grabbed")
	check.call(giant.get("_liveness_escalations") == 0, "An ordinary chase needs no stall recovery")
	_hide_player()
	_place_giant(Vector3.ZERO)

func _unreachable_survivor_ends_in_disengage() -> void:
	# Beyond every arm's reach of the navigable edge, in plain sight.
	player.global_position = ORIGIN + Vector3(0, 0, -(HALF + 12.0))
	_place_giant(Vector3(0, 0, -10))
	var seen := {"chase": false}
	var stats := await _simulate(_engagement_budget(), func() -> bool:
		if giant.phase == SlenderSpeaker.Phase.CHASE: seen.chase = true
		return seen.chase and giant.phase == SlenderSpeaker.Phase.PATROL and giant._encounter_decision.get("mode", "none") == "none")
	check.call(seen.chase, "Visible unreachable survivor is pursued first")
	check.call(stats.stopped, "Pursuit of a visible unreachable survivor ends instead of standing at the navigation edge")
	check.call(stats.longest_idle <= _idle_limit(), "Unreachable pursuit never stands idle beyond its stall window (%.1fs)" % stats.longest_idle)
	check.call(not player.is_player_dead and not player.is_executing(), "Unreachable survivor is never captured by proximity")
	var reason = giant.get("_liveness_reason")
	check.call(reason is String and not String(reason).is_empty() and String(reason) in giant.encounter_debug_text(), "Disengagement names its cause in the debug text")
	stats = await _simulate(6.0, func() -> bool: return giant.phase != SlenderSpeaker.Phase.PATROL)
	check.call(not stats.stopped, "Disengaged giant does not reacquire the same stationary survivor at once")
	check.call(stats.travel >= giant.settings.patrol_speed * stats.elapsed * .3, "Disengaged giant walks away on patrol (%.1fm)" % stats.travel)
	_hide_player()

func _unreachable_vehicle_ends_in_disengage() -> void:
	_hide_player()
	var vehicle: Node3D = VEHICLE.instantiate()
	stage.add_child(vehicle)
	vehicle.position = Vector3(HALF + 10.0, 0, 0)
	var chassis: Chassis = vehicle.get_node("Chassis")
	chassis.freeze = true
	for frame in 5: await tree.physics_frame
	_place_giant(Vector3(10, 0, 0), -PI * .5)
	var panels_before := 0
	for panel in chassis.find_children("*", "RigidBody3D", true, false):
		if panel is RVStructurePanel and not panel.is_destroyed: panels_before += 1
	var seen := {"chase": false}
	var stats := await _simulate(_engagement_budget(), func() -> bool:
		if giant.phase == SlenderSpeaker.Phase.CHASE: seen.chase = true
		return seen.chase and giant.phase == SlenderSpeaker.Phase.PATROL and giant._encounter_decision.get("mode", "none") == "none")
	check.call(seen.chase, "Visible parked RV beyond navigation is approached first")
	check.call(stats.stopped, "Approach to an unreachable parked RV ends instead of looping beside it")
	var panels_after := 0
	for panel in chassis.find_children("*", "RigidBody3D", true, false):
		if panel is RVStructurePanel and not panel.is_destroyed: panels_after += 1
	check.call(panels_after == panels_before, "Unreachable RV takes no proximity damage")
	stats = await _simulate(6.0, func() -> bool: return giant.phase != SlenderSpeaker.Phase.PATROL)
	check.call(not stats.stopped, "Disengaged giant does not reacquire the same parked RV at once")
	vehicle.queue_free()
	await tree.physics_frame

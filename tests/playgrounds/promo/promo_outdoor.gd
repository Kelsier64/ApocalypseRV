extends RefCounted

const TREE := "res://world/roadside_kit/tree.tscn"
const FLASHLIGHT := "res://props/flashlight.tscn"
const AERIAL_RAIL_SECONDS := 12.0
const TIME_LAPSE_SECONDS := 12.0
const DRIVE_SECONDS := {"D1": 13.0, "O4": 19.0}

var road_event: Dictionary
var event_mark := Vector3.INF
var giant_mark := Vector3.INF
var triggered := false
var white: WhiteApparition
var time_lapse_seconds := 0.0
var drive_replay := false
var drive_offset := 0.0

func placement(world) -> Transform3D:
	var field: WorldField = world.field
	var id: String = world.shot_id
	var distance := float(world.shot.distance)
	if world.shot.has("event"):
		var plan := RoadSpawns.plan(field, int(world.shot.band))
		var events: Array = plan[world.shot.event]
		if not events.is_empty():
			if id == "O1":
				event_mark = events.front()
				event_mark.y -= 0.5
			else:
				road_event = events.front()
				event_mark = road_event.transform.origin
	if id == "O2" or id == "D2":
		if event_mark.is_finite():
			var lane := field.road_query(event_mark.x, event_mark.z)
			var approach: Transform3D = lane.frame
			drive_offset = approach.basis.x.dot(event_mark - approach.origin)
			if id == "D2": drive_offset += 1.25
			var runup := 38.0 if id == "O2" else 16.0
			return _road_mark(field, float(lane.s) - runup * absf(approach.basis.z.z), drive_offset)
	if id == "D1":
		drive_offset = field.road_width(distance) * 0.5 + 0.7
		return _road_mark(field, distance - 14.0, drive_offset)
	if id == "D4": return _road_mark(field, distance, -4.5)
	if id == "O5":
		var parked := field.road_frame(distance)
		parked.basis = parked.basis.rotated(Vector3.UP, PI)
		return parked
	if id == "O3" and world.shot.has("stop"):
		var site := field.stop(int(world.shot.stop))
		var building: Transform3D = site.building
		var point := building * Vector3(-4.5, 0, 8)
		point.y = field.height_at(point.x, point.z)
		return Transform3D(building.basis, point)
	return field.road_frame(distance)

func _road_mark(field: WorldField, distance: float, lateral: float) -> Transform3D:
	var frame := field.road_frame(distance)
	frame.origin += frame.basis.x * lateral
	frame.origin.y = field.height_at(frame.origin.x, frame.origin.z)
	return frame

func prepare(world) -> bool:
	var generator: Node = world.get_node("WorldGenerator")
	var container := WorldEntities.get_container(world)
	var actor: Node3D = world.actor
	var rv: Chassis = world.rv
	var field: WorldField = generator.field
	if world.shot.get("seat", false):
		actor.camera_locked = false
		var seat: Node = rv.get_node("DriverSeat")
		seat.interact_hold(actor)
		if seat.current_driver != actor: return false
	if world.shot.has("event") and not event_mark.is_finite(): return false
	match world.shot_id:
		"O1":
			for child in container.get_children():
				if child is BarrelMan and child.global_position.distance_to(event_mark) < 15.0:
					child.queue_free()
			var enemy: BarrelMan = world.spawn(RoadSpawns.BARREL_MAN_SCENE, event_mark + Vector3.UP * 0.02, container)
			enemy.set_physics_process(false)
			world.subject = enemy
			var lane: Transform3D = field.road_frame(-event_mark.z)
			for offset in [-1.8, 1.7]:
				var point := event_mark + lane.basis.x * float(offset)
				point.y = field.height_at(point.x, point.z) + 0.5
				world.spawn(RoadSpawns.OIL_BARREL_SCENE, point, container, true)
			actor.global_position = event_mark + lane.basis.z * 8.0
			actor.global_position.y = field.height_at(actor.global_position.x, actor.global_position.z) + 0.12
			world._aim_at(event_mark + Vector3.UP * 0.72)
		"O2":
			world.subject = _event_actor(container, event_mark)
			if world.subject == null: return false
		"O3":
			world.spawn("res://props/scrap.tscn", actor.global_position + actor.global_basis.z * -1.8 + Vector3.UP * 0.08, container)
			white = world.spawn("res://enemies/white_apparition/white_apparition.tscn", actor.global_position, container)
			white.configure(actor, world.get_node("WorldClock"))
			white._world_id = white.get_world_3d().get_instance_id()
			white.set_physics_process(false)
		"O4", "O5":
			if world.shot_id == "O5":
				var slots: RVStructureSlots = rv.get_node("StructureSlots")
				for slot in ["roof_0", "roof_1", "roof_2"]:
					var panel := slots.panel(slot)
					panel.set_health(minf(panel.max_health, 20.0))
				# The RV has already lost the driver's side panel. The giant
				# still has to remove the roof and reach the seated survivor.
				slots.panel("left_0").set_health(0.0)
			for frame in 240:
				if NavigationServer3D.map_get_iteration_id(generator.giant_navigation_map) != 0:
					giant_mark = _find_giant_mark(generator, rv.global_position, world.shot_id == "O5")
					if giant_mark.is_finite(): break
				await world.get_tree().physics_frame
			if not giant_mark.is_finite(): return false
			print("PROMO GIANT MARK: ", giant_mark)
		"D1":
			var distance := float(world.shot.distance)
			for offset in [0.0, 7.0, 14.0]:
				var pose := _road_mark(field, distance + float(offset), field.road_width(distance) * 0.5 + 0.7)
				var tree: Node3D = world.spawn(TREE, pose.origin, container)
				tree.scale = Vector3.ONE * 0.74
		"D2":
			var chunk: Node3D
			for entry in generator.active_chunks:
				if entry.index == int(world.shot.band): chunk = entry.node
			if chunk == null: return false
			world.subject = chunk.get_node_or_null("RoadSpikeStrip")
			if world.subject == null: return false
			for wreck in chunk.get_children():
				if not str(wreck.name).begins_with("RoadWreck"): continue
				var lane := field.road_query(event_mark.x, event_mark.z)
				wreck.global_transform = _road_mark(field, float(lane.s) + 16.0, drive_offset + 4.4)
				break
		"D4":
			actor.add_item("Recovery Jack", false, RecoveryJack.SCENE)
			rv.global_basis = rv.global_basis.rotated(rv.global_basis.z, deg_to_rad(57))
			rv.global_position.y += 0.42
			rv.reset_physics_interpolation()
			world._aim_at(rv.global_position + Vector3.UP)
		"D5":
			world._aim_at(rv.global_position + rv.global_basis.z * 3.0 + Vector3.UP * 0.35)
		"W1", "W2", "W3":
			if world.director.use_generated_rail(): _aerial_rail(world)
	return true

func _event_actor(container: Node3D, mark: Vector3) -> Node3D:
	for entity in container.get_children():
		if entity is OilBarrel and entity.global_position.distance_to(mark) < 2.5: return entity
	return null

func _find_giant_mark(generator: Node, target: Vector3, parked: bool) -> Vector3:
	var field: WorldField = generator.field
	var best := Vector3.INF
	var best_score := INF
	for longitudinal in [-50.0, -35.0, -20.0, 0.0, 16.0, 27.0, 42.0, 60.0]:
		var frame := field.road_frame(-target.z + float(longitudinal))
		for side in [-1, 1]:
			for distance in [41.0, 48.0, 55.0, 68.0, 85.0]:
				var p := frame.origin + frame.basis.x * (float(distance) + field.road_width(-frame.origin.z) * 0.5) * float(side)
				p.y = field.height_at(p.x, p.z)
				if not SlenderSpeakerSpawns.static_valid(field, p) or not SlenderSpeakerSpawns.forest_valid(field, p): continue
				var nav := NavigationServer3D.map_get_closest_point(generator.giant_navigation_map, p)
				if nav.distance_to(p) > 1.8: continue
				var score := absf(float(longitudinal) - (0.0 if parked else 35.0)) + p.distance_to(target) * 0.25
				if score < best_score:
					best_score = score
					best = nav + Vector3.UP * 0.12
	return best

func _aerial_rail(world) -> void:
	var field: WorldField = world.field
	var center := float(world.shot.distance)
	world.director.clear_generated_rail()
	world.director.rail.duration = AERIAL_RAIL_SECONDS
	for offset in [-65.0, -36.0, -6.0, 24.0, 55.0]:
		var frame := field.road_frame(center + float(offset))
		var target := field.road_frame(center + float(offset) + 50.0).origin
		var origin := frame.origin + frame.basis.x * lerpf(39.0, 12.0, (float(offset) + 65.0) / 120.0)
		origin.y = maxf(field.height_at(origin.x, origin.z), frame.origin.y) + 32.0
		world.director.generated_rail_key(Transform3D(Basis.looking_at(target - origin), origin))

func trigger(world) -> bool:
	var rv: Chassis = world.rv
	if triggered:
		if world.shot_id != "D4": return false
		var result := RecoveryJack.deploy_from_inventory(world.actor, rv)
		world.director.notify(result.message)
		return result.has("jack")
	match world.shot_id:
		"O1":
			world.subject.set_physics_process(true)
		"O3":
			white._rng.seed = int(world.shot.seed) ^ 0x57484954
			if not white._try_emerge(world.actor.camera): return false
			white.set_physics_process(true)
			world.subject = white
		"O4", "O5":
			var giant: SlenderSpeaker = world.spawn(SlenderSpeakerSpawns.SCENE, giant_mark, WorldEntities.get_container(world))
			giant.set_giant_navigation_map(world.get_node("WorldGenerator").giant_navigation_map)
			var target := rv.global_position
			giant.look_at(Vector3(target.x, giant_mark.y, target.z))
			world.subject = giant
			if world.shot_id == "O4":
				rv.set_engine_running(true)
				rv.set_handbrake(false)
		"O2", "D1", "D2", "D3":
			if not rv.set_engine_running(true): return false
			rv.set_handbrake(false)
		"D4":
			rv.freeze = false
			rv.sleeping = false
			rv.angular_velocity = rv.global_basis.z * 0.65
		"D5":
			rv.set_handbrake(false)
			rv.sleeping = false
		"W1", "W2":
			return world.director.play_rail()
		"W3":
			if not world.director.play_rail(): return false
			time_lapse_seconds = TIME_LAPSE_SECONDS
	triggered = true
	return true

func tick(world, delta: float) -> void:
	if drive_replay:
		_drive_road(world)
	if time_lapse_seconds <= 0.0: return
	time_lapse_seconds -= delta
	var clock := world.get_node("WorldClock") as WorldClock
	var fog := 1.0 - smoothstep(2.0, 8.0, absf(time_lapse_seconds - 5.0))
	clock.weather.set_weather(Vector3(1.0 - fog, fog, fog), true)
	clock.advance_game_seconds(delta * WorldClock.DAY_SECONDS / 12.0, delta)

func _drive_road(world) -> void:
	var rv: Chassis = world.rv
	var field: WorldField = world.field
	var road := field.road_query(rv.global_position.x, rv.global_position.z)
	var frame: Transform3D = road.frame
	var lookahead := clampf(5.0 + rv.linear_velocity.length() * 0.65, 5.0, 13.0)
	var ahead := _road_mark(field, float(road.s) + lookahead * absf(frame.basis.z.z), drive_offset)
	var relative := rv.to_local(ahead.origin)
	var correction := -atan2(relative.x, maxf(0.1, -relative.z))
	rv.control_override = {"throttle": 1.0, "steering": clampf(correction * 2.4, -1.0, 1.0)}

func mark_jack_operator(world) -> bool:
	var rv: Chassis = world.rv
	var player: CharacterBody3D = world.actor
	var approach := rv.global_basis.z.slide(Vector3.UP).normalized()
	var side := Vector3.UP.cross(approach)
	if not RecoveryJack._can_lift_from(rv, approach): side = -side
	var prior := player.global_position
	var space := rv.get_world_3d().direct_space_state
	for along in [0.0, -2.0, 2.0, -4.0, 4.0]:
		for offset in [2.8, 3.4, 3.9]:
			var point := rv.global_position + approach * float(along) + side * float(offset)
			var hit := RecoveryJack._ground_point(space, point + Vector3.UP * 3.0, point - Vector3.UP * 5.0, [rv.get_rid(), player.get_rid()])
			if hit.is_empty(): continue
			player.global_position = Vector3(hit.position) + Vector3.UP * 0.05
			if RecoveryJack._find_deployment(player, rv, approach, side).is_empty(): continue
			world._aim_at(rv.global_position + Vector3.UP)
			player.reset_physics_interpolation()
			return true
	player.global_position = prior
	return false

## Unattended take for Movie Maker. Returns how long to keep filming, or -1 after failing.
func autoplay(world) -> float:
	match world.shot_id:
		"W1", "W2", "W3":
			var started: bool = world.trigger_take() if world.shot_id == "W3" else world.director.play_rail()
			if not started:
				world._fail("Could not start the rail")
				return -1.0
			var rail_seconds := float(world.director.rail.duration) + 0.5
			return maxf(TIME_LAPSE_SECONDS, rail_seconds) if world.shot_id == "W3" else rail_seconds
		"O3":
			if not world.trigger_take():
				world._fail("White apparition had no valid emergence point")
				return -1.0
			await world.get_tree().create_timer(0.6).timeout
			world._aim_at(world.subject.global_position + WhiteApparition.CHEST)
			return 4.5
		"O2", "D1", "D2", "D3", "O4":
			if not world.trigger_take():
				world._fail("Could not start the driving action")
				return -1.0
			drive_replay = true
			if world.director.exterior_requested(): world.director.follow_preset("chase", world.rv)
			if world.shot_id == "D3":
				await world.get_tree().create_timer(2.8).timeout
				world.rv.set_gear(2)
				await world.get_tree().create_timer(2.0).timeout
				world.rv.set_gear(3)
			return DRIVE_SECONDS.get(world.shot_id, 11.0)
		"D4":
			world.trigger_take()
			await world.get_tree().create_timer(7.0).timeout
			if world.rv.rollover_state() == Chassis.Rollover.UPRIGHT or not mark_jack_operator(world) or not world.trigger_take():
				world._fail("RV did not settle at a usable recovery-jack mark")
				return -1.0
			return 9.0
	if not world.trigger_take():
		world._fail("Could not start the take")
		return -1.0
	return 45.0 if world.shot_id == "O5" else 7.0

func autoplay_error(world) -> String:
	if world.shot_id == "D4" and world.rv.rollover_state() != Chassis.Rollover.UPRIGHT: return "Recovery jack did not right the RV"
	return ""

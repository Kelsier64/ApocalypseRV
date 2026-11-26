extends "res://tests/playgrounds/promo/promo_outdoor.gd"
## Trailer takes (T group). Each shot's `timeline` drives the RV, the cab speaker, the
## weather and, in unattended takes, the driver's view. F3 starts the timeline.

const TIMELINE := preload("res://tests/playgrounds/promo/promo_timeline.gd")
const BROADCAST := preload("res://tests/playgrounds/promo/promo_broadcast.gd")
const EYELIDS := preload("res://player/san_eyelids.gdshader")
const RV_SCENE := "res://rv/new_rv.tscn"
const CORPSE := "res://props/corpse.tscn"
const STEERING_GAIN := 2.4
## Throttle or brake per km/h of speed error.
const SPEED_GAIN := 0.12
## A sudden loss of this share of the speed, and at least IMPACT_DROP km/h, within
## IMPACT_WINDOW seconds is the crash.
const IMPACT_DROP := 10.0
const IMPACT_SHARE := 0.35
const IMPACT_WINDOW := 0.25

var timeline := TIMELINE.new()
var broadcast := BROADCAST.new()
var cruise: Dictionary = {}
var unattended := false
## The staged pole the giant stands beyond and the swerve aims at: {s, point, node}.
var pole: Dictionary = {}
## Armed swerve: {"within": metres}; "active" once the RV is that close to the pole.
var swerve: Dictionary = {}
var impact_seconds := -1.0
var wreck: Node3D
var giant: SlenderSpeaker
## Giant phases already marked in take.json, and whether the crawl input is held.
var _marked_phases: Dictionary = {}
var _crawl_seconds := 0.0
var _crawl_action := "move_forward"
## Unattended prone takes: the survivor turns to keep the giant in view.
var _gaze := {}
var _cut_away := false
## Set by giant_release: forget the RV once the current attack ends.
var _release_pending := false
## After the release the giant turns to face the survivor before its AI resumes.
var _turning := false
const GIANT_TURN_DEGREES := 75.0
var _speeds: Array[Vector2] = []
var _look := {}
var _eyes := {}
var _weather := {}
var _lids := ShaderMaterial.new()
var _lid_rect: ColorRect

func placement(world) -> Transform3D:
	if world.shot.has("rv_at_pole"): return _crashed_pose(world)
	return _road_mark(world.field, float(world.shot.distance), float(world.shot.get("lateral", 0.0)))

## Where T2 leaves the RV: turned off the road with the pole `ahead` metres in front of
## its centre and `side` metres to its right.
func _crashed_pose(world) -> Transform3D:
	var spec: Dictionary = world.shot.rv_at_pole
	var pole_spec: Dictionary = world.shot.crash_pole
	var point := _road_mark(world.field, float(world.shot.distance) + float(pole_spec.s), float(pole_spec.lateral))
	var basis := point.basis.rotated(Vector3.UP, deg_to_rad(float(spec.get("yaw", 0.0))))
	var origin := point.origin + basis.z * float(spec.ahead) - basis.x * float(spec.get("side", 0.0))
	origin.y = world.field.height_at(origin.x, origin.z)
	return Transform3D(basis, origin)

func prepare(world) -> bool:
	if not await super.prepare(world): return false
	timeline.load_from(world.shot.timeline)
	if not broadcast.attach(world.rv, int(world.shot.get("radio_level", 1))): return false
	if not world.shot.get("radio", true): broadcast.silence()
	_build_eyelids(world, 1.0 if world.shot.get("eyes_closed", false) else 0.0)
	if world.shot.get("invulnerable", false): world.actor.invulnerable = true
	if world.shot.has("wreck") and not await _stage_wreck(world, world.shot.wreck): return false
	if world.shot.has("crash_pole"): _stage_pole(world, world.shot.crash_pole)
	if world.shot.has("prone"): _stage_prone(world, world.shot.prone)
	if not world.shot.get("engine", true): return true
	# The engine idles behind the handbrake until the timeline starts.
	return world.rv.set_engine_running(true)

## The driver thrown clear: lying on the road in the crawl posture, looking at `look`
## (road coordinates, metres up) with the keyboard theirs for the crawl.
func _stage_prone(world, spec: Dictionary) -> void:
	var field: WorldField = world.field
	var actor: CharacterBody3D = world.actor
	var mark := _road_mark(field, float(world.shot.distance) + float(spec.s), float(spec.lateral))
	actor.global_position = mark.origin + Vector3.UP * 0.05
	actor.camera_locked = false
	actor.rv_support.clear()
	actor.set_prone(true)
	# The cut lands on the frame the giant's hand closes, after the grab takes the view.
	if world.shot.has("cut_away"):
		actor.grab_started.connect(func() -> void:
			if not _cut_away and is_instance_valid(giant): _cut_away_from_eyes.call_deferred(world, world.shot.cut_away))
	actor.reset_physics_interpolation()
	var look: Dictionary = spec.look
	var target := _road_mark(field, float(world.shot.distance) + float(look.s), float(look.lateral)).origin
	world._aim_at(target + Vector3.UP * float(look.get("up", 0.0)))

## The previous unit's RV on its side, as scenery: no physics, no processing, and out of
## the RV groups so neither monsters nor equipment treat it as a vehicle.
func _stage_wreck(world, spec: Dictionary) -> bool:
	var field: WorldField = world.field
	var container := WorldEntities.get_container(world)
	wreck = (load(RV_SCENE) as PackedScene).instantiate() as Node3D
	wreck.name = "PromoWreck"
	wreck.process_mode = Node.PROCESS_MODE_DISABLED
	container.add_child(wreck)
	var chassis := wreck.get_node("Chassis")
	for group in [Groups.RV, Groups.CHASSIS, Groups.MONSTER_DAMAGEABLE]: chassis.remove_from_group(group)
	var distance := float(world.shot.distance) + float(spec.s)
	var pose := _road_mark(field, distance, float(spec.lateral))
	pose.basis = pose.basis.rotated(pose.basis.y, deg_to_rad(float(spec.get("yaw", 0.0))))
	pose.basis = pose.basis.rotated(pose.basis.z, deg_to_rad(float(spec.get("roll", 90.0))))
	wreck.global_transform = pose
	await world.get_tree().process_frame
	_rest_on_ground(wreck, field.height_at(pose.origin.x, pose.origin.z))
	if spec.has("corpse"):
		var mark := _road_mark(field, distance + float(spec.corpse.s), float(spec.corpse.lateral))
		var corpse: CorpseProp = world.spawn(CORPSE, mark.origin + Vector3.UP * 0.6, container)
		corpse.kind = "player"
		corpse.item_name = "Player remains"
		corpse.rotate_y(deg_to_rad(float(spec.corpse.get("yaw", 0.0))))
	return true

## A utility pole on the flat shoulder. The generated poles stand on the embankment, where
## the RV stalls before reaching them; in fog this one reads as part of the same line.
func _stage_pole(world, spec: Dictionary) -> void:
	var field: WorldField = world.field
	var s := float(world.shot.distance) + float(spec.s)
	var pose := _road_mark(field, s, float(spec.lateral))
	pose.basis = pose.basis.rotated(pose.basis.x, deg_to_rad(float(spec.get("lean", 0.0))))
	var node := RoadsideKit.instantiate_module("pole")
	node.name = "PromoCrashPole"
	WorldEntities.get_container(world).add_child(node)
	node.global_transform = pose
	pole = {"s": s, "point": pose.origin, "node": node}

## Lowers or raises a node so its lowest mesh corner touches the ground height.
func _rest_on_ground(node: Node3D, ground: float) -> void:
	var lowest := INF
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var box := mesh.get_aabb()
		for corner in 8:
			lowest = minf(lowest, (mesh.global_transform * box.get_endpoint(corner)).y)
	if lowest < INF: node.global_position.y += ground + 0.03 - lowest

func trigger(world) -> bool:
	if timeline.running or triggered: return false
	if world.shot.get("seat", false): world.rv.set_handbrake(false)
	timeline.start()
	triggered = true
	return true

func tick(world, delta: float) -> void:
	super.tick(world, delta)
	broadcast.tick()
	if not timeline.advance(delta, func(cue: Dictionary) -> bool: return _fire(world, cue)):
		world._fail("Timeline action failed")
		return
	if not swerve.is_empty(): _steer(world)
	else: _cruise(world)
	_watch_impact(world)
	_watch_execution(world)
	_hold_crawl(delta)
	_track_gaze(world, delta)
	_ease_view(world, delta)

const DRIVING := ["drive", "gear", "brake", "steer"]

func _fire(world, cue: Dictionary) -> bool:
	var rv: Chassis = world.rv
	# Memory shots are driven by hand in live takes; only unattended takes follow the script.
	if str(cue.do) in DRIVING and world.shot.get("live_controls", false) and not unattended: return true
	match str(cue.do):
		"drive":
			var from := float(cruise.get("lateral", world.shot.get("lateral", 0.0)))
			cruise = {"speed": float(cue.speed), "lateral": float(cue.get("lateral", from)),
				"from": from, "seconds": float(cue.get("seconds", 0.0)), "time": 0.0}
			if rv.gear == 0: rv.set_gear(1)
		"gear":
			return rv.set_gear(int(cue.gear))
		"brake":
			cruise = {}
			rv.control_override = {"throttle": 0.0, "brake": 1.0, "steering": 0.0}
		"line":
			# JSON numbers arrive as floats; narration ids are their integer text.
			var id := str(int(cue.id)) if cue.id is float else str(cue.id)
			world.director.mark("line " + id)
			return broadcast.play(id)
		"static":
			broadcast.set_signal(float(cue.level), bool(cue.get("cut", false)))
		"radio_off":
			broadcast.silence()
		"weather":
			var clock := world.get_node("WorldClock") as WorldClock
			_weather = {"from": clock.weather.sample(), "to": Vector3(float(cue.to[0]), float(cue.to[1]), float(cue.to[2])),
				"seconds": maxf(0.01, float(cue.seconds)), "time": 0.0}
		"look":
			# Live takes leave the view to the mouse.
			if unattended:
				var seat: Node = world.actor.seated_in
				if not is_instance_valid(seat): return false
				var rest: Vector3 = seat.REST_CAMERA_ROTATION
				_look = {"camera": seat.seat_camera, "from": seat.seat_camera.rotation,
					"to": rest + Vector3(deg_to_rad(float(cue.pitch)), deg_to_rad(float(cue.yaw)), 0.0),
					"seconds": maxf(0.01, float(cue.seconds)), "time": 0.0}
		"gaze":
			# The prone survivor's view; live takes leave it to the mouse.
			if str(cue.target) != "giant" or not is_instance_valid(giant): return false
			if unattended:
				_gaze = {"up": float(cue.get("up", 0.0)), "seconds": maxf(0.01, float(cue.seconds)), "time": 0.0,
					"yaw": world.actor.rotation.y, "pitch": world.actor.camera.rotation.x}
		"eyes":
			_eyes ={"from": float(_lids.get_shader_parameter("closure")), "to": 0.0 if bool(cue.open) else 1.0,
				"seconds": maxf(0.01, float(cue.seconds)), "time": 0.0}
		"marker":
			world.director.mark(str(cue.name))
		"giant":
			return _place_giant(world, cue)
		"steer":
			if pole.is_empty(): return false
			swerve = {"within": float(cue.within), "active": false}
		"giant_smash":
			return _giant_smash(world)
		"giant_release":
			if not is_instance_valid(giant): return false
			_release_pending = true
		"crawl":
			# Live takes crawl with the keyboard.
			if unattended:
				_crawl_seconds = float(cue.seconds)
				_crawl_action = "move_back" if cue.get("back", false) else "move_forward"
	return true

## The giant stands in the RV's lane just beyond a pole, facing the RV, with its AI off.
## Its head loudspeaker still fades in and stages distance on its own.
func _place_giant(world, cue: Dictionary) -> bool:
	if pole.is_empty(): return false
	var field: WorldField = world.field
	var lateral := float(cue.get("lateral", cruise.get("lateral", world.shot.get("lateral", 0.0))))
	var mark := _road_mark(field, float(pole.s) + float(cue.get("beyond", 12.0)), lateral)
	giant = world.spawn(SlenderSpeakerSpawns.SCENE, mark.origin + Vector3.UP * 0.05, WorldEntities.get_container(world))
	giant.set_giant_navigation_map(world.get_node("WorldGenerator").giant_navigation_map)
	giant.set_physics_process(false)
	var rv: Vector3 = world.rv.global_position
	giant.look_at(Vector3(rv.x, giant.global_position.y, rv.z))
	# A take that opens on the giant starts with its music already at full level.
	if not bool(cue.get("fade", true)): giant.patrol_music._fade_elapsed = giant.patrol_music.FADE_SECONDS
	world.subject = giant
	world.director.mark("giant")
	return true

## The giant tears at the crashed RV's roof as if it had seen someone in the cabin. From
## there its own AI runs: it notices the survivor on the ground, grabs and executes them.
func _giant_smash(world) -> bool:
	if not is_instance_valid(giant): return false
	var rv: Chassis = world.rv
	var cabin: Vector3 = rv.get_node("DriverSeat").global_position + Vector3.UP * 0.6
	giant.target_vehicle = rv
	var plan: Dictionary = giant._parked_attack.update(giant, rv, 0.0, null, cabin)
	if not plan.has("surface_point"):
		push_error("PROMO: the giant found no roof to smash (%s)" % plan.get("status"))
		return false
	var stand: Vector3 = plan.get("standoff_point", plan.get("navigation_point", giant.global_position))
	giant.global_position = Vector3(stand.x, world.field.height_at(stand.x, stand.z) + 0.05, stand.z)
	var facing: Vector3 = plan.get("facing_point", plan.surface_point)
	giant.look_at(Vector3(facing.x, giant.global_position.y, facing.z))
	giant.reset_physics_interpolation()
	plan = giant._parked_attack.update(giant, rv, 0.0, null, cabin)
	if not plan.has("surface_point"): return false
	giant._parked_plan = plan
	if world.shot.has("prone") and world.shot.prone.has("from_giant"): _place_beside_giant(world, world.shot.prone.from_giant)
	giant.set_physics_process(true)
	giant._begin_smash(plan.get("smash_kind", "roof"))
	world.director.mark("smash")
	return true

## Moves the prone survivor out on the giant's side of the RV, where the wreck cannot
## block its sight: `distance` metres from the giant, `angle` degrees off the line from
## the RV through the giant, looking between the giant's chest and the roof, or turned
## that way and looking `pitch` degrees down at their own arms.
func _place_beside_giant(world, spec: Dictionary) -> void:
	var actor: CharacterBody3D = world.actor
	var away: Vector3 = (giant.global_position - world.rv.global_position).slide(Vector3.UP).normalized()
	var point: Vector3 = giant.global_position + away.rotated(Vector3.UP, deg_to_rad(float(spec.get("angle", 0.0)))) * float(spec.distance)
	point.y = world.field.height_at(point.x, point.z) + 0.05
	actor.global_position = point
	actor.reset_physics_interpolation()
	var focus := giant.global_position.lerp(world.rv.global_position, float(spec.get("toward_rv", 0.35)))
	world._aim_at(focus + Vector3.UP * float(spec.get("up", 4.0)))
	if spec.has("pitch"): actor.camera.rotation.x = deg_to_rad(float(spec.pitch))

## Cuts out of the survivor's eyes once the giant's hand has them: a still camera `back`
## metres behind the survivor (away from the giant), `side` metres to the side and `up`
## metres above the ground, that keeps the survivor in frame as they are lifted. The
## game's own execution view takes over at the speaker.
func _cut_away_from_eyes(world, spec: Dictionary) -> void:
	if _cut_away: return
	_cut_away = true
	_gaze = {}
	var actor: Node3D = world.actor
	var away: Vector3 = (actor.global_position - giant.global_position).slide(Vector3.UP).normalized()
	var point: Vector3 = actor.global_position + away * float(spec.back) + Vector3.UP.cross(away) * float(spec.get("side", 0.0))
	point.y = world.field.height_at(point.x, point.z) + float(spec.get("up", 1.5))
	if not world.director.track_from(actor, point, float(spec.get("aim_up", 1.0)), float(spec.get("fov", 60.0))):
		world._fail("Could not cut to the third-person camera")
		return
	world.director.mark("cut_away")

## Turns the prone survivor toward the giant's `up` point, easing in over `seconds`,
## then keeps the giant in view until it takes hold.
func _track_gaze(world, delta: float) -> void:
	if _gaze.is_empty() or not is_instance_valid(giant): return
	var actor: CharacterBody3D = world.actor
	if actor.is_grabbed() or actor.is_player_dead:
		_gaze = {}
		return
	_gaze.time += delta
	var offset: Vector3 = giant.global_position + Vector3.UP * float(_gaze.up) - actor.camera.global_position
	var t := smoothstep(0.0, 1.0, minf(1.0, _gaze.time / _gaze.seconds))
	actor.rotation.y = lerp_angle(float(_gaze.yaw), atan2(-offset.x, -offset.z), t)
	actor.camera.rotation.x = lerpf(float(_gaze.pitch), atan2(offset.y, offset.slide(Vector3.UP).length()), t)

## Marks the giant's attack phases.
func _watch_execution(world) -> void:
	if not is_instance_valid(giant): return
	if _release_pending and giant.phase in [SlenderSpeaker.Phase.PATROL, SlenderSpeaker.Phase.CONFIRM, SlenderSpeaker.Phase.CHASE, SlenderSpeaker.Phase.SEARCH]:
		# Left alone the giant keeps inspecting the roof it saw first and takes about
		# twenty seconds to settle on the survivor in plain sight on the road. Taking
		# the wreck out of the RV group leaves it only the survivor to pursue.
		world.rv.remove_from_group(Groups.RV)
		_release_pending = false
		giant._encounter.reset()
		giant._encounter_decision.clear()
		giant._parked_plan.clear()
		giant._parked_attack.reset()
		giant.target_vehicle = null
		giant._set_phase(SlenderSpeaker.Phase.PATROL)
		giant.set_physics_process(false)
		_turning = true
		world.director.mark("release")
	if _turning:
		var to: Vector3 = (world.actor.global_position - giant.global_position).slide(Vector3.UP)
		var yaw := atan2(-to.x, -to.z)
		giant.rotation.y = rotate_toward(giant.rotation.y, yaw, deg_to_rad(GIANT_TURN_DEGREES) * world.get_physics_process_delta_time())
		if absf(angle_difference(giant.rotation.y, yaw)) < 0.02:
			_turning = false
			giant.set_physics_process(true)
			world.director.mark("turned")
	var phase_names := {SlenderSpeaker.Phase.GRAB: "grab", SlenderSpeaker.Phase.LIFT: "lift",
		SlenderSpeaker.Phase.HOLD: "hold", SlenderSpeaker.Phase.CRUSH: "crush"}
	if phase_names.has(giant.phase) and not _marked_phases.has(giant.phase):
		_marked_phases[giant.phase] = timeline.clock
		world.director.mark(phase_names[giant.phase])
	if world.actor.is_player_dead and not _marked_phases.has("death"):
		_marked_phases["death"] = timeline.clock
		world.director.mark("death")

## Holds forward or back for the unattended crawl.
func _hold_crawl(delta: float) -> void:
	if _crawl_seconds <= 0.0: return
	_crawl_seconds -= delta
	if _crawl_seconds > 0.0: Input.action_press(_crawl_action)
	else: Input.action_release(_crawl_action)

## Full throttle at the pole once the RV is within the armed distance of it.
func _steer(world) -> void:
	var rv: Chassis = world.rv
	var flat := Vector3(pole.point.x, rv.global_position.y, pole.point.z)
	if not swerve.active:
		if rv.global_position.distance_to(flat) > swerve.within:
			_cruise(world)
			return
		swerve.active = true
		world.director.mark("swerve")
	if impact_seconds >= 0.0:
		rv.control_override = {"throttle": 0.0, "brake": 0.0, "steering": 0.0}
		return
	var relative := rv.to_local(flat)
	var correction := -atan2(relative.x, maxf(0.1, -relative.z))
	rv.control_override = {"throttle": 1.0, "brake": 0.0, "steering": clampf(correction * STEERING_GAIN, -1.0, 1.0)}

## Marks the crash: a sudden loss of speed while swerving.
func _watch_impact(world) -> void:
	if swerve.is_empty() or not swerve.active or impact_seconds >= 0.0: return
	var now := timeline.clock
	var speed: float = world.rv.linear_velocity.length() * 3.6
	_speeds.append(Vector2(now, speed))
	while _speeds.size() > 1 and now - _speeds.front().x > IMPACT_WINDOW: _speeds.pop_front()
	var peak := 0.0
	for sample in _speeds: peak = maxf(peak, sample.y)
	if peak - speed >= maxf(IMPACT_DROP, peak * IMPACT_SHARE):
		impact_seconds = now
		world.director.mark("impact")
		print("PROMO IMPACT: %.2f s, %.0f -> %.0f km/h, %.1f m from the pole" % [now, peak, speed, world.rv.global_position.distance_to(pole.point)])

func _cruise(world) -> void:
	if cruise.is_empty(): return
	var rv: Chassis = world.rv
	var field: WorldField = world.field
	var road := field.road_query(rv.global_position.x, rv.global_position.z)
	var frame: Transform3D = road.frame
	var speed := rv.linear_velocity.length() * 3.6
	var lookahead := clampf(5.0 + speed / 3.6 * 0.65, 5.0, 13.0)
	# A lateral move eases across `seconds` instead of turning straight at the new line.
	cruise.time += world.get_physics_process_delta_time()
	var blend := smoothstep(0.0, 1.0, cruise.time / cruise.seconds) if cruise.seconds > 0.0 else 1.0
	var ahead := _road_mark(field, float(road.s) + lookahead * absf(frame.basis.z.z), lerpf(cruise.from, cruise.lateral, blend))
	var relative := rv.to_local(ahead.origin)
	var correction := -atan2(relative.x, maxf(0.1, -relative.z))
	var error := float(cruise.speed) - speed
	rv.control_override = {"throttle": clampf(error * SPEED_GAIN, 0.0, 1.0), "brake": clampf(-error * SPEED_GAIN, 0.0, 1.0),
		"steering": clampf(correction * STEERING_GAIN, -1.0, 1.0)}

func _ease_view(world, delta: float) -> void:
	if not _look.is_empty():
		_look.time += delta
		var t := smoothstep(0.0, 1.0, minf(1.0, _look.time / _look.seconds))
		if is_instance_valid(_look.camera): _look.camera.rotation = (_look.from as Vector3).lerp(_look.to, t)
		if t >= 1.0: _look = {}
	if not _eyes.is_empty():
		_eyes.time += delta
		var closure := lerpf(_eyes.from, _eyes.to, smoothstep(0.0, 1.0, minf(1.0, _eyes.time / _eyes.seconds)))
		_set_lids(closure)
		if _eyes.time >= _eyes.seconds: _eyes = {}
	if not _weather.is_empty():
		_weather.time += delta
		var t := smoothstep(0.0, 1.0, minf(1.0, _weather.time / _weather.seconds))
		(world.get_node("WorldClock") as WorldClock).weather.set_weather((_weather.from as Vector3).lerp(_weather.to, t), true)
		if t >= 1.0: _weather = {}

## The game's own eyelid shader on a layer the clean view keeps visible.
func _build_eyelids(world, closure: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 47
	world.director.add_child(layer)
	_lids.shader = EYELIDS
	_lid_rect = ColorRect.new()
	_lid_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lid_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lid_rect.material = _lids
	layer.add_child(_lid_rect)
	_set_lids(closure)

func _set_lids(closure: float) -> void:
	_lids.set_shader_parameter("closure", closure)
	_lid_rect.visible = closure > 0.001

## Unattended take for Movie Maker. Returns how long to keep filming, or -1 after failing.
func autoplay(world) -> float:
	unattended = true
	if not world.trigger_take():
		world._fail("Could not start the trailer timeline")
		return -1.0
	if world.director.exterior_requested(): world.director.follow_preset("chase", world.rv)
	return timeline.length() + float(world.shot.get("tail", 0.5))

func autoplay_error(world) -> String:
	if not swerve.is_empty() and impact_seconds < 0.0: return "The RV never hit the pole"
	if world.shot.has("prone") and not _marked_phases.has("death"): return "The giant never executed the survivor"
	return ""

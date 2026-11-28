extends "res://tests/playgrounds/promo/promo_trailer.gd"
## Independent chase and crash coverage for scenes 21–23. The road dressing is
## shared with the reveal, while each take has its own blocking and timeline.

var _obstacle: Node3D
var _roof_hit := -1.0
var _swerve_at := -1.0
var _looked_forward := false
var _stopped := false
var _looked_up := false
var _roof_open := false
var crash_state: Dictionary = {}

func placement(world) -> Transform3D:
	var start: Dictionary = world.shot.start
	var field: WorldField = world.field
	var pose := _road_mark(field, float(world.shot.distance) + float(start.s), float(start.lateral))
	pose.origin.y = _filled_height(field, pose.origin)
	if start.has("rotation"):
		pose.basis = pose.basis * Basis.from_euler(_vector(start.rotation) * (PI / 180.0))
		pose.origin.y += float(start.height)
		# PromoWorld adds one metre along this basis to every RV spawn.
		pose.origin += Vector3.UP - pose.basis.y
	return pose

func prepare(world) -> bool:
	var reveal: Variant = JSON.parse_string(FileAccess.get_file_as_string(world.SHOT_PATH % "T2"))
	if not reveal is Dictionary or not reveal.has("dress"): return false
	world.shot.dress = reveal.dress
	if not await super.prepare(world): return false
	if world.shot.has("crash_car"):
		var spec: Dictionary = world.shot.crash_car
		var pose := _road_mark(world.field, float(world.shot.distance) + float(spec.s), float(spec.lateral))
		pose.origin.y = _filled_height(world.field, pose.origin)
		pose.basis = pose.basis.rotated(Vector3.UP, deg_to_rad(float(spec.yaw)) - RoadSpawns.WRECK_MODEL_YAW)
		_obstacle = (load(RoadSpawns.WRECK_SCENE) as PackedScene).instantiate()
		_obstacle.name = "PromoCrashCar"
		WorldEntities.get_container(world).add_child(_obstacle)
		_obstacle.global_transform = pose
		_rest_on_ground(_obstacle, pose.origin.y)
	if world.shot.chase_take == "collision":
		world.rv.body_entered.connect(func(body: Node) -> void:
			if _obstacle.is_ancestor_of(body) and impact_seconds < 0.0 and triggered:
				impact_seconds = timeline.clock
				world.director.mark("impact")
				_crack_windshield.call_deferred(world.rv))
	if world.shot.chase_take == "cabin": _stage_cabin(world)
	return true

func _fire(world, cue: Dictionary) -> bool:
	if not super._fire(world, cue): return false
	if cue.do == "giant":
		giant.global_position.y = _filled_height(world.field, giant.global_position) + 0.05
		giant.reset_physics_interpolation()
		if cue.has("speed"):
			# This cut opens in the middle of a pursuit. Seed the incoming
			# momentum, then let production steering and reach take over.
			giant.velocity = _road_ahead(world.field, giant.global_position) * (float(cue.speed) / 3.6)
			giant._set_phase(SlenderSpeaker.Phase.CHASE)
		if world.shot.chase_take == "exterior":
			var framing: Dictionary = world.shot.framing
			return world.director.follow_framed(world.rv, giant, _vector(framing.offset), _vector(framing.aim), float(framing.fov))
		elif world.shot.chase_take == "collision":
			giant.attack_landed.connect(func(collider: Node, _attack: String) -> void:
				if _roof_hit >= 0.0 or not collider is RVStructurePanel or collider.structure_kind != "roof": return
				_roof_hit = timeline.clock
				world.director.mark("roof_hit")
				if is_instance_valid(world.actor.seated_in): world.actor.seated_in.cabin_impact(Vector3.DOWN, 0.6)
				# In a straight pursuit the rear bulkhead obscures the giant;
				# the driver's side mirror shows its approach during the turn.
				_fire(world, {"do": "look", "yaw": 49, "pitch": 0, "lean": [-0.42, 0.04, -0.14], "seconds": 0.45}))
	return true

func tick(world, delta: float) -> void:
	super.tick(world, delta)
	if not triggered: return
	match world.shot.chase_take:
		"collision": _drive_into_crash(world)
		"cabin": _watch_cabin_roof(world)

func _drive_into_crash(world) -> void:
	var rv: Chassis = world.rv
	var spec: Dictionary = world.shot.crash_car
	var metres_left := -rv.to_local(_obstacle.global_position).z
	if _roof_hit >= 0.0 and not _looked_forward and timeline.clock - _roof_hit >= 0.95:
		_looked_forward = true
		world.director.mark("look_forward")
		_fire(world, {"do": "look", "yaw": 0, "pitch": 0, "lean": [0, 0, 0], "seconds": 0.45})
	if _swerve_at < 0.0 and metres_left <= float(spec.brake_at):
		_swerve_at = timeline.clock
		cruise = {}
		world.director.mark("swerve")
	if _swerve_at < 0.0: return
	# One full steering input while braking. The resulting collision, pose and
	# damage are resolved by the RV physics, including in the unattended take.
	var steer := float(spec.steer) if timeline.clock - _swerve_at <= float(spec.steer_seconds) and impact_seconds < 0.0 else 0.0
	rv.control_override = {"throttle": 0.0, "brake": 1.0, "steering": steer}
	if impact_seconds < 0.0 or _stopped or rv.linear_velocity.length() > 0.18 or rv.angular_velocity.length() > 0.08: return
	if timeline.clock - impact_seconds < 0.35: return
	_stopped = true
	world.director.mark("stopped")
	crash_state = _sample_crash_state(world)
	print("PROMO CRASH STATE: ", JSON.stringify(crash_state))

func _crack_windshield(rv: Chassis) -> void:
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var front := slots.occupant("front")
	# The wreck may hit the bumper beneath the glass. Dress the cracked glass
	# from the script's impact frame using the normal damage presentation.
	if front != null: front.take_damage(maxf(0.0, front.current_health - front.max_health * 0.28))

func _sample_crash_state(world) -> Dictionary:
	var rv: Chassis = world.rv
	var road: Dictionary = world.field.road_query(rv.global_position.x, rv.global_position.z)
	var frame: Transform3D = road.frame
	var local := frame.affine_inverse() * rv.global_transform
	var floor_height := _filled_height(world.field, rv.global_position)
	var rotation := local.basis.get_euler() * (180.0 / PI)
	var health := {}
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	for slot in RVStructureSlots.layout():
		var panel := slots.panel(slot.id)
		if panel.current_health < panel.max_health: health[slot.id] = panel.current_health
	return {
		"s": float(road.s) - float(world.shot.distance), "lateral": local.origin.x,
		"height": rv.global_position.y - floor_height - 1.0,
		"rotation": [rotation.x, rotation.y, rotation.z], "panels": health}

func _stage_cabin(world) -> void:
	var spec: Dictionary = world.shot.cabin
	var rv: Chassis = world.rv
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	for slot: String in spec.panels:
		slots.panel(slot).set_health(float(spec.panels[slot]))
	var actor: CharacterBody3D = world.actor
	actor.rv_support.clear()
	actor.set_prone(true)
	actor.global_position = rv.to_global(_vector(spec.position))
	world._aim_at(rv.to_global(_vector(spec.look)))
	actor.grab_started.connect(func() -> void:
		if not _cut_away and is_instance_valid(giant): _cut_away_from_eyes.call_deferred(world, world.shot.cut_away))

func _watch_cabin_roof(world) -> void:
	if _roof_open or not is_instance_valid(giant): return
	if not _looked_up and giant.phase == SlenderSpeaker.Phase.SMASH:
		_looked_up = true
		world.director.mark("roof_windup")
		_fire(world, {"do": "gaze", "target": "giant", "up": 9.0, "seconds": 0.75})
	var slots: RVStructureSlots = world.rv.get_node("StructureSlots")
	if slots.occupant(world.shot.cabin.roof) != null: return
	_roof_open = true
	_marked_phases["roof_open"] = timeline.clock
	world.director.mark("roof_open")

func _track_gaze(world, delta: float) -> void:
	super._track_gaze(world, delta)
	if not _roof_open or _gaze.is_empty(): return
	var actor: CharacterBody3D = world.actor
	var camera: Camera3D = actor.camera
	# Look from the first blow toward the opening, then lift the eyes to the
	# actual speaker. As it reaches in, return to the hand and torso framing.
	var weight := smoothstep(0.0, 0.65, timeline.clock - float(_marked_phases.roof_open))
	if giant.phase == SlenderSpeaker.Phase.GRAB:
		weight *= 1.0 - smoothstep(0.0, 0.45, giant.phase_elapsed)
	var to_speaker := actor.global_basis.inverse() * (giant._focus_position() - camera.global_position)
	var pitch := atan2(to_speaker.y, to_speaker.slide(Vector3.UP).length())
	var yaw := atan2(-to_speaker.x, -to_speaker.z)
	camera.rotation.x = lerpf(camera.rotation.x, pitch, weight)
	camera.rotation.y = lerp_angle(0, yaw, weight)

func autoplay_error(world) -> String:
	match world.shot.chase_take:
		"exterior":
			if not _marked_phases.has("chase"): return "The giant never chased the RV"
		"collision":
			if _roof_hit < 0.0: return "The giant never hit the roof"
			if not _stopped: return "The RV never hit the wreck and settled"
			if _roof_hit >= _swerve_at: return "The roof hit came too late for the driver's swerve"
		"cabin":
			if not _roof_open: return "The giant never opened the front roof"
			if not _marked_phases.has("death"): return "The giant never grabbed the prone survivor in the cabin"
	return super.autoplay_error(world)

static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

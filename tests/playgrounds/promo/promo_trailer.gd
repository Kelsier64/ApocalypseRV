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
## Render layer reserved for the loudspeakers in takes with head fill.
const GIANT_HEAD_FILL_LAYER := 1 << 7

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
## giant_watch: the still giant's head follows the RV until giant_wake hands it to its AI.
var _watching := false
## giant_watch `seconds`: the share of the game's head turn rate the watching head uses.
var _watch_rate := 1.0
var _head_fill: OmniLight3D
var _head_fill_spec: Dictionary = {}
const GIANT_TURN_DEGREES := 75.0
## A giant placed by bearing may stand at most this far above or below the road.
const MAX_REVEAL_RISE := 2.0
## Sight rays toward the giant start this far out from the driver's eyes, past the cab.
const CAB_CLEARANCE := 2.0
## The giant's head loudspeaker, as a share of its height; the sight check needs it in view.
const HEAD_HEIGHT_SHARE := 0.9
## A look at the giant aims this share of the way up it, so the window frames all of it.
const LOOK_HEIGHT_SHARE := 0.5
var _speeds: Array[Vector2] = []
var _look := {}
## The seat camera's rest position before the first lean.
var _seat_rest := Vector3.INF
var _eyes := {}
var _weather := {}
var _lids := ShaderMaterial.new()
var _lid_rect: ColorRect

func placement(world) -> Transform3D:
	if world.shot.has("rv_at_pole"): return _crashed_pose(world)
	var distance := float(world.shot.distance) - float(world.shot.get("lead_in_distance", 0.0))
	return _road_mark(world.field, distance, float(world.shot.get("lateral", 0.0)))

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
	if world.shot.has("dress"): _dress(world, world.shot.dress)
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

## Scatter layers a dressed zone clears: the green ground cover. Rocks, logs, stumps and
## dry bushes stay on the bare floor.
const CLEARED_SCATTER := ["tall_grass", "grass", "reed", "shore_reed", "fern", "roadside_grass", "verge_weeds", "sapling"]

## Bare forest floor for a scene. From `from` to `to` metres past the shot's start and up to
## `width` metres either side of the road, easing out over `fade` metres beyond that, the
## generated trees, bushes and green ground cover go and the ground turns `ground` (hex).
## `plant` then stands dead trees and conifers there instead (see _plant).
func _dress(world, spec: Dictionary) -> void:
	var field: WorldField = world.field
	var start := float(world.shot.distance)
	var zone := {"from": start + float(spec.from), "to": start + float(spec.to),
		"width": float(spec.get("width", 150.0)), "fade": float(spec.get("fade", 20.0))}
	var dirt := Color(str(spec.get("ground", "54432f")))
	var unbridge := bool(spec.get("unbridge", false))
	var reach := float(zone.width) + float(zone.fade)
	# Roadside sites advertise themselves with a sign on the shoulder, outside the site.
	var signs: Array[Vector3] = []
	if spec.get("hide_sites", false):
		for site: Dictionary in field.sites_near_z(-(float(zone.from) + float(zone.to)) * 0.5, (float(zone.to) - float(zone.from)) * 0.5 + reach):
			if site.get("placement", "roadside") == "off_road" or site.kind == "entrance" or not site.has("road"): continue
			var sign: Vector3 = site.road * Vector3(float(site.side) * 12.0, 0, 21.0)
			if _zone_weight(field, zone, sign) > 0.0: signs.append(sign)
	var cleared := 0
	var recoloured := 0
	for entry: Dictionary in world.get_node("WorldGenerator").active_chunks:
		# Bands are numbered along the road, so one far from the zone holds nothing in it.
		var band_start := int(entry.index) * field.profile.chunk_length
		if band_start > float(zone.to) + reach or band_start + field.profile.chunk_length < float(zone.from) - reach: continue
		for child in (entry.node as Node).get_children():
			if child is MultiMeshInstance3D and _clears(child.name): cleared += _clear_instances(field, zone, child)
			elif child is ForestTrunks: _disable_trunks(field, zone, child)
			elif child is MeshInstance3D and child.name == "Ground": recoloured += _recolour(field, zone, child, dirt, unbridge)
			# `unbridge` takes the bridges down; _recolour fills the ground up to the road under them.
			elif unbridge and child.name in ["BridgeDeck", "BridgeStructure"]: child.free()
			elif unbridge and child is MeshInstance3D and child.name == "Road": _soil_road(child)
			# With its trees gone a site would stand bare in the scene; `hide_sites` hides it.
			elif child is Node3D and child.has_meta("poi_id") and spec.get("hide_sites", false) and _zone_weight(field, zone, child.global_position) > 0.0:
				child.visible = false
			elif child is Node3D and signs.any(func(sign: Vector3) -> bool: return Vector2(sign.x, sign.z).distance_to(Vector2(child.position.x, child.position.z)) < 0.5):
				child.visible = false
	var planted := _plant(world, spec.get("plant", {}), zone)
	print("PROMO DRESS: %d plants cleared, %d ground points recoloured, %d trees planted" % [cleared, recoloured, planted])

func _clears(title: String) -> bool:
	if title.begins_with("ForestTree") or title.begins_with("ForestBrush"): return true
	for layer: String in CLEARED_SCATTER:
		if title.begins_with("Scatter_%s_" % layer): return true
	return false

## How fully the dressing covers `point`: 1 inside the zone, easing to 0 across its fade.
func _zone_weight(field: WorldField, zone: Dictionary, point: Vector3) -> float:
	# The road's s follows -z, so a point far outside the zone along z needs no road query.
	var reach := float(zone.width) + float(zone.fade)
	if -point.z < float(zone.from) - reach or -point.z > float(zone.to) + reach: return 0.0
	var query := field.road_query(point.x, point.z)
	var s := float(query.s)
	var frame: Transform3D = query.frame
	var lateral := absf((point - frame.origin).dot(frame.basis.x))
	var outside := maxf(maxf(float(zone.from) - s, s - float(zone.to)), lateral - float(zone.width))
	return 1.0 - smoothstep(0.0, float(zone.fade), outside)

## Shrinks the instances inside the zone to nothing, as a felled tree's batch does.
func _clear_instances(field: WorldField, zone: Dictionary, node: MultiMeshInstance3D) -> int:
	var multi := node.multimesh
	var count := 0
	for i in multi.instance_count:
		var pose := multi.get_instance_transform(i)
		if _zone_weight(field, zone, node.global_transform * pose.origin) < 0.5: continue
		multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), pose.origin))
		count += 1
	return count

## Turns off the trunk and shrub collision of the plants _clear_instances removed.
func _disable_trunks(field: WorldField, zone: Dictionary, body: ForestTrunks) -> void:
	for shape in body.get_children():
		if shape is CollisionShape3D and shape.has_meta("tree_point") and _zone_weight(field, zone, shape.get_meta("tree_point")) >= 0.5:
			shape.disabled = true

## Blends the ground's vertex colour toward `dirt`; the alpha keeps the dirt-track distance.
## With `fill` the ground under a bridge also rises to the road as an embankment.
func _recolour(field: WorldField, zone: Dictionary, node: MeshInstance3D, dirt: Color, fill: bool) -> int:
	var mesh := node.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	# A road bend of 60 degrees puts a point `width` metres off it twice as far away in x.
	var reach := 2.0 * (float(zone.width) + float(zone.fade)) + 20.0
	var count := 0
	var raised := false
	for i in vertices.size():
		var point := node.global_transform * vertices[i]
		if absf(point.x - field.road_x(-point.z)) > reach: continue
		# The fill reaches FILL_SLOPE past the road edge; 60 m in x covers it on a bend.
		if fill and absf(point.x - field.road_x(-point.z)) < 60.0:
			var height := _filled_height(field, point)
			if height > point.y + 0.01:
				vertices[i].y += height - point.y
				raised = true
		var weight := _zone_weight(field, zone, point)
		if weight <= 0.0: continue
		var colour := colours[i].lerp(dirt, weight)
		colour.a = colours[i].a
		colours[i] = colour
		count += 1
	if count == 0 and not raised: return 0
	arrays[Mesh.ARRAY_COLOR] = colours
	if raised:
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = _grid_normals(vertices)
	var material := mesh.surface_get_material(0)
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null: mesh.surface_set_material(0, material)
	if raised:
		var shape := node.get_child(0).get_child(0) as CollisionShape3D
		shape.shape = mesh.create_trimesh_shape()
	return count

## Metres either side of the road's edge over which a filled bridge gap slopes back down.
const FILL_SLOPE := 18.0

## The ground at `point` once the gap under a bridge is filled: raised to the road within a
## metre of its edge, easing back to the valley floor FILL_SLOPE metres out. Never lowered.
func _filled_height(field: WorldField, point: Vector3) -> float:
	var ground := field.height_at(point.x, point.z)
	var query := field.road_query(point.x, point.z)
	var gap := field.landforms.bridge_gap(float(query.s))
	if gap <= 0.0: return ground
	var edge := float(query.width) * 0.5
	var weight := gap * (1.0 - smoothstep(edge + 1.0, edge + FILL_SLOPE, float(query.distance)))
	return maxf(ground, lerpf(ground, float(query.height), weight))

## Normals for the generator's ground grid (rows of equal z), from neighbouring heights.
func _grid_normals(vertices: PackedVector3Array) -> PackedVector3Array:
	var columns := 1
	while columns < vertices.size() and is_equal_approx(vertices[columns].z, vertices[0].z): columns += 1
	var rows := vertices.size() / columns
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for j in rows:
		for i in columns:
			var left := vertices[j * columns + maxi(i - 1, 0)]
			var right := vertices[j * columns + mini(i + 1, columns - 1)]
			var near := vertices[maxi(j - 1, 0) * columns + i]
			var far := vertices[mini(j + 1, rows - 1) * columns + i]
			var slope_x := (right.y - left.y) / maxf(right.x - left.x, 0.01)
			var slope_z := (far.y - near.y) / minf(far.z - near.z, -0.01)
			normals[j * columns + i] = Vector3(-slope_x, 1.0, -slope_z).normalized()
	return normals

## Clears the road shader's bridge flag, so verge soil reaches the asphalt where a deck was.
func _soil_road(node: MeshInstance3D) -> void:
	var mesh := node.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colours.is_empty(): return
	colours.fill(Color(0, 0, 0))
	arrays[Mesh.ARRAY_COLOR] = colours
	var material := mesh.surface_get_material(0)
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null: mesh.surface_set_material(0, material)

## Stands the game's own tree meshes on a jittered `spacing` grid in the zone, kept off the
## road by `road_margin` metres beyond its edge. `density` and `left_density` fill a share
## of the grid points, with a `dead` share bare. `clear` forbids trees within `width` metres
## of the sightlines from the road to the giant, or within `around` metres of its feet.
## `extra_trees` sets individual trunks at road offsets (`s`, `lateral`) for the chase.
func _plant(world, spec: Dictionary, zone: Dictionary) -> int:
	if spec.is_empty(): return 0
	var field: WorldField = world.field
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var spacing := float(spec.get("spacing", 10.0))
	var density := float(spec.get("density", 0.6))
	var left_density := float(spec.get("left_density", density))
	var lines := _clear_lines(world, spec.get("clear", {}))
	var poses: Array = [[], [], [], [], [], []]
	var planted := 0
	var s := float(zone.from)
	while s <= float(zone.to):
		var lateral := -float(zone.width)
		while lateral <= float(zone.width):
			var distance := s + rng.randf_range(-0.4, 0.4) * spacing
			var offset := lateral + rng.randf_range(-0.4, 0.4) * spacing
			var point := _road_mark(field, distance, offset).origin
			point.y = _filled_height(field, point)
			lateral += spacing
			var filled := rng.randf() < (left_density if offset < 0.0 else density)
			var dead := rng.randf() < float(spec.get("dead", 0.7))
			var kind := 4 + rng.randi() % 2 if dead else rng.randi() % 4
			var height := rng.randf_range(8.0, 14.0) if dead else rng.randf_range(11.0, 18.0)
			var width := rng.randf_range(2.2, 3.2) if dead else rng.randf_range(2.6, 3.8)
			var angle := rng.randf_range(-PI, PI)
			if not filled or _zone_weight(field, zone, point) < 1.0: continue
			var sample := field.surface(point.x, point.z)
			if sample.reserved or is_finite(float(sample.water_height)): continue
			if sample.road.distance < float(sample.road.width) * 0.5 + float(spec.get("road_margin", 8.0)): continue
			if _blocks_view(point, lines): continue
			poses[kind].append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(width, height, width)), point + Vector3.DOWN * 0.15))
			planted += 1
		s += spacing
	for tree: Dictionary in spec.get("extra_trees", []):
		var pose := _road_mark(field, float(world.shot.distance) + float(tree.s), float(tree.lateral))
		pose.origin.y = _filled_height(field, pose.origin) - 0.15
		pose.basis = Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(2.5, 12.0, 2.5))
		poses[4].append(pose)
		planted += 1
	# The streamer frees entities it finds behind the player, so the planting stands at the
	# far end of its zone, with the trees placed relative to it.
	var parent := Node3D.new()
	parent.name = "PromoForest"
	WorldEntities.get_container(world).add_child(parent)
	parent.global_position = _road_mark(field, float(zone.to), 0.0).origin
	var trunks := ForestTrunks.new()
	trunks.name = "ForestTrunks"
	for kind in poses.size():
		var local: Array = poses[kind].map(func(pose: Transform3D) -> Transform3D: return pose.translated(-parent.global_position))
		trunks.visuals.merge(ForestScenery.batch(parent, "PromoTree%d" % kind, ForestMeshes.tree(kind), local))
		for pose: Transform3D in local:
			trunks.add_trunk(pose.origin, pose.basis.y.length())
	parent.add_child(trunks)
	return planted

## The flat sightlines `_plant` keeps open, as [from, to, width] with the giant's spot taken
## from the timeline's first giant cue placed by `s`.
func _clear_lines(world, spec: Dictionary) -> Array:
	if spec.is_empty(): return []
	var field: WorldField = world.field
	var start := float(world.shot.distance)
	var spot := Vector3.INF
	for cue: Dictionary in world.shot.timeline:
		if str(cue.do) == "giant" and cue.has("s"):
			spot = _road_mark(field, start + float(cue.s), float(cue.get("lateral", 0.0))).origin
			break
	if spot == Vector3.INF: return []
	var target := Vector2(spot.x, spot.z)
	var lines := [[target, target, float(spec.get("around", 8.0))]]
	var s := start + float(spec.from)
	while s <= start + float(spec.to):
		var eye := _road_mark(field, s, float(spec.get("lateral", 0.0))).origin
		lines.append([Vector2(eye.x, eye.z), target, float(spec.get("width", 5.0))])
		s += 3.0
	return lines

func _blocks_view(point: Vector3, lines: Array) -> bool:
	var flat := Vector2(point.x, point.z)
	for line: Array in lines:
		if Geometry2D.get_closest_point_to_segment(flat, line[0], line[1]).distance_to(flat) < float(line[2]): return true
	return false

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
	_watch_chase(world)
	_hold_crawl(delta)
	_track_gaze(world, delta)
	_watch_rv(world, delta)
	_update_head_fill(world)
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
					"seconds": maxf(0.01, float(cue.seconds)), "time": 0.0}
				if cue.has("target"):
					# Follows the subject until the next look, turned `yaw` degrees further left
					# (negative right) to keep a window pillar off it.
					var subject: Node3D = giant if cue.target == "giant" else wreck
					if not is_instance_valid(subject): return false
					_look.subject = subject
					_look.yaw = deg_to_rad(float(cue.get("yaw", 0.0)))
				else: _look.to = rest + Vector3(deg_to_rad(float(cue.pitch)), deg_to_rad(float(cue.yaw)), 0.0)
				# `lean` moves the head [right, up, back] metres from its rest over the same
				# seconds, e.g. toward the side window so more of a tall subject clears the
				# roof. It holds until a later look leans again.
				if cue.has("lean"):
					if _seat_rest == Vector3.INF: _seat_rest = seat._camera_rest_position
					_look.seat = seat
					_look.lean_from = seat._camera_rest_position
					_look.lean_to = _seat_rest + Vector3(float(cue.lean[0]), float(cue.lean[1]), float(cue.lean[2]))
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
		"giant_watch":
			if not is_instance_valid(giant): return false
			_watching = true
			# `seconds` slows the head so its full yaw range takes that long; the game's
			# own rate otherwise.
			var settings = giant.settings
			_watch_rate = float(settings.head_yaw_degrees) / float(cue.seconds) / float(settings.head_turn_degrees) if cue.has("seconds") else 1.0
			print("PROMO WATCH: ", _giant_from_eyes(world))
			world.director.mark("watch")
		"giant_wake":
			# Its own AI from here: it sees the RV, confirms and chases it.
			if not is_instance_valid(giant): return false
			_watching = false
			giant.set_physics_process(true)
			world.director.mark("wake")
		"wind":
			(world.get_node("WorldClock") as WorldClock).wind.set_override(int(cue.tier))
		"crawl":
			# Live takes crawl with the keyboard.
			if unattended:
				_crawl_seconds = float(cue.seconds)
				_crawl_action = "move_back" if cue.get("back", false) else "move_forward"
	return true

## The giant stands with its AI off, `beyond` metres past the staged pole in the RV's lane,
## or, with `bearing`, where the driver will see it `reveal` seconds after the cue (see
## _reveal_spot), or with `s` at a fixed ground spot `s` metres past the shot's start and
## `lateral` metres off the road (negative is left), unchecked for sight. It faces the RV, or the road with `facing: "road"`, turned `facing_yaw`
## degrees from it toward the direction of travel. Its head loudspeaker
## still fades in and stages distance on its own.
func _place_giant(world, cue: Dictionary) -> bool:
	var field: WorldField = world.field
	var spot: Vector3
	var eye := Vector3.INF
	if cue.has("bearing"):
		var reveal := _reveal_spot(world, cue)
		if reveal.is_empty(): return false
		spot = reveal.spot
		eye = reveal.eye
	elif cue.has("s"): spot = _road_mark(field, float(world.shot.distance) + float(cue.s), float(cue.get("lateral", 0.0))).origin
	elif pole.is_empty(): return false
	else: spot = _road_mark(field, float(pole.s) + float(cue.get("beyond", 12.0)), float(cue.get("lateral", cruise.get("lateral", world.shot.get("lateral", 0.0))))).origin
	giant = world.spawn(SlenderSpeakerSpawns.SCENE, spot + Vector3.UP * 0.05, WorldEntities.get_container(world))
	giant.set_giant_navigation_map(world.get_node("WorldGenerator").giant_navigation_map)
	giant.set_physics_process(false)
	var rv: Vector3 = world.rv.global_position
	if str(cue.get("facing", "")) == "road":
		var road: Vector3 = (field.road_query(spot.x, spot.z).frame as Transform3D).origin
		giant.look_at(Vector3(road.x, giant.global_position.y, road.z))
		# facing_yaw turns it from the road toward the direction of travel, so its head has
		# further to turn when it finds the RV.
		var forward := -giant.global_basis.z
		var turn := deg_to_rad(float(cue.get("facing_yaw", 0.0)))
		giant.rotate_y(turn * signf(forward.signed_angle_to(_road_ahead(field, spot), Vector3.UP)))
	else: giant.look_at(Vector3(rv.x, giant.global_position.y, rv.z))
	if eye != Vector3.INF:
		var blocked := _sight_blocked(eye)
		if blocked != "":
			push_error("PROMO: the driver will not see the giant: %s" % blocked)
			return false
	# A take that opens on the giant starts with its music already at full level.
	if not bool(cue.get("fade", true)): giant.patrol_music._fade_elapsed = giant.patrol_music.FADE_SECONDS
	if cue.has("head_fill"): _add_head_fill(cue.head_fill)
	world.subject = giant
	world.director.mark("giant")
	return true

## Light the three speaker cabinets without lighting the forest or fog around them.
func _add_head_fill(spec: Dictionary) -> void:
	for mesh: MeshInstance3D in giant.find_children("Speaker_*", "MeshInstance3D", true, false):
		mesh.layers |= GIANT_HEAD_FILL_LAYER
	_head_fill_spec = spec
	_head_fill = OmniLight3D.new()
	_head_fill.name = &"PromoHeadFill"
	_head_fill.light_cull_mask = GIANT_HEAD_FILL_LAYER
	_head_fill.light_color = Color("d4dfe5")
	_head_fill.light_energy = 0.0
	_head_fill.light_volumetric_fog_energy = 0.0
	_head_fill.omni_range = 15.0
	giant.add_child(_head_fill)

## Keep the fill slightly off to one side as the RV passes and the giant turns.
func _update_head_fill(world) -> void:
	if not is_instance_valid(_head_fill): return
	var start := float(_head_fill_spec.at)
	if timeline.clock < start: return
	var head := giant._focus_position()
	var toward_rv: Vector3 = (world.rv.global_position - head).slide(Vector3.UP).normalized()
	_head_fill.global_position = head + toward_rv * 5.0 + toward_rv.cross(Vector3.UP) * 4.0 + Vector3.UP * 2.5
	_head_fill.light_energy = float(_head_fill_spec.energy) * smoothstep(start, start + float(_head_fill_spec.seconds), timeline.clock)

## Where the driver will see the giant `reveal` seconds after the cue: `bearing` degrees left
## of the road ahead (negative is right) and `range` metres away on the ground, from the
## driver's eyes carried on at the RV's current velocity. Fails when that ground is more than
## `max_rise` metres (default MAX_REVEAL_RISE) above or below the road, so a seed or start
## distance that puts the reveal over a ravine or behind a bank fails the take instead.
func _reveal_spot(world, cue: Dictionary) -> Dictionary:
	var seat: Node = world.actor.seated_in
	if not is_instance_valid(seat):
		push_error("PROMO: a giant placed by bearing needs the driver seated")
		return {}
	var field: WorldField = world.field
	var rv: Chassis = world.rv
	var eye: Vector3 = (seat.seat_camera as Camera3D).global_position + rv.linear_velocity.slide(Vector3.UP) * float(cue.get("reveal", 0.0))
	var spot := eye + _road_ahead(field, eye).rotated(Vector3.UP, deg_to_rad(float(cue.bearing))) * float(cue.range)
	spot.y = field.height_at(spot.x, spot.z)
	var rise := spot.y - field.road_height(float(field.road_query(eye.x, eye.z).s))
	print("PROMO GIANT: bearing %.0f, %.1f m from the eyes, ground %+.1f m from the road" % [float(cue.bearing), float(cue.range), rise])
	if absf(rise) > float(cue.get("max_rise", MAX_REVEAL_RISE)):
		push_error("PROMO: the giant's ground is %+.1f m from the road; move the shot's distance to flatter ground" % rise)
		return {}
	return {"eye": eye, "spot": spot}

## Where the giant's head is from the driver's eyes, for tuning a shot's timing.
func _giant_from_eyes(world) -> String:
	var eye: Vector3 = (world.actor.seated_in.seat_camera as Camera3D).global_position
	var offset := _giant_point(HEAD_HEIGHT_SHARE) - eye
	return "giant %.0f degrees off the road ahead, head %.1f m away at %.1f degrees up" % [
		rad_to_deg(_road_ahead(world.field, eye).signed_angle_to(offset.slide(Vector3.UP), Vector3.UP)), offset.length(),
		rad_to_deg(atan2(offset.y, offset.slide(Vector3.UP).length()))]

## The flat direction of travel along the road nearest `at`.
func _road_ahead(field: WorldField, at: Vector3) -> Vector3:
	var s := float(field.road_query(at.x, at.z).s)
	return (field.road_frame(s + 1.0).origin - field.road_frame(s).origin).slide(Vector3.UP).normalized()

## What blocks the line from `eye` to the giant's waist or head, or "" when both are clear.
## The rays start outside the cab, which is still behind the predicted eye anyway.
func _sight_blocked(eye: Vector3) -> String:
	var space := giant.get_world_3d().direct_space_state
	var own: Array[RID] = []
	for body: CollisionObject3D in giant.find_children("*", "CollisionObject3D", true, false): own.append(body.get_rid())
	own.append(giant.get_rid())
	for share in [0.5, HEAD_HEIGHT_SHARE]:
		var target := _giant_point(share)
		var from := eye + (target - eye).normalized() * CAB_CLEARANCE
		var query := PhysicsRayQueryParameters3D.create(from, target)
		query.exclude = own
		var hit := space.intersect_ray(query)
		if not hit.is_empty(): return "%s at %.0f%% of its height" % [(hit.collider as Node).name, share * 100.0]
	return ""

## A point on the giant `share` of the way up its visible height.
func _giant_point(share: float) -> Vector3:
	var top := -INF
	for mesh: MeshInstance3D in giant.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var box := mesh.get_aabb()
		for corner in 8: top = maxf(top, (mesh.global_transform * box.get_endpoint(corner)).y)
	var height := top - giant.global_position.y if top > -INF else 0.0
	return giant.global_position + Vector3.UP * height * share

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

## The still giant's head loudspeaker turns to follow the RV's cab.
func _watch_rv(world, delta: float) -> void:
	if not _watching or not is_instance_valid(giant): return
	giant._head_look.update(giant, world.rv.get_node("DriverSeat").global_position, delta * _watch_rate)

## Marks the first moment the giant chases.
func _watch_chase(world) -> void:
	if not is_instance_valid(giant) or _marked_phases.has("chase"): return
	if giant.phase == SlenderSpeaker.Phase.CHASE:
		_marked_phases["chase"] = timeline.clock
		world.director.mark("chase")

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
	if not _look.is_empty() and is_instance_valid(_look.camera):
		_look.time += delta
		var t := smoothstep(0.0, 1.0, minf(1.0, _look.time / _look.seconds))
		var camera: Camera3D = _look.camera
		var subject: Node3D = _look.get("subject")
		var tracking := is_instance_valid(subject)
		var to: Vector3 = _look.get("to", camera.rotation)
		if tracking:
			var point := _giant_point(LOOK_HEIGHT_SHARE) if subject == giant else subject.global_position
			to = _aim(camera, point) + Vector3(0.0, float(_look.yaw), 0.0)
		var from: Vector3 = _look.from
		camera.rotation = Vector3(lerp_angle(from.x, to.x, t), lerp_angle(from.y, to.y, t), lerpf(from.z, to.z, t))
		if _look.has("seat") and is_instance_valid(_look.seat):
			_look.seat._camera_rest_position = (_look.lean_from as Vector3).lerp(_look.lean_to, t)
		if t >= 1.0 and not tracking: _look = {}
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

## The seat camera's local rotation that points it at `point`.
func _aim(camera: Camera3D, point: Vector3) -> Vector3:
	var parent := camera.get_parent() as Node3D
	var local := parent.global_basis.orthonormalized().inverse() * (point - camera.global_position)
	return Vector3(atan2(local.y, Vector2(local.x, local.z).length()), atan2(-local.x, -local.z), 0.0)

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

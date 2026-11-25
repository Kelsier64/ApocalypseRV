extends "res://world/main_world.gd"

const DIRECTOR := preload("res://tests/playgrounds/promo/promo_director.gd")
const PLAYER := preload("res://tests/playgrounds/promo/promo_player.gd")
const WORKSHOP_RV := preload("res://rv/new_rv.tscn")
const LOCATIONS := preload("res://tests/playgrounds/promo/promo_locations.gd")
const BUNKER := preload("res://tests/playgrounds/promo/promo_bunker.gd")
const OUTDOOR := preload("res://tests/playgrounds/promo/promo_outdoor.gd")
const WORKSHOP := preload("res://tests/playgrounds/promo/promo_workshop.gd")
const TRAILER := preload("res://tests/playgrounds/promo/promo_trailer.gd")
const TIMELINE := preload("res://tests/playgrounds/promo/promo_timeline.gd")
const SHOTS := ["B1", "B2", "B3", "B4", "B5", "B6", "O1", "O2", "O3", "O4", "O5",
	"D1", "D2", "D3", "D4", "D5", "D6", "R1", "R2", "R3", "W1", "W2", "W3", "T1", "T2", "T3"]
const SHOT_PATH := "res://tests/playgrounds/promo/shots/%s.json"
static var next_shot := ""
static var next_variant := 0

var shot_id := "R2"
var shot: Dictionary
var variant := 0
var subject: Node3D
var field: WorldField
var road_pose: Transform3D
var stage: RefCounted
var staged: Array[Node3D] = []
var take_ready := false
var failed := false
var _reloading := false
var director: Node
var actor: CharacterBody3D
var rv: Chassis
var station: CraftingStation
var apparition: BlackApparition
var _entrance: Dictionary
var _shooting_position := Vector3.INF
var _apparition_position := Vector3.INF

func _enter_tree() -> void:
	if _initial_placement_done: return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="): shot_id = argument.trim_prefix("--shot=").to_upper()
		if argument.begins_with("--variant="): variant = argument.trim_prefix("--variant=").to_int()
	if not next_shot.is_empty():
		variant = next_variant
		shot_id = next_shot
		next_shot = ""
	if shot_id not in SHOTS:
		_fail.call_deferred("Unknown shot %s. Available: %s" % [shot_id, ", ".join(SHOTS)])
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHOT_PATH % shot_id))
	if not config is Dictionary:
		_fail.call_deferred("Invalid shot file: " + shot_id)
		return
	shot = config
	var variations: Array = shot.get("variants", [])
	if variant < 0 or variant > variations.size():
		_fail.call_deferred("Invalid variant for " + shot_id)
		return
	if variant > 0: shot.merge(variations[variant - 1], true)
	if shot.has("timeline"):
		var problem: String = TIMELINE.check(shot.timeline)
		if not problem.is_empty():
			_fail.call_deferred("%s: %s" % [shot_id, problem])
			return
	# Skip checkpoint preparation and restore while the scene enters the tree.
	set_meta("checkpoint_staging", true)
	var generator := get_node("WorldGenerator")
	generator.world_seed = int(shot.seed)
	field = WorldField.new(generator.world_seed, generator.profile)
	var distance := float(shot.distance)
	if shot.has("interior"):
		stage = BUNKER.new()
		var candidates := LOCATIONS.bunkers(field, distance, 800.0)
		if candidates.is_empty():
			_fail.call_deferred("No bunker candidate for shot " + shot_id)
			return
		_entrance = candidates.front()
		distance = _entrance.s
	else:
		if shot.get("workshop", false): stage = WORKSHOP.new()
		else: stage = TRAILER.new() if shot.has("timeline") else OUTDOOR.new()
		var original := get_node("NewRv")
		remove_child(original)
		original.free()
		var workshop := WORKSHOP_RV.instantiate()
		workshop.name = "NewRv"
		add_child(workshop)
	actor = get_node("Player")
	actor.set_script(PLAYER)
	get_node("StartRun").restore({"version": 1, "phase": "sealed"})
	super._enter_tree()
	road_pose = field.road_frame(distance)
	if stage is OUTDOOR: road_pose = stage.placement(self)
	$NewRv.transform = road_pose * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0))
	rv = $NewRv/Chassis
	if not stage is BUNKER: rv.starter_kits = true
	if not (shot_id in ["O2", "O4", "O5", "D1", "D2", "D3", "D4", "D5"] or shot.get("drives", false)): rv.freeze = true
	if stage is OUTDOOR and not shot.get("seat", false):
		var mark := road_pose * Vector3(4.5, 0, 0)
		mark.y = field.height_at(mark.x, mark.z) + 0.15
		actor.transform = Transform3D(road_pose.basis, mark)
	else:
		actor.transform = $NewRv.transform * Transform3D(Basis.IDENTITY, Vector3(0.15, 0.52, 1.85))
	if not _entrance.is_empty():
		var building: Transform3D = _entrance.building
		var point := building * Vector3(0, 0, 4)
		point.y = field.height_at(point.x, point.z) + 1.25
		actor.transform = Transform3D(building.basis, point)
	# Prime the production streamer around the take, including distant sites.
	var band := floori(-actor.position.z / generator.profile.chunk_length)
	generator.restore_bands.assign(range(band - generator.profile.chunks_behind, band + generator.profile.chunks_ahead + 1))
	actor.camera_locked = true
	if shot_id == "D4": rv.freeze = true
	if stage is OUTDOOR and shot.get("seat", false): rv.allow_test_controls = true
	# Natural giant rolls are reserved in the filmed regions; F10 places the chosen encounter.
	for segment in range(maxi(1, floori(distance / SlenderSpeakerSpawns.SEGMENT_LENGTH) - 1), floori(distance / SlenderSpeakerSpawns.SEGMENT_LENGTH) + 2):
		generator.generated_giant_segments.append(segment)

func _ready() -> void:
	if shot.is_empty() or not is_instance_valid(actor): return
	super._ready()
	# Combat and survival normally stay paused while a checkpoint is staging.
	remove_meta("checkpoint_staging")
	var clock: WorldClock = $WorldClock
	clock.running = false
	clock.weather_running = false
	clock.weather.set_weather(Vector3(float(shot.weather[0]), float(shot.weather[1]), float(shot.weather[2])), true)
	clock.set_time(1, float(shot.hour))
	$DeviationPressure.set_physics_process(false)
	$WhiteApparitionEncounter.set_physics_process(false)
	$BlackApparitionEncounter.set_physics_process(false)
	director = DIRECTOR.new()
	director.world = self
	add_child(director)
	_prepare_take.call_deferred()

func _prepare_take() -> void:
	if not await wait_for_play():
		_fail("Terrain and navigation did not become ready")
		return
	if stage is BUNKER:
		var manager: PoiInstanceManager = $PoiInstances
		var door: Node3D
		for node in get_tree().get_nodes_in_group("poi_entrances"):
			if is_ancestor_of(node) and node.get_meta("poi_id", "") == _entrance.id:
				door = node
				break
		if door == null:
			_fail("Bunker entrance did not stream in: " + _entrance.id)
			return
		actor.camera_locked = false
		await manager.enter(actor, door, _entrance.id, _entrance.seed)
		if manager.state != PoiInstanceManager.State.INDOOR:
			_fail("Bunker could not be staged: " + manager.last_error)
			return
	actor.camera_locked = false
	rv.current_power = rv.max_power
	rv.current_fuel = rv.max_fuel
	if not await stage.prepare(self):
		_fail("Could not stage " + shot_id)
		return
	actor.reset_physics_interpolation()
	# Floor contact from the previous mark can persist for one physics frame.
	var settled := 0
	for frame in 150:
		await get_tree().physics_frame
		settled = settled + 1 if actor.is_on_floor() or is_instance_valid(actor.seated_in) else 0
		if settled >= 4: break
	if settled < 4:
		_fail("Player did not settle on the shot floor")
		return
	actor.camera_locked = false
	take_ready = true
	print("PROMO READY: ", shot_id, " variant=", variant, " seed=", shot.seed, " position=", actor.global_position)
	if "--preview" in OS.get_cmdline_user_args(): director.preview.call_deferred()

func _terrain_ready(generator: Node) -> bool:
	if not super._terrain_ready(generator): return false
	return generator.restore_bands.all(func(band): return generator.active_chunks.any(func(entry): return entry.index == band))

func find_bunker_lane(interior: PoiInterior) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(interior.layout.seed)
	var space := interior.get_world_3d().direct_space_state
	var uses_bunker_population := shot_id in ["B3", "B4"]
	var distances := InteriorLayout.distances(interior.layout)
	var entry := interior.spawn_transform().origin
	for index in interior.rooms.size():
		var room := interior.rooms[index]
		if uses_bunker_population:
			var definition := InteriorLayout.definition(interior.layout, index)
			var bounds: AABB = definition.describe().bounds
			if distances[index] < 24.0 or definition.role != &"ordinary" or bounds.size.x < 5.0 or bounds.size.z < 5.0: continue
		if not room.get_meta("bunker_dark", false) and shot_id in ["B1", "B2", "B4"]: continue
		var reserved: Array[Vector3] = []
		for pick in 16:
			var candidate := BunkerContent._position(interior, index, rng, reserved)
			if candidate.is_empty(): break
			var point: Vector3 = candidate.point
			if uses_bunker_population and point.distance_to(entry) < 18.0: continue
			for other in reserved:
				var distance := point.distance_to(other)
				if distance < 4.5 or distance > 7.0: continue
				if not _clear_shooting_lane(space, other, point): continue
				_shooting_position = other
				_apparition_position = point
				break
			if _apparition_position.is_finite(): break
		if _apparition_position.is_finite(): break
	if not _apparition_position.is_finite(): return false
	actor.global_position = _shooting_position + Vector3.UP * 0.08
	actor.velocity = Vector3.ZERO
	_aim_at(_apparition_position + Vector3.UP * 1.35)
	return true

func _clear_shooting_lane(space: PhysicsDirectSpaceState3D, origin: Vector3, target: Vector3) -> bool:
	var lateral := (target - origin).cross(Vector3.UP).normalized() * 0.42
	for side in [-1, 1]:
		for height in [0.85, 1.45]:
			var light := origin + lateral * float(side) + Vector3.UP * float(height)
			var ray := PhysicsRayQueryParameters3D.create(light, target + Vector3.UP * 1.3, 1)
			if not space.intersect_ray(ray).is_empty(): return false
	return true

func _aim_at(point: Vector3) -> void:
	var offset: Vector3 = point - actor.camera.global_position
	actor.rotation.y = atan2(-offset.x, -offset.z)
	actor.camera.rotation.x = atan2(offset.y, offset.slide(Vector3.UP).length())

func trigger_take() -> bool:
	return take_ready and stage.trigger(self)

func _physics_process(delta: float) -> void:
	if not take_ready: return
	if stage is OUTDOOR: stage.tick(self, delta)

func spawn(scene_path: String, point: Vector3, parent: Node3D, frozen := false) -> Node3D:
	var scene := load(scene_path) as PackedScene
	var entity := scene.instantiate() as Node3D
	entity.position = parent.to_local(point)
	if entity is RigidBody3D: entity.freeze = frozen
	parent.add_child(entity)
	staged.append(entity)
	return entity

## Reloads the scene with another shot. A negative variant keeps the current one
## for the same shot and selects the default for a different shot.
func reload_take(id: String, next := -1) -> void:
	if id not in SHOTS or _reloading or not (take_ready or failed): return
	_reloading = true
	get_tree().paused = false
	await _finish_streaming()
	next_variant = next if next >= 0 else (variant if shot_id == id else 0)
	next_shot = id
	var error := get_tree().reload_current_scene()
	if error != OK:
		next_shot = ""
		_reloading = false
		push_error("Could not reload take: " + error_string(error))

## Unattended runs and tests exit with an error; an interactive session keeps
## running and shows the reason so another shot can be picked from the panel.
func _fail(reason: String) -> void:
	push_error("PROMO: " + reason)
	take_ready = false
	failed = true
	if "--preview" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless" or not is_instance_valid(director):
		get_tree().quit(2)
		return
	director.show_error(reason)

func finish_preview() -> void:
	var tree := get_tree()
	await _finish_streaming()
	tree.unload_current_scene()
	tree.create_timer(0.08).timeout.connect(tree.quit)

func _finish_streaming() -> void:
	take_ready = false
	var generator := $WorldGenerator
	generator.set_process(false)
	while generator.building:
		await get_tree().process_frame
	await get_tree().process_frame

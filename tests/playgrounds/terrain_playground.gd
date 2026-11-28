extends Node3D
## Tour every landform of the generated world: meadow, cliff, wetland, ridge,
## canyon and basin, plus the river crossing and the dry valley cut. Each
## scenario parks the RV on the road inside that terrain; walk out or drive on
## to see it and the blend into the next landform.

const SCENARIOS := ["Meadow", "Cliff", "Wetland", "Ridge", "Canyon", "Basin", "River", "Valley"]
const DEFAULT_SEED := 42
const START_HOUR := 12.0
## Landform stations: the first one past the start where the terrain is fully
## shaped, the ground does not blend for this far either way, and no river
## bridge or dry valley is this close.
const FIRST_S := 900.0
const SCAN_STEP := 20.0
const SCAN_END := 20000.0
const PURE_MARGIN := 150.0
const CROSSING_CLEARANCE := 320.0
## Prefer a station this far from any roadside or offroad site.
const SITE_CLEARANCE := 120.0
## River and Valley park this far short of the crossing, facing it.
const RIVER_APPROACH := 110.0
const VALLEY_APPROACH := 260.0
const STARTER_PROPS := ["OilBarrel", "Scrap", "Scrap2", "Scrap3", "GasolineCan", "SpareBattery", "Flashlight"]
const WEATHERS := ["clear", "overcast", "fog", "rain"]

var controls := PlaygroundControls.new()
var main: Node3D
var clock: WorldClock
var field: WorldField
var rv: Chassis
var player: CharacterBody3D
var world_seed := DEFAULT_SEED
var station := 0.0


func _ready() -> void:
	get_window().title = "ApocalypseRV - Terrain"
	var scenario := PlaygroundControls.scenario(SCENARIOS[0])
	if scenario not in SCENARIOS: scenario = SCENARIOS[0]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): world_seed = argument.trim_prefix("--seed=").to_int()
	var profile := WorldProfile.new()
	field = WorldField.new(world_seed, profile)
	station = station_for(field, scenario)
	print("PLAYGROUND scenario=%s seed=%d s=%.0f kind=%s" % [scenario, world_seed, station, field.landforms.kind_at(station)])
	main = load("res://world/test_world.tscn").instantiate()
	var generator := main.get_node("WorldGenerator")
	generator.world_seed = world_seed
	generator.profile = profile
	var band := floori(station / profile.chunk_length)
	generator.restore_bands.assign(range(band - profile.chunks_behind, band + profile.chunks_ahead + 1))
	# The fixture's starter items belong to the origin, which is not loaded here.
	for title: String in STARTER_PROPS:
		var prop := main.get_node_or_null(title)
		if prop != null: prop.free()
	var frame := field.road_frame(station)
	main.get_node("NewRv").transform = Transform3D.IDENTITY
	rv = main.get_node("NewRv/Chassis")
	rv.transform = frame
	rv.position.y += 1.8
	player = main.get_node("Player")
	player.position = rv.position + frame.basis.x * 4.0
	get_tree().node_added.connect(_remove_monster)
	add_child(main)
	clock = main.get_node("WorldClock")
	clock.running = false
	clock.weather_running = false
	clock.set_time(1, START_HOUR)
	_set_weather(0)
	rv.handbrake = true
	rv.set_gear(0)
	for enemy in get_tree().get_nodes_in_group(Groups.MONSTERS): enemy.queue_free()
	_build_controls(scenario)
	await main.wait_for_play()
	# Let the chassis settle on its wheels before standing the player beside it.
	for i in range(Engine.physics_ticks_per_second): await get_tree().physics_frame
	var beside := rv.to_global(Vector3(3.6, 0.0, 1.65))
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(beside.x, field.height_at(beside.x, beside.z) + 0.1, beside.z)
	player.rotation.y = rv.global_rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("TERRAIN_READY scenario=%s ground=%s" % [scenario, _ground_text()])


## Road distance where the scenario parks the RV, derived from the seed's plan.
static func station_for(source: WorldField, scenario: String) -> float:
	var landforms := source.landforms
	match scenario:
		"River":
			var index := 0
			while float(landforms.river(index).s) < FIRST_S: index += 1
			return float(landforms.river(index).s) - RIVER_APPROACH
		"Valley":
			var row := 0
			while float(landforms.dry_valley(row).s) - VALLEY_APPROACH < FIRST_S: row += 1
			return float(landforms.dry_valley(row).s) - VALLEY_APPROACH
	var kind := TerrainLandforms.KINDS.find(scenario.to_lower())
	var fallback := -1.0
	var s := FIRST_S
	while s < SCAN_END:
		if _pure(landforms, s, kind) and _pure(landforms, s - PURE_MARGIN, kind) and _pure(landforms, s + PURE_MARGIN, kind) and _clear_of_crossings(landforms, s):
			if _site_distance(source, s) >= SITE_CLEARANCE: return s
			if fallback < 0.0: fallback = s
		s += SCAN_STEP
	if fallback < 0.0:
		push_warning("No clean %s station before s=%.0f; parking at the first stretch of it" % [scenario, SCAN_END])
		s = FIRST_S
		while landforms.kind_at(s) != TerrainLandforms.KINDS[kind] and s < SCAN_END: s += SCAN_STEP
		fallback = s
	return fallback


static func _pure(landforms: TerrainLandforms, s: float, kind: int) -> bool:
	var a := landforms.appearance_at(s)
	return int(a.x) == kind and a.z == 0.0


static func _clear_of_crossings(landforms: TerrainLandforms, s: float) -> bool:
	if landforms.dry_valley_weight(s) > 0.0: return false
	for river: Dictionary in landforms.rivers_near(-s, CROSSING_CLEARANCE):
		if absf(float(river.s) - s) < CROSSING_CLEARANCE: return false
	return true


static func _site_distance(source: WorldField, s: float) -> float:
	var nearest := INF
	for site: Dictionary in source.sites_near_z(-s, SITE_CLEARANCE):
		nearest = minf(nearest, absf(float(site.s) - s))
	return nearest


func _build_controls(scenario: String) -> void:
	add_child(controls)
	controls.scenarios(SCENARIOS, scenario)
	controls.note("Play normally: walk out from the road, board the RV and drive on to see the next landform blend in. Each landform lasts about 1.8 km of road. Monsters are removed and the clock is stopped at noon in clear weather. Pass --seed=N on the command line for another world; the landform order changes with the seed.")
	controls.choice("Weather", PackedStringArray(WEATHERS.map(func(key: String) -> String: return key.capitalize())), 0, _set_weather)
	controls.slider("Hour", 0.0, 24.0, 0.25, START_HOUR, func(hour: float) -> void: clock.set_time(clock.day_number(), fmod(hour, 24.0)))
	controls.toggle("Clock runs", false, func(on: bool) -> void: clock.running = on)
	controls.readout("Ground", _ground_text)
	controls.readout("Road distance", func() -> String: return "%.0f m (parked at %.0f m)" % [_viewer_s(), station])
	controls.readout("Next landform", _next_landform_text)
	controls.readout("Seed", func() -> String: return str(world_seed))


func _set_weather(index: int) -> void:
	clock.weather.set_weather(RVTerminalCommands.WEATHER_PRESETS[WEATHERS[index]], true)
	# Presets reroll natural wind; keep it calm so dust does not hide the ground.
	clock.wind.set_override(WorldWind.CALM)
	clock.apply_time()


func _viewer_s() -> float:
	var viewer := get_viewport().get_camera_3d()
	return -viewer.global_position.z if viewer != null else station


func _ground_text() -> String:
	var a := field.landforms.appearance_at(_viewer_s())
	var text: String = TerrainLandforms.KINDS[int(a.x)].capitalize()
	if a.z > 0.0: text += " > %s %.0f%%" % [TerrainLandforms.KINDS[int(a.y)].capitalize(), a.z * 100.0]
	var weights := field.landforms.material_weights(a)
	return "%s, rock %.2f, moisture %.2f" % [text, weights.x, weights.y]


func _next_landform_text() -> String:
	var s := _viewer_s()
	var here := field.landforms.kind_at(s)
	var ahead := s
	while field.landforms.kind_at(ahead) == here and ahead < s + TerrainLandforms.REGION_LENGTH * 2.0: ahead += SCAN_STEP
	return "%s in %.0f m" % [field.landforms.kind_at(ahead).capitalize(), ahead - s]


func _remove_monster(node: Node) -> void:
	if node is Monster: node.queue_free.call_deferred()


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_remove_monster): get_tree().node_added.disconnect(_remove_monster)

extends Node3D
## Listen to the sparse ambience: mostly silence, with a distant sound now and
## then that depends on the hour and the place, rarer and farther in fog and
## rain, muffled in the RV cabin and under a roof; and the faint interior hum
## with its drips and creaks. Real terrain picks forest and road by itself; check
## that part in the generated world. Also the weather wind: silent when calm,
## a dark bed swelling with the gusts, treetop rushes among trees, the RV hull
## whistling and rattling, and other outside sound masked in a strong wind.

const SCENARIOS := ["Lot"]
const PLACES := {"Open ground": Vector2(0, 0), "Forest": Vector2(1, 0), "Roadside": Vector2(0, 1), "Road through forest": Vector2(1, 1)}
const FOG := [WorldWeather.FOG_NONE, WorldWeather.FOG_LIGHT, WorldWeather.FOG_MEDIUM, WorldWeather.FOG_HEAVY]
const RAIN := [0.0, 1.0, 2.0]
const ROOMS := {
	"Off": [],
	"Bunker": ["res://assets/audio/rooms/small_room.tres", "res://assets/audio/ambience/room_small.ogg"],
	"Stairwell": ["res://assets/audio/rooms/corridor.tres", "res://assets/audio/ambience/room_hall.ogg"],
	"Hall": ["res://assets/audio/rooms/hall.tres", "res://assets/audio/ambience/room_hall.ogg"],
}
const SHELTER_AT := Vector3(12, 0, -8)
const START_HOUR := 12.0
const WIND_TIERS := ["Calm", "Breeze", "Strong wind", "Gale"]
const START_WIND := WorldWind.STRONG
## Candidate wind beds to compare, one folder per set holding wind_breeze.ogg,
## wind_strong.ogg and wind_gale.ogg; kept out of Git under .godot.
const CANDIDATES := "res://.godot/wind-candidates"
const BED_FILES := ["wind_breeze.ogg", "wind_strong.ogg", "wind_gale.ogg"]
## Candidate treetop rush sets sit beside the beds in rushes-<set> folders of WAV files.
const RUSH_PREFIX := "rushes-"

var controls := PlaygroundControls.new()
var clock: WorldClock
var interior_listener: SubViewport
var _fog := 0
var _rain := 0
var rv: Chassis
var _candidates: Array[String] = []
var _rush_sets: Array[String] = []


func _ready() -> void:
	get_window().title = "ApocalypseRV - Ambience"
	var scenario := PlaygroundControls.scenario(SCENARIOS[0])
	print("PLAYGROUND scenario=%s" % scenario)
	PlaygroundStage.flat_lot(self)
	# The clock drives the lot's sky and sun only if it finds them by these names.
	for child in get_children():
		if child is WorldEnvironment: child.name = "WorldEnvironment"
		elif child is DirectionalLight3D: child.name = "DirectionalLight3D"
	_build_shelter()
	rv = PlaygroundStage.parked_rv(self, Vector3(-8, 1.6, -6))
	clock = WorldClock.new()
	clock.name = "WorldClock"
	# The weather stays where the Playground tab puts it. The clock runs so the
	# gusts move; turn it off to freeze the hour.
	clock.weather_running = false
	add_child(clock)
	clock.set_time(1, START_HOUR)
	_apply_weather()
	clock.wind.set_override(START_WIND)
	# An empty interior world to listen from, with its own camera at the centre.
	interior_listener = SubViewport.new()
	interior_listener.own_world_3d = true
	add_child(interior_listener)
	var room_camera := Camera3D.new()
	interior_listener.add_child(room_camera)
	room_camera.current = true
	add_child(controls)
	controls.scenarios(SCENARIOS, scenario)
	controls.note("Mostly silence is the point: a sound comes every 30 to 90 seconds, rarer in fog and rain. Play one now skips the wait. The weather is frozen at the values below; the clock runs so the wind gusts, and Clock runs (Wind section) freezes the hour too. The lot has no terrain, so Place stands in for the trees and road around you. Sit in the RV (ahead, left) or stand under the open shed (ahead, right) to hear them muffled. Interior listens as if you had walked into one; the lot goes quiet meanwhile.")
	controls.button("Play one now", func() -> void: _ambience().play_next())
	controls.slider("Hour", 0.0, 24.0, 0.25, START_HOUR, func(hour: float) -> void: clock.set_time(1, fmod(hour, 24.0)))
	controls.choice("Place", PackedStringArray(PLACES.keys()), 0, _set_place)
	controls.choice("Fog", PackedStringArray(["None", "Light", "Medium", "Heavy"]), 0, func(index: int) -> void:
		_fog = index
		_apply_weather())
	controls.choice("Rain", PackedStringArray(["None", "Light", "Heavy"]), 0, func(index: int) -> void:
		_rain = index
		_apply_weather())
	controls.choice("Interior", PackedStringArray(ROOMS.keys()), 0, _set_room)
	controls.readout("Last sound", _last_sound)
	controls.readout("Next in", func() -> String: return "%d s" % ceili(_ambience().until_next) if _ambience() else "-")
	controls.readout("Muffle", func() -> String: return "%d%%" % roundi(get_node("/root/Sfx").cover(&"Outdoors") * 100.0))
	controls.section("Wind")
	controls.note("Calm is silent. From a breeze up, a low wind bed swells and fades with the gusts; Place Forest shelters the ground, so the bed drops and treetop rushes pass overhead in a strong wind or gale. Strong wind and gales whistle over the RV roof and rattle its panels; every missing panel whistles louder. Inside the RV cabin and under the shed the wind is muffled; Interior fades it out. Play a treetop rush plays one now at the current strength (stand in Place Forest to hear it as in the game). Recordings and Treetop rushes switch to candidate cuts if any are on disk.")
	controls.choice("Strength", PackedStringArray(WIND_TIERS), START_WIND, func(index: int) -> void: clock.wind.set_override(index))
	controls.toggle("Clock runs", true, func(on: bool) -> void: clock.running = on)
	controls.button("Play a treetop rush", func() -> void: _wind_audio().play_rush(clock.wind.strength()))
	controls.buttons([["Remove a hull panel", _remove_panel], ["Restore panels", _restore_panels]])
	_candidates = _candidate_sets()
	if not _candidates.is_empty():
		var names := PackedStringArray(["Chosen"])
		names.append_array(_candidates)
		controls.choice("Recordings", names, 0, _set_candidate)
	if DirAccess.dir_exists_absolute(CANDIDATES):
		_rush_sets.assign(Array(DirAccess.get_directories_at(CANDIDATES)).filter(func(folder: String) -> bool: return folder.begins_with(RUSH_PREFIX)))
	if not _rush_sets.is_empty():
		var sets := PackedStringArray(["Shipped"])
		for folder in _rush_sets: sets.append(folder.trim_prefix(RUSH_PREFIX).capitalize())
		controls.choice("Treetop rushes", sets, 0, _set_rush_set)
	controls.readout("Wind", func() -> String: return "%s, %.1f m/s, gust %.2f" % [clock.wind.description(), clock.wind_velocity.length(), clock.wind.gust(clock.elapsed_seconds)])
	controls.readout("Bed", _bed_text)
	controls.readout("Outside masked", func() -> String: return "%d%%" % roundi(get_node("/root/Sfx").exterior_masking() * 100.0))
	controls.readout("RV", func() -> String: return "%d panels missing, %d rattles" % [_rv_wind().missing_panels(), _rv_wind().rattles])
	_set_place(0)
	for i in range(Engine.physics_ticks_per_second): await get_tree().physics_frame
	var player := PlaygroundStage.player(self, Vector3(0, 0.05, 2))
	# Rain looks for its listener when the clock starts, before the player exists.
	clock.get_node("WeatherRain").listener = player


func _ambience() -> WorldAmbience:
	return clock.get_node_or_null("WorldAmbience") as WorldAmbience


func _last_sound() -> String:
	var ambience := _ambience()
	if ambience == null or ambience.last_sound.is_empty(): return "-"
	return "%s, %d m" % [String(ambience.last_sound).capitalize(), roundi(ambience.last_distance)]


func _set_place(index: int) -> void:
	var place: Vector2 = PLACES.values()[index]
	_ambience().forest_override = place.x
	_ambience().road_override = place.y
	# Trees keep most of the wind off the ground, as WorldWind.exposure_for does.
	_wind_audio().exposure_override = 1.0 - WorldWind.TREE_SHELTER * place.x


func _wind_audio() -> WorldWindAudio:
	return clock.get_node("WorldWindAudio") as WorldWindAudio


func _rv_wind() -> RVWindAudio:
	return rv.get_node("Audio").weather_wind


func _bed_text() -> String:
	var levels := _wind_audio().bed_levels
	return "breeze %.2f, strong %.2f, gale %.2f, %d rushes" % [levels[0], levels[1], levels[2], _wind_audio().rushes]


func _remove_panel() -> void:
	var slots := rv.get_node("StructureSlots") as RVStructureSlots
	for slot: String in rv.get_node("Audio").HULL_SLOTS:
		var panel := slots.occupant(slot)
		if panel != null and not panel is RVDoor:
			panel.set_health(0.0)
			return


func _restore_panels() -> void:
	var slots := rv.get_node("StructureSlots") as RVStructureSlots
	for slot: String in rv.get_node("Audio").HULL_SLOTS:
		var panel := slots.panel(slot)
		if panel != null and panel.is_destroyed: panel.set_health(panel.max_health)


func _candidate_sets() -> Array[String]:
	var found: Array[String] = []
	for folder in DirAccess.get_directories_at(CANDIDATES):
		if BED_FILES.all(func(file: String) -> bool: return FileAccess.file_exists(CANDIDATES.path_join(folder).path_join(file))):
			found.append(folder)
	return found


func _set_candidate(index: int) -> void:
	var beds: Array[AudioStream] = []
	if index > 0:
		for file: String in BED_FILES:
			var stream := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(CANDIDATES.path_join(_candidates[index - 1]).path_join(file)))
			stream.loop = true
			beds.append(stream)
	_wind_audio().bed_override = beds


func _set_rush_set(index: int) -> void:
	if index == 0:
		_wind_audio().rush_override = null
		return
	var event: SoundEvent = WorldWindAudio.TREE_RUSH.duplicate()
	var samples: Array[AudioStream] = []
	var folder := CANDIDATES.path_join(_rush_sets[index - 1])
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() == "wav":
			samples.append(AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(folder.path_join(file))))
	event.samples = samples
	_wind_audio().rush_override = event


func _apply_weather() -> void:
	clock.weather.set_weather(Vector3(0.0, RAIN[_rain], FOG[_fog]), true)
	clock.apply_time()


func _set_room(index: int) -> void:
	var sfx := get_node("/root/Sfx")
	var room: Array = ROOMS.values()[index]
	if room.is_empty(): sfx.set_listener_viewport(get_tree().root)
	else: sfx.set_listener_viewport(interior_listener, load(room[0]), load(room[1]))


## An open-sided shed: a solid roof on four posts.
func _build_shelter() -> void:
	var roof := StaticBody3D.new()
	roof.position = SHELTER_AT + Vector3(0, 3.2, 0)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(6, 0.25, 6)
	roof.add_child(shape)
	add_child(roof)
	RoadsideKit.part(self, Vector3(6, 0.25, 6), roof.position, Color("5d5f5c"))
	for corner in [Vector3(-2.8, 0, -2.8), Vector3(2.8, 0, -2.8), Vector3(-2.8, 0, 2.8), Vector3(2.8, 0, 2.8)]:
		RoadsideKit.part(self, Vector3(0.2, 3.1, 0.2), SHELTER_AT + corner + Vector3(0, 1.55, 0), Color("4a4c4a"))

extends Node3D
## Listen to the sparse ambience: mostly silence, with a distant sound now and
## then that depends on the hour and the place, rarer and farther in fog and
## rain, muffled in the RV cabin and under a roof; and the faint interior hum
## with its drips and creaks. Real terrain picks forest and road by itself; check
## that part in the generated world.

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

var controls := PlaygroundControls.new()
var clock: WorldClock
var interior_listener: SubViewport
var _fog := 0
var _rain := 0


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
	PlaygroundStage.parked_rv(self, Vector3(-8, 1.6, -6))
	clock = WorldClock.new()
	clock.name = "WorldClock"
	# The hour and the weather stay where the Playground tab puts them.
	clock.running = false
	add_child(clock)
	clock.set_time(1, START_HOUR)
	_apply_weather()
	# An empty interior world to listen from, with its own camera at the centre.
	interior_listener = SubViewport.new()
	interior_listener.own_world_3d = true
	add_child(interior_listener)
	var room_camera := Camera3D.new()
	interior_listener.add_child(room_camera)
	room_camera.current = true
	add_child(controls)
	controls.scenarios(SCENARIOS, scenario)
	controls.note("Mostly silence is the point: a sound comes every 30 to 90 seconds, rarer in fog and rain. Play one now skips the wait. Time and weather are frozen at the values below. The lot has no terrain, so Place stands in for the trees and road around you. Sit in the RV (ahead, left) or stand under the open shed (ahead, right) to hear them muffled. Interior listens as if you had walked into one; the lot goes quiet meanwhile.")
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

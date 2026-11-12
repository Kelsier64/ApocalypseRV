extends "res://world/main_world.gd"
## The main-world departure flow with stable, immediate light fog for demos.

const COMPASS_SCENE := "res://props/electronic_compass.tscn"
const COMPASS_DEFINITION = preload("res://props/electronic_compass_definition.tres")

func _enter_tree() -> void:
	if not _initial_placement_done:
		var generator := get_node("WorldGenerator")
		var demo_profile: WorldProfile = generator.profile.duplicate()
		demo_profile.opening_shelter = "starting_shelter"
		generator.profile = demo_profile
	super._enter_tree()

func _ready() -> void:
	super._ready()
	if fresh_start:
		# The first item goes into the active slot and is equipped by Player.
		var player := get_node("Player")
		player.add_item(COMPASS_DEFINITION.display_name, COMPASS_DEFINITION.is_large, COMPASS_SCENE)
		player.add_item(ItemNames.FLASHLIGHT, false, "res://props/flashlight.tscn")
	var rv: Chassis = get_node("NewRv/Chassis")
	rv.unlimited_materials = true
	rv.unlimited_fuel = true
	rv.add_fuel(rv.max_fuel)
	var clock: WorldClock = get_node("WorldClock")
	clock.weather.set_weather(Vector3(0.0, 0.0, WorldWeather.FOG_LIGHT), true)
	clock.weather_running = false
	clock.apply_time()
	get_node("StartRun").phase_changed.connect(_on_demo_phase_changed)

func _on_demo_phase_changed(_phase: String) -> void:
	# StartRun resumes weather on departure; the demo keeps its light fog.
	get_node("WorldClock").weather_running = false

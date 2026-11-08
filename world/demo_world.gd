extends "res://world/main_world.gd"
## The main-world departure flow with stable, immediate light fog for demos.

const COMPASS_SCENE := "res://props/electronic_compass.tscn"
const COMPASS_DEFINITION = preload("res://props/electronic_compass_definition.tres")

func _ready() -> void:
	super._ready()
	if fresh_start:
		# The first item goes into the active slot and is equipped by Player.
		get_node("Player").add_item(COMPASS_DEFINITION.display_name, COMPASS_DEFINITION.is_large, COMPASS_SCENE)
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

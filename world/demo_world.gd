extends "res://world/main_world.gd"
## The main-world departure flow with stable, immediate light fog for demos.

func _ready() -> void:
	super._ready()
	var clock: WorldClock = get_node("WorldClock")
	clock.weather.set_weather(Vector3(0.0, 0.0, WorldWeather.FOG_LIGHT), true)
	clock.weather_running = false
	clock.apply_time()
	get_node("StartRun").phase_changed.connect(_on_demo_phase_changed)

func _on_demo_phase_changed(_phase: String) -> void:
	# StartRun resumes weather on departure; the demo keeps its light fog.
	get_node("WorldClock").weather_running = false

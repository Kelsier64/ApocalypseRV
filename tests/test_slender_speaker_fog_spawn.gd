extends SceneTree
## The spawn gate follows sampled weather from the generator's owning world.
const GENERATOR = preload("res://world/world_generator.gd")
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func run() -> void:
	# Keep this fixture out of the tree: testing weather needs no terrain bake.
	var fixture := Node.new()
	var world := Node3D.new()
	fixture.add_child(world)
	var generator := GENERATOR.new()
	world.add_child(generator)
	var foreign_world := Node3D.new()
	fixture.add_child(foreign_world)
	var foreign_clock := WorldClock.new()
	foreign_clock.name = "WorldClock"
	foreign_world.add_child(foreign_clock)
	foreign_clock.weather.set_weather(Vector3(0, 0, WorldWeather.FOG_HEAVY), true)
	check(not generator._giant_weather_allows_spawn(), "Missing owning clock fails closed despite another world's heavy fog")
	var clock := WorldClock.new()
	clock.name = "WorldClock"
	world.add_child(clock)
	for conditions in [Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 2, 0)]:
		clock.weather.set_weather(conditions, true)
		check(not generator._giant_weather_allows_spawn(), "Overcast, clear and rain without fog cannot permit a giant: %s" % conditions)
	for strength in [WorldWeather.FOG_LIGHT, WorldWeather.FOG_MEDIUM, WorldWeather.FOG_HEAVY]:
		clock.weather.set_weather(Vector3(0, 0, strength), true)
		check(generator._giant_weather_allows_spawn(), "Light, medium and heavy fog permit a giant: %.1f" % strength)
	foreign_clock.weather.set_weather(Vector3(1, 0, 0), true)
	check(generator._giant_weather_allows_spawn(), "Foreign clear weather cannot override owning heavy fog")
	clock.weather.set_weather(Vector3(1, 0, 0), true)
	clock.weather.set_weather(Vector3(0, 0, WorldWeather.FOG_MEDIUM))
	check(not generator._giant_weather_allows_spawn(), "Fog target alone does not authorize spawning before the transition")
	clock.weather.advance(WorldWeather.TRANSITION * 0.5 - 1.0)
	check(clock.weather.sample().z < WorldWeather.FOG_LIGHT and not generator._giant_weather_allows_spawn(), "Transition below sampled light fog threshold rejects spawn")
	clock.weather.advance(1.0)
	check(is_equal_approx(clock.weather.sample().z, WorldWeather.FOG_LIGHT) and generator._giant_weather_allows_spawn(), "Exactly sampled light fog threshold authorizes spawn")
	clock.weather.advance(WorldWeather.TRANSITION * 0.5)
	clock.weather.set_weather(Vector3(1, 0, 0))
	check(generator._giant_weather_allows_spawn(), "Clear target does not suppress spawning while sampled fog remains thick")
	clock.weather.advance(WorldWeather.TRANSITION * 0.5)
	check(generator._giant_weather_allows_spawn(), "Fading fog still authorizes at the inclusive light fog threshold")
	clock.weather.advance(1.0)
	check(clock.weather.sample().z < WorldWeather.FOG_LIGHT and not generator._giant_weather_allows_spawn(), "Fading fog stops authorizing below the light fog threshold")
	fixture.free()
	if failures.is_empty(): print("PASS: Slender Speaker fog spawn gate uses owning sampled weather and inclusive light fog threshold")
	quit(0 if failures.is_empty() else 1)

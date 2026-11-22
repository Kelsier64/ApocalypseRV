extends RefCounted
## Wind is derived from the weather segment; it is never saved and never draws.

static func run(check: Callable) -> void:
	_check_first_segment(check)
	_check_determinism(check)
	_check_transition(check)
	_check_restore(check)
	_check_tiers(check)
	_check_override(check)
	_check_dust(check)

static func _wind_for(weather: WorldWeather, seed_value: int) -> WorldWind:
	var wind := WorldWind.new()
	wind.initialize(weather, seed_value)
	return wind

static func _fresh(seed_value: int) -> WorldWeather:
	var weather := WorldWeather.new()
	weather.initialize(seed_value)
	return weather

static func _check_first_segment(check: Callable) -> void:
	for seed_value: int in [1, 42, 314159, 2026]:
		var weather := _fresh(seed_value)
		var wind := _wind_for(weather, seed_value)
		check.call(wind.target_tier() == WorldWind.CALM and wind.strength() == 0.0 and wind.speed(1234.0) == 0.0 and wind.velocity(1234.0).is_zero_approx(), "A new run's first weather segment is calm for seed %d" % seed_value)
		weather.advance(weather.remaining * 0.5)
		check.call(wind.target_tier() == WorldWind.CALM, "The first segment stays calm until it ends for seed %d" % seed_value)

static func _check_determinism(check: Callable) -> void:
	for seed_value: int in [42, 314159]:
		var first := _fresh(seed_value)
		var second := _fresh(seed_value)
		var first_wind := _wind_for(first, seed_value)
		var second_wind := _wind_for(second, seed_value)
		var same := true
		for _segment in range(10):
			first.advance(first.remaining + WorldWeather.TRANSITION)
			second.advance(second.remaining + WorldWeather.TRANSITION)
			for seconds: float in [0.0, 37.5, 4000.0, 86400.0 * 3.0 + 11.0]:
				same = same and first_wind.target_tier() == second_wind.target_tier() and first_wind.strength() == second_wind.strength() and first_wind.heading(seconds) == second_wind.heading(seconds) and first_wind.gust(seconds) == second_wind.gust(seconds)
		check.call(same, "Wind tier, heading and gusts are deterministic per seed and weather RNG state (seed %d)" % seed_value)
	var a := _wind_for(_fresh(42), 42)
	var b := _wind_for(_fresh(43), 43)
	var differs := false
	for index in range(20): differs = differs or a.gust(index * 50.0) != b.gust(index * 50.0)
	check.call(differs, "Different world seeds give different gusts")
	var smooth := true
	var in_range := true
	var previous := a.gust(0.0)
	# Steps of 1/200 of a noise period, whatever the gust frequency is tuned to.
	var step_seconds := 0.005 / WorldWind.GUST_FREQUENCY
	for step in range(1, 2000):
		var value := a.gust(step * step_seconds)
		in_range = in_range and value >= 0.0 and value <= 1.0
		smooth = smooth and absf(value - previous) < 0.05
		previous = value
	check.call(in_range and smooth, "Gusts stay between 0 and 1 and change smoothly over game time")

static func _check_transition(check: Callable) -> void:
	# Find a natural segment change that alters the tier, then follow its blend.
	var weather := _fresh(42)
	var wind := _wind_for(weather, 42)
	var found := false
	for _segment in range(40):
		# Settle the previous transition first; it always ends before the segment.
		weather.advance(WorldWeather.TRANSITION)
		var before := wind.strength()
		var heading_before := wind.heading(0.0)
		weather.advance(weather.remaining)
		if wind.target_tier() == roundi(before): continue
		found = true
		check.call(is_equal_approx(wind.strength(), before) and is_equal_approx(wind.heading(0.0), heading_before), "A new weather segment starts its wind from the outgoing tier and heading")
		weather.advance(WorldWeather.TRANSITION * 0.5)
		var middle := wind.strength()
		check.call(middle > minf(before, wind.target_tier()) and middle < maxf(before, wind.target_tier()), "Wind strength blends between tiers during the weather transition")
		weather.advance(WorldWeather.TRANSITION)
		check.call(is_equal_approx(wind.strength(), wind.target_tier()), "Wind settles on the new tier once the weather transition ends")
		break
	check.call(found, "Seed 42 reaches a segment that changes the wind tier")

static func _check_restore(check: Callable) -> void:
	var weather := _fresh(314159)
	var wind := _wind_for(weather, 314159)
	for _segment in range(5): weather.advance(weather.remaining + WorldWeather.TRANSITION)
	var restored := WorldWeather.new()
	check.call(restored.restore(weather.capture()), "Weather with wind restores from the unchanged five-field capture")
	var restored_wind := _wind_for(restored, 314159)
	var same := wind.target_tier() == restored_wind.target_tier() and wind.strength() == restored_wind.strength()
	for seconds: float in [0.0, 900.0, 77777.0]:
		same = same and wind.heading(seconds) == restored_wind.heading(seconds) and wind.gust(seconds) == restored_wind.gust(seconds) and wind.speed(seconds) == restored_wind.speed(seconds)
	check.call(same, "Wind survives a weather capture and restore without its own saved fields")
	# Restoring in the middle of a transition settles on the segment's own wind.
	weather.advance(weather.remaining + WorldWeather.TRANSITION * 0.5)
	var mid := WorldWeather.new()
	mid.restore(weather.capture())
	var mid_wind := _wind_for(mid, 314159)
	check.call(mid_wind.target_tier() == wind.target_tier() and is_equal_approx(mid_wind.strength(), mid_wind.target_tier()), "A restore during a weather transition starts at the new segment's tier")
	# A restore into an already-initialized wind also settles instead of blending.
	var replay := WorldWeather.new()
	var replay_wind := _wind_for(replay, 314159)
	replay.initialize(314159)
	replay.advance(replay.remaining + WorldWeather.TRANSITION * 0.5)
	replay_wind.strength()
	replay.restore(weather.capture())
	check.call(replay_wind.target_tier() == wind.target_tier() and is_equal_approx(replay_wind.strength(), replay_wind.target_tier()), "Restoring under a live wind does not blend from the previous world")

static func _check_tiers(check: Callable) -> void:
	var monotonic := true
	var lifted := false
	var seen := {}
	for roll_index in range(100):
		for step_index in range(10):
			var tier_roll := roll_index / 100.0
			var step_roll := step_index / 10.0
			var dry := WorldWind.tier_for(tier_roll, step_roll, false)
			var stormy := WorldWind.tier_for(tier_roll, step_roll, true)
			seen[dry] = true
			monotonic = monotonic and stormy >= dry and stormy <= dry + 1 and stormy <= WorldWind.GALE
			lifted = lifted or stormy > dry
			if roll_index > 0: monotonic = monotonic and dry >= WorldWind.tier_for((roll_index - 1) / 100.0, step_roll, false)
	check.call(seen.size() == WorldWind.NAMES.size(), "Every wind tier, calm to gale, is reachable")
	check.call(monotonic and lifted, "Heavy rain only raises the wind tier, by at most one step")
	# Natural segments over many seeds produce more than one tier.
	var natural := {}
	for seed_value in range(8):
		var weather := _fresh(seed_value)
		var wind := _wind_for(weather, seed_value)
		for _segment in range(6):
			weather.advance(weather.remaining)
			natural[wind.target_tier()] = true
	check.call(natural.size() >= 3, "Natural weather segments vary the wind tier")

static func _check_override(check: Callable) -> void:
	var weather := _fresh(42)
	var wind := _wind_for(weather, 42)
	for _segment in range(3): weather.advance(weather.remaining + WorldWeather.TRANSITION)
	var natural := wind.target_tier()
	var saved := weather.capture()
	wind.set_override(WorldWind.GALE)
	check.call(wind.target_tier() == WorldWind.GALE and is_equal_approx(wind.strength(), WorldWind.GALE) and weather.capture() == saved, "A wind override applies at once and does not touch the weather capture")
	wind.override_heading = 1.0
	check.call(is_equal_approx(wind.heading(500.0), 1.0) and wind.direction(500.0).is_equal_approx(Vector3(sin(1.0), 0, -cos(1.0))), "A heading override fixes the wind direction")
	wind.override_heading = NAN
	wind.set_override(-1)
	check.call(wind.target_tier() == natural and is_equal_approx(wind.strength(), natural), "Clearing the override returns to the natural tier")
	wind.set_override(WorldWind.GALE)
	var restored := WorldWeather.new()
	restored.restore(weather.capture())
	check.call(_wind_for(restored, 42).override_tier == -1, "A load returns the wind to nature")

static func _check_dust(check: Callable) -> void:
	var kinds := TerrainLandforms.KINDS
	var wet := [kinds.find("wetland"), kinds.find("basin")]
	var dry := [kinds.find("canyon"), kinds.find("ridge")]
	var gale_speed: float = WorldWind.SPEEDS[WorldWind.GALE]
	var strong_speed: float = WorldWind.SPEEDS[WorldWind.STRONG]
	var ordered := true
	for speed_value: float in [strong_speed, gale_speed]:
		for w: int in wet:
			for d: int in dry:
				var low := WorldWind.dust_amount(speed_value * WorldWind.exposure_for(Vector3(w, w, 0)), WorldWind.dryness_for(Vector3(w, w, 0)), 0.0)
				var high := WorldWind.dust_amount(speed_value * WorldWind.exposure_for(Vector3(d, d, 0)), WorldWind.dryness_for(Vector3(d, d, 0)), 0.0)
				ordered = ordered and low < high
	check.call(ordered, "Wetland and forest basin raise less dust than canyon and ridge in the same wind")
	var canyon := Vector3(dry[0], dry[0], 0)
	var canyon_strong := WorldWind.dust_amount(strong_speed * WorldWind.exposure_for(canyon), WorldWind.dryness_for(canyon), 0.0)
	var canyon_gale := WorldWind.dust_amount(gale_speed * WorldWind.exposure_for(canyon), WorldWind.dryness_for(canyon), 0.0)
	check.call(canyon_gale > canyon_strong and canyon_strong > 0.0, "Dust grows from strong wind to a gale on dry ground")
	var rain_free := true
	for rain: float in [1.0, 1.5, 2.0]:
		rain_free = rain_free and WorldWind.dust_amount(gale_speed * 2.0, 1.0, rain) == 0.0
	check.call(rain_free, "Rain lays all dust, even in a gale on the driest ground")
	check.call(WorldWind.dust_amount(0.0, 1.0, 0.0) == 0.0, "Calm raises no dust")
	var blend_ok := true
	for t: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var mixed := WorldWind.dryness_for(Vector3(wet[0], dry[0], t))
		blend_ok = blend_ok and mixed >= WorldWind.dryness_for(Vector3(wet[0], wet[0], 0)) - 0.0001 and mixed <= WorldWind.dryness_for(canyon) + 0.0001
	check.call(blend_ok, "Dryness blends continuously across a landform transition")
	# The live path: calm first segment has no dust; an overridden gale over
	# canyon in a rain-free segment does, and rain removes it.
	var weather := _fresh(42)
	var wind := _wind_for(weather, 42)
	check.call(wind.dust_at(100.0, canyon) == 0.0, "The calm first segment raises no dust")
	weather.set_weather(Vector3.ZERO, true)
	wind.set_override(WorldWind.GALE)
	var any_dust := false
	for index in range(40): any_dust = any_dust or wind.dust_at(index * 37.0, canyon) > 0.0
	weather.set_weather(Vector3(0, 1, 0), true)
	var rained := true
	for index in range(40): rained = rained and wind.dust_at(index * 37.0, canyon) == 0.0
	check.call(any_dust and rained, "Live dust appears in a dry gale over canyon and vanishes in rain")

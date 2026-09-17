extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.environment = Environment.new()
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	world.add_child(sun)
	var clock := WorldClock.new()
	clock.running = false
	world.add_child(clock)
	check(clock.day_number() == 1 and clock.hour_of_day() == 8.0, "New game starts day 1 at 08:00")
	check(holder.environment.volumetric_fog_enabled == ForestFog.supported(), "World clock selects supported fog renderer")
	clock.advance(1800)
	check(clock.day_number() == 2 and is_equal_approx(clock.hour_of_day(), 8.0), "30 real minutes advances exactly one full day")
	clock.set_time(5, 23.99)
	clock.advance(1)
	check(clock.day_number() == 6 and clock.hour_of_day() < 0.01, "Midnight wraps time and increments day")
	var saved := clock.capture()
	clock.set_time(1, 12)
	check(clock.restore(saved) and clock.capture() == saved, "Clock restores fractional time and speed")
	for bad in [{}, {"elapsed_seconds": NAN, "day_length_minutes": 30}, {"elapsed_seconds": -1, "day_length_minutes": 30}, {"elapsed_seconds": 0, "day_length_minutes": 0}, {"elapsed_seconds": "8", "day_length_minutes": 30}]:
		check(not clock.restore(bad) and clock.capture() == saved, "Malformed clock cannot mutate live time")
	clock.set_time(1, 8)
	var morning := sun.global_basis
	clock.set_time(1, 16)
	check(morning != sun.global_basis and sun.light_energy > 0, "Sun and shadows rotate through the day")
	clock.set_time(1, 12)
	var noon_fog := holder.environment.fog_light_color
	check(sun.global_basis.z.is_equal_approx(clock.sun_direction()), "Sky disk direction matches the actual light")
	clock.set_time(1, 22)
	check(sun.light_energy == 0 and holder.environment.fog_light_color.get_luminance() < noon_fog.get_luminance() * 0.4, "Night has no solar illumination or bright daytime fog")
	check(clock.sky_material.get_shader_parameter("horizon_color") == holder.environment.fog_light_color, "Sky horizon follows fog color")
	clock.set_time(1, 23.99999)
	var before := clock.sun_direction()
	clock.set_time(2, 0)
	check(before.distance_to(clock.sun_direction()) < 0.00001, "Solar orbit continuous across midnight")
	clock.running = true
	paused = true
	var frozen := clock.elapsed_seconds
	await process_frame
	await process_frame
	check(clock.elapsed_seconds == frozen, "Tree pause stops world time")
	paused = false
	await process_frame
	await process_frame
	check(clock.elapsed_seconds > frozen, "Resume advances world time")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: world clock rate, rollover, persistence, pause, sun direction and night fog")
	quit(0 if failures.is_empty() else 1)

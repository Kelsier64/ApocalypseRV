extends RefCounted
## Runs inside the resource-cycle process, before the final driving interaction.

static func run(world: Node3D, rv: Chassis, player: CharacterBody3D, check: Callable) -> void:
	var tree := world.get_tree()
	var saved := {
		"fuel": rv.current_fuel, "power": rv.current_power,
		"fuel_cheat": rv.unlimited_fuel, "power_cheat": rv.unlimited_power,
		"materials_cheat": rv.unlimited_materials, "engine": rv.energy.engine_running,
		"charging": rv.energy.charging, "items": rv.storage.items.duplicate(true),
	}
	rv.set_engine_running(false)
	var clock := WorldClock.new()
	clock.name = "WorldClock"
	clock.running = false
	clock.weather_running = false
	clock.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(clock)
	# A disabled checkpoint candidate deliberately shares the root viewport.
	# Command lookup must follow the RV hierarchy rather than global groups.
	var staged := Node3D.new()
	staged.set_meta("entity_domain", true)
	staged.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(staged)
	var staged_clock := WorldClock.new()
	staged_clock.name = "WorldClock"
	staged.add_child(staged_clock)
	staged_clock.set_time(12, 4.0)
	staged_clock.weather.set_weather(Vector3(0, 1, 1), true)
	var staged_time := staged_clock.capture()
	var staged_weather := staged_clock.weather.capture()
	var commands := RVTerminalCommands.new()
	var context := {"rv": rv, "world": staged, "clock": staged_clock}
	var clock_before := clock.capture()
	var weather_before := clock.weather.capture()
	var children_before := world.get_child_count()
	for line in ["help", "help cheat", "help time", "help weather", "cheat", "cheat status", "status", "time", "weather"]:
		check.call(commands.execute(line, context).ok, "Terminal read succeeds: " + line)
	for line in ["", "che", "cheat ", "cheat p", "cheat power ", "time ", "time set ", "weather ", "weather set ", "weather set heavy_"]:
		commands.completion_candidates(line, context)
	check.call(commands.completion_candidates("cheat power ", context) == PackedStringArray(["cheat power false", "cheat power true"]), "Cheat completion lists only exact boolean spellings")
	check.call(commands.completion_candidates("weather set heavy_", context) == PackedStringArray(["weather set heavy_fog", "weather set heavy_rain"]), "Weather completion includes heavy fog and rain")
	check.call(clock.capture() == clock_before and clock.weather.capture() == weather_before and world.get_child_count() == children_before and _resources_unchanged(rv, saved), "Help, completion and status preserve resources, time, weather RNG and hierarchy")
	check.call(_flags(rv) == [saved.fuel_cheat, saved.power_cheat, saved.materials_cheat], "Read-only commands do not change cheats")
	check.call(commands.execute("cheat true", context).ok and _flags(rv) == [true, true, true], "Cheat true enables all flags on the connected RV")
	check.call(commands.execute("cheat power false", context).ok and _flags(rv) == [true, false, true], "Individual cheat changes only its resource")
	for line in ["cheat TRUE", "cheat 1", "cheat on", "cheat fuel False", "cheat power 0", "cheat materials yes", "cheat status true", "cheat true false", "cheat unknown true", "cheat fuel", "cheat fuel true extra"]:
		check.call(not commands.execute(line, context).ok and _flags(rv) == [true, false, true], "Malformed cheat is atomic: " + line)
	for line in ["cheat true; time set 00:00", "weather set clear | exit", "time set $(date)", "time set 12:00\ntime"]:
		check.call(not commands.execute(line, context).ok and commands.completion_candidates(line, context).is_empty(), "Shell syntax is rejected without evaluation: " + line.replace("\n", " "))
	check.call(_resources_unchanged(rv, saved), "Cheat commands preserve finite resource values")
	check.call(commands.execute("cheat false", context).ok and _flags(rv) == [false, false, false], "Cheat false disables all flags")
	for resource in ["fuel", "power", "materials"]:
		check.call(commands.execute("cheat " + resource + " true", context).ok and rv.get("unlimited_" + resource), "Each resource can be enabled: " + resource)
	check.call("\n".join(commands.execute("status", context).lines).count("UNLIMITED") == 3, "Shell status marks each unlimited resource")
	clock.set_time(3, 8.0)
	clock.deviation_fog = 0.5
	weather_before = clock.weather.capture()
	check.call(commands.execute("time set 23:59", context).ok and clock.day_number() == 3 and is_equal_approx(clock.elapsed_seconds, 3 * WorldClock.DAY_SECONDS - 60.0), "Time defaults to current day and applies immediately")
	check.call(commands.execute("time", context).lines[0] == "Day 3 23:59", "Time prints day and a padded 24-hour stamp")
	check.call(commands.execute("time set 00:00 1", context).ok and clock.elapsed_seconds == 0.0, "Time accepts the first minute")
	check.call(commands.execute("time set 01:05 1", context).ok and commands.execute("time", context).lines[0] == "Day 1 01:05", "Time retains exact minute boundaries without fractional-hour rounding")
	check.call(commands.execute("time set 23:59 1000000", context).ok and clock.day_number() == 1000000, "Time accepts the last supported day")
	var time_before := clock.elapsed_seconds
	for line in ["time set 24:00", "time set 23:60", "time set 1:00", "time set 01:0", "time set -1:00", "time set 01:00 0", "time set 01:00 -1", "time set 01:00 1000001", "time set 01:00 1.5", "time set 01:00 +1", "time set 01:00 99999999999999999999999", "time set", "time 01:00", "time set 01:00 1 extra"]:
		check.call(not commands.execute(line, context).ok and clock.elapsed_seconds == time_before, "Malformed time is atomic: " + line)
	check.call(clock.weather.capture() == weather_before and clock.deviation_fog == 0.5 and not clock.running and not clock.weather_running and _resources_unchanged(rv, saved), "Time jumps do not catch up resources/weather or change staging/deviation policy")
	for preset: String in RVTerminalCommands.WEATHER_PRESETS:
		var result := commands.execute("weather set " + preset, context)
		var expected: Vector3 = RVTerminalCommands.WEATHER_PRESETS[preset]
		check.call(result.ok and clock.weather.sample().is_equal_approx(expected) and clock.weather.target == expected, "Weather preset immediately sets sample and target: " + preset)
		check.call(result.lines[0].begins_with("Sample: ") and result.lines[1].begins_with("Target: "), "Weather reports sample and target in English: " + preset)
	weather_before = clock.weather.capture()
	for line in ["weather storm", "weather set", "weather set snow", "weather set CLEAR", "weather set clear extra"]:
		check.call(not commands.execute(line, context).ok and clock.weather.capture() == weather_before, "Malformed weather is atomic: " + line)
	check.call(clock.deviation_fog == 0.5 and not clock.running and not clock.weather_running, "Weather changes preserve staging and deviation fog")
	clock.set_time(2, 12.0)
	var natural_time := clock.elapsed_seconds
	var remaining := clock.weather.remaining
	clock.running = true
	clock.weather_running = true
	clock.advance(1.0)
	check.call(clock.elapsed_seconds > natural_time and clock.weather.remaining < remaining, "Time and weather settings preserve subsequent natural progression")
	var rng_before := clock.weather.rng.state
	clock.weather.advance(clock.weather.remaining + WorldWeather.TRANSITION)
	check.call(clock.weather.rng.state != rng_before and WorldWeather.valid_state(clock.weather.capture()), "Preset weather still selects its next natural conditions")
	clock.running = false
	clock.weather_running = false
	world.remove_child(clock)
	check.call(not commands.execute("time set 12:00", context).ok and not commands.execute("weather set clear", context).ok, "Missing owning clock rejects mutation instead of selecting the staged clock")
	world.add_child(clock)
	check.call(staged_clock.capture() == staged_time and staged_clock.weather.capture() == staged_weather, "Commands leave the staged world's clock and weather unchanged")
	var terminal: Item = rv.get_node("TabletScreen")
	var ui: Node = terminal.ui_instance
	terminal.interact_hold(player)
	check.call(ui.visible and terminal.current_user == player and ui._owns_session(), "Production terminal opens a valid player session")
	if ui.visible and ui._owns_session():
		var chord := InputEventKey.new()
		chord.keycode = KEY_D
		chord.physical_keycode = KEY_D
		chord.ctrl_pressed = true
		chord.pressed = true
		Input.parse_input_event(chord)
		await tree.process_frame
		chord.pressed = false
		Input.parse_input_event(chord)
		check.call(ui.mode == ui.Mode.SHELL, "Real Ctrl+D input opens the shell")
		ui.submit_command("rvctl")
		check.call(ui.mode == ui.Mode.TUI, "rvctl returns to vehicle controls")
		ui._refresh()
		check.call(ui._texts["overview:status"].text.count("UNLIMITED") == 3 and ui._texts["materials"].text.contains("UNLIMITED"), "TUI displays all unlimited flags including materials")
		check.call(ui._texts["overview:status"].text.contains("%.1f / %.1f" % [rv.current_fuel, rv.max_fuel]) and ui._texts["overview:status"].text.contains("%.1f / %.1f" % [rv.current_power, rv.max_power]), "Unlimited UI retains finite fuel and power amounts")
		terminal._close_ui()
		terminal.interact_hold(player)
		check.call(ui.visible and _flags(rv) == [true, true, true], "Closing and reopening the tablet retains session cheats")
		ui.enter_shell()
		ui.submit_command("cheat false")
		check.call(_flags(rv) == [false, false, false], "Owned shell dispatches cheat mutations")
		# Leave the UI visible to exercise its ownership guard directly.
		terminal.current_user = null
		var history_size: int = ui.command_history.size()
		time_before = clock.elapsed_seconds
		weather_before = clock.weather.capture()
		for line in ["cheat true", "time set 00:00 1", "weather set clear"]: ui.submit_command(line)
		check.call(_flags(rv) == [false, false, false] and clock.elapsed_seconds == time_before and clock.weather.capture() == weather_before and ui.command_history.size() == history_size, "Shell rejects commands after session ownership is lost")
		terminal.current_user = player
	terminal._close_ui()
	rv.current_fuel = saved.fuel
	rv.current_power = saved.power
	rv.unlimited_fuel = saved.fuel_cheat
	rv.unlimited_power = saved.power_cheat
	rv.unlimited_materials = saved.materials_cheat
	rv.storage.items = saved.items
	rv.set_engine_running(saved.engine)
	rv.energy.charging = saved.charging
	clock.queue_free()
	staged.queue_free()
	await tree.process_frame

static func _flags(rv: Chassis) -> Array:
	return [rv.unlimited_fuel, rv.unlimited_power, rv.unlimited_materials]

static func _resources_unchanged(rv: Chassis, saved: Dictionary) -> bool:
	return rv.current_fuel == saved.fuel and rv.current_power == saved.power and rv.storage.items == saved.items

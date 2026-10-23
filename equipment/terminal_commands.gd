class_name RVTerminalCommands
extends RefCounted
## Explicit game-command dispatch only. Input is never evaluated as code or an OS command.
## Handlers receive (args: PackedStringArray, context: Dictionary) and return
## {ok: bool, lines: PackedStringArray or Array[String], action: String}.
## Each output entry is a single line; CR/LF are rejected.
## Completers receive the same arguments, retaining an empty final token after
## whitespace, and return full replacement command lines. They must be read-only.

const MAX_INPUT_LENGTH := 512
const MAX_OUTPUT_LINES := 128
const MAX_OUTPUT_LENGTH := 16384
const ACTIONS := ["", "open_tui", "close_tablet", "clear"]
const UNSUPPORTED := "|&;<>$`\"'\\(){}[]"
const WEATHER_PRESETS := {
	"clear": Vector3(1, 0, 0), "overcast": Vector3.ZERO,
	"rain": Vector3(0, 1, 0), "heavy_rain": Vector3(0, 2, 0),
	"fog": Vector3(0, 0, 0.5), "medium_fog": Vector3(0, 0, 1),
	"heavy_fog": Vector3(0, 0, 2), "storm": Vector3(0, 2, 2),
}

var _commands: Dictionary = {}
var _help_length := 0

func _init() -> void:
	register_command("help", "help [command]", "List commands or show command usage.", _help, _complete_help)
	register_command("status", "status", "Read connected RV status.", _status)
	register_command("rvctl", "rvctl", "Open RV controls.", _open_tui)
	register_command("clear", "clear", "Clear shell output.", _clear)
	register_command("exit", "exit", "Close the tablet.", _exit)
	register_command("cheat", "cheat [status|true|false|fuel|power|materials|fly] [true|false|status]", "Read or change session-only RV resources or operator flight. cheat true/false changes resources only.", _cheat, _complete_cheat)
	register_command("time", "time [set HH:MM [day]]", "Read or immediately set world time (day 1-1000000).", _time, _complete_set)
	register_command("weather", "weather [set preset]", "Read sample/target or immediately set weather. Use Tab to list presets.", _weather, _complete_weather)

func register_command(name: String, usage: String, description: String, handler: Callable, completer: Callable = Callable()) -> bool:
	if _commands.size() >= MAX_OUTPUT_LINES or not _valid_name(name) or _commands.has(name) or not handler.is_valid() or handler.get_argument_count() != 2:
		return false
	if not completer.is_null() and (not completer.is_valid() or completer.get_argument_count() != 2):
		return false
	if usage.is_empty() or usage.length() > MAX_INPUT_LENGTH or description.length() > MAX_INPUT_LENGTH:
		return false
	if not _string_lines([usage, description]).ok:
		return false
	var help_length := _help_line(usage, description).length()
	if _help_length + help_length > MAX_OUTPUT_LENGTH:
		return false
	_commands[name] = {"usage": usage, "description": description, "handler": handler, "completer": completer}
	_help_length += help_length
	return true

func execute(line: String, context: Dictionary) -> Dictionary:
	var parsed := _parse(line)
	if not parsed.ok:
		return _error(parsed.error)
	var tokens: PackedStringArray = parsed.tokens
	if tokens.is_empty():
		return _result(true)
	var name := tokens[0]
	if not _commands.has(name):
		return _error("Unknown command: %s" % name)
	var handler: Callable = _commands[name].handler
	if not handler.is_valid():
		return _error("Command unavailable: %s" % name)
	return _validate_result(handler.call(tokens.slice(1), context))

func completion_candidates(line: String, context: Dictionary = {}) -> PackedStringArray:
	var parsed := _parse(line)
	if not parsed.ok:
		return PackedStringArray()
	var tokens: PackedStringArray = parsed.tokens
	var trailing_space := line.ends_with(" ") or line.ends_with("\t")
	if tokens.size() <= 1 and not (trailing_space and not tokens.is_empty()):
		var prefix := tokens[0] if not tokens.is_empty() else ""
		return _matching_names(prefix)
	var name := tokens[0]
	if not _commands.has(name):
		return PackedStringArray()
	var completer: Callable = _commands[name].completer
	if not completer.is_valid():
		return PackedStringArray()
	var args := tokens.slice(1)
	if trailing_space:
		args.append("")
	var raw: Variant = completer.call(args, context)
	var lines := _string_lines(raw)
	if not lines.ok:
		return PackedStringArray()
	var result := PackedStringArray()
	for candidate: String in lines.lines:
		var candidate_parse := _parse(candidate)
		if candidate_parse.ok and not candidate_parse.tokens.is_empty() and candidate_parse.tokens[0] == name and not result.has(candidate):
			result.append(candidate)
	result.sort()
	return result

func _parse(line: String) -> Dictionary:
	if line.length() > MAX_INPUT_LENGTH:
		return {"ok": false, "error": "Command exceeds 512 characters."}
	for index in range(line.length()):
		var character := line.substr(index, 1)
		var code := line.unicode_at(index)
		if UNSUPPORTED.contains(character) or (code < 32 and code != 9) or code == 127:
			return {"ok": false, "error": "Unsupported shell syntax. Use a command and plain arguments."}
	var tokens := line.replace("\t", " ").split(" ", false)
	if not tokens.is_empty() and not _valid_name(tokens[0]):
		return {"ok": false, "error": "Command names must use lowercase letters, digits, '-' or '_'."}
	return {"ok": true, "tokens": tokens}

func _valid_name(name: String) -> bool:
	if name.is_empty() or name.length() > 64:
		return false
	for index in range(name.length()):
		var code := name.unicode_at(index)
		var letter := code >= 97 and code <= 122
		if not letter and (index == 0 or not ((code >= 48 and code <= 57) or code == 45 or code == 95)):
			return false
	return true

func _string_lines(raw: Variant) -> Dictionary:
	if not (raw is PackedStringArray or raw is Array) or raw.size() > MAX_OUTPUT_LINES:
		return {"ok": false}
	var total := 0
	var lines := PackedStringArray()
	for entry: Variant in raw:
		if not entry is String or entry.contains("\r") or entry.contains("\n"):
			return {"ok": false}
		total += entry.length()
		if total > MAX_OUTPUT_LENGTH:
			return {"ok": false}
		lines.append(entry)
	return {"ok": true, "lines": lines}

func _validate_result(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not raw.get("ok") is bool or not raw.get("action") is String or not ACTIONS.has(raw.action):
		return _error("Invalid command result.")
	var lines := _string_lines(raw.get("lines"))
	if not lines.ok or (not raw.ok and not raw.action.is_empty()):
		return _error("Invalid command result.")
	return _result(raw.ok, lines.lines, raw.action)

func _result(ok: bool, lines: PackedStringArray = PackedStringArray(), action: String = "") -> Dictionary:
	return {"ok": ok, "lines": lines, "action": action}

func _error(message: String) -> Dictionary:
	return _result(false, PackedStringArray([message]))

func _usage(name: String) -> Dictionary:
	return _error("Usage: %s" % _commands[name].usage)

func _matching_names(prefix: String) -> PackedStringArray:
	var names := PackedStringArray()
	for name: String in _commands:
		if name.begins_with(prefix):
			names.append(name)
	names.sort()
	return names

func _help(args: PackedStringArray, _context: Dictionary) -> Dictionary:
	if args.size() > 1:
		return _usage("help")
	if args.size() == 1:
		if not _commands.has(args[0]):
			return _error("Unknown command: %s" % args[0])
		var command: Dictionary = _commands[args[0]]
		return _result(true, PackedStringArray([command.usage, command.description]))
	var lines := PackedStringArray()
	for name in _matching_names(""):
		lines.append(_help_line(_commands[name].usage, _commands[name].description))
	return _result(true, lines)

func _help_line(usage: String, description: String) -> String:
	return "%-18s %s" % [usage, description]

func _complete_help(args: PackedStringArray, _context: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if args.size() == 1:
		for name in _matching_names(args[0]):
			lines.append("help " + name)
	return lines

func _status(args: PackedStringArray, context: Dictionary) -> Dictionary:
	if not args.is_empty():
		return _usage("status")
	var rv: Variant = context.get("rv")
	if typeof(rv) != TYPE_OBJECT or not is_instance_valid(rv) or (rv is Node and rv.is_queued_for_deletion()):
		return _error("RV unavailable.")
	var status_lines: Variant = context.get("status_lines")
	if status_lines is Callable and status_lines.is_valid() and status_lines.get_argument_count() == 0:
		var lines := _string_lines(status_lines.call())
		if lines.ok and not lines.lines.is_empty():
			return _result(true, lines.lines)
		return _error("RV status unavailable.")
	if rv is Chassis:
		return _result(true, PackedStringArray([
			"Speed: %.1f km/h" % (rv.road_speed() * 3.6),
			"Fuel: %.1f / %.1f%s" % [rv.current_fuel, rv.max_fuel, _unlimited(rv.unlimited_fuel)],
			"Power: %.1f / %.1f%s" % [rv.current_power, rv.max_power, _unlimited(rv.unlimited_power)],
			"Materials: %d / %d%s" % [rv.storage.used(), rv.storage.capacity, _unlimited(rv.unlimited_materials)],
			"Parking brake: %s" % ("ON" if rv.handbrake else "OFF"),
		]))
	return _error("RV status unavailable.")

func _open_tui(args: PackedStringArray, _context: Dictionary) -> Dictionary:
	return _result(true, PackedStringArray(), "open_tui") if args.is_empty() else _usage("rvctl")

func _clear(args: PackedStringArray, _context: Dictionary) -> Dictionary:
	return _result(true, PackedStringArray(), "clear") if args.is_empty() else _usage("clear")

func _exit(args: PackedStringArray, _context: Dictionary) -> Dictionary:
	return _result(true, PackedStringArray(), "close_tablet") if args.is_empty() else _usage("exit")

func _connected_rv(context: Dictionary) -> Chassis:
	var rv: Variant = context.get("rv")
	return rv if rv is Chassis and is_instance_valid(rv) and not rv.is_queued_for_deletion() else null

func _unlimited(enabled: bool) -> String:
	return " UNLIMITED" if enabled else ""

func _cheat(args: PackedStringArray, context: Dictionary) -> Dictionary:
	if not args.is_empty() and args[0] == "fly": return _cheat_fly(args.slice(1), context)
	var all_flags := args.size() == 1 and args[0] in ["true", "false"]
	var one_flag := args.size() == 2 and args[0] in ["fuel", "power", "materials"] and args[1] in ["true", "false"]
	if not (args.is_empty() or (args.size() == 1 and args[0] == "status") or all_flags or one_flag):
		return _usage("cheat")
	var rv := _connected_rv(context)
	if rv == null: return _error("RV unavailable.")
	if all_flags:
		for resource in ["fuel", "power", "materials"]: rv.set("unlimited_" + resource, args[0] == "true")
	elif one_flag: rv.set("unlimited_" + args[0], args[1] == "true")
	return _result(true, PackedStringArray([
		"Fuel: %s" % ("UNLIMITED" if rv.unlimited_fuel else "finite"),
		"Power: %s" % ("UNLIMITED" if rv.unlimited_power else "finite"),
		"Materials: %s" % ("UNLIMITED" if rv.unlimited_materials else "finite"),
	]))

func _cheat_fly(args: PackedStringArray, context: Dictionary) -> Dictionary:
	if args.size() > 1 or (args.size() == 1 and args[0] not in ["true", "false", "status"]): return _usage("cheat")
	var rv := _connected_rv(context)
	if rv == null: return _error("RV unavailable.")
	var player: Variant = context.get("player")
	if not player is Node3D or not is_instance_valid(player) or player.is_queued_for_deletion() or not player.is_inside_tree() or not player.has_method("set_cheat_flying") or not WorldEntities.same_world(player, rv):
		return _error("Terminal operator unavailable.")
	if args.size() == 1 and args[0] != "status":
		if not player.set_cheat_flying(args[0] == "true"):
			return _error("Flight change blocked. Leave seats, grabs and placement; use open space to disable flight.")
	var flying: bool = player.is_cheat_flying()
	var lines := PackedStringArray(["Flight: %s" % ("ON" if flying else "OFF")])
	if flying: lines.append("Close terminal: WASD fly, Space up, Ctrl down, Shift fast. cheat fly false disables in open space.")
	return _result(true, lines)

func _world_clock(context: Dictionary) -> WorldClock:
	var rv := _connected_rv(context)
	if rv == null or not rv.is_inside_tree(): return null
	# Resolve through this RV's ancestors only. Never use current_scene, a
	# global group, or WorldEntities.get_container (which may create a node).
	var ancestor: Node = rv.get_parent()
	while ancestor != null and not ancestor is Viewport:
		var clock := ancestor.get_node_or_null("WorldClock") as WorldClock
		if clock != null and not clock.is_queued_for_deletion(): return clock
		if ancestor.has_meta("entity_domain"): break
		ancestor = ancestor.get_parent()
	return null

func _digits(value: String) -> bool:
	if value.is_empty(): return false
	for index in value.length():
		if value.unicode_at(index) < 48 or value.unicode_at(index) > 57: return false
	return true

func _time(args: PackedStringArray, context: Dictionary) -> Dictionary:
	if not args.is_empty() and (args.size() < 2 or args.size() > 3 or args[0] != "set"):
		return _usage("time")
	var hour := 0
	var minute := 0
	var day := 0
	if not args.is_empty():
		var stamp := args[1]
		if stamp.length() != 5 or stamp.substr(2, 1) != ":" or not _digits(stamp.left(2)) or not _digits(stamp.right(2)):
			return _usage("time")
		hour = int(stamp.left(2))
		minute = int(stamp.right(2))
		if hour > 23 or minute > 59: return _usage("time")
		if args.size() == 3:
			if not _digits(args[2]) or args[2].length() > 7: return _usage("time")
			day = int(args[2])
			if day < 1 or day > 1000000: return _usage("time")
	var clock := _world_clock(context)
	if clock == null: return _error("World clock unavailable.")
	if not args.is_empty():
		if day == 0: day = clock.day_number()
		if day < 1 or day > 1000000: return _usage("time")
		# Keep minute boundaries exact: fractional hours can round just below
		# the requested minute, including in the clock's minute notification.
		clock.restore({"elapsed_seconds": (day - 1) * WorldClock.DAY_SECONDS + hour * 3600.0 + minute * 60.0, "day_length_minutes": clock.day_length_minutes})
	var minutes := floori(fposmod(clock.elapsed_seconds, WorldClock.DAY_SECONDS) / 60.0)
	return _result(true, PackedStringArray(["Day %d %02d:%02d" % [clock.day_number(), minutes / 60, minutes % 60]]))

func _weather(args: PackedStringArray, context: Dictionary) -> Dictionary:
	if not args.is_empty() and (args.size() != 2 or args[0] != "set" or not WEATHER_PRESETS.has(args[1])):
		return _usage("weather")
	var clock := _world_clock(context)
	if clock == null: return _error("World clock unavailable.")
	if not args.is_empty():
		clock.weather.set_weather(WEATHER_PRESETS[args[1]], true)
		clock.apply_time()
	return _result(true, PackedStringArray([
		_weather_line("Sample", clock.weather.sample()),
		_weather_line("Target", clock.weather.target),
	]))

func _weather_line(label: String, value: Vector3) -> String:
	var conditions := PackedStringArray(["clear" if value.x > 0.5 else "overcast"])
	if value.y > 0.0: conditions.append("rain" if value.y <= 1.0 else "heavy rain")
	if value.z > 0.0: conditions.append("light fog" if value.z <= 0.5 else ("medium fog" if value.z <= 1.0 else "heavy fog"))
	return "%s: %s (clear %.2f, rain %.2f, fog %.2f)" % [label, ", ".join(conditions), value.x, value.y, value.z]

func _complete_options(prefix: String, options: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for option: String in options:
		if option.begins_with(prefix): result.append(option)
	return result

func _complete_cheat(args: PackedStringArray, _context: Dictionary) -> PackedStringArray:
	if args.size() == 1:
		return _complete_options("cheat " + args[0], ["cheat status", "cheat true", "cheat false", "cheat fuel", "cheat power", "cheat materials", "cheat fly"])
	if args.size() == 2 and args[0] == "fly":
		return _complete_options("cheat fly " + args[1], ["cheat fly true", "cheat fly false", "cheat fly status"])
	if args.size() == 2 and args[0] in ["fuel", "power", "materials"]:
		var prefix := "cheat " + args[0] + " "
		return _complete_options(prefix + args[1], [prefix + "true", prefix + "false"])
	return PackedStringArray()

func _complete_set(args: PackedStringArray, _context: Dictionary) -> PackedStringArray:
	return _complete_options("time " + args[0], ["time set"]) if args.size() == 1 else PackedStringArray()

func _complete_weather(args: PackedStringArray, _context: Dictionary) -> PackedStringArray:
	if args.size() == 1: return _complete_options("weather " + args[0], ["weather set"])
	if args.size() == 2 and args[0] == "set":
		var options: Array = []
		for preset: String in WEATHER_PRESETS: options.append("weather set " + preset)
		return _complete_options("weather set " + args[1], options)
	return PackedStringArray()

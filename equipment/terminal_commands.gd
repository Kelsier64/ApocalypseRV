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

var _commands: Dictionary = {}
var _help_length := 0

func _init() -> void:
	register_command("help", "help [command]", "List commands or show command usage.", _help, _complete_help)
	register_command("status", "status", "Read connected RV status.", _status)
	register_command("rvctl", "rvctl", "Open RV controls.", _open_tui)
	register_command("clear", "clear", "Clear shell output.", _clear)
	register_command("exit", "exit", "Close the tablet.", _exit)
	register_command("cheat", "cheat", "Reserved for future game commands.", _cheat)

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
			"Fuel: %.1f / %.1f" % [rv.current_fuel, rv.max_fuel],
			"Power: %.1f / %.1f" % [rv.current_power, rv.max_power],
			"Parking brake: %s" % ("ON" if rv.handbrake else "OFF"),
		]))
	return _error("RV status unavailable.")

func _open_tui(args: PackedStringArray, _context: Dictionary) -> Dictionary:
	return _result(true, PackedStringArray(), "open_tui") if args.is_empty() else _usage("rvctl")

func _clear(args: PackedStringArray, _context: Dictionary) -> Dictionary:
	return _result(true, PackedStringArray(), "clear") if args.is_empty() else _usage("clear")

func _exit(args: PackedStringArray, _context: Dictionary) -> Dictionary:
	return _result(true, PackedStringArray(), "close_tablet") if args.is_empty() else _usage("exit")

func _cheat(_args: PackedStringArray, _context: Dictionary) -> Dictionary:
	return _error("cheat: not implemented.")

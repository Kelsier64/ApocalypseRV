extends SceneTree
## Safe simulated shell parsing, explicit dispatch and read-only completion.

const COMMANDS = preload("res://equipment/terminal_commands.gd")
var failures: Array[String] = []
var handler_calls := 0
var status_calls := 0
var captured_args := PackedStringArray()
var captured_context: Dictionary = {}

func _init() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func run() -> void:
	var commands := COMMANDS.new()
	var rv := Node.new()
	rv.set_meta("fuel", 42)
	var context := {"rv": rv, "player": rv, "terminal": rv, "status_lines": _status_lines}
	for blank in ["", "  ", "\t  \t"]:
		var result := commands.execute(blank, context)
		check(result.ok and result.lines.is_empty() and result.action.is_empty(), "Blank input has no output or action")
	check(commands.execute("  help\t status  ", context).ok, "Spaces and tabs parse consistently")
	check(commands.execute("help", context).lines.size() == 6, "Help lists all built-ins")
	check(commands.execute("help status", context).lines[0] == "status", "Help exposes registered usage")
	check(not commands.execute("help missing", context).ok, "Help rejects unknown command")
	check(not commands.execute("missing", context).ok, "Unknown command returns structured error")
	check(not commands.execute("STATUS", context).ok, "Command names are lowercase")
	check(not commands.execute("9invalid", context).ok, "Names start with a letter")
	check(not commands.execute("help one two", context).ok, "Built-in argument count enforced")
	check(not commands.execute("x".repeat(513), context).ok, "Input length is bounded")
	check(commands.execute("status", context).lines == PackedStringArray(["Fuel: 42"]), "Status reads provided connected RV lines")
	check(status_calls == 1, "Status provider called once")
	check(not commands.execute("status", {}).ok, "Missing RV reports unavailable")
	check(not commands.execute("status", {"rv": 42, "status_lines": _status_lines}).ok, "Invalid RV rejects status provider")
	check(status_calls == 1, "Unavailable RV does not call status provider")
	check(not commands.execute("status", {"rv": rv, "status_lines": func(): return [3]}).ok, "Malformed status provider rejected")
	check(not commands.execute("status", {"rv": rv}).ok, "Unknown RV type has no arbitrary property dispatch")
	for name: String in {"rvctl": "open_tui", "clear": "clear", "exit": "close_tablet"}:
		var expected: String = {"rvctl": "open_tui", "clear": "clear", "exit": "close_tablet"}[name]
		var result := commands.execute(name, context)
		check(result.ok and result.action == expected and result.lines.is_empty(), "Explicit UI action: " + name)
		check(not commands.execute(name + " extra", context).ok, "UI command refuses arguments: " + name)
	check(not commands.execute("cheat fuel 999", context).ok, "Reserved cheat is unavailable")
	check(not commands.register_command("cheat", "cheat", "override", _custom_handler), "Reserved command cannot be replaced")
	check(commands.register_command("echo", "echo [text]", "Echo plain text.", _custom_handler, _custom_completer), "Custom command registration succeeds")
	check(not commands.register_command("echo", "echo", "duplicate", _custom_handler), "Duplicate rejected")
	check(not commands.register_command("Bad", "Bad", "invalid", _custom_handler), "Invalid name rejected")
	check(not commands.register_command("empty", "empty", "invalid", Callable()), "Missing handler rejected")
	check(not commands.register_command("wrong_arity", "wrong_arity", "invalid", func(): return {}), "Handler with wrong signature rejected")
	check(not commands.register_command("wrong_completer", "wrong_completer", "invalid", _custom_handler, func(): return []), "Completer with wrong signature rejected")
	check(not commands.register_command("bad_usage", "bad_usage\nextra", "invalid", _custom_handler), "Multiline usage cannot invalidate help")
	check(not commands.register_command("bad_description", "bad_description", "invalid\rextra", _custom_handler), "Multiline description cannot invalidate help")
	var echoed := commands.execute(" echo\t hello   world ", context)
	check(echoed.ok and echoed.lines == PackedStringArray(["hello world"]), "Registered handler receives tokenized arguments")
	check(captured_args == PackedStringArray(["hello", "world"]) and captured_context.rv == rv, "Handler receives explicit arguments and context")
	check(handler_calls == 1, "Custom handler dispatches exactly once")
	for syntax in ["echo a | status", "echo a > file", "echo a < file", "echo a & status", "echo a; status", "echo $(status)", "echo `status`", "echo \"quoted\"", "echo 'quoted'", "echo a\\ b", "echo a\nstatus", "echo a\rstatus", "echo " + String.chr(1)]:
		var result := commands.execute(syntax, context)
		check(not result.ok and result.action.is_empty() and result.lines[0].begins_with("Unsupported"), "Unsupported syntax rejected: " + syntax)
		check(commands.completion_candidates(syntax, context).is_empty(), "Unsupported syntax has no completion")
	check(handler_calls == 1 and status_calls == 1, "Invalid syntax never dispatches")
	check(commands.completion_candidates("st") == PackedStringArray(["status"]), "Command-prefix completion")
	check(commands.completion_candidates("").size() == 7, "Empty completion lists registered commands")
	check(commands.completion_candidates("help st") == PackedStringArray(["help status"]), "Help completes command argument")
	check(commands.completion_candidates("help ").size() == 7, "Trailing space retains empty argument")
	check(commands.completion_candidates("echo h", context) == PackedStringArray(["echo hello"]), "Custom completion returns valid unique same-command lines")
	check(handler_calls == 1 and status_calls == 1, "Completion never executes handlers or status")
	var boundary := commands.execute("echo " + "x".repeat(507), context)
	check(boundary.ok and boundary.lines[0].length() == 507, "Exactly 512 characters dispatch normally")
	check(not commands.execute("echo " + "x".repeat(508), context).ok and handler_calls == 2, "Overlength command never reaches handler")
	check(rv.get_meta("fuel") == 42 and rv.get_child_count() == 0 and context.size() == 4, "Built-ins, parsing and completion leave world and context unchanged")
	var oversized_lines: Array[String] = []
	oversized_lines.resize(129)
	oversized_lines.fill("")
	var malformed: Array = [null, true, {}, {"ok": 1, "lines": [], "action": ""}, {"ok": true, "lines": [1], "action": ""}, {"ok": true, "lines": [], "action": "spawn"}, {"ok": false, "lines": [], "action": "clear"}, {"ok": true, "lines": "text", "action": ""}, {"ok": true, "lines": oversized_lines, "action": ""}, {"ok": true, "lines": ["x".repeat(16385)], "action": ""}]
	for index in range(malformed.size()):
		var bad_value: Variant = malformed[index]
		var bad_handler := func(_args: PackedStringArray, _context: Dictionary): return bad_value
		var name := "bad%d" % index
		check(commands.register_command(name, name, "Malformed result fixture.", bad_handler), "Malformed fixture registers")
		var result := commands.execute(name, context)
		check(not result.ok and result.action.is_empty() and result.lines == PackedStringArray(["Invalid command result."]), "Malformed result fails closed: " + name)
	for separator in ["\n", "\r", "\r\n"]:
		var multiline: String = "row" + separator + "row"
		var multiline_handler := func(_args: PackedStringArray, _context: Dictionary): return {"ok": true, "lines": PackedStringArray([multiline]), "action": "clear"}
		var isolated := COMMANDS.new()
		check(isolated.register_command("multiline", "multiline", "Invalid multiline output.", multiline_handler), "Multiline handler fixture registers")
		var rejected := isolated.execute("multiline", {})
		check(not rejected.ok and rejected.action.is_empty() and rejected.lines == PackedStringArray(["Invalid command result."]), "CR/LF output rejects the entire result and action")
	var bypass_handler := func(_args: PackedStringArray, _context: Dictionary): return {"ok": true, "lines": ["row\n".repeat(129)], "action": ""}
	var line_boundary := COMMANDS.new()
	check(line_boundary.register_command("line_bypass", "line_bypass", "Rendered line limit fixture.", bypass_handler), "Rendered line overflow fixture registers")
	check(not line_boundary.execute("line_bypass", {}).ok, "A single entry cannot bypass the rendered line limit")
	var capped := COMMANDS.new()
	var initial_count := capped.completion_candidates("").size()
	for index in range(COMMANDS.MAX_OUTPUT_LINES - initial_count):
		var name := "command%d" % index
		check(capped.register_command(name, name, "Registry boundary fixture.", _custom_handler), "Commands register through the inclusive capacity boundary")
	check(not capped.register_command("overflow", "overflow", "Must be rejected.", _custom_handler), "Registration over the 128-command limit is rejected")
	var capped_help := capped.execute("help", {})
	check(capped_help.ok and capped_help.lines.size() == COMMANDS.MAX_OUTPUT_LINES, "Help remains valid at the registry capacity boundary")
	check(capped.completion_candidates("").size() == COMMANDS.MAX_OUTPUT_LINES and not capped.execute("overflow", {}).ok, "Rejected command is absent from completion and dispatch")
	var help_budget := COMMANDS.new()
	var used_help_length := 0
	for line: String in help_budget.execute("help", {}).lines:
		used_help_length += line.length()
	var remaining_help_length: int = COMMANDS.MAX_OUTPUT_LENGTH - used_help_length
	var budget_index := 0
	while remaining_help_length >= 19:
		var line_length := mini(remaining_help_length, COMMANDS.MAX_INPUT_LENGTH * 2 + 1)
		if remaining_help_length - line_length > 0 and remaining_help_length - line_length < 19:
			line_length -= 19 - (remaining_help_length - line_length)
		var usage_length := mini(line_length - 1, COMMANDS.MAX_INPUT_LENGTH)
		var description_length := line_length - usage_length - 1
		var name := "budget%d" % budget_index
		var usage := name + "u".repeat(usage_length - name.length())
		check(help_budget.register_command(name, usage, "d".repeat(description_length), _custom_handler), "Registration accepts metadata through the aggregate help length boundary")
		remaining_help_length -= line_length
		budget_index += 1
	check(remaining_help_length == 0, "Help fixture reaches exact aggregate length boundary")
	check(not help_budget.register_command("over_budget", "over_budget", "", _custom_handler), "Registration exceeding aggregate help length budget is rejected")
	var budget_help := help_budget.execute("help", {})
	var rendered_help_length := 0
	for line: String in budget_help.lines:
		rendered_help_length += line.length()
	check(budget_help.ok and rendered_help_length == COMMANDS.MAX_OUTPUT_LENGTH, "Help remains valid at exact aggregate length boundary")
	check(help_budget.completion_candidates("over_budget").is_empty() and not help_budget.execute("over_budget", {}).ok, "Metadata budget rejection leaves registry unchanged")
	var chassis := Chassis.new()
	chassis.current_fuel = 17.5
	var direct_status := commands.execute("status", {"rv": chassis})
	check(direct_status.ok and direct_status.lines.has("Fuel: 17.5 / 100.0"), "Typed Chassis fallback reads live fuel")
	check(chassis.current_fuel == 17.5 and chassis.handbrake, "Direct RV status does not mutate vehicle")
	chassis.free()
	rv.free()
	check(not commands.execute("status", context).ok, "Freed RV fails closed")
	if failures.is_empty():
		print("PASS: RV terminal commands parse, dispatch, complete and fail closed without world mutation")
	quit(0 if failures.is_empty() else 1)

func _status_lines() -> PackedStringArray:
	status_calls += 1
	return PackedStringArray(["Fuel: 42"])

func _custom_handler(args: PackedStringArray, context: Dictionary) -> Dictionary:
	handler_calls += 1
	captured_args = args
	captured_context = context
	return {"ok": true, "lines": [" ".join(args)], "action": ""}

func _custom_completer(_args: PackedStringArray, _context: Dictionary) -> PackedStringArray:
	return PackedStringArray(["echo hello", "echo hello", "status", "echo hello | status"])

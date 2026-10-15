extends "res://world/main_world.gd"
## Optional inspection opens the actual terminal; normal F6 play has no shortcuts.
func _ready() -> void:
	super._ready()
	if "--terminal-review" in OS.get_cmdline_user_args(): _inspect_terminal.call_deferred()

func _inspect_terminal() -> void:
	if not await wait_for_play(): return
	var terminal: Item = get_node("StartRun/Tutorial").designated_terminal()
	if terminal != null: terminal.interact_hold(get_node("Player"))

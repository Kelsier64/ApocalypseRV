extends "res://world/main_world.gd"
## Optional inspection opens the actual terminal; normal F6 play has no shortcuts.
func _ready() -> void:
	super._ready()
	if "--terminal-review" in OS.get_cmdline_user_args(): _inspect_terminal.call_deferred()
	if "--workshop-review" in OS.get_cmdline_user_args(): _inspect_workshop.call_deferred()

func _inspect_terminal() -> void:
	if not await wait_for_play(): return
	var terminal: Item = get_node("StartRun/Tutorial").designated_terminal()
	if terminal != null: terminal.interact_hold(get_node("Player"))

func _inspect_workshop() -> void:
	if not await wait_for_play(): return
	var building: Node3D = get_node("StartRun").shelter
	var camera := Camera3D.new()
	camera.fov = 76.0
	add_child(camera)
	camera.global_position = building.to_global(Vector3(14, 7.5, -23))
	camera.look_at(building.to_global(Vector3(0, 1.4, -10)))
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

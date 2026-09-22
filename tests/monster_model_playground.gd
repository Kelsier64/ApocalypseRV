extends "res://tests/monster_pursuit_playground.gd"
## Close view of the production monster approaching and attacking a real player.

func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("Monster Model Preview")
	var camera := get_viewport().get_camera_3d()
	camera.position = Vector3(4.5, 1.5, -2.5)
	camera.fov = 50.0
	camera.look_at(Vector3(2.5, 0.8, 0))
	status.position.y = 110
	status.add_theme_font_size_override("font_size", 16)

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F6:
			monster.take_damage(5)
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()

func _process(delta: float) -> void:
	super._process(delta)
	status.text += "\nGLB preview: TEST_InPlace only; walk/attack/climb clips pending.\nF6: damage flash | R: reset"

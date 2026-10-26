extends "res://tests/monster_pursuit_playground.gd"
## Inspect the new skin pose, or switch to the production chase/attack behavior.
@export var crawler_scene: PackedScene = preload("res://enemies/crawler.tscn")
var preview := true
var angle := 0.5
var paused := false
var comparison: Raker

func _ready() -> void:
	monster_scene = crawler_scene
	super._ready()
	DisplayServer.window_set_title(monster.monster_name + " - Raker Model Variant")
	monster.position = Vector3(0, -0.25, 0)
	monster.set_physics_process(false)
	monster.get_node("BodyMesh").preview_speed = 1.0
	player.position = Vector3(5, -0.25, 0)
	player.hide()
	for canvas in player.find_children("*", "CanvasLayer", true, false):
		canvas.hide()
		canvas.process_mode = Node.PROCESS_MODE_DISABLED
	device.hide()
	for light in find_children("*", "DirectionalLight3D", true, false): light.shadow_enabled = true
	get_viewport().scaling_3d_scale = 1.0
	get_viewport().get_camera_3d().fov = 42.0
	comparison = preload("res://enemies/raker.tscn").instantiate()
	add_child(comparison)
	comparison.position = Vector3(-2.7, -0.25, 0)
	comparison.set_physics_process(false)
	comparison.hide()
	status.position = Vector2(20, 20)
	status.add_theme_font_size_override("font_size", 18)
	_frame_camera()

func _frame_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	var center := monster.global_position + Vector3(0, 0.8, 0)
	var distance := 4.2
	if comparison.visible:
		center = (monster.global_position + comparison.global_position) * 0.5 + Vector3.UP * 1.1
		distance = 7.0
	camera.position = center + Vector3(sin(angle) * distance, 0.65, -cos(angle) * distance)
	camera.look_at(center)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_LEFT: angle -= PI / 4.0
		KEY_RIGHT: angle += PI / 4.0
		KEY_SPACE:
			if preview:
				paused = not paused
				monster.get_node("BodyMesh").preview_speed = 0.0 if paused else 1.0
		KEY_TAB: comparison.visible = not comparison.visible
		KEY_F4:
			preview = not preview
			paused = false
			monster.set_physics_process(not preview)
			monster.get_node("BodyMesh").preview_speed = 1.0 if preview else -1.0
		KEY_R: get_tree().reload_current_scene()
	_frame_camera()

func _process(_delta: float) -> void:
	_frame_camera()
	status.text = "%s | %s\nLeft / Right: orbit | Space: idle / crawl | Tab: original Raker\nF4: preview / live pursuit | R: reset | Player HP: %.0f" % [monster.monster_name.to_upper(), "POSE PREVIEW" if preview else "LIVE AI", player.current_player_health]

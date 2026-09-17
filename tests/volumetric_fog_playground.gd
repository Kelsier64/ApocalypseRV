extends "res://tests/day_night_playground.gd"
var use_volume := true
var fog_density := 0.14
func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Volumetric Fog Validation"
	clock.set_time(1, 8.0)
	time_controls.text += "\nB local volume / old distance fog"
	print("FOG renderer=", RenderingServer.get_current_rendering_method())
	main.get_node("NewRv/Chassis").headlights_requested = true
	if "--entry" in OS.get_cmdline_user_args():
		player.global_position = site.route[-1] + Vector3.UP * 0.1
		player.global_basis = site.building.basis
		player.camera.rotation = Vector3.ZERO
		player.camera.current = true
		player.in_ui_mode = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		use_volume = not use_volume
		var env := clock.environment
		env.volumetric_fog_enabled = use_volume
		env.fog_depth_begin = 160.0 if use_volume else 18.0
		env.fog_depth_end = 420.0 if use_volume else 380.0
		env.fog_depth_curve = 1.8 if use_volume else 0.65
		print("FOG mode=", "VOLUME" if use_volume else "DISTANCE")
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_7, KEY_8]:
		fog_density = clampf(fog_density * (1.5 if event.keycode == KEY_7 else 1.0 / 1.5), 0.01, 0.3)
		for node in main.get_node("WorldGenerator").find_children("*", "FogVolume", true, false):
			if node.material is ShaderMaterial: node.material.set_shader_parameter("density", fog_density)
		print("FOG local density=", fog_density)
		return
	super._unhandled_input(event)

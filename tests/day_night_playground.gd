extends "res://tests/outdoor_horror_playground.gd"
## Production clock and route, with test-only time controls.
const HOURS := [6.25, 12.0, 17.75, 22.0]
var time_index := 0
var clock: WorldClock
var time_controls: Label

func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Day Night Validation"
	clock = main.get_node("WorldClock")
	clock.running = false
	clock.set_time(1, HOURS[time_index])
	stage = 2
	_view()
	time_controls = Label.new()
	time_controls.text = "F1 dawn / noon / dusk / night | F12 fast cycle | Home hold time\nF2 views | K reload night curve | F6 RV/cabin | Esc settings | F11 clean view"
	time_controls.position = Vector2(24, 245)
	time_controls.add_theme_font_size_override("font_size", 18)
	label.get_parent().add_child(time_controls)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			clock.running = false
			time_index = (time_index + 1) % HOURS.size()
			clock.set_time(clock.day_number(), HOURS[time_index])
			print("DAY NIGHT preset hour=", clock.hour_of_day(), " sun=", clock.sun_direction(), " energy=", clock.sun.light_energy)
			return
		if event.keycode == KEY_F12:
			clock.day_length_minutes = 1.0
			clock.running = true
			return
		if event.keycode == KEY_5:
			camera.current = true
			camera.global_position = site.road.origin + Vector3.UP * 30
			camera.look_at(camera.global_position + clock.sun_direction() * 100)
			return
		if event.keycode == KEY_HOME:
			clock.running = not clock.running
			return
		# F8 stops projects launched by the Godot editor before input reaches us.
		if event.keycode == KEY_K:
			var effect := main.get_node("DarkAdaptation") as NightVisionEffect
			var curve_path := effect.profile.curve.resource_path if effect.profile.curve != null else ""
			if curve_path.is_empty(): curve_path = "res://world/night_vision_curve.tres"
			var curve := ResourceLoader.load(curve_path, "Curve", ResourceLoader.CACHE_MODE_REPLACE) as Curve
			if curve != null:
				effect.profile.curve = curve
				print("DAY NIGHT reloaded curve: ", curve_path)
			return
	super._unhandled_input(event)

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(time_controls): time_controls.visible = not clean_view

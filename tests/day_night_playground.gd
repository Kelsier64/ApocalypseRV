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
	time_controls.text = "F1 dawn / noon / dusk / night | F12 fast cycle | Home hold time\nF2 views | 5 inspect sun | F6 RV/cabin | F8 resolution | F11 clean view"
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
	super._unhandled_input(event)

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(time_controls): time_controls.visible = not clean_view

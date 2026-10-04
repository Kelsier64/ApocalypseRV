extends Node3D
var rv: Chassis
var actor: CharacterBody3D
var seat: Node3D
var observer: Camera3D
var view := 0
var cutaway := true
var shell_visibility: Dictionary = {}
func _ready():
	DisplayServer.window_set_title("Player Driving Playground")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.16,.19,.23)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .8
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40,-25,0)
	add_child(sun)
	var shell = preload("res://rv/new_rv.tscn").instantiate()
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	seat = rv.get_node("DriverSeat")
	for child in rv.get_children():
		if child is Node3D and child != seat:
			shell_visibility[child] = child.visible
			child.hide()
	actor = preload("res://player/player.tscn").instantiate()
	actor.position = Vector3(10,0,0)
	add_child(actor)
	observer = Camera3D.new()
	observer.fov = 55
	add_child(observer)
	await get_tree().physics_frame
	await get_tree().physics_frame
	seat.interact_hold(actor)
	_view()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var label := Label.new()
	label.position = Vector2(20,150)
	label.text = "F1 Center | F2 Left | F3 Right | F4 View | F5 Pedals | F6 Shell\nProduction cockpit / frozen RV"
	canvas.add_child(label)
func _input(event):
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F1: rv.steering = 0
		KEY_F2: rv.steering = .35
		KEY_F3: rv.steering = -.35
		KEY_F4:
			view = (view + 1) % 3
			_view()
		KEY_F5:
			rv.throttle_input = 1.0 - rv.throttle_input
			rv.brake_input = rv.throttle_input
		KEY_F6:
			cutaway = not cutaway
			for child: Node3D in shell_visibility: child.visible = shell_visibility[child] and not cutaway
func _view():
	if view == 1:
		seat.seat_camera.make_current()
		return
	observer.global_position = seat.to_global(Vector3(1.8,1.65,-1.9) if view == 0 else Vector3(1.9,1.15,.05))
	observer.look_at(seat.to_global(Vector3(0,.85,-.25)))
	observer.make_current()

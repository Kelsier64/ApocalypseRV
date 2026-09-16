extends "res://tests/rv_climb_playground.gd"
## Production actors/vehicle; boosted panel HP keeps both modes visible for inspection.
var hanger: Monster

func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("Monster Boarding Validation")
	replay = false
	driving = false
	Input.action_release("move_forward")
	player.enter_seat_mode(rv.get_node("DriverSeat"))
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	rv.get_node("Ceiling").current_health = 6000
	rv.get_node("RightMiddle").current_health = 6000
	hanger = preload("res://enemies/zombie.tscn").instantiate()
	hanger.position = Vector3(2.65, 0.6, 0)
	hanger.rotation.y = PI / 2.0
	add_child(hanger)
	hanger.target_player = player
	hanger.ai_state = Monster.State.CHASE
	# Demo holds stay long enough for screenshots; normal actors retain production tuning.
	hanger.grip_capacity = 1000

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F6:
			if rv.has_node("RightMiddle"): rv.get_node("RightMiddle").current_health = 15
			return
		if event.keycode == KEY_F5:
			if rv.has_node("Ceiling"): rv.get_node("Ceiling").current_health = 15
		if event.keycode == KEY_F7:
			hanger.boarding.grip = 0.1
			return
	super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(hanger) or not is_instance_valid(monster): return
	status.text += "\nRoof actor: %s | Door actor: %s\nF6: door HP -> 15 | F5: roof HP -> 15 | F7: exhaust grip\nDemo panel HP boosted; F2 uses scripted movement, not wheel handling." % [monster.boarding.describe(monster), hanger.boarding.describe(hanger)]

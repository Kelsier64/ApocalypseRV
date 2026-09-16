extends "res://tests/rv_climb_playground.gd"
## Actual breach/pursuit logic; roof rendering hidden to expose cabin movement.
var scenario := "DOOR BREACH -> CABIN PURSUIT"

func _ready() -> void:
	super._ready()
	rv.position.y = 0.95
	player.max_player_health = 10000
	player.current_player_health = 10000
	player.enter_seat_mode(rv.get_node("DriverSeat"))
	rv.get_node("RightMiddle").current_health = 15
	rv.get_node("Ceiling").visible = false
	monster.position = rv.to_global(Vector3(2.65, -0.35, 0))
	monster.rotation.y = PI / 2
	monster.boarding.rng.seed = 7
	observer.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_R: get_tree().reload_current_scene()
	if event.keycode == KEY_F3 and rv.has_node("Ceiling"):
		monster.free()
		monster = preload("res://enemies/zombie.tscn").instantiate()
		add_child(monster)
		monster.position = rv.to_global(Vector3(0, 2.55, 2.8))
		rv.get_node("Ceiling").current_health = 15
		rv.get_node("Ceiling").visible = true
		scenario = "ROOF BREACH -> CABIN PURSUIT"
	if event.keycode == KEY_F4:
		player.seated_in = null
		player.in_ui_mode = true
		player.position = rv.to_global(Vector3(6, -1.2, 1.5))
		scenario = "PLAYER OUTSIDE -> EXIT PURSUIT"

func _physics_process(_delta: float) -> void:
	observer.position = rv.to_global(Vector3(9, 14, 9))
	observer.look_at(rv.to_global(Vector3(0, 0.5, 0)))
	if not is_instance_valid(monster): return
	status.text = "%s\nBlue: player | Red: monster | Player HP: %.0f\nDoor: %s | Roof: %s | %s\nF3: roof breach | F4: move player outside | R: reset\nRoof mesh hidden initially for inspection; collision/AI unchanged.\nDemo: panel HP 15, player HP 10000; production damage and movement." % [scenario, player.current_player_health, "intact" if rv.has_node("RightMiddle") else "DESTROYED", "intact" if rv.has_node("Ceiling") else "DESTROYED", monster.boarding.describe(monster)]

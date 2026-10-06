extends "res://tests/rv_climb_playground.gd"
## Split-roof review uses the production ladder, tablet and structure controller.

func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Split Roof Acceptance"
	rv.add_item("Metal Parts", 100)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			var terminal: Node = rv.get_node("TabletScreen")
			terminal.interact_hold(player)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F11:
			rv.get_node("StructureSlots").panel("roof_1").take_damage(999.0)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	status.text += "\nF1: tablet structure page | F11: destroy middle roof only"

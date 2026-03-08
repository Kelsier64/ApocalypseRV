extends CanvasLayer

signal close_requested

func _ready():
	var btn = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Header/CloseButton")
	if btn:
		btn.pressed.connect(_on_close_pressed)
		
	# Focus the button so UI navigation works if they don't want to use mouse
	if btn and btn.is_visible_in_tree():
		btn.grab_focus()

func _on_close_pressed():
	close_requested.emit()

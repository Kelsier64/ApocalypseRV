extends Item
var storage_ui: CanvasLayer

func interact(player: Node3D) -> String:
	if not can_operate(): return "Install or repair the item storage box first"
	if not player.enter_ui_mode(): return "Finish the current interaction first"
	if not is_instance_valid(storage_ui):
		storage_ui = CanvasLayer.new()
		storage_ui.set_script(load("res://equipment/item_storage_ui.gd"))
		add_child(storage_ui)
	storage_ui.open(player, get_connected_rv())
	return ""

func _on_service_stopped() -> void:
	if is_instance_valid(storage_ui): storage_ui.close()

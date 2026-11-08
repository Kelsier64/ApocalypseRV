extends Item
var storage_ui: CanvasLayer

func get_interaction_prompt(_player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null: return "Item storage box | Install on the RV first"
	if not can_operate(): return "Item storage box | Repair the box or finish moving it first"
	return "Item storage box | Items %d / %d\nE Open shared storage. No power needed.\nStored items stay in the RV. Check the tablet for materials." % [rv.stored_items.size(), rv.item_capacity]

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

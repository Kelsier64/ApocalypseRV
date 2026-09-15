extends Equipment
var storage_ui: CanvasLayer

func get_interaction_prompt(_player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null: return "道具箱｜未接入 RV，請先安裝到車上"
	if not can_operate(): return "道具箱｜無法開啟，請先維修或結束搬移"
	return "道具箱｜本車道具 %d / %d\nE：開啟共用倉庫，存入／取出道具（不耗電）\n拆除箱子不會帶走物品；材料由面板查看數量" % [rv.stored_items.size(), rv.item_capacity]

func interact(player: Node3D) -> String:
	if not can_operate(): return "道具箱尚未接入或無法使用，請先安裝／維修"
	if not player.enter_ui_mode(): return "請先結束目前操作"
	if not is_instance_valid(storage_ui):
		storage_ui = CanvasLayer.new()
		storage_ui.set_script(load("res://equipment/item_storage_ui.gd"))
		add_child(storage_ui)
	storage_ui.open(player, get_connected_rv())
	return ""

func _on_service_stopped() -> void:
	if is_instance_valid(storage_ui): storage_ui.close()

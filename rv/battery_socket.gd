extends Equipment
class_name BatterySocket

@export var preinstalled_battery: bool = false
var installed_battery: BatteryState

func _ready() -> void:
	super._ready()
	if preinstalled_battery: installed_battery = BatteryState.new()
var _visual_state := ""

func get_interaction_prompt(player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null: return "電池插槽｜未連接 RV，請先安裝到車上"
	if not can_operate(): return "電池插槽｜無法供電，請先維修或結束搬移"
	var text := "電池插槽｜%s" % ("電量 %.1f / %.0f" % [installed_battery.charge, installed_battery.capacity] if installed_battery else "空槽")
	text += "\n接入電池供電；搬移／脫落／損壞時，電池會掉落"
	if has_other_battery(): return text + "\n本車已有另一個插槽供電，請先取出那顆電池"
	if rv.linear_velocity.length() > 0.5: return text + "\n車輛仍在移動，請停穩後操作"
	if player.get_active_item_name() == ItemNames.BATTERY:
		text += "\n短按 E：交換電池（舊電池回到原背包格）" if rv.energy.battery else "\n短按 E：裝入手持電池"
	else:
		text += "\n請先用 1–6／滾輪選取背包電池，再短按 E 裝入"
	if rv.energy.battery:
		text += "\n長按 E 1 秒：取出電池"
		if player.inventory.items.size() >= PlayerInventory.MAX_SLOTS: text += "（需空背包格）"
	return text

func interact(player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null or not can_operate(): return "插槽未接入或無法使用，請先安裝／維修"
	if has_other_battery(): return "本車已有另一個插槽供電，請先取出那顆電池"
	if rv.linear_velocity.length() > 0.5: return "請先把車停穩，再更換電池"
	if player.get_active_item_name() != ItemNames.BATTERY: return "尚未選取電池：請用 1–6 或滾輪選取背包中的電池"
	if not rv.exchange_battery(player, self): return "無法裝入：手持物品沒有有效電池狀態"
	_update_visual()
	return "電池已接入，電量 %.1f / %.0f" % [rv.current_power, rv.max_power]

func interact_hold(player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null or not can_operate(): return "插槽未接入或無法使用，請先安裝／維修"
	if has_other_battery(): return "本車已有另一個插槽供電，請先取出那顆電池"
	if rv.linear_velocity.length() > 0.5: return "請先把車停穩，再取出電池"
	if rv.energy.battery == null: return "插槽已經是空的"
	if not rv.remove_battery_to_player(player, self): return "背包已滿：先空出一格，或手持另一顆電池短按 E 交換"
	_update_visual()
	return "電池已取出，車上用電暫停；電池已存入背包"

func _process(_delta: float) -> void:
	_update_visual()

func _update_visual() -> void:
	var state := "%.0f / %.0f" % [installed_battery.charge, installed_battery.capacity] if installed_battery else "EMPTY"
	if state == _visual_state: return
	_visual_state = state
	var cell := get_node_or_null("Cell") as MeshInstance3D
	if cell: cell.visible = installed_battery != null
	var label := get_node_or_null("Charge") as Label3D
	if label: label.text = state

func _on_service_stopped() -> void:
	if is_being_placed or support_lost or is_destroyed or current_health <= 0.0:
		drop_battery()

func confirm_placement(pose: Transform3D, parent: Node3D, support: Node3D = null):
	if installed_battery and get_connected_rv() != RVConnection.resolve(parent):
		drop_battery()
	super.confirm_placement(pose, parent, support)

func detach_from_support() -> void:
	drop_battery()
	super.detach_from_support()

func drop_battery() -> void:
	if installed_battery == null or not is_inside_tree(): return
	var container := WorldEntities.get_container(self)
	if container == null or container.is_queued_for_deletion(): return
	var rv := get_connected_rv()
	if rv and (not rv.is_inside_tree() or rv.is_queued_for_deletion()): return
	var battery := installed_battery
	installed_battery = null
	var prop: Prop = load("res://props/battery.tscn").instantiate()
	prop.restore_item_state({"id": battery.id, "battery": battery.snapshot()})
	# Put the loose battery outside the chassis collision, with point velocity.
	var drop_position := global_position + Vector3.UP * 0.6
	if rv:
		var local := rv.to_local(global_position)
		local.x = maxf(2.8, absf(local.x) + 0.6) * (1.0 if local.x >= 0.0 else -1.0)
		drop_position = rv.to_global(local) + Vector3.UP * 0.6
	prop.position = container.to_local(drop_position)
	container.add_child(prop)
	prop.linear_velocity = ClimbMath.point_velocity(rv, drop_position)
	_update_visual()

func has_other_battery() -> bool:
	var rv := get_connected_rv()
	if rv == null: return false
	for device in rv.get_equipment():
		if device != self and device is BatterySocket and device.installed_battery:
			return true
	return false

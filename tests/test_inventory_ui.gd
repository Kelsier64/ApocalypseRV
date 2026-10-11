extends SceneTree

const INVENTORY_UI := preload("res://player/inventory_ui.gd")
var failures: Array[String] = []

class InventoryHost extends Node:
	var seated_in: Node = null

func _init() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var fallback := InventoryItemIcons.texture_for("res://unknown/item.tscn")
	_expect(fallback != null, "Unknown scenes have a visible fallback icon")
	var paths: Array[String] = ["res://rv/battery_socket.tscn"]
	for id in SaveSceneCatalog.PROPS:
		paths.append("res://props/" + id + ".tscn")
	for id in SaveSceneCatalog.DEVICES:
		paths.append("res://equipment/" + id + ".tscn")
	for path in paths:
		_expect(InventoryItemIcons.ICONS.has(path), "Trusted item has a registered icon: " + path)
		var texture := InventoryItemIcons.texture_for(path)
		_expect(texture != null and texture != fallback, "Trusted item does not use the fallback: " + path)
		_expect(texture != null and texture.resource_path.ends_with(".png"), "Trusted item uses a model snapshot texture: " + path)
	for pair in [["gas_can", "gas_can_empty"], ["battery", "battery_large"], ["engine_standard", "engine_upgraded"]]:
		_expect(InventoryItemIcons.texture_for("res://props/" + pair[0] + ".tscn") != InventoryItemIcons.texture_for("res://props/" + pair[1] + ".tscn"), "Item variants retain per-scene snapshot resources: " + str(pair))
	for pistol_icon in [[PistolRules.PISTOL_SCENE, "pistol.png"], [PistolRules.AMMO_SCENE, "pistol_ammo.png"]]:
		var texture := InventoryItemIcons.texture_for(pistol_icon[0])
		_expect(texture != null and texture.resource_path.ends_with(pistol_icon[1]), "Pistol items use their matching model snapshot: " + pistol_icon[1])
	var player_corpse_state := {"corpse": {"kind": "player"}}
	var player_corpse_snapshot := player_corpse_state.duplicate(true)
	var player_corpse_texture := InventoryItemIcons.texture_for("res://props/corpse.tscn", player_corpse_state)
	var raker_corpse_texture := InventoryItemIcons.texture_for("res://props/corpse.tscn", {"corpse": {"kind": "raker"}})
	_expect(player_corpse_texture != null and player_corpse_texture != raker_corpse_texture, "Player and raker corpses use distinct model snapshots")
	_expect(player_corpse_texture != null and player_corpse_texture.resource_path.ends_with("corpse_player.png"), "Player corpse uses its matching model snapshot")
	_expect(raker_corpse_texture == InventoryItemIcons.texture_for("res://props/corpse.tscn"), "Corpses without a kind use the default raker snapshot")
	_expect(player_corpse_state == player_corpse_snapshot, "Corpse icon lookup does not mutate saved state")

	var host := InventoryHost.new()
	root.add_child(host)
	var ui = INVENTORY_UI.new()
	host.add_child(ui)
	await process_frame
	_expect(ui.slots_container.get_child_count() == PlayerInventory.MAX_SLOTS, "Hotbar presents every selectable inventory slot")
	_expect(ui.slots_container.get_parent() == ui.get_child(0), "Six slots sit directly on the root UI control")
	for child in ui.get_child(0).get_children():
		_expect(not (child is Panel), "Root UI control has no common panel enclosing the slots")
	for index in range(ui.slots_container.get_child_count()):
		var panel := ui.slots_container.get_child(index) as Panel
		_expect(is_equal_approx(panel.size.x, panel.size.y), "Hotbar slots are square")
	var before := [
		{"name": "Renamed cargo", "is_large": true, "scene_path": "res://props/oil_barrel.tscn", "state": {"id": "ui-test", "condition": 37.0}},
		{"name": "Stored flashlight", "is_large": false, "scene_path": "res://props/flashlight.tscn", "state": {"flashlight": {"charge": 50.0, "on": false}}},
	]
	var items := before.duplicate(true)
	ui.update_slots(items, 0)
	var slot := ui.slots_container.get_child(0) as Panel
	await process_frame
	var item_name := slot.get_node("ItemName") as Label
	var icon := slot.get_node("ItemIcon") as TextureRect
	var large := slot.get_node("LargeItem") as Label
	var empty := slot.get_node("EmptyMark") as Control
	var selection := slot.get_node("Selection") as ColorRect
	_expect(icon.visible and icon.texture == InventoryItemIcons.texture_for("res://props/oil_barrel.tscn"), "Icon follows scene identity despite a custom item name")
	_expect(ui.selected_name == item_name and item_name.visible and item_name.text.contains("Renamed cargo"), "Selected item name is shown above its own slot")
	_expect(item_name.get_parent() == slot, "Item name belongs to its slot")
	var panel_rect := slot.get_global_rect()
	var name_rect := item_name.get_global_rect()
	_expect(absf(name_rect.get_center().x - panel_rect.get_center().x) < 2.0 and name_rect.end.y <= panel_rect.position.y + 1.0, "Item name is centered above its slot")
	for index in range(1, ui.slots_container.get_child_count()):
		_expect(not (ui.slots_container.get_child(index).get_node("ItemName") as Label).visible, "Nonactive slot names stay hidden")
	_expect(large.visible and large.text == "2H", "Large item shows its carrying restriction in the slot")
	_expect(not empty.visible and selection.visible, "Occupied active slot is selected without an empty marker")
	var style := slot.get_theme_stylebox("panel")
	ui.update_slots(items, 0)
	_expect(slot.get_theme_stylebox("panel") == style, "Repeated unchanged refresh preserves the slot style resource")
	_expect(items == before, "Presentation does not add icon data or alter saved item state")

	ui.update_slots([], 0)
	_expect(icon.texture == null and not icon.visible, "Removing an item clears its stale icon")
	_expect(not large.visible, "Removing large cargo clears its slot indicator")
	_expect(not ui.selected_name.visible and not item_name.visible, "Empty selection hides the previous item name")
	_expect(not ui.selected_name.text.contains("空手"), "Empty hands have no name caption")
	_expect(empty.visible and selection.visible, "Empty slots remain visibly selectable")
	ui.update_slots([], PlayerInventory.MAX_SLOTS - 1)
	_expect(not selection.visible and (ui.slots_container.get_child(PlayerInventory.MAX_SLOTS - 1).get_node("Selection") as ColorRect).visible, "Selection can move to an empty final slot")
	var corpse_items := [{"name": "Corpse", "is_large": true, "scene_path": "res://props/corpse.tscn", "state": player_corpse_state.duplicate(true)}]
	var corpse_before := corpse_items.duplicate(true)
	ui.update_slots(corpse_items, 0)
	_expect(icon.visible and icon.texture == player_corpse_texture, "Hotbar selects the player corpse snapshot from saved state")
	_expect(corpse_items == corpse_before, "Displaying a corpse snapshot does not mutate its inventory state")

	var flashlight := [{"name": "Flashlight", "is_large": false, "scene_path": "res://props/flashlight.tscn", "state": {"flashlight": {"charge": 36.2, "on": false}}}]
	ui.update_slots(flashlight, 0, true)
	_expect(ui.flashlight_hint.visible and ui.flashlight_hint.text.contains("37") and ui.flashlight_hint.text.contains("關閉"), "Selected flashlight displays rounded charge and off state")
	flashlight[0].state.flashlight = {"charge": 12.0, "on": true}
	ui.update_slots(flashlight, 0, true)
	_expect(ui.flashlight_hint.visible and ui.flashlight_hint.text.contains("12") and ui.flashlight_hint.text.contains("開啟"), "Flashlight presentation follows charge and toggle changes")
	ui.update_slots(flashlight, 0, false)
	_expect(not ui.flashlight_hint.visible, "Player modes can suppress the flashlight hint")
	ui.update_slots(flashlight, 1, true)
	_expect(not ui.flashlight_hint.visible, "Selecting empty hands clears the flashlight hint")
	_check_pistol_presentation(ui)
	_check_input_passthrough(ui)

	var seat := Node.new()
	host.add_child(seat)
	host.seated_in = seat
	await process_frame
	await process_frame
	_expect(not ui.visible, "Seating hides inventory from the driving dashboard")
	host.seated_in = null
	await process_frame
	await process_frame
	_expect(ui.visible, "Leaving a seat restores the hotbar")
	host.free()
	if failures.is_empty():
		print("PASS: inventory icons, empty selection, large cargo, flashlight and pistol hints, ammo counts, input passthrough and seated visibility")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_pistol_presentation(ui) -> void:
	var items := [
		{"name": "Pistol", "is_large": false, "scene_path": PistolRules.PISTOL_SCENE, "state": {"pistol": {"loaded_rounds": 7}}},
		{"name": "Ammo", "is_large": false, "scene_path": PistolRules.AMMO_SCENE, "state": {"ammo": {"rounds": 19}}},
		{"name": "Second pistol", "is_large": false, "scene_path": PistolRules.PISTOL_SCENE, "state": {"pistol": {"loaded_rounds": 2}}},
	]
	var weapon_data := {"reload_remaining": 0.0, "reserve": 19, "can_use": true}
	var items_before := items.duplicate(true)
	var weapon_before := weapon_data.duplicate(true)
	ui.update_slots(items, 0, true, weapon_data)
	var pistol_slot := ui.slots_container.get_child(0) as Panel
	var ammo_slot := ui.slots_container.get_child(1) as Panel
	var second_slot := ui.slots_container.get_child(2) as Panel
	var pistol_count := pistol_slot.get_node("AmmoCount") as Label
	var ammo_count := ammo_slot.get_node("AmmoCount") as Label
	_expect(pistol_count.visible and pistol_count.text == "7/%d" % PistolRules.MAGAZINE_CAPACITY, "Pistol slot shows loaded rounds and magazine capacity")
	_expect(ammo_count.visible and ammo_count.text == "19", "Unselected ammo box shows its remaining rounds")
	_expect(ui.pistol_hint.visible and ui.pistol_hint.text.contains("7/%d" % PistolRules.MAGAZINE_CAPACITY) and ui.pistol_hint.text.contains("備彈 19"), "Selected pistol hint displays loaded ammunition and supplied reserve")
	_expect(ui.pistol_hint.get_parent() == pistol_slot and not ui.flashlight_hint.visible, "Pistol hint belongs to the selected slot without a stale flashlight hint")
	var ready_text: String = ui.pistol_hint.text
	var pistol_style := pistol_slot.get_theme_stylebox("panel")
	var ammo_style := ammo_slot.get_theme_stylebox("panel")
	_expect(items == items_before and weapon_data == weapon_before, "Pistol presentation leaves inventory and weapon data unchanged")

	items[0].state.pistol.loaded_rounds = 6
	items[1].state.ammo.rounds = 18
	weapon_data.reserve = 18
	weapon_data.reload_remaining = PistolRules.RELOAD_SECONDS
	items_before = items.duplicate(true)
	weapon_before = weapon_data.duplicate(true)
	ui.update_slots(items, 0, true, weapon_data)
	_expect(pistol_count.text == "6/%d" % PistolRules.MAGAZINE_CAPACITY and ammo_count.text == "18", "Ammo counts refresh even when occupied slot appearance is unchanged")
	_expect(ui.pistol_hint.text.contains("6/%d" % PistolRules.MAGAZINE_CAPACITY) and ui.pistol_hint.text.contains("備彈 18") and ui.pistol_hint.text.contains("換彈 %.1fs" % PistolRules.RELOAD_SECONDS), "Pistol hint refreshes ammunition, reserve and reload countdown")
	_expect(pistol_slot.get_theme_stylebox("panel") == pistol_style and ammo_slot.get_theme_stylebox("panel") == ammo_style, "Ammunition refresh preserves both slot style resources")
	_expect(items == items_before and weapon_data == weapon_before, "Reload presentation does not alter canonical state or weapon status")
	weapon_data.reload_remaining = 0.0
	weapon_data.can_use = false
	ui.update_slots(items, 0, true, weapon_data)
	_expect(ui.pistol_hint.visible and ui.pistol_hint.text.contains("無法使用") and not ui.pistol_hint.text.contains("換彈"), "Blocked pistol shows its usage restriction and clears a completed reload hint")
	weapon_data.can_use = true
	ui.update_slots(items, 0, true, weapon_data)
	_expect(ui.pistol_hint.text != ready_text and not ui.pistol_hint.text.contains("無法使用"), "Restoring pistol use clears the restriction while retaining updated ammunition")
	ui.update_slots(items, 0, false, weapon_data)
	_expect(not ui.pistol_hint.visible and ui.pistol_hint.text.is_empty() and pistol_count.visible, "Player modes suppress and clear pistol hints while retaining slot ammunition")
	ui.update_slots(items, 2, true, weapon_data)
	_expect(ui.pistol_hint.visible and ui.pistol_hint.get_parent() == second_slot and ui.pistol_hint.text.contains("2/%d" % PistolRules.MAGAZINE_CAPACITY), "Switching pistols moves the hint and displays the selected magazine")
	_expect(not (pistol_slot.get_node("ItemName") as Label).visible and (second_slot.get_node("ItemName") as Label).visible, "Only the newly selected pistol has a name caption")
	ui.update_slots(items, 1, true, weapon_data)
	_expect(not ui.pistol_hint.visible and ui.pistol_hint.text.is_empty(), "Selecting an ammunition box clears the pistol hint")
	ui.update_slots(items, PlayerInventory.MAX_SLOTS - 1, true, weapon_data)
	_expect(not ui.pistol_hint.visible and ui.pistol_hint.text.is_empty(), "Selecting empty hands clears the pistol hint")

	# Replacing a small occupied pistol with another small item reuses its style.
	ui.update_slots(items, 0, true, weapon_data)
	pistol_style = pistol_slot.get_theme_stylebox("panel")
	items[0] = {"name": "Flashlight", "is_large": false, "scene_path": "res://props/flashlight.tscn", "state": {"flashlight": {"charge": 50.0, "on": false}}}
	ui.update_slots(items, 0, true, weapon_data)
	_expect(not pistol_count.visible and pistol_count.text.is_empty(), "Replacing a pistol with a nonammo item clears stale slot ammunition")
	_expect(pistol_slot.get_theme_stylebox("panel") == pistol_style, "Item identity refresh preserves an unchanged occupied slot style")
	_expect(not ui.pistol_hint.visible and ui.pistol_hint.text.is_empty() and ui.flashlight_hint.visible, "Switching to flashlight clears pistol hint and restores flashlight hint")
	ui.update_slots([], 0, true, weapon_data)
	for panel in ui.slots_container.get_children():
		var count := panel.get_node("AmmoCount") as Label
		_expect(not count.visible and count.text.is_empty(), "Empty slots clear ammunition labels: " + str(panel.name))
	_expect(not ui.pistol_hint.visible and ui.pistol_hint.text.is_empty(), "Removing inventory clears the selected pistol hint")

func _check_input_passthrough(node: Node) -> void:
	if node is Control:
		_expect(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Hotbar decoration passes mouse input through: " + str(node.name))
	for child in node.get_children():
		_check_input_passthrough(child)

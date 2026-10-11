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
		print("PASS: inventory icons, empty selection, large cargo, flashlight hints, input passthrough and seated visibility")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_input_passthrough(node: Node) -> void:
	if node is Control:
		_expect(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Hotbar decoration passes mouse input through: " + str(node.name))
	for child in node.get_children():
		_check_input_passthrough(child)

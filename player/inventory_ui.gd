extends CanvasLayer
## Presentation only: inventory records and input remain owned by Player.

const SLOT_SIZE := Vector2(84, 84)
const SLOT_GAP := 8
const BAR_WIDTH := PlayerInventory.MAX_SLOTS * 84 + (PlayerInventory.MAX_SLOTS - 1) * SLOT_GAP
const MUTED := Color("8c968e")

var slots_container: HBoxContainer
var selected_name: Label
var flashlight_hint: Label
var pistol_hint: Label

func _ready() -> void:
	var control := Control.new()
	control.theme = IndustrialTheme.make(16)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)

	flashlight_hint = _label("FlashlightHint", "", 13, IndustrialTheme.AMBER)
	control.add_child(flashlight_hint)
	_above_slot(flashlight_hint, -54, -32)
	pistol_hint = _label("PistolHint", "", 13, IndustrialTheme.AMBER)
	control.add_child(pistol_hint)
	_above_slot(pistol_hint, -54, -32)
	pistol_hint.offset_left = -160
	pistol_hint.offset_right = 160

	slots_container = HBoxContainer.new()
	slots_container.name = "Slots"
	slots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(slots_container)
	slots_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	slots_container.offset_left = -BAR_WIDTH / 2.0
	slots_container.offset_right = BAR_WIDTH / 2.0
	slots_container.offset_top = -108
	slots_container.offset_bottom = -24
	slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_container.add_theme_constant_override("separation", SLOT_GAP)
	for index in range(PlayerInventory.MAX_SLOTS):
		_make_slot(index)
	update_slots([])
	UILayout.attach(self, control)

func _make_slot(index: int) -> void:
	var panel := Panel.new()
	panel.name = "Slot%d" % (index + 1)
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots_container.add_child(panel)
	var item_name := _label("ItemName", "", 16, IndustrialTheme.INK)
	panel.add_child(item_name)
	_above_slot(item_name, -30, -6)
	item_name.hide()

	var key := _label("Key", str(index + 1), 13, MUTED)
	panel.add_child(key)
	key.position = Vector2(8, 3)

	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel.add_child(icon)
	icon.position = Vector2(12, 18)
	icon.size = Vector2(60, 60)

	var large := _label("LargeItem", "2H", 11, IndustrialTheme.AMBER)
	panel.add_child(large)
	large.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	large.offset_left = -25
	large.offset_right = -5
	large.offset_top = 4
	large.offset_bottom = 20
	large.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ammo_count := _label("AmmoCount", "", 11, IndustrialTheme.AMBER)
	panel.add_child(ammo_count)
	ammo_count.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ammo_count.offset_left = -52
	ammo_count.offset_right = -6
	ammo_count.offset_top = 4
	ammo_count.offset_bottom = 20
	ammo_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var empty_mark := Control.new()
	empty_mark.name = "EmptyMark"
	empty_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(empty_mark)
	empty_mark.position = Vector2(36, 42)
	for mark_size in [Vector2(12, 2), Vector2(2, 12)]:
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = Color("46534e")
		line.position = (Vector2(12, 12) - mark_size) / 2.0
		line.size = mark_size
		empty_mark.add_child(line)

	var selection := ColorRect.new()
	selection.name = "Selection"
	selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection.color = IndustrialTheme.AMBER
	panel.add_child(selection)
	selection.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	selection.offset_left = 14
	selection.offset_right = -14
	selection.offset_top = -3
	selection.offset_bottom = -1

func update_slots(inventory: Array, active_slot: int = 0, show_flashlight_hint: bool = true, weapon_data: Dictionary = {}) -> void:
	if not slots_container:
		return
	var selected: Dictionary = inventory[active_slot] if active_slot >= 0 and active_slot < inventory.size() else {}
	var flashlight: Dictionary = selected.get("state", {}).get("flashlight", {}) if selected.get("scene_path", "") == "res://props/flashlight.tscn" else {}
	flashlight_hint.visible = show_flashlight_hint and not flashlight.is_empty()
	flashlight_hint.text = "電量 %d%%  ·  L %s" % [ceili(float(flashlight.get("charge", 0.0))), "開啟" if flashlight.get("on", false) else "關閉"] if flashlight_hint.visible else ""
	pistol_hint.visible = show_flashlight_hint and selected.get("scene_path", "") == PistolRules.PISTOL_SCENE
	pistol_hint.text = ""
	if pistol_hint.visible:
		var rounds := int(selected.get("state", {}).get("pistol", {}).get("loaded_rounds", 0))
		pistol_hint.text = "彈量 %d/%d · 備彈 %d" % [rounds, PistolRules.MAGAZINE_CAPACITY, int(weapon_data.get("reserve", 0))]
		var remaining := float(weapon_data.get("reload_remaining", 0.0))
		if remaining > 0.0:
			pistol_hint.text += " · 換彈 %.1fs" % remaining
		if not weapon_data.get("can_use", true):
			pistol_hint.text += " · 無法使用"

	for index in range(slots_container.get_child_count()):
		var panel := slots_container.get_child(index) as Panel
		var item: Dictionary = inventory[index] if index < inventory.size() else {}
		var occupied := not item.is_empty()
		var active := index == active_slot
		var large := bool(item.get("is_large", false))
		var item_name := panel.get_node("ItemName") as Label
		item_name.text = str(item.get("name", "物品")) if occupied else ""
		item_name.visible = active and occupied
		if active:
			selected_name = item_name
			if flashlight_hint.get_parent() != panel:
				flashlight_hint.reparent(panel, false)
			if pistol_hint.get_parent() != panel:
				pistol_hint.reparent(panel, false)
		var icon := panel.get_node("ItemIcon") as TextureRect
		icon.texture = InventoryItemIcons.texture_for(str(item.get("scene_path", "")), item.get("state", {})) if occupied else null
		icon.visible = occupied
		var ammo_count := panel.get_node("AmmoCount") as Label
		ammo_count.text = ""
		if item.get("scene_path", "") == PistolRules.AMMO_SCENE:
			ammo_count.text = str(int(item.get("state", {}).get("ammo", {}).get("rounds", 0)))
		elif item.get("scene_path", "") == PistolRules.PISTOL_SCENE:
			ammo_count.text = "%d/%d" % [int(item.get("state", {}).get("pistol", {}).get("loaded_rounds", 0)), PistolRules.MAGAZINE_CAPACITY]
		ammo_count.visible = not ammo_count.text.is_empty()
		panel.get_node("EmptyMark").visible = not occupied
		panel.get_node("LargeItem").visible = large
		panel.get_node("Selection").visible = active
		panel.get_node("Key").modulate = IndustrialTheme.AMBER if active else Color.WHITE
		# Reuse the style while charge/state refreshes leave slot appearance unchanged.
		var appearance := "%s:%s:%s" % [occupied, active, large]
		if panel.get_meta("appearance", "") == appearance:
			continue
		panel.set_meta("appearance", appearance)
		var fill := Color("252e2e") if occupied else Color("121b1d")
		if large:
			fill = Color("342e25")
		if active:
			fill = fill.lightened(0.08)
		var style := IndustrialTheme.box(fill, IndustrialTheme.AMBER if active else Color("46534e"), 0)
		style.set_corner_radius_all(5)
		style.set_border_width_all(2 if active else 1)
		panel.add_theme_stylebox_override("panel", style)

func _above_slot(label: Label, top: float, bottom: float) -> void:
	# Only the held item's caption is visible, so it can extend beyond its square.
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.offset_left = -120
	label.offset_right = 120
	label.offset_top = top
	label.offset_bottom = bottom
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _process(_delta: float) -> void:
	# Driving uses its own dashboard in this screen area.
	visible = get_parent().seated_in == null

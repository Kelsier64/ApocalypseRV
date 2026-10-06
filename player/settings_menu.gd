extends CanvasLayer
## Native-resolution settings overlay. The simulation intentionally keeps running.

const CATEGORIES: Array[StringName] = [&"display", &"input", &"audio", &"help"]
var player
var settings
var controls: Dictionary = {}
var _root: Control
var _panel: PanelContainer
var _tabs: TabContainer
var _status: Label
var _save_message: Label
var _retry: Button
var _reset: Button
var _return: Button
var _preset: OptionButton
var _preset_current: Label
var _resolution_label: Label
var _modal: Control
var _modal_text: Label
var _modal_accept: Button
var _modal_cancel: Button
var _modal_kind := ""
var _refreshing := false
var _modal_focus_modes: Dictionary = {}

func _ready() -> void:
	layer = 60
	visible = false
	player = get_parent()
	settings = get_node("/root/GameSettings")
	# The interior viewport matches native window size; only its 3D is scaled.
	# CanvasLayer remains visible independently when the seated Player hides.
	_build()
	settings.setting_changed.connect(_on_setting_changed)
	settings.save_completed.connect(_on_save_completed)
	settings.window_preview_changed.connect(_on_window_preview_changed)
	player.grab_started.connect(close_menu)
	get_tree().root.size_changed.connect(_resize)
	_resize()
	_refresh()

func _exit_tree() -> void:
	if is_instance_valid(settings):
		settings.cancel_window_preview()
		settings.flush()

func open_menu() -> bool:
	if visible or not player.can_open_settings():
		return false
	player.set_settings_open(true)
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()
	_update_status()
	_return.grab_focus()
	return true

func close_menu() -> void:
	if not visible:
		return
	settings.cancel_window_preview()
	_hide_modal()
	settings.flush()
	visible = false
	player.set_settings_open(false)
	if player.is_player_dead or player.is_grabbed() or player.in_ui_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if visible:
		if not _modal_kind.is_empty():
			_cancel_modal()
		else:
			close_menu()
		_handle_event()
		return
	# Tablet and storage retain ownership of their own first Escape.
	if player.in_ui_mode:
		return
	if player.is_placing_equipment():
		player.cancel_equipment_placement()
		_handle_event()
	elif open_menu():
		_handle_event()

func _unhandled_input(_event: InputEvent) -> void:
	# GUI gets its normal turn before leftovers can reach gameplay handlers.
	if visible:
		_handle_event()

func _handle_event() -> void:
	get_viewport().set_input_as_handled()
	get_tree().root.set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible:
		return
	if player.is_player_dead or player.is_grabbed() or player.in_ui_mode or not player.can_open_settings():
		close_menu()
		return
	_update_status()
	_update_resolution_summary()
	if _modal_kind == "window":
		_modal_text.text = "保留此顯示模式？\n%.0f 秒後自動還原；設定期間遊戲持續運行。" % ceilf(settings.preview_remaining())

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = IndustrialTheme.make(18)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.4)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_root.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)
	var title := _label("設定", 28)
	title.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	content.add_child(title)
	_status = _label("")
	content.add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	_tabs.tab_changed.connect(func(_index: int):
		if is_instance_valid(_reset):
			_reset.disabled = _tabs.current_tab == 3)
	content.add_child(_tabs)
	var pages: Array[VBoxContainer] = []
	for tab_name in ["視訊", "操作與視角", "音訊", "按鍵說明"]:
		var scroll := ScrollContainer.new()
		scroll.name = tab_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		_tabs.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 12)
		scroll.add_child(page)
		pages.append(page)
	_build_display(pages[0])
	_build_input(pages[1])
	_add_slider(pages[2], &"master_volume", "主音量", "所有遊戲音效；0% 為靜音。", 0.0, 1.0, 0.01, "percent")
	_build_help(pages[3])
	var save_row := HBoxContainer.new()
	content.add_child(save_row)
	_save_message = _label("")
	_save_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_save_message)
	_retry = _button("重試儲存", func(): _on_save_completed(settings.flush()))
	_retry.visible = false
	save_row.add_child(_retry)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)
	_reset = _button("恢復本頁預設", func(): settings.reset_category(CATEGORIES[_tabs.current_tab]))
	footer.add_child(_reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_return = _button("返回遊戲 [Esc]", close_menu)
	footer.add_child(_return)
	footer.add_child(_button("退出遊戲", _show_quit))
	_build_modal()

func _build_display(page: VBoxContainer) -> void:
	_section(page, "畫質與清晰度")
	_preset = _option(["遊戲預設", "低（較流暢）", "中（均衡）", "高（較清晰）", "自訂"])
	_preset.set_item_disabled(4, true)
	_preset.item_selected.connect(func(index: int):
		if not _refreshing and index < 4:
			settings.apply_preset(index))
	var preset_row := _row(page, "畫質組合", "一次調整解析度、抗鋸齒、陰影與霧。遊戲預設會依場景調整解析度。", _preset)
	_preset_current = preset_row.current
	_preset_current.hide()
	_add_option(page, &"render_mode", "3D 解析度", "只調整遊戲場景的清晰度；選單、文字與 HUD 維持清楚。", ["依場景自動", "自訂比例"], [0, 1])
	_resolution_label = controls[&"render_mode"].current
	_resolution_label.show()
	_add_slider(page, &"render_scale", "解析度比例", "100% 與視窗同樣清晰；降低比例可提升效能，但畫面會較模糊。", 0.5, 1.0, 0.05, "percent")
	_add_option(page, &"aa", "抗鋸齒", "減少物體邊緣的鋸齒；MSAA 越高，顯示卡負載越大。", ["關", "FXAA（較省效能）", "MSAA 2×", "MSAA 4×"], [0, 1, 2, 3])
	_add_option(page, &"shadow_quality", "陰影品質", "較高品質讓陰影邊緣更平滑。", ["遊戲預設", "低", "中", "高"], [0, 1, 2, 3])
	_add_option(page, &"fog_quality", "霧效果", "體積霧呈現局部霧氣與光影；天氣造成的濃霧會保留。", ["距離霧（較省效能）", "體積霧：低", "體積霧：中", "體積霧：高"], [0, 1, 2, 3])
	_section(page, "顯示與效能")
	_add_option(page, &"window_mode", "顯示模式", "切換後有 15 秒確認；未確認會自動還原。", ["視窗", "全螢幕"], [0, 1])
	_add_toggle(page, &"vsync", "垂直同步", "減少畫面撕裂；可能增加操作延遲。")
	_add_option(page, &"max_fps", "幀率上限", "限制每秒顯示的畫面數，降低顯示卡負載。", ["不限", "30 FPS", "60 FPS", "120 FPS", "144 FPS"], [0, 30, 60, 120, 144])
	_section(page, "色彩")
	_add_toggle(page, &"retro", "復古色調", "讓戶外呈現偏冷、低飽和的色彩；不改變畫面清晰度。")
	_add_slider(page, &"brightness", "亮度", "100% 為遊戲預設亮度。", 0.75, 1.25, 0.05, "percent")
	_add_slider(page, &"contrast", "對比", "100% 為遊戲預設明暗差異。", 0.75, 1.25, 0.05, "percent")
	_add_slider(page, &"saturation", "飽和度", "0% 為灰階；100% 為遊戲預設色彩。", 0.0, 1.5, 0.05, "percent")

func _section(page: VBoxContainer, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	var heading := _label(title, 18)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	row.add_child(heading)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)

func _build_input(page: VBoxContainer) -> void:
	_add_slider(page, &"sensitivity", "滑鼠靈敏度", "同時套用步行與駕駛視角；以原始靈敏度為 1 倍。", 0.25, 2.0, 0.05, "multiple")
	_add_toggle(page, &"invert_y", "反轉垂直視角", "反轉滑鼠上下移動的視角方向。")
	_add_slider(page, &"walk_fov", "步行視野", "較大視野顯示更多周圍環境；原始為 75°。", 60.0, 100.0, 1.0, "degrees")
	_add_slider(page, &"drive_fov", "駕駛視野", "調整駕駛座視角；原始為 80°。", 60.0, 100.0, 1.0, "degrees")

func _build_help(page: VBoxContainer) -> void:
	page.add_child(_label("固定按鍵說明；此頁不提供重新綁定。"))
	var rows := [
		["步行 / 視角", "WASD 移動、左 Shift 衝刺、滑鼠視角、Space 跳躍；衝刺與跳躍消耗耐力。"],
		["梯子攀爬", "靠近梯子面向踏板，W 上爬、S 下爬、Space 脫離；大型物品須先放下。側門梯登車，車內梯穿過屋頂開口。"],
		["拾取 / 互動", "短按 E 拾取、加油或進出副本；長按 E 約 1 秒入座、開平板、拆裝輪胎。"],
		["設備放置", "長按 F 約 2 秒搬移設備；左鍵確認、右鍵或 Esc 取消；R 切換貼面 / 直立。車體結構請到平板配置。"],
		["自由放置", "Q/E 旋轉 15°、Shift 旋轉 5°、方向鍵移動 5 cm。"],
		["背包 / 手電筒", "1–6 或滾輪選取、G 丟棄；大型物品鎖定選取；手持手電筒時 L 開關。"],
		["駕駛", "W 油門、A/D 轉向、S 漸進腳煞車、Space 手煞車、E 離座；設定開啟時無控制輸入。"],
		["引擎 / 排檔 / 車燈", "B 啟停、L 頭燈；Z 倒檔、X 空檔、C 一檔、R 升檔、T 降檔。"],
		["照明 / 儀表", "從平板控制車內、工作與維修燈、儀表亮度及引擎視覺震動。"],
		["電池 / 引擎", "持有零件時短 E 交換、長 E 取出；更換引擎須停穩、熄火且拉手煞車。"],
		["維修", "引擎：手持維修包 H 3 秒；設備 / 輪槽：熄火停穩後 H 2 秒，花 2 金屬。"],
		["後坡板", "控制柄 E；展開須停穩、手煞車、後門全開及合適地面；無人 / 物才可收起。"],
		["副本地圖", "M 顯示已探索地圖；Page Up / Page Down 切換樓層。"],
		["保存 / 載入", "主世界 F6 / F9；保存須室外離座、結束互動且地形建立完成。設定選單內不接受保存 / 載入。"],
		["設定 / 返回", "Esc 開啟 / 關閉設定；平板或儲物 UI 開啟時，先關閉該 UI；放置時先取消放置。"],
		["選單導覽", "Tab / Shift+Tab 移動焦點；方向鍵調整；Enter / Space 啟用按鈕；Esc 先取消確認提示。"]
	]
	for item in rows:
		var box := VBoxContainer.new()
		page.add_child(box)
		var title := _label(item[0])
		title.add_theme_color_override("font_color", IndustrialTheme.AMBER)
		box.add_child(title)
		box.add_child(_label(item[1]))

func _add_option(page: VBoxContainer, key: StringName, title: String, description: String, labels: Array, values: Array) -> void:
	var option := _option(labels)
	var row := _row(page, title, description, option)
	row.current.hide()
	controls[key] = {"control": option, "current": row.current, "reason": row.reason, "values": values, "description": row.description}
	option.item_selected.connect(func(index: int):
		if _refreshing:
			return
		if key == &"window_mode":
			if not settings.begin_window_preview(int(values[index])):
				_refresh()
		else:
			settings.set_setting(key, values[index]))

func _add_toggle(page: VBoxContainer, key: StringName, title: String, description: String) -> void:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var buttons: Array[Button] = []
	for value: bool in [false, true]:
		var button := Button.new()
		button.text = "開" if value else "關"
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 38
		button.toggled.connect(func(pressed: bool):
			if pressed and not _refreshing: settings.set_setting(key, value))
		pair.add_child(button)
		buttons.append(button)
	var row := _row(page, title, description, pair)
	pair.focus_mode = Control.FOCUS_NONE
	row.current.hide()
	controls[key] = {"control": pair, "current": row.current, "reason": row.reason, "buttons": buttons}

func _add_slider(page: VBoxContainer, key: StringName, title: String, description: String, minimum: float, maximum: float, step_value: float, format_kind: String = "decimal") -> void:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.custom_minimum_size = Vector2(220, 32)
	var row := _row(page, title, description, slider)
	row.current.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.current.add_theme_font_size_override("font_size", 20)
	row.current.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	controls[key] = {"control": slider, "current": row.current, "reason": row.reason, "format": format_kind, "panel": row.panel}
	slider.value_changed.connect(func(value: float):
		if not _refreshing:
			settings.set_setting(key, value))

func _row(page: VBoxContainer, title: String, description: String, control: Control) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", IndustrialTheme.box(Color("20272a")))
	page.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)
	var explanation := VBoxContainer.new()
	explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(explanation)
	explanation.add_child(_label(title, 20))
	var detail := _label(description, 16)
	detail.add_theme_color_override("font_color", Color("b6b8a9"))
	explanation.add_child(detail)
	var value_box := VBoxContainer.new()
	value_box.custom_minimum_size.x = 280
	row.add_child(value_box)
	value_box.add_child(control)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.focus_mode = Control.FOCUS_ALL
	var current := _label("", 16)
	value_box.add_child(current)
	var reason := _label("", 15)
	reason.add_theme_color_override("font_color", IndustrialTheme.AMBER)
	reason.visible = false
	value_box.add_child(reason)
	return {"current": current, "reason": reason, "description": detail, "panel": panel}

func _refresh() -> void:
	_refreshing = true
	_preset.select(settings.preset_index())
	_preset_current.text = "目前：" + _preset.get_item_text(_preset.selected)
	for key in controls:
		var entry: Dictionary = controls[key]
		var control: Control = entry.control
		var value = settings.get_setting(key)
		entry.reason.visible = false
		if entry.has("buttons"):
			for index in range(2):
				var button: Button = entry.buttons[index]
				var selected: bool = bool(value) == bool(index)
				button.set_pressed_no_signal(selected)
				button.text = ("✓ " if selected else "") + ("開" if index == 1 else "關")
		elif control is OptionButton:
			var index: int = entry.values.find(value)
			control.select(maxi(0, index))
			entry.current.text = "目前：" + control.get_item_text(control.selected)
		elif control is HSlider:
			control.set_value_no_signal(float(value))
			entry.current.text = _format_value(float(value), entry.format)
	var scale: HSlider = controls[&"render_scale"].control
	scale.editable = int(settings.get_setting(&"render_mode")) == 1
	controls[&"render_scale"].panel.visible = scale.editable
	for button: Button in controls[&"vsync"].buttons:
		button.disabled = not settings.supports_vsync_toggle()
	_set_reason(&"vsync", "目前顯示驅動不支援切換垂直同步。" if not settings.supports_vsync_toggle() else "")
	var fog: OptionButton = controls[&"fog_quality"].control
	var volume_supported: bool = settings.supports_volumetric_fog()
	for index in range(1, 4):
		fog.set_item_disabled(index, not volume_supported)
	if not volume_supported:
		fog.select(0)
		controls[&"fog_quality"].current.show()
		controls[&"fog_quality"].current.text = "實際：距離霧（相容模式降級）"
	else:
		controls[&"fog_quality"].current.hide()
	_set_reason(&"fog_quality", "目前渲染器不支援體積霧。" if not volume_supported else "")
	_update_resolution_summary()
	_refreshing = false
	_on_save_completed(settings.last_save_error)

func _set_reason(key: StringName, message: String) -> void:
	controls[key].reason.text = message
	controls[key].reason.visible = not message.is_empty()

func _format_value(value: float, kind: String) -> String:
	match kind:
		"percent": return "%.0f%%" % (value * 100.0)
		"degrees": return "%.0f°" % value
		"multiple": return "%.2f 倍" % value
	return "%.2f" % value

func _update_resolution_summary() -> void:
	if not is_instance_valid(_resolution_label): return
	# The actor's viewport follows it indoors. Read the applied scale, rather
	# than the saved manual percentage, which is unused in automatic mode.
	var viewport: Viewport = player.get_viewport()
	var dimensions := Vector2i(viewport.get_visible_rect().size)
	var ratio := viewport.scaling_3d_scale
	var rendered := Vector2i(Vector2(dimensions) * ratio)
	_resolution_label.text = "3D：%d × %d（%.0f%%）" % [rendered.x, rendered.y, ratio * 100.0]
	var automatic: bool = int(settings.get_setting(&"render_mode")) == 0
	var explanation := "自動：戶外降低解析度，室內使用完整解析度。" if automatic else "自訂：100% 與視窗同樣清晰；較低比例讓畫面更模糊。"
	controls[&"render_mode"].description.text = "%s\n視窗：%d × %d；選單與文字不受影響。" % [explanation, dimensions.x, dimensions.y]

func _on_setting_changed(_key: StringName, _value: Variant) -> void:
	_refresh()

func _on_save_completed(error: Error) -> void:
	_retry.visible = error != OK
	_save_message.text = "設定無法儲存（%s）；目前仍已套用，可重試。" % error_string(error) if error != OK else "設定自動儲存；不會建立遊戲檢查點。"

func _update_status() -> void:
	_status.text = "遊戲持續運行  ·  HP %.0f / %.0f" % [player.current_player_health, player.max_player_health]
	if is_instance_valid(player.seated_in):
		var chassis = player.seated_in.get_connected_rv()
		if is_instance_valid(chassis):
			_status.text += "  ·  車速 %.0f km/h" % (chassis.linear_velocity.length() * 3.6)

func _resize() -> void:
	var dimensions := get_tree().root.get_visible_rect().size
	_panel.custom_minimum_size = Vector2(minf(1040, maxf(0, dimensions.x - 40)), minf(650, maxf(0, dimensions.y - 40)))

func _build_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.visible = false
	_root.add_child(_modal)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	_modal_text = _label("")
	box.add_child(_modal_text)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_modal_accept = _button("確認", _accept_modal)
	buttons.add_child(_modal_accept)
	_modal_cancel = _button("取消", _cancel_modal)
	buttons.add_child(_modal_cancel)
	for button in [_modal_accept, _modal_cancel]:
		var other: Button = _modal_cancel if button == _modal_accept else _modal_accept
		button.focus_next = button.get_path_to(other)
		button.focus_previous = button.get_path_to(other)
		button.focus_neighbor_left = button.get_path_to(other)
		button.focus_neighbor_right = button.get_path_to(other)
		button.focus_neighbor_top = button.get_path_to(other)
		button.focus_neighbor_bottom = button.get_path_to(other)

func _show_quit() -> void:
	_modal_kind = "quit"
	_modal_text.text = "確定退出遊戲？\n未以 F6 保存的遊戲進度將遺失。\n設定會保存；此處不會自動保存遊戲進度。"
	_modal_accept.text = "退出遊戲"
	_modal_cancel.text = "取消"
	_show_modal()

func _on_window_preview_changed(active: bool) -> void:
	_refresh()
	if active and visible:
		_modal_kind = "window"
		_modal_accept.text = "保留顯示模式"
		_modal_cancel.text = "還原"
		_show_modal()
	elif _modal_kind == "window":
		_hide_modal()

func _accept_modal() -> void:
	if _modal_kind == "window":
		settings.confirm_window_preview()
	elif _modal_kind == "quit":
		settings.cancel_window_preview()
		settings.flush()
		get_tree().quit()
	_hide_modal()

func _cancel_modal() -> void:
	if _modal_kind == "window":
		settings.cancel_window_preview()
	_hide_modal()

func _hide_modal() -> void:
	_modal_kind = ""
	_modal.hide()
	for control in _modal_focus_modes:
		if is_instance_valid(control):
			control.focus_mode = _modal_focus_modes[control]
	_modal_focus_modes.clear()
	if visible:
		_return.grab_focus()

func _show_modal() -> void:
	# Explicitly remove background controls from keyboard navigation. Arrow
	# neighbors and Tab then remain on the two confirmation buttons only.
	if _modal_focus_modes.is_empty():
		_suspend_background_focus(_panel)
	_modal.show()
	_modal_cancel.grab_focus()

func _suspend_background_focus(node: Node) -> void:
	if node is Control and node.focus_mode != Control.FOCUS_NONE:
		_modal_focus_modes[node] = node.focus_mode
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_suspend_background_focus(child)

func _option(labels: Array) -> OptionButton:
	var option := OptionButton.new()
	for label in labels:
		option.add_item(str(label))
	return option

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button

func _label(text: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label

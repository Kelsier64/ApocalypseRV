extends SceneTree
## Terminal navigation, native controls and ownership through real input dispatch.
var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
var tablet: Item
var ui: Node
var close_count := 0

class OtherTerminal extends Node:
	var rv: Node3D
	var current_user: Node
	var ui_instance: CanvasLayer
	func can_operate() -> bool: return true
	func get_connected_rv() -> Node3D: return rv
	func is_management_active() -> bool: return ui_instance.visible

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func frames(count: int = 2) -> void:
	for frame in count: await process_frame
func key(code: Key, pressed: bool, ctrl: bool = false, echo: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	event.echo = echo
	event.shift_pressed = shift
	Input.parse_input_event(event)
func tap(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	key(code, true, ctrl, false, shift)
	await process_frame
	key(code, false, ctrl, false, shift)
	await frames()
func click(button: BaseButton) -> void:
	await frames()
	var point := button.get_global_rect().get_center()
	check(button.get_viewport().get_visible_rect().has_point(point), "Native control is reachable inside the viewport: " + button.name)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	button.get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		button.get_viewport().push_input(event, true)
		await process_frame

func visible_text(node: Node) -> PackedStringArray:
	var result := PackedStringArray()
	if node is Control and not node.is_visible_in_tree(): return result
	if node is Label or node is RichTextLabel or node is Button:
		result.append(node.text)
	if node is OptionButton:
		for index in node.item_count: result.append(node.get_item_text(index))
	for child in node.get_children(): result.append_array(visible_text(child))
	return result

func check_presentation() -> void:
	var cjk := RegEx.new()
	cjk.compile("[\\x{3400}-\\x{9fff}]")
	for page in ["overview", "energy", "equipment", "crafting", "structure"]:
		ui.select_page(page)
		for text in visible_text(ui):
			check(cjk.search(text) == null, "Terminal uses English presentation on " + page + ": " + text)
			var lower := text.to_lower()
			check(not lower.contains("brightness") and not lower.contains("vibration") and not lower.contains("display"), "Retired display settings are absent on " + page)
			check(not lower.contains("ctrl+c") and not lower.contains("ctrl+d") and not lower.contains("ctrl +"), "Hidden TUI exit chords have no visible hint")
	for button in ui.find_children("*", "Button", true, false):
		var text: String = button.text.to_lower()
		check(not text.contains("close") and not text.contains("exit") and not text.contains("shell"), "TUI has no close or shell button")

func run() -> void:
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	world.add_child(floor_body)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	# SceneTree starts this deferred call before the newly added scene has
	# finished ready; its registered socket/controller references come later.
	await frames()
	rv.get_battery_socket().set_physics_process(false)
	var station: CraftingStation = rv.get_node("CraftingStation")
	station.set_physics_process(false)
	var construction: RVStructureConstruction = rv.get_node("StructureSlots").construction
	construction.set_physics_process(false)
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(20, 0.05, 0)
	world.add_child(player)
	await physics_frame
	await physics_frame
	rv.current_power = 80.0
	rv.set_engine_running(false)
	tablet = rv.get_node("TabletScreen")
	ui = tablet.ui_instance
	ui.close_requested.connect(func(): close_count += 1)
	var initial_power := rv.current_power
	tablet.interact_hold(player)
	check(ui.visible and ui.is_management_active() and tablet.is_management_active() and player.in_ui_mode, "Opening tablet enters management with player UI ownership")
	check(ui.current_page == "overview", "Every tablet open begins on overview")
	check(is_equal_approx(rv.current_power, initial_power - tablet.power_cost_per_open), "Opening debits one tablet fee")
	check(ui.terminal_lines.is_empty() and ui.command_history.is_empty(), "Fresh terminal has no startup banner or synthetic command history")
	await check_navigation_and_controls()
	await check_page_navigation(station, construction)
	check_presentation()
	await check_shell_and_shortcuts()
	await check_construction_and_queue(station, construction)
	await check_closing_and_lifecycle()
	station.cancel_jobs()
	world.queue_free()
	await frames()
	for failure in failures: push_error("FAIL: " + failure)
	if failures.is_empty(): print("PASS: RV terminal TUI, shell, native controls, construction and input ownership")
	quit(0 if failures.is_empty() else 1)

func check_navigation_and_controls() -> void:
	var pages := ["overview", "energy", "equipment", "crafting", "structure"]
	for index in pages.size():
		await tap(KEY_F1 + index)
		check(ui.current_page == pages[index], "Function key selects management page: " + pages[index])
	ui.select_page("display")
	check(ui.current_page == "structure", "Retired Display page cannot be selected")
	check(ui.slot_controls.size() == 11 and not ui.slot_controls.has("floor"), "Structure grid exposes eleven slots without the fixed floor")
	ui.select_slot("rear")
	await tap(KEY_UP)
	check(ui.selected_slot == "roof_2", "Up from the rear selects the centered rear roof slot")
	ui.select_slot("front")
	await tap(KEY_DOWN)
	check(ui.selected_slot == "roof_0", "Down from the front selects the centered front roof slot")
	await tap(KEY_LEFT)
	check(ui.selected_slot == "left_0", "Left selects the matching wall in the structure grid")
	await tap(KEY_RIGHT)
	await tap(KEY_DOWN)
	check(ui.selected_slot == "roof_1", "Grid keyboard navigation preserves row and column")
	await click(ui.slot_controls["right_1"])
	check(ui.selected_slot == "right_1", "Native pointer click selects the intended structure slot")
	for slot in RVStructureSlots.layout():
		ui.slot_controls[slot.id].pressed.emit()
		check(ui.selected_slot == slot.id, "Structure grid selects its own slot: " + slot.id)
		var selector: OptionButton = ui.controls["structure:type"]
		var allowed := RVStructureSlots.types_for_slot(slot.id)
		check(selector.item_count == allowed.size(), "Type selector contains exactly the types for " + slot.id)
		for index in selector.item_count:
			check(allowed.has(str(selector.get_item_metadata(index))), "Type selector excludes foreign slot types: " + slot.id)
	var selected_before: String = ui.selected_slot
	ui.select_slot("floor")
	check(ui.selected_slot == selected_before, "Fixed floor cannot become the selected construction target")
	ui.select_page("energy")
	check(ui.controls["engine"] is Button and ui.controls["charging_enabled"] is CheckButton and ui.controls["charging_threshold"] is SpinBox and ui.controls["charging_reserve"] is SpinBox, "Energy page exposes native action, toggle and numeric controls")
	ui.select_page("overview")
	var headlights: CheckButton = ui.controls["headlights"]
	var previous_headlights := rv.headlights_requested
	await click(headlights)
	check(rv.headlights_requested != previous_headlights and headlights.button_pressed == rv.headlights_requested, "Pointer click changes actual headlight state")
	headlights.grab_focus()
	await tap(KEY_SPACE)
	check(rv.headlights_requested == previous_headlights, "Focused toggle supports keyboard activation")
	ui.controls["engine"].pressed.emit()
	check(rv.energy.engine_running, "Engine action starts the connected vehicle")
	ui.controls["engine"].pressed.emit()
	check(not rv.energy.engine_running, "Engine action stops the connected vehicle")
	ui.select_page("equipment")
	check(not ui.controls.has("work"), "Retired work lighting has no terminal control")
	for kind in ["cabin", "service"]:
		var toggle: CheckButton = ui.controls[kind]
		var requested: bool = rv.interior_requested[kind]
		toggle.button_pressed = not requested
		check(rv.interior_requested[kind] != requested, "Native light toggle updates the connected RV: " + kind)
		toggle.button_pressed = requested
	# Refresh changes display state without sending the old SpinBox limits back.
	rv.max_fuel = 100.0
	rv.energy.fuel_reserve = 150.0
	ui.on_open()
	check(rv.energy.fuel_reserve == 150.0 and ui.controls["charging_reserve"].value == 150.0, "Opening preserves saved reserve above a smaller tank capacity without emitted signals")
	rv.energy.fuel_reserve = 5.0
	ui.on_open()

func focus_target(id: String) -> Control:
	var target: Control = ui.controls[id]
	return target.get_line_edit() if target is SpinBox else target

func expect_focus(id: String, note: String) -> void:
	check(root.gui_get_focus_owner() == focus_target(id), note + ": " + id)

func expect_toggle_contrast(toggle: CheckButton, note: String) -> void:
	var value := toggle.text.replace("[", "").replace("]", "").strip_edges()
	check(value == ("ON" if toggle.button_pressed else "OFF"), note + " keeps its actual ON/OFF value visible")
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := toggle.get_theme_stylebox(state)
		check(style is StyleBoxFlat and style.bg_color == RVTerminalTheme.AMBER, note + " retains the focus background in " + state)
	for color in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		check(toggle.get_theme_color(color) == RVTerminalTheme.BACKGROUND, note + " retains contrasting text in " + color)

func expect_scrolled_into_view(target: Control, note: String) -> void:
	var ancestor := target.get_parent()
	while ancestor and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
	check(ancestor is ScrollContainer, note + " has a scrolling page")
	if ancestor is ScrollContainer:
		check(ancestor.get_global_rect().encloses(target.get_global_rect()), note + " is fully visible after keyboard focus")

func check_tab_order(page: String, order: Array[String]) -> void:
	ui.select_page(page)
	focus_target(order[0]).grab_focus()
	for index in range(1, order.size() + 1):
		await tap(KEY_TAB)
		expect_focus(order[index % order.size()], "Tab follows reading order within " + page)
	await tap(KEY_TAB, false, true)
	expect_focus(order[-1], "Shift+Tab wraps within " + page)
	check(ui.current_page == page, "Tab navigation preserves the selected page: " + page)

func check_page_navigation(station: CraftingStation, construction: RVStructureConstruction) -> void:
	# Navigate native controls through Input.parse_input_event; setup alone may
	# select a page or grab initial focus. No arrow assertion emits pressed.
	var saved_items: Dictionary = rv.storage.items.duplicate(true)
	for recipe in RecipeCatalog.all():
		for item in recipe.costs: rv.storage.items[item] = 1000
	ui.select_page("overview")
	var engine_before: bool = rv.energy.engine_running
	var headlights_before: bool = rv.headlights_requested
	var overview: Array[String] = ["engine", "headlights", "inspect:equipment", "inspect:structure"]
	for id in overview.slice(1):
		await tap(KEY_DOWN)
		expect_focus(id, "Overview Down visits every action")
	for index in range(overview.size() - 2, -1, -1):
		await tap(KEY_UP)
		expect_focus(overview[index], "Overview Up reverses every action")
	for pair in [["engine", "inspect:equipment"], ["headlights", "inspect:structure"]]:
		focus_target(pair[0]).grab_focus()
		await tap(KEY_RIGHT)
		expect_focus(pair[1], "Overview Right crosses matching panels")
		await tap(KEY_LEFT)
		expect_focus(pair[0], "Overview Left returns across matching panels")
	check(rv.energy.engine_running == engine_before and rv.headlights_requested == headlights_before, "Overview arrows never activate engine or headlights")
	await check_tab_order("overview", overview)
	focus_target("page:overview").grab_focus()
	await tap(KEY_RIGHT)
	expect_focus("page:energy", "Header Right reaches the next page button")
	check(ui.current_page == "overview", "Moving through header focus does not activate another page")
	await tap(KEY_LEFT)
	expect_focus("page:overview", "Header Left returns to the previous page button")
	await tap(KEY_TAB)
	expect_focus("engine", "Tab from the header enters the active page controls")
	ui.controls["inspect:equipment"].hide()
	focus_target("headlights").grab_focus()
	await tap(KEY_DOWN)
	expect_focus("inspect:structure", "Overview skips an action hidden after page construction")
	ui.controls["inspect:equipment"].show()
	ui.controls["inspect:equipment"].disabled = true
	focus_target("headlights").grab_focus()
	await tap(KEY_DOWN)
	expect_focus("inspect:structure", "Overview skips an action disabled after page construction")
	ui.controls["inspect:equipment"].disabled = false

	ui.select_page("energy")
	var charging_before: bool = rv.energy.charging_enabled
	var threshold_before: float = rv.energy.recharge_below
	var reserve_before: float = rv.energy.fuel_reserve
	await tap(KEY_DOWN)
	expect_focus("charging_threshold", "Energy Down enters the numeric editor")
	await tap(KEY_RIGHT)
	check(is_equal_approx(rv.energy.recharge_below, threshold_before + 0.05), "Threshold Right adjusts charging by one five-percent step")
	await tap(KEY_LEFT)
	check(is_equal_approx(rv.energy.recharge_below, threshold_before), "Threshold Left restores the previous charging value")
	await tap(KEY_DOWN)
	expect_focus("charging_reserve", "Energy Down reaches fuel reserve")
	await tap(KEY_RIGHT)
	check(is_equal_approx(rv.energy.fuel_reserve, reserve_before + 1.0), "Reserve Right adjusts actual fuel reserve by one step")
	await tap(KEY_LEFT)
	check(is_equal_approx(rv.energy.fuel_reserve, reserve_before), "Reserve Left restores actual fuel reserve")
	await tap(KEY_UP)
	expect_focus("charging_threshold", "Energy Up leaves reserve for threshold")
	await tap(KEY_UP)
	expect_focus("charging_enabled", "Energy Up returns to charging master")
	await tap(KEY_LEFT)
	await tap(KEY_RIGHT)
	check(rv.energy.charging_enabled == charging_before, "Charging arrows move focus without changing charging state")
	await check_tab_order("energy", ["charging_enabled", "charging_threshold", "charging_reserve"])

	ui.select_page("equipment")
	var equipment_order: Array[String] = ["cabin", "service"]
	var toggles: Array[String] = []
	var device_states: Dictionary = {}
	for device in rv.get_equipment(): device_states[device.persistent_id] = device.enabled
	var cabin_before: bool = rv.interior_requested.cabin
	var service_before: bool = rv.interior_requested.service
	await tap(KEY_DOWN)
	expect_focus("service", "Equipment Down reaches service lamp")
	for id in ui.device_selectors:
		await tap(KEY_DOWN)
		expect_focus("select:" + id, "Equipment Down visits every installed device")
		check(ui.selected_device == id, "Arrow focus selects installed equipment details: " + id)
		equipment_order.append("select:" + id)
		if ui.controls.has("device:" + id):
			equipment_order.append("device:" + id)
			toggles.append("device:" + id)
			await tap(KEY_RIGHT)
			expect_focus("device:" + id, "Every equipment selector reaches its own ON/OFF action")
			expect_toggle_contrast(ui.controls["device:" + id], "Focused equipment switch")
			await tap(KEY_LEFT)
			expect_focus("select:" + id, "Equipment Left returns to the matching selector")
		else:
			await tap(KEY_RIGHT)
			expect_focus("select:" + id, "Equipment without a switch cannot enter another device's ON/OFF action")
		await frames(3)
		expect_scrolled_into_view(focus_target("select:" + id), "Focused installed equipment")
	for index in toggles.size() - 1:
		focus_target(toggles[index]).grab_focus()
		await tap(KEY_DOWN)
		expect_focus(toggles[index + 1], "Equipment Down remains in the ON/OFF column")
		check(ui.selected_device == toggles[index + 1].trim_prefix("device:"), "Equipment switch focus selects the matching details")
		await tap(KEY_UP)
		expect_focus(toggles[index], "Equipment Up reverses the ON/OFF column")
		check(ui.selected_device == toggles[index].trim_prefix("device:"), "Equipment reverse switch focus selects the matching details")
	check(not toggles.is_empty(), "Fixture includes switchable installed equipment")
	if toggles.size() >= 3:
		var skipped: BaseButton = ui.controls[toggles[1]]
		skipped.hide()
		focus_target(toggles[0]).grab_focus()
		await tap(KEY_DOWN)
		expect_focus(toggles[2], "Equipment arrows skip a hidden ON/OFF control")
		skipped.show()
		skipped.disabled = true
		focus_target(toggles[0]).grab_focus()
		await tap(KEY_DOWN)
		expect_focus(toggles[2], "Equipment arrows skip a disabled ON/OFF control")
		skipped.disabled = false
	if not toggles.is_empty():
		focus_target(toggles[0]).grab_focus()
		await tap(KEY_UP)
		expect_focus("service", "Up above the first equipment switch reaches lighting")
	await check_tab_order("equipment", equipment_order)
	for device in rv.get_equipment(): check(device.enabled == device_states[device.persistent_id], "Equipment arrows and Tab preserve enabled state: " + device.persistent_id)
	check(rv.interior_requested.cabin == cabin_before and rv.interior_requested.service == service_before, "Equipment navigation preserves both lighting masters")
	if not toggles.is_empty():
		var toggle_id: String = toggles[0]
		var device_id := toggle_id.trim_prefix("device:")
		focus_target(toggle_id).grab_focus()
		await tap(KEY_ENTER)
		check(ui.controls[toggle_id].button_pressed != device_states[device_id], "Enter activates a focused equipment switch")
		expect_toggle_contrast(ui.controls[toggle_id], "Equipment switch after Enter")
		await tap(KEY_SPACE)
		check(ui.controls[toggle_id].button_pressed == device_states[device_id], "Space also activates equipment and restores its state")
		expect_toggle_contrast(ui.controls[toggle_id], "Equipment switch after Space")
		await check_equipment_membership(toggle_id)

	ui.select_page("crafting")
	var recipe_order: Array[String] = []
	var materials_before: Dictionary = rv.get_all_items().duplicate(true)
	for recipe in RecipeCatalog.all():
		var recipe_id: String = recipe.recipe_id
		var control_id := "recipe:" + recipe_id
		recipe_order.append(control_id)
		focus_target(control_id).grab_focus()
		await frames()
		check(ui.selected_recipe == recipe_id, "Focusing a recipe selects its details without activation: " + recipe_id)
		check(not ui.controls["craft:add"].disabled, "Fixture affords recipe: " + recipe_id)
		await tap(KEY_RIGHT)
		expect_focus("craft:add", "Every recipe, including bottom entries, reaches Add to queue")
		await tap(KEY_LEFT)
		expect_focus(control_id, "Left from Add to queue returns to the selected recipe")
		await frames(3)
		expect_scrolled_into_view(focus_target(control_id), "Focused recipe")
	for index in range(recipe_order.size() - 1, 0, -1):
		await tap(KEY_UP)
		expect_focus(recipe_order[index - 1], "Recipe Up stays in the recipe list")
	for index in range(1, recipe_order.size()):
		await tap(KEY_DOWN)
		expect_focus(recipe_order[index], "Recipe Down stays in the recipe list")
	var craft_order: Array[String] = recipe_order.duplicate()
	craft_order.append_array(["craft:station", "craft:add"])
	await check_tab_order("crafting", craft_order)
	check(station.jobs.is_empty() and rv.get_all_items() == materials_before, "Crafting arrows and Tab neither queue jobs nor spend materials")
	focus_target("craft:add").grab_focus()
	await tap(KEY_ENTER)
	check(station.jobs.size() == 1 and not ui.controls["craft:cancel"].disabled, "Enter on Add to queue starts a job and enables cancellation")
	await tap(KEY_DOWN)
	expect_focus("craft:cancel", "Crafting Down reaches newly available queue cancellation")
	await tap(KEY_UP)
	expect_focus("craft:add", "Crafting Up returns from queue cancellation to Add")
	await tap(KEY_DOWN)
	await tap(KEY_ENTER)
	check(station.jobs.is_empty() and rv.get_all_items() == materials_before, "Enter on queue cancellation refunds the keyboard-created job")
	expect_focus("craft:add", "Refunding the last job restores focus from disabled cancellation to Add")
	rv.storage.items.clear()
	ui.select_page("crafting")
	check(ui.controls["craft:add"].disabled, "Unavailable crafting action is disabled")
	var unavailable_recipe: String = ui.selected_recipe
	focus_target("recipe:" + unavailable_recipe).grab_focus()
	await tap(KEY_RIGHT)
	check(root.gui_get_focus_owner() != ui.controls["craft:add"], "Right never lands on unavailable Add to queue")
	await tap(KEY_ENTER)
	check(station.jobs.is_empty(), "Unavailable crafting navigation cannot queue a job")
	rv.storage.items = saved_items

	ui.select_page("structure")
	await frames(3)
	var roof_center: float = ui.slot_controls["roof_1"].get_global_rect().get_center().x
	for id in ["front", "rear"]:
		check(absf(ui.slot_controls[id].get_global_rect().get_center().x - roof_center) < 1.0, "Structure " + id + " is centered on the roof column")
	for row in 3:
		ui.select_slot("right_%d" % row)
		await tap(KEY_RIGHT)
		expect_focus("structure:type", "Right leaves every right wall for available part actions")
		await tap(KEY_LEFT)
		expect_focus("slot:right_%d" % row, "Left from part selector returns to the selected wall")
		check(ui.selected_slot == "right_%d" % row, "Moving to part actions preserves the selected grid row")
	var part_before: Dictionary = VehicleSnapshot.capture(rv)
	ui.select_slot("roof_1")
	focus_target("structure:type").grab_focus()
	await tap(KEY_DOWN)
	var action: Control = root.gui_get_focus_owner()
	check(action != ui.controls["structure:repair"] or not action.disabled, "Structure Down skips disabled repair")
	check(action != ui.controls["structure:rebuild"], "Structure Down skips rebuild hidden for an intact panel")
	check(not construction.is_building() and VehicleSnapshot.capture(rv) == part_before, "Navigating structure actions never begins construction or changes vehicle state")
	# Actions after the grid depend on the last selected slot. Build the
	# expected suffix from that slot, then traverse every grid cell via Tab.
	ui.select_slot("rear")
	var structure_order: Array[String] = ["slot:front", "slot:left_0", "slot:roof_0", "slot:right_0", "slot:left_1", "slot:roof_1", "slot:right_1", "slot:left_2", "slot:roof_2", "slot:right_2", "slot:rear", "structure:type"]
	for operation in ["repair", "rebuild", "convert"]:
		var control: BaseButton = ui.controls["structure:" + operation]
		if control.is_visible_in_tree() and not control.disabled: structure_order.append("structure:" + operation)
	await check_tab_order("structure", structure_order)
	await check_popup_navigation()
	await check_narrow_navigation()
	ui.select_page("overview")

func check_equipment_membership(original_toggle_id: String) -> void:
	# Install and detach a real extra Item so the production equipment registry
	# rebuilds the list while keyboard focus is on an existing ON/OFF control.
	ui.select_page("equipment")
	focus_target(original_toggle_id).grab_focus()
	var original_id := original_toggle_id.trim_prefix("device:")
	var original_count: int = rv.get_equipment().size()
	var extra: CabinLightStrip = load("res://equipment/cabin_light_strip.tscn").instantiate()
	extra.position = Vector3(0, 8, 0)
	extra.freeze = true
	world.add_child(extra)
	extra.set_physics_process(false)
	extra.confirm_placement(Transform3D(Basis.IDENTITY, rv.global_position + Vector3(0, 8, 0)), rv, rv)
	await create_timer(0.3).timeout
	await frames(3)
	check(rv.get_equipment().size() == original_count + 1 and ui.device_selectors.has(extra.persistent_id), "Installing a real light strip rebuilds the displayed equipment membership")
	expect_focus(original_toggle_id, "Equipment membership rebuild preserves the focused device switch")
	check(ui.selected_device == original_id, "Membership rebuild preserves the focused switch's details")
	expect_toggle_contrast(ui.controls[original_toggle_id], "Rebuilt equipment switch")
	var extra_id: String = extra.persistent_id
	focus_target("select:" + extra_id).grab_focus()
	await tap(KEY_RIGHT)
	expect_focus("device:" + extra_id, "The newly installed light strip has a reachable ON/OFF action")
	var old_ids: Array = ui.device_selectors.keys()
	var old_index: int = old_ids.find(extra_id)
	old_ids.erase(extra_id)
	var nearest_id: String = old_ids[mini(old_index, old_ids.size() - 1)]
	extra.detach_from_support()
	await create_timer(0.3).timeout
	await frames(3)
	check(rv.get_equipment().size() == original_count and not ui.controls.has("device:" + extra_id), "Detaching the focused fixture removes its obsolete switch")
	var fallback_id := ("device:" if ui.controls.has("device:" + nearest_id) else "select:") + nearest_id
	expect_focus(fallback_id, "Removing focused equipment restores focus to the nearest remaining available device")
	check(ui.selected_device == nearest_id, "Removed equipment focus recovery selects the surviving device details")
	var survivor: Control = root.gui_get_focus_owner()
	check(is_instance_valid(survivor) and survivor.is_visible_in_tree() and not survivor.disabled, "Removed equipment never leaves keyboard focus on a freed or unavailable control")
	extra.queue_free()
	await frames()
	focus_target(original_toggle_id).grab_focus()

func check_narrow_navigation() -> void:
	# A single-column layout must keep the same logical navigation even when
	# details and actions occupy a separate vertical section of the page.
	root.size = Vector2i(900, 620)
	await frames(4)
	ui.select_page("overview")
	await tap(KEY_DOWN)
	expect_focus("headlights", "Narrow overview keeps the same first Down target")
	await tap(KEY_DOWN)
	expect_focus("inspect:equipment", "Narrow overview keeps the complete reading order")
	ui.select_page("equipment")
	for id in ui.device_selectors:
		if not ui.controls.has("device:" + id): continue
		focus_target("select:" + id).grab_focus()
		await tap(KEY_RIGHT)
		expect_focus("device:" + id, "Narrow equipment still reaches its matching switch")
		await frames(3)
		expect_scrolled_into_view(focus_target("device:" + id), "Narrow equipment switch")
	ui.select_page("crafting")
	var recipes := RecipeCatalog.all()
	var last_id: String = recipes[-1].recipe_id
	focus_target("recipe:" + last_id).grab_focus()
	await tap(KEY_RIGHT)
	check(root.gui_get_focus_owner() == ui.controls["craft:station"] or root.gui_get_focus_owner() == ui.controls["craft:add"], "Narrow bottom recipe reaches an available action")
	await frames(3)
	expect_scrolled_into_view(root.gui_get_focus_owner(), "Narrow crafting action")
	await tap(KEY_LEFT)
	expect_focus("recipe:" + last_id, "Narrow crafting action returns to the selected bottom recipe")
	ui.select_page("structure")
	await frames(3)
	var roof_center: float = ui.slot_controls["roof_1"].get_global_rect().get_center().x
	for id in ["front", "rear"]:
		check(absf(ui.slot_controls[id].get_global_rect().get_center().x - roof_center) < 1.0, "Narrow structure " + id + " remains centered on the roof column")
	ui.select_slot("right_2")
	await tap(KEY_RIGHT)
	expect_focus("structure:type", "Narrow structure grid reaches its part selector")
	await frames(3)
	expect_scrolled_into_view(focus_target("structure:type"), "Narrow structure selector")
	await tap(KEY_LEFT)
	expect_focus("slot:right_2", "Narrow part selector returns to the same grid row")
	root.size = Vector2i(1280, 720)
	await frames(4)

func check_popup_navigation() -> void:
	ui.select_slot("roof_1")
	var selector: OptionButton = ui.controls["structure:type"]
	selector.grab_focus()
	await tap(KEY_ENTER)
	await frames()
	var popup := selector.get_popup()
	check(popup.visible, "Enter opens the focused native structure type menu")
	if not popup.visible: return
	var slot_before: String = ui.selected_slot
	var selected_before: int = selector.selected
	await tap(KEY_DOWN)
	check(popup.visible and ui.selected_slot == slot_before and selector.selected == selected_before, "Popup Down owns navigation without changing the structure grid or applying a choice")
	await tap(KEY_ENTER)
	check(not popup.visible and selector.selected != selected_before and ui.selected_slot == slot_before, "Popup Enter applies its focused choice without activating construction")
	selector.select(selected_before)
	ui.select_slot(slot_before)

func check_shell_and_shortcuts() -> void:
	ui.select_page("energy")
	ui.controls["charging_reserve"].get_line_edit().grab_focus()
	await tap(KEY_C, true)
	check(not ui.is_management_active() and ui.visible and player.in_ui_mode, "Ctrl+C leaves TUI even from a focused numeric field while shell retains ownership")
	check(ui.terminal_lines.is_empty(), "Normal TUI exit adds no shell banner")
	for button in ui.find_children("*", "Button", true, false):
		check(not button.is_visible_in_tree(), "Shell has no visible buttons")
	for label in ui.find_children("*", "Label", true, false):
		check(not label.is_visible_in_tree(), "Shell has no visible banner, title or footer")
	var owned_power := rv.current_power
	tablet.interact_hold(player)
	check(is_equal_approx(rv.current_power, owned_power) and not ui.is_management_active(), "Interacting with an owned shell cannot reopen it or charge another fee")
	ui.shell_input.text = "status"
	ui.shell_input.grab_focus()
	await tap(KEY_ENTER)
	check(not ui.terminal_lines.is_empty() and ui.command_history.has("status"), "Enter submits shell input to real command processing and history")
	check(ui.shell_input.is_editing(), "Submitting a shell command keeps the prompt ready for the next command")
	ui.shell_input.text = ""
	await tap(KEY_UP)
	check(ui.shell_input.text == "status", "History Up recalls the previous command")
	await tap(KEY_DOWN)
	check(ui.shell_input.text.is_empty(), "History Down restores the empty draft")
	ui.shell_input.text = "unfinished draft"
	await tap(KEY_UP)
	check(ui.shell_input.text == "status", "History Up recalls a command while preserving the nonempty draft")
	await tap(KEY_DOWN)
	check(ui.shell_input.text == "unfinished draft", "History Down restores the unsubmitted nonempty draft exactly")
	ui.shell_input.text = "rvc"
	await tap(KEY_TAB)
	check(ui.shell_input.text == "rvctl", "Tab completes the management command")
	await tap(KEY_ENTER)
	check(ui.is_management_active() and player.in_ui_mode and is_equal_approx(rv.current_power, owned_power), "rvctl enters management without reopening charge or releasing ownership")
	ui.select_page("overview")
	ui.controls["engine"].grab_focus()
	await tap(KEY_Q)
	check(ui.is_management_active(), "Q has no TUI exit binding")
	ui.select_page("energy")
	ui.controls["charging_threshold"].get_line_edit().grab_focus()
	await tap(KEY_D, true)
	check(not ui.is_management_active() and player.in_ui_mode, "Ctrl+D also leaves TUI from a focused number field")
	ui.submit_command("nonsense")
	var output_count: int = ui.terminal_lines.size()
	check(output_count > 0 and not ui.is_management_active(), "Unknown command reports an error without changing terminal mode")
	var state_before := VehicleSnapshot.capture(rv)
	ui.submit_command("cheat")
	check(VehicleSnapshot.capture(rv) == state_before and not ui.is_management_active(), "Reserved cheat command cannot modify gameplay or enter management")
	ui.submit_command("help status")
	check(ui.terminal_lines.size() > output_count, "Per-command help writes shell output")
	ui.submit_command("clear")
	check(ui.terminal_lines.is_empty() and ui.command_history.has("status"), "Clear erases scrollback and preserves command history")
	ui.submit_command("rvctl")

func check_construction_and_queue(station: CraftingStation, construction: RVStructureConstruction) -> void:
	rv.storage.items[ItemNames.METAL_PARTS] = 100
	rv.storage.items[ItemNames.UNREFINED_FUEL] = 100
	rv.current_power = 80.0
	rv.set_engine_running(false)
	ui.select_page("crafting")
	var recipe: Button = ui.controls["recipe:gasoline"]
	recipe.pressed.emit()
	check(ui.selected_recipe == "gasoline" and not ui.controls["craft:add"].disabled, "Recipe selection exposes an affordable craft action")
	check(station.jobs.is_empty(), "Selecting a recipe does not implicitly spend materials or queue work")
	ui.controls["craft:add"].pressed.emit()
	check(station.jobs.size() == 1, "Crafting action queues a real station job")
	var panel: Node = rv.get_node("StructureSlots").panel("front")
	panel.set_health(40.0)
	ui.select_page("structure")
	ui.select_slot("front")
	ui.controls["structure:repair"].pressed.emit()
	check(construction.is_building() and construction.job.slot == "front", "Repair targets the selected structure slot")
	var materials := rv.get_all_items()
	ui.select_page("overview")
	focus_target("inspect:structure").grab_focus()
	await tap(KEY_TAB)
	expect_focus("structure:cancel", "Tab reaches global cancellation during active construction")
	await tap(KEY_ENTER)
	check(not construction.is_building() and rv.get_all_items() == materials, "Native cancellation stops construction without spending materials")
	ui.select_page("structure")
	ui.select_slot("front")
	ui.controls["structure:repair"].pressed.emit()
	check(construction.is_building(), "Selected structure can start another repair after cancellation")
	ui.enter_shell()
	check(not construction.is_building() and panel.current_health == 40.0 and rv.get_all_items() == materials, "Leaving TUI cancels this terminal's construction without repairing or charging")
	check(station.jobs.size() == 1, "Leaving TUI preserves independently queued crafting")
	check(not construction.begin(tablet, "front", "repair").is_empty(), "Shell ownership does not authorize structure construction")
	ui.submit_command("rvctl")
	check(construction.begin(tablet, "front", "repair").is_empty(), "Returning to TUI restores construction authorization")
	construction.cancel()
	ui.select_page("crafting")
	ui.controls["recipe:gasoline"].pressed.emit()
	ui.controls["craft:add"].pressed.emit()
	check(station.jobs.size() == 2, "Crafting remains usable after a shell round trip")
	ui.controls["craft:cancel"].pressed.emit()
	check(station.jobs.is_empty() and rv.get_item_count(ItemNames.METAL_PARTS) == 100, "Native queue cancellation refunds reserved craft materials")
	# A construction job belongs to its authorizing terminal, even if another
	# terminal on the same RV leaves management.
	var other := OtherTerminal.new()
	other.rv = rv
	other.current_user = Node.new()
	other.add_child(other.current_user)
	other.ui_instance = CanvasLayer.new()
	other.add_child(other.ui_instance)
	world.add_child(other)
	check(construction.begin(other, "front", "repair").is_empty(), "Independent terminal starts its own construction fixture")
	ui.enter_shell()
	check(construction.is_building() and construction.job.terminal == other, "Leaving this terminal's TUI cannot cancel a different terminal's construction")
	construction.cancel()
	other.free()
	ui.submit_command("rvctl")

func check_closing_and_lifecycle() -> void:
	ui.select_page("structure")
	var selector: OptionButton = ui.controls["structure:type"]
	selector.grab_focus()
	selector.show_popup()
	await frames()
	check(selector.get_popup().visible, "Structure type popup is open before the hidden exit chord")
	var owned_power := rv.current_power
	await tap(KEY_D, true)
	check(not ui.is_management_active() and not selector.get_popup().visible and ui.visible and player.in_ui_mode and tablet.current_user == player, "Ctrl+D dismisses an open structure popup and enters shell with the same operator")
	check(is_equal_approx(rv.current_power, owned_power) and close_count == 0, "Popup shell exit keeps ownership without an opening fee or close request")
	ui.submit_command("rvctl")
	check(ui.is_management_active() and tablet.current_user == player, "rvctl returns from popup shell exit to management with the same operator")
	ui.select_page("structure")
	selector.grab_focus()
	selector.show_popup()
	await frames()
	await tap(KEY_ESCAPE)
	check(not ui.visible and not player.in_ui_mode and not player.settings_open and close_count == 1, "Escape closes tablet from a type popup and consumes the event before settings")
	var history: PackedStringArray = ui.command_history.duplicate()
	var origin := player.global_position
	key(KEY_W, true)
	tablet.interact_hold(player)
	await physics_frame
	await physics_frame
	check(ui.is_management_active() and ui.current_page == "overview" and ui.command_history == history, "Reopening returns to overview and preserves transient history")
	check(player.global_position.distance_to(origin) < 0.05, "Held gameplay movement cannot leak through tablet ownership")
	ui.enter_shell()
	ui.shell_input.grab_focus()
	await tap(KEY_ESCAPE)
	check(not player.in_ui_mode and not player.settings_open and close_count == 2, "Escape also closes shell immediately without opening settings")
	await physics_frame
	await physics_frame
	check(player.global_position.distance_to(origin) < 0.05, "Held movement remains blocked after closing until released")
	key(KEY_W, false)
	await physics_frame
	await physics_frame
	check(not player.is_gameplay_input_blocked(), "Releasing held movement restores gameplay input after tablet closes")
	tablet.interact_hold(player)
	ui.enter_shell()
	ui.submit_command("exit")
	check(not ui.visible and not player.in_ui_mode and close_count == 3, "Shell exit closes the tablet through the same ownership release")
	var engine_running: bool = rv.energy.engine_running
	var history_size: int = ui.command_history.size()
	ui.controls["engine"].pressed.emit()
	ui.submit_command("rvctl")
	check(rv.energy.engine_running == engine_running and not ui.visible and ui.command_history.size() == history_size, "Closed terminal cannot write vehicle state or execute stale shell input")
	tablet.interact_hold(player)
	ui.enter_shell()
	player.is_player_dead = true
	tablet._physics_process(0.01)
	check(not ui.visible and tablet.current_user == null and not player.in_ui_mode, "Operator death closes shell and releases its owner")
	player.is_player_dead = false
	tablet.interact_hold(player)
	ui.enter_shell()
	rv.current_power = 0.0
	tablet._physics_process(0.01)
	check(not ui.visible and not player.in_ui_mode, "Loss of usable power closes shell and releases ownership")
	rv.current_power = 80.0
	tablet.interact_hold(player)
	ui.enter_shell()
	tablet.detach_from_support()
	check(not ui.visible and not player.in_ui_mode, "Loss of mounted support closes shell and releases ownership")

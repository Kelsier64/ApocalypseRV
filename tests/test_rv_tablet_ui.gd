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
func key(code: Key, pressed: bool, ctrl: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	event.echo = echo
	Input.parse_input_event(event)
func tap(code: Key, ctrl: bool = false) -> void:
	key(code, true, ctrl)
	await process_frame
	key(code, false, ctrl)
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
	ui.controls["structure:cancel"].pressed.emit()
	check(not construction.is_building() and rv.get_all_items() == materials, "Native cancellation stops construction without spending materials")
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

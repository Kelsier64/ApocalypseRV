extends SceneTree

const UI_LAYOUT := preload("res://core/ui_layout.gd")
var failures: Array[String] = []
var resize_events: Array[Vector2] = []
var clicks: int = 0

func _init() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var requested := Vector2i(2080, 1440)
	var fitted: Vector2i = UI_LAYOUT.fitted_window_size(requested, Vector2i(1280, 720))
	_expect(fitted.x > 0 and fitted.y > 0 and fitted.x <= 1152 and fitted.y <= 648, "Large saved window fits within usable desktop margins")
	_expect(absf(float(fitted.x) / fitted.y - float(requested.x) / requested.y) < 0.003, "Desktop fitting preserves the requested aspect ratio")
	_expect(UI_LAYOUT.fitted_window_size(Vector2i(800, 450), Vector2i(1920, 1080)) == Vector2i(800, 450), "Desktop fitting keeps an already fitting window unchanged")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var layer := CanvasLayer.new()
	viewport.add_child(layer)
	var screen := Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	var backdrop := Control.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hotbar := Button.new()
	hotbar.text = "Inventory"
	screen.add_child(hotbar)
	hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.offset_left = -240.0
	hotbar.offset_right = 240.0
	hotbar.offset_top = -90.0
	hotbar.offset_bottom = -18.0
	hotbar.pressed.connect(func() -> void: clicks += 1)
	var observer: Node = UI_LAYOUT.attach(layer, screen)
	observer.connect("resized", func(logical_size: Vector2) -> void: resize_events.append(logical_size))
	for case in [
		[Vector2i(800, 450), 5.0 / 6.0],
		[Vector2i(1280, 720), 1.0],
		[Vector2i(1920, 1080), 1.5],
		[Vector2i(3440, 1440), 2.0],
		[Vector2i(800, 1280), 5.0 / 6.0],
	]:
		viewport.size = case[0]
		await process_frame
		await process_frame
		_check_layout(layer, screen, backdrop, hotbar, Vector2(case[0]), case[1])
		_check_click(viewport, hotbar)
	_expect(not resize_events.is_empty() and resize_events.back().is_equal_approx(screen.size), "Resize observers receive the current logical dimensions")

	var other_viewport := SubViewport.new()
	other_viewport.size = Vector2i(1920, 1080)
	root.add_child(other_viewport)
	layer.reparent(other_viewport)
	await process_frame
	await process_frame
	_check_layout(layer, screen, backdrop, hotbar, Vector2(1920, 1080), 1.5)
	other_viewport.size = Vector2i(800, 450)
	await process_frame
	await process_frame
	_check_layout(layer, screen, backdrop, hotbar, Vector2(800, 450), 5.0 / 6.0)
	_check_click(other_viewport, hotbar)
	var event_count := resize_events.size()
	viewport.size = Vector2i(640, 360)
	await process_frame
	await process_frame
	_expect(resize_events.size() == event_count, "Resizing the old viewport does not alter a reparented overlay")
	_expect(screen.size.is_equal_approx(Vector2(960, 540)), "Reparented overlay keeps the new viewport's logical size")
	viewport.free()
	other_viewport.free()
	if failures.is_empty():
		print("PASS: desktop fitting, live overlay resize, anchors, scaled GUI input and viewport reparenting")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_layout(layer: CanvasLayer, screen: Control, backdrop: Control, hotbar: Button, dimensions: Vector2, expected_scale: float) -> void:
	var description := " at " + str(dimensions)
	_expect(layer.scale.is_equal_approx(Vector2.ONE * expected_scale), "Overlay scale follows the viewport" + description)
	_expect(screen.position.is_equal_approx(Vector2.ZERO) and screen.size.is_equal_approx(dimensions / expected_scale), "Root uses logical dimensions with its origin at the screen corner" + description)
	var transform := backdrop.get_global_transform_with_canvas()
	_expect((transform * Vector2.ZERO).is_equal_approx(Vector2.ZERO) and (transform * backdrop.size).is_equal_approx(dimensions), "Full rect reaches both physical screen edges" + description)
	var hotbar_transform := hotbar.get_global_transform_with_canvas()
	var start := hotbar_transform * Vector2.ZERO
	var end := hotbar_transform * hotbar.size
	_expect(absf((start.x + end.x) * 0.5 - dimensions.x * 0.5) < 0.1, "Hotbar stays horizontally centered" + description)
	_expect(start.x >= 0.0 and start.y >= 0.0 and end.x <= dimensions.x and end.y <= dimensions.y, "Hotbar remains entirely visible" + description)
	_expect(absf(dimensions.y - end.y - 18.0 * expected_scale) < 0.1, "Hotbar keeps its scaled bottom margin" + description)

func _check_click(viewport: SubViewport, button: Button) -> void:
	var position := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	viewport.push_input(motion, true)
	var before := clicks
	for is_pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = is_pressed
		viewport.push_input(event, true)
	_expect(clicks == before + 1, "Physical mouse coordinates activate the scaled button at " + str(viewport.size))

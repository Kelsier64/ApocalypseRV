class_name UILayout
extends Node
## Scale UI independently of native 3D viewports, including after world transfers.
signal resized(logical_size: Vector2)

var _layer: CanvasLayer
var _screen: Control
var _minimum_size := Vector2(960, 540)
var _last_dimensions := Vector2.ZERO

static func fitted_window_size(requested: Vector2i, usable: Vector2i) -> Vector2i:
	var available := Vector2(usable) * 0.9
	var factor := minf(1.0, minf(available.x / maxf(1, requested.x), available.y / maxf(1, requested.y)))
	return Vector2i(Vector2(requested) * factor).max(Vector2i.ONE)

static func overlay_scale(dimensions: Vector2, minimum_size: Vector2 = Vector2(960, 540)) -> float:
	var readable := maxf(1.0, minf(dimensions.x / 1280.0, dimensions.y / 720.0))
	var fit := minf(dimensions.x / minimum_size.x, dimensions.y / minimum_size.y)
	return maxf(0.001, minf(readable, fit))

static func attach(layer: CanvasLayer, screen: Control, minimum_size: Vector2 = Vector2(960, 540)) -> UILayout:
	var layout := UILayout.new()
	layout._layer = layer
	layout._screen = screen
	layout._minimum_size = minimum_size
	layer.add_child(layout)
	layout.update_layout()
	return layout

func _process(_delta: float) -> void:
	update_layout()

func update_layout() -> void:
	var dimensions := _layer.get_viewport().get_visible_rect().size
	if dimensions == _last_dimensions:
		return
	_last_dimensions = dimensions
	var factor := overlay_scale(dimensions, _minimum_size)
	_layer.scale = Vector2.ONE * factor
	_screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_screen.size = dimensions / factor
	resized.emit(_screen.size)

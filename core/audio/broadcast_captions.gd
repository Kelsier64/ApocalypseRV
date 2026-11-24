extends CanvasLayer
class_name BroadcastCaptions
## Screen-space captions for the dispatch voice. Off unless the "captions" setting is on;
## shown only while the speaking player is playing and the camera is within its range.
const NODE_NAME := &"BroadcastCaptions"

var source: AudioStreamPlayer3D
var text := ""
var _panel: PanelContainer
var _label: Label

static func show_for(player: AudioStreamPlayer3D, line: String) -> void:
	if line.is_empty() or player == null or not player.is_inside_tree(): return
	var root := player.get_tree().root
	var captions := root.get_node_or_null(NodePath(NODE_NAME)) as BroadcastCaptions
	if captions == null:
		captions = BroadcastCaptions.new()
		captions.name = NODE_NAME
		root.add_child(captions)
	captions.source = player
	captions.text = line
	captions._label.text = line
	captions._refresh()

static func enabled(tree: SceneTree) -> bool:
	var settings := tree.root.get_node_or_null("GameSettings")
	return settings != null and bool(settings.get_setting(&"captions"))

func _init() -> void:
	layer = 5
	var screen := Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var bottom := CenterContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_top = -150.0
	bottom.offset_bottom = -88.0
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	screen.add_child(bottom)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.theme = IndustrialTheme.make(18)
	_panel.add_theme_stylebox_override("panel", IndustrialTheme.box(Color(0.03, 0.035, 0.035, 0.72), Color.TRANSPARENT, 10))
	bottom.add_child(_panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", IndustrialTheme.INK)
	_panel.add_child(_label)
	_panel.hide()

func _ready() -> void:
	HUDVisibility.attach(self)

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	if not is_inside_tree(): return
	if not is_instance_valid(source) or not source.playing:
		source = null
		_panel.hide()
		return
	_panel.visible = enabled(get_tree()) and _audible()

func _audible() -> bool:
	var camera := source.get_viewport().get_camera_3d()
	if camera == null: return true
	return source.max_distance <= 0.0 or camera.global_position.distance_to(source.global_position) <= source.max_distance

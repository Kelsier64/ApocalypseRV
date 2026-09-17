extends Node
class_name OutdoorPresentation
## Main viewport only. Canvas/UI stays native; the interior has its own viewport.
const SETTINGS_PATH := "user://display_preferences.cfg"
var retro_enabled := true
var effect: ColorRect
var label: Label
var _last_size := Vector2i.ZERO
var _last_active := false
var _notice_time := 0.0

func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		retro_enabled = bool(settings.get_value("display", "retro", true))
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	effect = ColorRect.new()
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/terrain/retro.gdshader")
	effect.material = material
	layer.add_child(effect)
	var notice := CanvasLayer.new()
	notice.layer = 46
	add_child(notice)
	label = Label.new()
	label.position = Vector2(24, 325)
	label.add_theme_font_size_override("font_size", 20)
	notice.add_child(label)
	apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		set_retro(not retro_enabled, true)
		get_viewport().set_input_as_handled()

func set_retro(value: bool, persist: bool = false) -> void:
	retro_enabled = value
	if persist:
		var settings := ConfigFile.new()
		settings.load(SETTINGS_PATH)
		settings.set_value("display", "retro", value)
		settings.save(SETTINGS_PATH)
	_notice_time = 3.0
	label.text = "Retro display: %s | F8" % ("ON" if value else "OFF")
	apply()

func _process(delta: float) -> void:
	_notice_time = maxf(0.0, _notice_time - delta)
	label.visible = _notice_time > 0
	apply()

func apply() -> void:
	var manager := get_parent().get_node_or_null("PoiInstances") as PoiInstanceManager
	var active := retro_enabled and (manager == null or manager.active_id.is_empty())
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if size == _last_size and active == _last_active: return
	_last_size = size
	_last_active = active
	get_viewport().scaling_3d_scale = minf(1.0, 540.0 / maxf(1, size.y)) if active else 1.0
	effect.visible = active

func _exit_tree() -> void:
	if is_inside_tree(): get_viewport().scaling_3d_scale = 1.0

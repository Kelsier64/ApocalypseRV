extends Node
## Local preferences, independent from checkpoint/world simulation state.
signal setting_changed(key: StringName, value: Variant)
signal save_completed(error: Error)
signal window_preview_changed(active: bool)

const DEFAULTS := {
	"window_mode": 0, "vsync": true, "max_fps": 0,
	"render_mode": 0, "render_scale": 1.0, "aa": 0,
	"shadow_quality": 0, "fog_quality": 2, "retro": true,
	"brightness": 1.0, "contrast": 1.0, "saturation": 1.0,
	"sensitivity": 1.0, "invert_y": false, "walk_fov": 75.0,
	"drive_fov": 80.0, "master_volume": 1.0,
}
const RANGES := {
	"render_scale": Vector2(0.5, 1.0), "brightness": Vector2(0.75, 1.25),
	"contrast": Vector2(0.75, 1.25), "saturation": Vector2(0.0, 1.5),
	"sensitivity": Vector2(0.25, 2.0), "walk_fov": Vector2(60.0, 100.0),
	"drive_fov": Vector2(60.0, 100.0), "master_volume": Vector2(0.0, 1.0),
}
const INPUT_KEYS := ["sensitivity", "invert_y", "walk_fov", "drive_fov"]
const QUALITY_KEYS := ["render_mode", "render_scale", "aa", "shadow_quality", "fog_quality"]
const PRESETS := [
	{"render_mode": 0, "render_scale": 1.0, "aa": 0, "shadow_quality": 0, "fog_quality": 2},
	{"render_mode": 1, "render_scale": 0.5, "aa": 0, "shadow_quality": 1, "fog_quality": 0},
	{"render_mode": 1, "render_scale": 0.75, "aa": 1, "shadow_quality": 2, "fog_quality": 2},
	{"render_mode": 1, "render_scale": 1.0, "aa": 3, "shadow_quality": 3, "fog_quality": 3},
]
var storage_path := "user://display_preferences.cfg"
var last_save_error: Error = OK
var window_preview_seconds := 15.0
var values: Dictionary = DEFAULTS.duplicate()
var _config := ConfigFile.new()
var _dirty := false
var _save_delay := -1.0
var _viewports: Dictionary = {}
var _outdoor_active := true
var _preview: Dictionary = {}
var _preset := 0
var _applying_preset := false
var _original_directional_size := 4096
var _original_directional_filter := 2
var _original_positional_filter := 2

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_original_directional_size = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)
	_original_directional_filter = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)
	_original_positional_filter = ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2)
	load_preferences()
	register_viewport.call_deferred(get_tree().root)

func get_setting(key: StringName) -> Variant:
	if key == &"quality_preset": return _preset
	return values.get(String(key), DEFAULTS.get(String(key)))

func _section(key: String) -> String:
	if key in INPUT_KEYS: return "input"
	if key == "master_volume": return "audio"
	return "display"

func _valid(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key): return false
	if RANGES.has(key):
		if not (value is float or value is int) or not is_finite(float(value)): return false
		var bounds: Vector2 = RANGES[key]
		return float(value) >= bounds.x and float(value) <= bounds.y
	if DEFAULTS[key] is bool: return value is bool
	if not value is int: return false
	match key:
		"window_mode", "render_mode": return value in [0, 1]
		"max_fps": return value in [0, 30, 60, 120, 144]
		"aa", "shadow_quality", "fog_quality": return value >= 0 and value <= 3
	return false

func load_preferences(path: String = "") -> Error:
	if not _preview.is_empty(): cancel_window_preview()
	if not path.is_empty(): storage_path = path
	_config = ConfigFile.new()
	var result := _config.load(storage_path)
	values = DEFAULTS.duplicate()
	if result == OK:
		for key: String in DEFAULTS:
			var candidate: Variant = _config.get_value(_section(key), key, DEFAULTS[key])
			if _valid(key, candidate): values[key] = candidate
		if not _config.has_section_key("display", "render_mode"):
			values.render_mode = 0 if values.retro else 1
			values.render_scale = 1.0
	_preset = _matching_preset_index()
	var saved_preset: Variant = _config.get_value("display", "quality_preset", _preset)
	if saved_preset is int and saved_preset in [0, 1, 2, 3, 4]:
		_preset = saved_preset if saved_preset == 4 or saved_preset == _preset else 4
	_dirty = false
	_save_delay = -1.0
	last_save_error = OK
	_apply_global()
	_apply_all_viewports()
	for key: String in values: setting_changed.emit(StringName(key), values[key])
	return result

func set_setting(key: StringName, value: Variant, persist: bool = true) -> bool:
	var name := String(key)
	if not _valid(name, value): return false
	if values[name] == value: return true
	values[name] = float(value) if RANGES.has(name) else value
	if name in QUALITY_KEYS and not _applying_preset: _preset = 4
	if persist:
		_dirty = true
		_save_delay = 0.3
	_apply_global(name)
	if name in QUALITY_KEYS or name in ["retro", "brightness", "contrast", "saturation"]:
		_apply_all_viewports()
	setting_changed.emit(key, values[name])
	return true

func preset_index() -> int:
	return _preset

func _matching_preset_index() -> int:
	for index in PRESETS.size():
		var matches := true
		for key: String in QUALITY_KEYS:
			if values[key] != PRESETS[index][key]: matches = false
		if matches: return index
	return 4

func apply_preset(index: int) -> void:
	if index < 0 or index >= PRESETS.size(): return
	_applying_preset = true
	for key: String in QUALITY_KEYS: set_setting(StringName(key), PRESETS[index][key])
	_applying_preset = false
	_preset = index
	_dirty = true
	_save_delay = 0.3
	setting_changed.emit(&"quality_preset", index)

func reset_category(category: StringName) -> void:
	if String(category) not in ["display", "input", "audio"]: return
	if category == &"display": apply_preset(0)
	for key: String in DEFAULTS:
		if _section(key) != String(category): continue
		if key == "window_mode":
			if values.window_mode != DEFAULTS.window_mode: begin_window_preview(DEFAULTS.window_mode)
		else: set_setting(StringName(key), DEFAULTS[key])

func flush() -> Error:
	if not _dirty: return last_save_error
	_config.set_value("display", "quality_preset", _preset)
	for key: String in values:
		var value: Variant = values[key]
		if key == "window_mode" and not _preview.is_empty(): value = _preview.preference
		_config.set_value(_section(key), key, value)
	last_save_error = _config.save(storage_path)
	_save_delay = -1.0
	if last_save_error == OK: _dirty = false
	save_completed.emit(last_save_error)
	return last_save_error

func supports_volumetric_fog() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

func supports_vsync_toggle() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility" and DisplayServer.get_name() != "headless"

func volumetric_fog_enabled() -> bool:
	return supports_volumetric_fog() and int(values.fog_quality) > 0

func _apply_global(changed: String = "") -> void:
	if changed.is_empty() or changed == "max_fps": Engine.max_fps = int(values.max_fps)
	if changed.is_empty() or changed == "master_volume":
		var master := AudioServer.get_bus_index("Master")
		if master >= 0:
			AudioServer.set_bus_mute(master, float(values.master_volume) <= 0.0)
			AudioServer.set_bus_volume_db(master, linear_to_db(maxf(0.0001, float(values.master_volume))))
	if DisplayServer.get_name() != "headless":
		if _preview.is_empty() and (changed.is_empty() or changed == "window_mode"):
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if int(values.window_mode) == 1 else DisplayServer.WINDOW_MODE_WINDOWED
			if DisplayServer.window_get_mode() != mode: DisplayServer.window_set_mode(mode)
		if changed.is_empty() or changed == "vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync or not supports_vsync_toggle() else DisplayServer.VSYNC_DISABLED)
	if DisplayServer.get_name() == "headless": return
	if changed.is_empty() or changed == "shadow_quality":
		var quality := int(values.shadow_quality)
		RenderingServer.directional_shadow_atlas_set_size(_original_directional_size if quality == 0 else (2048 if quality == 1 else 4096), ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", true))
		RenderingServer.directional_soft_shadow_filter_set_quality(_original_directional_filter if quality == 0 else quality)
		RenderingServer.positional_soft_shadow_filter_set_quality(_original_positional_filter if quality == 0 else quality)
	if supports_volumetric_fog() and (changed.is_empty() or changed == "fog_quality"):
		var fog := int(values.fog_quality)
		RenderingServer.environment_set_volumetric_fog_volume_size(32 if fog == 1 else (96 if fog == 3 else 64), 96 if fog == 3 else 64)

func register_viewport(viewport: Viewport, indoor: bool = false) -> void:
	var id := viewport.get_instance_id()
	if _viewports.has(id): return
	var layer := CanvasLayer.new()
	layer.name = "VideoEffects"
	layer.layer = 0
	viewport.add_child(layer)
	var effect := ColorRect.new()
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/terrain/retro.gdshader")
	effect.material = material
	layer.add_child(effect)
	_viewports[id] = {"viewport": weakref(viewport), "indoor": indoor, "effect": weakref(effect), "atlas": viewport.positional_shadow_atlas_size}
	viewport.size_changed.connect(_apply_viewport.bind(id))
	_apply_viewport(id)

func viewport_effect(viewport: Viewport) -> ColorRect:
	var entry: Dictionary = _viewports.get(viewport.get_instance_id(), {})
	return entry.effect.get_ref() as ColorRect if not entry.is_empty() else null

func set_outdoor_active(active: bool) -> void:
	if _outdoor_active == active: return
	_outdoor_active = active
	_apply_all_viewports()

func _apply_all_viewports() -> void:
	for id: int in _viewports.keys(): _apply_viewport(id)

func _apply_viewport(id: int) -> void:
	if not _viewports.has(id): return
	var entry: Dictionary = _viewports[id]
	var viewport := entry.viewport.get_ref() as Viewport
	if viewport == null:
		_viewports.erase(id)
		return
	var indoor: bool = entry.indoor
	var legacy_scale := minf(1.0, 540.0 / maxf(1.0, viewport.get_visible_rect().size.y)) if not indoor and _outdoor_active else 1.0
	viewport.scaling_3d_scale = legacy_scale if int(values.render_mode) == 0 else float(values.render_scale)
	viewport.msaa_3d = Viewport.MSAA_2X if int(values.aa) == 2 else (Viewport.MSAA_4X if int(values.aa) == 3 else Viewport.MSAA_DISABLED)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if int(values.aa) == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.positional_shadow_atlas_size = int(entry.atlas) if int(values.shadow_quality) == 0 else (2048 if int(values.shadow_quality) == 1 else 4096)
	var effect := entry.effect.get_ref() as ColorRect
	if effect == null: return
	var material := effect.material as ShaderMaterial
	material.set_shader_parameter("retro_enabled", bool(values.retro) and not indoor)
	for key in ["brightness", "contrast", "saturation"]: material.set_shader_parameter(key, float(values[key]))
	effect.visible = (indoor or _outdoor_active) and ((bool(values.retro) and not indoor) or values.brightness != 1.0 or values.contrast != 1.0 or values.saturation != 1.0)

func begin_window_preview(mode: int) -> bool:
	if mode not in [0, 1]: return false
	if not _preview.is_empty(): cancel_window_preview()
	if int(values.window_mode) == mode: return false
	_preview = {"preference": values.window_mode, "deadline": Time.get_ticks_msec() + int(window_preview_seconds * 1000.0)}
	if DisplayServer.get_name() != "headless":
		_preview.native_mode = DisplayServer.window_get_mode()
		_preview.size = DisplayServer.window_get_size()
		_preview.position = DisplayServer.window_get_position()
	values.window_mode = mode
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if mode == 1 else DisplayServer.WINDOW_MODE_WINDOWED)
	setting_changed.emit(&"window_mode", mode)
	window_preview_changed.emit(true)
	return true

func preview_remaining() -> float:
	return maxf(0.0, (float(_preview.deadline) - Time.get_ticks_msec()) / 1000.0) if not _preview.is_empty() else 0.0

func confirm_window_preview() -> void:
	if _preview.is_empty(): return
	_preview.clear()
	_dirty = true
	flush()
	window_preview_changed.emit(false)

func cancel_window_preview() -> void:
	if _preview.is_empty(): return
	values.window_mode = _preview.preference
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(_preview.native_mode)
		if _preview.native_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			var available := DisplayServer.screen_get_usable_rect()
			var size: Vector2i = _preview.size.min(available.size)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(Vector2i(Vector2(_preview.position).clamp(Vector2(available.position), Vector2(available.end - size))))
	_preview.clear()
	setting_changed.emit(&"window_mode", values.window_mode)
	window_preview_changed.emit(false)

func _process(delta: float) -> void:
	if not _preview.is_empty() and preview_remaining() <= 0.0: cancel_window_preview()
	if _save_delay >= 0.0:
		_save_delay -= delta
		if _save_delay <= 0.0: flush()
	for id: int in _viewports.keys():
		if _viewports[id].viewport.get_ref() == null: _viewports.erase(id)

func _exit_tree() -> void:
	cancel_window_preview()
	flush()

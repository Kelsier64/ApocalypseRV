extends Control
## Artwork for the terminal's LCD, mapped to its recessed glass.
const FONT = preload("res://assets/fonts/NotoSansMono-Regular.ttf")
const BACKLIGHT := Color("071c19")
const INK := Color("caeed7")
const MUTED := Color("7cad9a")
const TRACK := Color("21463d")
const ALERT := Color("f5ad77")
const ROW_NAMES := ["HEALTH", "STAMINA", "HUNGER", "SAN"]

var day := ""
var time := ""
var values := PackedInt32Array()
var bar_pixels := PackedInt32Array()

func show_reading(new_day: String, new_time: String, new_values: PackedInt32Array, fractions: PackedFloat32Array) -> void:
	var bars := PackedInt32Array()
	for fraction in fractions:
		bars.append(roundi(clampf(fraction, 0.0, 1.0) * (size.x - 44.0)))
	if day == new_day and time == new_time and values == new_values and bar_pixels == bars: return
	day = new_day
	time = new_time
	values = new_values
	bar_pixels = bars
	queue_redraw()
	(get_viewport() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKLIGHT)
	if values.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color("0d201d"))
		draw_string(FONT, Vector2(31, size.y - 30), "STANDBY", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, MUTED.darkened(0.45))
		return

	draw_rect(Rect2(0, 0, size.x, 91), Color("112f29"))
	draw_string(FONT, Vector2(22, 61), time if not time.is_empty() else "--:--", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, INK)
	_right_text(day, 57, 32, MUTED)
	draw_rect(Rect2(22, 90, size.x - 44, 2), TRACK)
	for i in ROW_NAMES.size():
		var baseline := 146.0 + i * 80.0
		var bar := Rect2(22, baseline + 12, size.x - 44, 9)
		var color := ALERT if bar_pixels[i] <= bar.size.x * 0.20 else INK
		draw_string(FONT, Vector2(22, baseline), ROW_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 37, INK)
		_right_text(str(values[i]), baseline, 39, color)
		draw_rect(bar, TRACK)
		bar.size.x = bar_pixels[i]
		if bar.size.x > 0.0: draw_rect(bar, color)
		for division in range(1, 10):
			draw_rect(Rect2(22 + (size.x - 44) * division / 10.0, bar.position.y, 2, bar.size.y), BACKLIGHT)

func _right_text(value: String, baseline: float, font_size: int, color: Color) -> void:
	var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(FONT, Vector2(size.x - 22 - width, baseline), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

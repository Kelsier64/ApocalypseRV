extends PanelContainer
## Character-cell frames surround native, focusable Godot controls.
var heading := ""

func _ready() -> void:
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = 20
	padding.content_margin_right = 20
	padding.content_margin_top = 36
	padding.content_margin_bottom = 16
	add_theme_stylebox_override("panel", padding)
	resized.connect(queue_redraw)

func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var cell := font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var height := font.get_height(font_size)
	var columns := maxi(4, int(size.x / cell))
	var title := "┌─ " + heading.to_upper() + " "
	var top := title + "─".repeat(maxi(0, columns - title.length() - 1)) + "┐"
	draw_string(font, Vector2(0, font.get_ascent(font_size)), top, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, RVTerminalTheme.DIM)
	draw_string(font, Vector2(0, size.y - font.get_descent(font_size)), "└" + "─".repeat(columns - 2) + "┘", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, RVTerminalTheme.DIM)
	var y := height + font.get_ascent(font_size)
	while y < size.y - height:
		draw_string(font, Vector2(0, y), "│", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, RVTerminalTheme.DIM)
		draw_string(font, Vector2((columns - 1) * cell, y), "│", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, RVTerminalTheme.DIM)
		y += height

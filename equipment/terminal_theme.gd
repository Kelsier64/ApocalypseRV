extends RefCounted
class_name RVTerminalTheme

const FONT = preload("res://assets/fonts/NotoSansMono-Regular.ttf")
const INK := Color("d8dee9")
const DIM := Color("8995a6")
const CYAN := Color("62d8df")
const AMBER := Color("edc967")
const GREEN := Color("70dc99")
const BACKGROUND := Color("101419")

static func style(fill: Color, margin: float = 8.0) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_content_margin(side, margin)
	return result

static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 20
	for type in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit", "SpinBox", "RichTextLabel", "PopupMenu"]:
		theme.set_color("font_color", type, INK)
	for type in ["Button", "CheckButton", "OptionButton"]:
		theme.set_stylebox("normal", type, style(Color.TRANSPARENT))
		theme.set_stylebox("disabled", type, style(Color.TRANSPARENT))
		theme.set_stylebox("hover", type, style(Color("26333c")))
		theme.set_stylebox("pressed", type, style(AMBER))
		theme.set_stylebox("focus", type, style(AMBER))
		theme.set_color("font_focus_color", type, BACKGROUND)
		theme.set_color("font_pressed_color", type, BACKGROUND)
		theme.set_color("font_disabled_color", type, DIM)
	# ON is a value, not an interaction highlight. Keep the focus style so
	# keyboard users can still locate an enabled toggle when navigating.
	theme.set_stylebox("pressed", "CheckButton", style(Color.TRANSPARENT))
	theme.set_stylebox("hover_pressed", "CheckButton", style(Color("26333c")))
	theme.set_color("font_pressed_color", "CheckButton", INK)
	theme.set_color("font_hover_pressed_color", "CheckButton", INK)
	var empty := PlaceholderTexture2D.new()
	empty.size = Vector2.ZERO
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		theme.set_icon(icon, "CheckButton", empty)
	for type in ["LineEdit", "RichTextLabel"]:
		theme.set_stylebox("normal", type, style(Color.TRANSPARENT, 0))
		theme.set_stylebox("focus", type, style(Color.TRANSPARENT, 0))
		theme.set_color("caret_color", type, INK)
		theme.set_color("selection_color", type, AMBER)
		theme.set_color("font_selected_color", type, BACKGROUND)
	theme.set_stylebox("panel", "PopupMenu", style(BACKGROUND))
	theme.set_stylebox("hover", "PopupMenu", style(AMBER))
	theme.set_color("font_hover_color", "PopupMenu", BACKGROUND)
	return theme

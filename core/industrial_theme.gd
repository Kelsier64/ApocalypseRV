extends RefCounted
class_name IndustrialTheme
## Presentation only; shared by native-resolution controls, never the 3D filter.
const INK := Color("dfdccb")
const AMBER := Color("c1a46b")
const BACKGROUND := Color("151b1d")
const BORDER := Color("65665a")
static var cached: Dictionary = {}

static func box(fill: Color, edge: Color = BORDER, margin: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_content_margin_all(margin)
	return style

static func make(size: int = 22) -> Theme:
	if cached.has(size): return cached[size]
	var theme := Theme.new()
	theme.default_font_size = size
	# Keep Godot's bundled font and fallback chain, including Chinese glyphs.
	for type in ["Label", "Button", "CheckButton", "LineEdit", "RichTextLabel"]:
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, Color("fff2d2"))
		theme.set_color("font_focus_color", type, Color("fff2d2"))
		theme.set_color("font_disabled_color", type, Color("85897f"))
	theme.set_stylebox("normal", "Button", box(BACKGROUND))
	theme.set_stylebox("hover", "Button", box(Color("303831"), AMBER))
	theme.set_stylebox("pressed", "Button", box(Color("4b4637"), AMBER))
	theme.set_stylebox("disabled", "Button", box(Color("191e20"), Color("3a423e")))
	var focus := box(Color(0, 0, 0, 0), AMBER)
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("panel", "PanelContainer", box(Color(0.06, 0.08, 0.085, 0.94)))
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	cached[size] = theme
	return theme

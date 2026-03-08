extends CanvasLayer

var health_bar: ProgressBar
var health_label: Label
var damage_flash: ColorRect

func _ready():
	# Create the UI elements programmatically
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	health_label = Label.new()
	health_label.text = "HP: 100 / 100"
	health_label.add_theme_font_size_override("font_size", 18)
	health_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	vbox.add_child(health_label)
	
	health_bar = ProgressBar.new()
	health_bar.min_value = 0
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.custom_minimum_size = Vector2(200, 20)
	health_bar.show_percentage = false
	
	# Style the bar
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.8, 0.15, 0.1)
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	health_bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	health_bar.add_theme_stylebox_override("background", bg_style)
	
	vbox.add_child(health_bar)
	
	# Damage flash (full-screen red overlay)
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)

func set_health(current: float, maximum: float):
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current
	if health_label:
		health_label.text = "HP: " + str(int(current)) + " / " + str(int(maximum))
	
	# Flash red on damage
	if damage_flash:
		damage_flash.color = Color(0.8, 0.0, 0.0, 0.3)
		var tween = create_tween()
		tween.tween_property(damage_flash, "color:a", 0.0, 0.3)

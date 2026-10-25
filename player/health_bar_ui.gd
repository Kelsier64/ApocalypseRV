extends CanvasLayer

var health_bar: ProgressBar
var health_label: Label
var stamina_bar: ProgressBar
var stamina_label: Label
var food_bar: ProgressBar
var food_label: Label
var food_penalty: Label
var damage_flash: ColorRect

func _ready():
	HUDVisibility.attach(self)
	var screen := Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	# Create the UI elements programmatically
	var margin = MarginContainer.new()
	margin.theme = IndustrialTheme.make(18)
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	screen.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	health_label = Label.new()
	health_label.text = "HP: 100 / 100"
	health_label.add_theme_font_size_override("font_size", 18)
	health_label.add_theme_color_override("font_color", IndustrialTheme.INK)
	vbox.add_child(health_label)
	
	health_bar = ProgressBar.new()
	health_bar.min_value = 0
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.custom_minimum_size = Vector2(200, 20)
	health_bar.show_percentage = false
	
	# Style the bar
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color("a5543e")
	health_bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = IndustrialTheme.BACKGROUND
	bg_style.border_color = IndustrialTheme.BORDER
	bg_style.set_border_width_all(1)
	health_bar.add_theme_stylebox_override("background", bg_style)
	
	vbox.add_child(health_bar)

	stamina_label = Label.new()
	stamina_label.text = "STA: 100 / 100"
	stamina_label.add_theme_font_size_override("font_size", 18)
	stamina_label.add_theme_color_override("font_color", IndustrialTheme.INK)
	vbox.add_child(stamina_label)

	stamina_bar = ProgressBar.new()
	stamina_bar.min_value = 0
	stamina_bar.max_value = 100
	stamina_bar.value = 100
	stamina_bar.custom_minimum_size = Vector2(200, 14)
	stamina_bar.show_percentage = false
	var stamina_fill = StyleBoxFlat.new()
	stamina_fill.bg_color = IndustrialTheme.AMBER
	stamina_bar.add_theme_stylebox_override("fill", stamina_fill)
	stamina_bar.add_theme_stylebox_override("background", bg_style)
	vbox.add_child(stamina_bar)
	food_label = Label.new()
	vbox.add_child(food_label)
	food_bar = ProgressBar.new()
	food_bar.max_value = PlayerSurvival.MAX_HUNGER
	food_bar.custom_minimum_size = Vector2(200, 14)
	food_bar.show_percentage = false
	food_bar.add_theme_stylebox_override("background", bg_style)
	vbox.add_child(food_bar)
	food_penalty = Label.new()
	food_penalty.add_theme_font_size_override("font_size", 14)
	vbox.add_child(food_penalty)
	set_food(PlayerSurvival.MAX_HUNGER)
	
	# Damage flash (full-screen red overlay)
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(damage_flash)
	UILayout.attach(self, screen)

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

func set_stamina(current: float, maximum: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = maximum
		stamina_bar.value = current
	if stamina_label:
		stamina_label.text = "STA: %d / %d" % [ceili(current), int(maximum)]

func set_food(current: float) -> void:
	if not food_bar: return
	food_bar.value = current
	food_label.text = "FOOD: %d / 100" % ceili(current)
	var color := Color("c6503e") if current <= 20.0 else (IndustrialTheme.AMBER if current < 40.0 else IndustrialTheme.INK)
	food_label.add_theme_color_override("font_color", color)
	food_penalty.add_theme_color_override("font_color", color)
	food_penalty.text = "Starving: -1 HP / 5s" if current <= 0.0 else ("No sprint · Slow stamina recovery" if current <= 20.0 else ("Slow stamina recovery" if current < 40.0 else ""))
	food_penalty.visible = current < 40.0
	var fill := food_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill == null or fill.bg_color != color:
		fill = StyleBoxFlat.new()
		fill.bg_color = color
		food_bar.add_theme_stylebox_override("fill", fill)

extends Control
## Physical LCD artwork, shared by the world mesh and first-person mesh copies.
const FONT = preload("res://assets/fonts/NotoSansMono-Regular.ttf")
const INK := Color(0.40, 0.96, 0.77)
const DIM := Color(0.12, 0.36, 0.31)
var angle := 0.0
var distance := -1.0
var status := "STANDBY"

func show_reading(new_angle: float, new_distance: float, new_status: String) -> void:
	if is_equal_approx(angle, new_angle) and ceili(distance) == ceili(new_distance) and status == new_status: return
	angle = new_angle
	distance = new_distance
	status = new_status
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.045, 0.041))
	for y in range(0, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.12))
	draw_string(FONT, Vector2(18, 32), "BLDG", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	# A building glyph identifies the target without a floating world marker.
	for column in 3:
		draw_rect(Rect2(204 + column * 11, 13 - column * 3, 8, 19 + column * 3), INK)
	draw_line(Vector2(16, 45), Vector2(240, 45), DIM, 2)
	var center := Vector2(128, 153)
	draw_arc(center, 78, 0.0, TAU, 64, DIM, 2, true)
	for tick in 24:
		var direction := Vector2.UP.rotated(tick * TAU / 24.0)
		draw_line(center + direction * 69, center + direction * (79 if tick % 6 == 0 else 75), INK if tick % 6 == 0 else DIM, 2, true)
	if distance >= 0.0:
		var points := PackedVector2Array()
		for point in [Vector2(0, -59), Vector2(31, 30), Vector2(0, 15), Vector2(-31, 30)]:
			points.append(center + point.rotated(angle))
		draw_colored_polygon(points, INK)
		draw_circle(center, 4, Color(0.025, 0.12, 0.10))
	else:
		draw_line(center - Vector2(19, 0), center + Vector2(19, 0), DIM, 4)
	var reading := "%d m" % ceili(distance) if distance >= 0.0 else "-- m"
	_centered(reading, 278, 36, INK)
	draw_line(Vector2(16, 292), Vector2(240, 292), DIM, 2)
	_centered(status, 316, 20, INK if distance >= 0.0 else DIM)

func _centered(value: String, baseline: float, font_size: int, color: Color) -> void:
	var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(FONT, Vector2((size.x - width) * 0.5, baseline), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

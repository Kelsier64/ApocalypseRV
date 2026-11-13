extends SceneTree
## Offline authoring source for the printed RV instrument faces and lamp symbols in assets/rv_status/.
## Run: godot --headless --path . -s scripts/build_rv_instrument_art.gd
## Dial sweeps are read from rv/instrument_cluster.gd so print and needles cannot drift apart.
const Cluster := preload("res://rv/instrument_cluster.gd")
const PRINT := "#e8e4cf"
const DIM := "#9aa39a"
const RED := "#e2553a"
const FACE := "#090d0e"
# Stroke lettering in a 10 x 16 box, the way gauge faces are pad-printed.
const GLYPHS := {
	"0": "M5 0C1.9 0 0 3 0 8S1.9 16 5 16S10 13 10 8S8.1 0 5 0Z",
	"1": "M2.2 3.4L6.2 0V16",
	"2": "M0.5 4.2C0.5 1.6 2.4 0 5 0S9.5 1.6 9.5 4.4C9.5 7 7.4 8.8 0.4 16H10",
	"3": "M0.8 2.6C1.8 0.9 3.3 0 5.1 0C7.7 0 9.4 1.6 9.4 3.9C9.4 6.2 7.7 7.6 4.6 7.6C7.9 7.6 10 9.2 10 11.8C10 14.3 8 16 5.1 16C2.9 16 1.2 15 0.3 13.2",
	"4": "M7.4 16V0L0 11.2H10",
	"5": "M9.2 0H1.9L1 7C2.2 6 3.6 5.6 5.1 5.6C8 5.6 10 7.7 10 10.7C10 13.8 8 16 5 16C3 16 1.2 15 0.3 13.3",
	"6": "M8.9 1.3C7.9 0.4 6.8 0 5.6 0C2.2 0 0 3.2 0 9C0 13.5 1.8 16 5 16C7.9 16 10 14 10 11C10 8.1 8 6.2 5.2 6.2C2.6 6.2 0.6 7.8 0.1 10",
	"7": "M0 0H10L3.6 16",
	"8": "M5 7.6C2.4 7.6 0.8 6.1 0.8 3.9C0.8 1.6 2.5 0 5 0S9.2 1.6 9.2 3.9C9.2 6.1 7.6 7.6 5 7.6C2 7.6 0 9.3 0 11.8C0 14.3 2 16 5 16S10 14.3 10 11.8C10 9.3 8 7.6 5 7.6Z",
	"9": "M1.1 14.7C2.1 15.6 3.2 16 4.4 16C7.8 16 10 12.8 10 7C10 2.5 8.2 0 5 0C2.1 0 0 2 0 5C0 7.9 2 9.8 4.8 9.8C7.4 9.8 9.4 8.2 9.9 6",
	"E": "M9.5 0H0.5V16H9.5M0.5 7.8H7.4",
	"F": "M9.5 0H0.5V16M0.5 7.8H7.4",
	"R": "M0.5 16V0H5.8C8.3 0 9.8 1.7 9.8 4.2S8.3 8.4 5.8 8.4H0.5M5.4 8.4L10 16",
	"N": "M0.5 16V0L9.5 16V0",
	"K": "M0.5 0V16M9.6 0L0.5 9.4M3.8 6L10 16",
	"M": "M0 16V0L5 9.5L10 0V16",
	"H": "M0.5 0V16M9.5 0V16M0.5 7.8H9.5",
	"P": "M0.5 16V0H5.8C8.3 0 9.8 1.8 9.8 4.4S8.3 8.8 5.8 8.8H0.5",
	"X": "M0.5 0L9.5 16M9.5 0L0.5 16",
	"/": "M8.6 -1L1.4 17",
}
# Solid pictograms on a 64 x 64 grid; INK is replaced by the colour. Shapes are filled
# and strokes are heavy so a lamp still reads at about 16 screen pixels.
const ICONS := {
	"engine": '<path fill="INK" d="M14 26H24V19H44V26H52V48H14ZM4 31H14V43H4ZM52 32H60V42H52ZM25 10H43V16H25ZM31 16H37V19H31Z"/>',
	"fuel": '<path fill="INK" fill-rule="evenodd" d="M10 8H38V50H10ZM16 14H32V27H16Z"/><path fill="INK" d="M6 50H42V57H6Z"/><path fill="none" stroke="INK" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round" d="M38 24L48 32V46A5 5 0 0 0 58 46V24L50 15"/>',
	"battery": '<path fill="INK" fill-rule="evenodd" d="M5 22H59V54H5ZM12 35H26V41H12ZM38 35H43V30H49V35H54V41H49V46H43V41H38Z"/><path fill="INK" d="M12 13H25V22H12ZM39 13H52V22H39Z"/>',
	"door": '<path fill="none" stroke="INK" stroke-width="6" stroke-linejoin="round" d="M11 9H35V55H11Z"/><path fill="INK" d="M35 6L56 15V61L35 58Z"/>',
	"brake": '<circle cx="32" cy="32" r="16" fill="none" stroke="INK" stroke-width="5.5"/><path fill="none" stroke="INK" stroke-width="5.5" stroke-linecap="round" d="M9 14A28 28 0 0 0 9 50M55 14A28 28 0 0 1 55 50"/><path fill="none" stroke="INK" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round" d="M27 42V22H34A6 6 0 0 1 34 34H27"/>',
	"tire": '<path fill="none" stroke="INK" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round" d="M17 8C7 24 7 40 17 52H47C57 40 57 24 47 8"/><path fill="none" stroke="INK" stroke-width="5" stroke-linecap="round" d="M19 60V57M32 60V57M45 60V57"/><path fill="none" stroke="INK" stroke-width="7" stroke-linecap="round" d="M32 16V33"/><circle cx="32" cy="43.5" r="4.2" fill="INK"/>',
	"ramp": '<path fill="INK" d="M46 6H60V54H46ZM4 54L46 28V54Z"/><path fill="none" stroke="INK" stroke-width="5" stroke-linecap="round" d="M3 60H61"/>',
	"headlight": '<path fill="INK" d="M30 12C52 12 60 20 60 32S52 52 30 52Z"/><path fill="none" stroke="INK" stroke-width="6" stroke-linecap="round" d="M5 17L21 21M5 32H21M5 47L21 43"/>',
	"charging": '<path fill="INK" d="M38 4L12 36H29L24 60L52 26H35Z"/>',
}

func _init() -> void:
	var folder := "res://assets/rv_status/"
	_write(folder + "dial_speed.svg", _round_dial(512, 140.0, 20.0, 10.0, -1.0, "KM/H", 1.0))
	_write(folder + "dial_rpm.svg", _round_dial(512, Cluster.RPM_FULL_SCALE, 1000.0, 500.0, Chassis.ENGINE_REDLINE_RPM, "X1000 RPM", 0.001))
	_write(folder + "dial_fuel.svg", _level_dial(256, "fuel"))
	_write(folder + "dial_battery.svg", _level_dial(256, "battery"))
	for id: String in ICONS:
		_write(folder + id + ".svg", '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64">%s</svg>' % _icon(id, "#ffffff"))
	_write(folder + "gear_strip.svg", _gear_strip())
	quit()

func _icon(id: String, color: String) -> String:
	return (ICONS[id] as String).replace("INK", color)

func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body + "\n")
	file.close()
	print("WROTE: ", path)

## Direction on the face for a needle rotation, in SVG coordinates (y down).
func _dir(needle_rotation: float) -> Vector2:
	return Vector2(-sin(needle_rotation), -cos(needle_rotation))

func _tick(center: Vector2, needle_rotation: float, outer: float, inner: float, width: float, color: String) -> String:
	var a := center + _dir(needle_rotation) * outer
	var b := center + _dir(needle_rotation) * inner
	return '<path d="M%.2f %.2fL%.2f %.2f" stroke="%s" stroke-width="%.1f"/>' % [a.x, a.y, b.x, b.y, color, width]

func _arc(center: Vector2, from_rotation: float, to_rotation: float, radius: float, width: float, color: String) -> String:
	var points := PackedStringArray()
	for i in range(25):
		var p := center + _dir(lerpf(from_rotation, to_rotation, i / 24.0)) * radius
		points.append("%.2f,%.2f" % [p.x, p.y])
	return '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.1f"/>' % [" ".join(points), color, width]

func _text(value: String, center: Vector2, height: float, weight: float, color: String) -> String:
	var scale := height / 16.0
	var advance := 13.2
	var width := (value.length() - 1) * advance + 10.0
	var out := '<g transform="translate(%.2f %.2f) scale(%.4f)" fill="none" stroke="%s" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round">' % [center.x - width * scale * 0.5, center.y - height * 0.5, scale, color, weight / scale]
	for i in range(value.length()):
		var glyph: String = value[i]
		if glyph == " ": continue
		out += '<path transform="translate(%.1f 0)" d="%s"/>' % [i * advance, GLYPHS[glyph]]
	return out + "</g>"

func _face(size: int) -> String:
	var r := size * 0.5
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><circle cx="%.0f" cy="%.0f" r="%.0f" fill="%s"/><circle cx="%.0f" cy="%.0f" r="%.1f" fill="none" stroke="#1b2325" stroke-width="%.1f"/>' % [size, size, size, size, r, r, r, FACE, r, r, r * 0.965, r * 0.012]

func _round_dial(size: int, full_scale: float, major: float, minor: float, redline: float, unit: String, label_scale: float) -> String:
	var r := size * 0.5
	var c := Vector2(r, r)
	var out := _face(size)
	if redline > 0.0:
		out += _arc(c, Cluster.dial_rotation(redline / full_scale), Cluster.dial_rotation(1.0), r * 0.895, r * 0.07, RED)
	var value := 0.0
	while value <= full_scale + 0.001:
		var rotation := Cluster.dial_rotation(value / full_scale)
		var is_major := is_zero_approx(fmod(value, major))
		var color := RED if redline > 0.0 and value >= redline else PRINT
		out += _tick(c, rotation, r * 0.93, r * (0.77 if is_major else 0.85), r * (0.036 if is_major else 0.018), color)
		if is_major:
			out += _text(str(roundi(value * label_scale)), c + _dir(rotation) * r * 0.57, r * 0.175, r * 0.034, PRINT)
		value += minor
	var words := unit.split(" ")
	for i in range(words.size()):
		out += _text(words[i], c + Vector2(0, r * (0.27 + i * 0.14)), r * 0.085, r * 0.016, DIM)
	return out + "</svg>"

func _level_dial(size: int, id: String) -> String:
	var r := size * 0.5
	var c := Vector2(r, r)
	var out := _face(size)
	out += _arc(c, Cluster.level_rotation(0.0), Cluster.level_rotation(0.18), r * 0.86, r * 0.1, RED)
	for i in range(9):
		var ratio := i / 8.0
		var is_major := i % 4 == 0
		out += _tick(c, Cluster.level_rotation(ratio), r * 0.92, r * (0.68 if is_major else (0.76 if i % 2 == 0 else 0.82)), r * (0.06 if is_major else 0.032), PRINT)
	# Letters sit beside the hub, outside the needle sweep.
	out += _text("E", c + Vector2(-r * 0.56, r * 0.06), r * 0.26, r * 0.048, PRINT)
	out += _text("F", c + Vector2(r * 0.56, r * 0.06), r * 0.26, r * 0.048, PRINT)
	var icon_scale := r * 0.44 / 64.0
	out += '<g transform="translate(%.2f %.2f) scale(%.4f)">%s</g>' % [r - 32.0 * icon_scale, r * 1.34, icon_scale, _icon(id, DIM)]
	return out + "</svg>"

## One cell per gear in Cluster.GEAR_GLYPHS order; the cluster offsets UVs to pick a cell.
func _gear_strip() -> String:
	var cell := Vector2(96, 128)
	var count := Cluster.GEAR_GLYPHS.length()
	var out := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [cell.x * count, cell.y, cell.x * count, cell.y]
	for i in range(count):
		out += _text(Cluster.GEAR_GLYPHS[i], Vector2(cell.x * (i + 0.5), cell.y * 0.5), 84.0, 12.0, "#ffffff")
	return out + "</svg>"

extends RefCounted
## Camera rail: a centripetal Catmull-Rom spline through keyframes, travelled at constant speed.
## Only the start and end ease, so the camera never stops at an inner keyframe.

const SAMPLES_PER_SEGMENT := 32
const MIN_DURATION := 1.0
const MAX_DURATION := 120.0

enum Source { NONE, GENERATED, SAVED, EDITED }

var keys: Array[Dictionary] = []
var duration := 8.0
var ease_ends := true
var source := Source.NONE
var _lengths := PackedFloat32Array()
var _dirty := true

func size() -> int:
	return keys.size()

func playable() -> bool:
	return keys.size() >= 2

func authored() -> bool:
	return source == Source.SAVED or source == Source.EDITED

func clear(next_source := Source.EDITED) -> void:
	keys.clear()
	source = next_source
	_dirty = true

func add(frame: Transform3D, fov: float, next_source := Source.EDITED) -> void:
	var rotation := frame.basis.orthonormalized().get_rotation_quaternion()
	# Keep neighbouring quaternions in one hemisphere so the spline takes the short way.
	if not keys.is_empty() and (keys.back().rotation as Quaternion).dot(rotation) < 0.0: rotation = -rotation
	keys.append({"position": frame.origin, "rotation": rotation, "fov": fov})
	source = next_source
	_dirty = true

func remove_last() -> void:
	if keys.is_empty(): return
	keys.pop_back()
	source = Source.EDITED
	_dirty = true

func set_duration(seconds: float) -> void:
	duration = clampf(seconds, MIN_DURATION, MAX_DURATION)
	if source != Source.NONE: source = Source.EDITED

## progress 0..1 over the whole rail. Returns {transform, fov}.
func sample(progress: float) -> Dictionary:
	if keys.is_empty(): return {}
	if keys.size() == 1: return {"transform": _frame(0), "fov": float(keys[0].fov)}
	var t := clampf(progress, 0.0, 1.0)
	if ease_ends: t = _ease(t)
	var located := _locate(t)
	var segment: int = located.x
	var weight: float = located.y
	var a := keys[maxi(segment - 1, 0)]
	var b := keys[segment]
	var c := keys[segment + 1]
	var d := keys[mini(segment + 2, keys.size() - 1)]
	var knots := _knots(segment)
	var span := knots[2] - knots[1]
	var rotation: Quaternion = (b.rotation as Quaternion).spherical_cubic_interpolate_in_time(c.rotation, a.rotation, d.rotation, weight, span, knots[0] - knots[1], knots[3] - knots[1])
	var fov := cubic_interpolate_in_time(float(b.fov), float(c.fov), float(a.fov), float(d.fov), weight, span, knots[0] - knots[1], knots[3] - knots[1])
	return {"transform": Transform3D(Basis(rotation.normalized()), _point(segment, weight)), "fov": fov}

func to_data() -> Dictionary:
	var rows: Array = []
	for key in keys:
		var p: Vector3 = key.position
		var q: Quaternion = key.rotation
		rows.append([p.x, p.y, p.z, q.x, q.y, q.z, q.w, key.fov])
	return {"duration": duration, "ease_ends": ease_ends, "keys": rows}

func from_data(data: Variant, next_source := Source.SAVED) -> bool:
	if not data is Dictionary or not data.get("keys") is Array: return false
	var loaded: Array[Dictionary] = []
	for row in data.keys:
		if not row is Array or row.size() != 8: return false
		if not row.all(func(value): return (value is float or value is int) and is_finite(float(value))): return false
		var rotation := Quaternion(row[3], row[4], row[5], row[6])
		if rotation.length_squared() <= 0.001: return false
		loaded.append({"position": Vector3(row[0], row[1], row[2]), "rotation": rotation.normalized(), "fov": float(row[7])})
	keys.clear()
	for key in loaded: add(Transform3D(Basis(key.rotation), key.position), key.fov, next_source)
	duration = clampf(float(data.get("duration", duration)), MIN_DURATION, MAX_DURATION)
	ease_ends = bool(data.get("ease_ends", true))
	source = next_source
	return true

func load_file(path: String) -> bool:
	if not FileAccess.file_exists(path): return false
	return from_data(JSON.parse_string(FileAccess.get_file_as_string(path)))

func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null: return FileAccess.get_open_error()
	output.store_string(JSON.stringify(to_data(), "  ") + "\n")
	output.close()
	source = Source.SAVED
	return OK

func _frame(index: int) -> Transform3D:
	return Transform3D(Basis(keys[index].rotation), keys[index].position)

## Ramp speed up over the first and down over the last part; constant in between.
static func _ease(t: float) -> float:
	const RAMP := 0.18
	# Piecewise: quadratic ramps joined to a linear middle, continuous in speed.
	var peak := 1.0 / (1.0 - RAMP)
	if t < RAMP: return peak * t * t / (2.0 * RAMP)
	if t > 1.0 - RAMP:
		var r := 1.0 - t
		return 1.0 - peak * r * r / (2.0 * RAMP)
	return peak * (t - RAMP * 0.5)

## Maps rail progress to (segment, weight) by arc length.
func _locate(t: float) -> Vector2:
	if _dirty: _measure()
	var total := _lengths[_lengths.size() - 1]
	var segments := keys.size() - 1
	if total <= 0.001:
		# Rotation-only rail: spread time evenly across the keyframes.
		var scaled := t * segments
		var index := mini(floori(scaled), segments - 1)
		return Vector2(index, scaled - index)
	var goal := t * total
	var low := 0
	var high := _lengths.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if _lengths[middle] < goal: low = middle
		else: high = middle
	var span := _lengths[high] - _lengths[low]
	var fraction := 0.0 if span <= 0.0 else (goal - _lengths[low]) / span
	var step := float(low) + fraction
	var segment := mini(floori(step / SAMPLES_PER_SEGMENT), segments - 1)
	return Vector2(segment, clampf(step / SAMPLES_PER_SEGMENT - segment, 0.0, 1.0))

func _measure() -> void:
	_lengths = PackedFloat32Array([0.0])
	var total := 0.0
	for segment in keys.size() - 1:
		var previous := _point(segment, 0.0)
		for step in range(1, SAMPLES_PER_SEGMENT + 1):
			var point := _point(segment, float(step) / SAMPLES_PER_SEGMENT)
			total += point.distance_to(previous)
			_lengths.append(total)
			previous = point
	_dirty = false

## Control points of a segment; missing end neighbours are mirrored so the
## first and last segments keep a natural tangent.
func _controls(segment: int) -> Array[Vector3]:
	var b: Vector3 = keys[segment].position
	var c: Vector3 = keys[segment + 1].position
	var a: Vector3 = keys[segment - 1].position if segment > 0 else b + (b - c)
	var d: Vector3 = keys[segment + 2].position if segment + 2 < keys.size() else c + (c - b)
	return [a, b, c, d]

## Centripetal knot times: uneven key spacing never overshoots or doubles back.
func _knots(segment: int) -> PackedFloat32Array:
	var p := _controls(segment)
	var times := PackedFloat32Array([0.0])
	for i in 3: times.append(times[i] + maxf(sqrt(p[i].distance_to(p[i + 1])), 0.0001))
	return times

func _point(segment: int, weight: float) -> Vector3:
	var p := _controls(segment)
	var k := _knots(segment)
	var t := lerpf(k[1], k[2], weight)
	var a1 := p[0].lerp(p[1], (t - k[0]) / (k[1] - k[0]))
	var a2 := p[1].lerp(p[2], (t - k[1]) / (k[2] - k[1]))
	var a3 := p[2].lerp(p[3], (t - k[2]) / (k[3] - k[2]))
	var b1 := a1.lerp(a2, (t - k[0]) / (k[2] - k[0]))
	var b2 := a2.lerp(a3, (t - k[1]) / (k[3] - k[1]))
	return b1.lerp(b2, (t - k[1]) / (k[2] - k[1]))

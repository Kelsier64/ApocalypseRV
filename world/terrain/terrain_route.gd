extends RefCounted
class_name TerrainRoute
## A graph x=f(s), z=-s: every cross-section advances into new world space.
## Curvature and width bounds keep the offset carriageway from folding too.
var profile: WorldProfile
var phase: float
var handedness: float
var long_wave: float
var short_wave: float
const HEIGHT_STEP := 5.0
var _height_knots: Array[float] = [0.0]
var _height_slopes: Array[float] = [0.0]

func _init(field: WorldField) -> void:
	profile = field.profile
	var rng := field.rng_for(0, "terrain_route", 13)
	phase = rng.randf_range(-PI, PI)
	handedness = -1.0 if rng.randf() < 0.5 else 1.0
	long_wave = rng.randf_range(5600.0, 6400.0)
	short_wave = rng.randf_range(500.0, 560.0)

func x(s: float) -> float:
	var scale := sqrt(maxf(36.0, profile.min_turn_radius) / 36.0)
	var t := s / scale
	var fade := smoothstep(450.0, 1050.0, t)
	return handedness * fade * (156.0 * sin(t * TAU / short_wave + phase) + 24.0 * sin(t * TAU / 1500.0 - phase))

func _curve(s: float) -> Vector3:
	# Analytic derivatives keep nearest-point queries stable at the tight apexes.
	var scale := sqrt(maxf(36.0, profile.min_turn_radius) / 36.0)
	var t := s / scale
	var k := TAU / short_wave
	var k2 := TAU / 1500.0
	var a := t * k + phase
	var b := t * k2 - phase
	var value := handedness * (156.0 * sin(a) + 24.0 * sin(b))
	var first := handedness * (156.0 * k * cos(a) + 24.0 * k2 * cos(b)) / scale
	var second := -handedness * (156.0 * k * k * sin(a) + 24.0 * k2 * k2 * sin(b)) / (scale * scale)
	var u := clampf((t - 450.0) / 600.0, 0.0, 1.0)
	var fade := u * u * (3.0 - 2.0 * u)
	var df := 0.0
	var ddf := 0.0
	if u > 0.0 and u < 1.0:
		df = 6.0 * u * (1.0 - u) / (600.0 * scale)
		ddf = 6.0 * (1.0 - 2.0 * u) / pow(600.0 * scale, 2.0)
	return Vector3(value * fade, value * df + first * fade, value * ddf + 2.0 * first * df + second * fade)

func height(s: float) -> float:
	if s <= 450.0: return 0.0
	var t := (s - 450.0) / HEIGHT_STEP
	var index := floori(t)
	# Always integrate in world order, including when a distant band is queried
	# first. Grade is measured along the actual winding road, not its Z advance.
	while _height_knots.size() <= index + 1:
		var previous := _height_knots.size() - 1
		var start := 450.0 + previous * HEIGHT_STEP
		var next := _vertical_slope(start + HEIGHT_STEP)
		var middle := _vertical_slope(start + HEIGHT_STEP * 0.5)
		_height_knots.append(_height_knots[previous] + HEIGHT_STEP / 6.0 * (_height_slopes[previous] + 4.0 * middle + next))
		_height_slopes.append(next)
	var u := t - index
	# Cubic Hermite interpolation preserves continuous road pitch at every knot.
	return (2.0 * u * u * u - 3.0 * u * u + 1.0) * _height_knots[index] + (u * u * u - 2.0 * u * u + u) * HEIGHT_STEP * _height_slopes[index] + (-2.0 * u * u * u + 3.0 * u * u) * _height_knots[index + 1] + (u * u * u - u * u) * HEIGHT_STEP * _height_slopes[index + 1]

func _vertical_slope(s: float) -> float:
	var grade := profile.max_grade * 0.90 * sin((s - 450.0) * TAU / long_wave)
	var slope := float(_curve(s).y)
	return grade * sqrt(1.0 + slope * slope)

func width(s: float) -> float:
	var blend := smoothstep(300.0, 700.0, s)
	var wave := 0.5 + 0.32 * sin(s * TAU / 960.0 + phase) + 0.18 * sin(s * TAU / 430.0 - phase)
	var target := lerpf(profile.narrow_width * 0.72, profile.road_width * 1.30, smoothstep(0.12, 0.88, wave))
	return lerpf(profile.road_width, target, blend)

func query(px: float, pz: float) -> Dictionary:
	# Nearby road queries use Newton projection with a curvature-aware Hessian.
	# Far-off terrain uses several bounded seeds to avoid a different local root.
	var best_s := -pz
	var best_distance := INF
	# Stay inside the tightest bend's reach before taking the single-root path.
	# Beyond it, the apex can be a stationary maximum instead of the nearest road.
	var starts := [0.0] if absf(px - x(-pz)) < 20.0 else [-220.0, 0.0, 220.0]
	for start: float in starts:
		var s := -pz + start
		for iteration in range(8):
			var curve := _curve(s)
			var center := float(curve.x)
			var slope := float(curve.y)
			var second := float(curve.z)
			var hessian := maxf(0.25, 1.0 + slope * slope + (center - px) * second)
			var correction := clampf(((center - px) * slope + s + pz) / hessian, -80.0, 80.0)
			s -= correction
			if absf(correction) < 0.001: break
		var distance := Vector2(x(s) - px, s + pz).length_squared()
		if distance < best_distance:
			best_s = s
			best_distance = distance
	var forward := Vector3(x(best_s + 0.5) - x(best_s - 0.5), 0.0, -1.0).normalized()
	var frame := Transform3D(Basis.looking_at(forward), Vector3(x(best_s), height(best_s), -best_s))
	return {"s": best_s, "distance": sqrt(best_distance), "height": frame.origin.y, "width": width(best_s), "frame": frame}

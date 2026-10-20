extends RefCounted
class_name TerrainRoute
## A graph x=f(s), z=-s: every cross-section advances into new world space.
## Curvature and width bounds keep the offset carriageway from folding too.
var profile: WorldProfile
var phase: float
var handedness: float
var long_wave: float
var short_wave: float

func _init(field: WorldField) -> void:
	profile = field.profile
	var rng := field.rng_for(0, "terrain_route")
	phase = rng.randf_range(-PI, PI)
	handedness = -1.0 if rng.randf() < 0.5 else 1.0
	long_wave = rng.randf_range(2200.0, 2600.0)
	short_wave = rng.randf_range(850.0, 1050.0)

func x(s: float) -> float:
	var scale := sqrt(maxf(80.0, profile.min_turn_radius) / 80.0)
	var t := s / scale
	var fade := smoothstep(300.0, 1200.0, t)
	return handedness * fade * (128.0 * sin(t * TAU / 1200.0 + phase) + 42.0 * sin(t * TAU / 620.0 - phase))

func height(s: float) -> float:
	var t := maxf(0.0, s - 300.0)
	# Integral of bounded grades; no accumulated knots or load-order state.
	var limit := 44.0 * TAU / long_wave + 10.0 * TAU / short_wave
	return profile.max_grade * 0.94 / limit * (44.0 * (1.0 - cos(t * TAU / long_wave)) + 10.0 * (1.0 - cos(t * TAU / short_wave)))

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
	var starts := [0.0] if absf(px - x(-pz)) < 45.0 else [-160.0, 0.0, 160.0]
	for start: float in starts:
		var s := -pz + start
		for iteration in range(6):
			var center := x(s)
			var slope := (x(s + 0.5) - x(s - 0.5))
			var second := (x(s + 0.5) - 2.0 * center + x(s - 0.5)) * 4.0
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

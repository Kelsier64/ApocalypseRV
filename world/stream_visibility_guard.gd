extends RefCounted
class_name WorldStreamVisibility
## Transient camera visibility, independent of weather and saved game time.
var limit := INF

## INF means there is no outdoor coverage provider/camera. Invalid coverage
## conceals the view; a completed band opens only with actual elapsed time.
func update(clearance: float, real_delta: float, profile: WorldAtmosphereProfile) -> float:
	var target := profile.landscape_end
	if is_nan(clearance):
		target = 1.0
	elif clearance != INF:
		target = clampf(clearance - profile.stream_margin, 1.0, target)
	if target < limit:
		limit = target
	elif is_finite(real_delta) and real_delta > 0.0:
		limit = move_toward(limit, target, real_delta * profile.stream_reveal_speed)
	return limit

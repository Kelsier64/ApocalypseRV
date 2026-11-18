class_name RVTireModel
extends RefCounted

static func grip_curve(slip: float, peak: float, sliding_fraction: float) -> float:
	var normalized := absf(slip) / maxf(peak, 0.001)
	if normalized <= 1.0:
		return normalized * (2.0 - normalized)
	return sliding_fraction + (1.0 - sliding_fraction) / normalized

static func grip_limit(profile: RVHandlingProfile, load: float, nominal_load: float, surface: float, condition: float) -> float:
	var load_factor := pow(clampf(load / maxf(1.0, nominal_load), 0.25, 3.0), -profile.tire_load_sensitivity)
	var condition_grip := profile.flat_grip if condition <= 0.0 else lerpf(0.72, 1.0, condition / 100.0)
	return maxf(0.0, load) * load_factor * surface * condition_grip

static func force(profile: RVHandlingProfile, slip: Vector2, grip: float) -> Vector2:
	var forward := signf(slip.x) * grip_curve(slip.x, profile.longitudinal_peak_slip, profile.sliding_grip_fraction)
	var lateral := signf(slip.y) * grip_curve(slip.y, profile.lateral_peak_angle, profile.sliding_grip_fraction)
	return Vector2(forward, lateral).limit_length() * grip

enum Surface { ASPHALT, SHOULDER, OFFROAD }

static func surface_grip(profile: RVHandlingProfile, field: WorldField, point: Vector3) -> float:
	match surface(field, point):
		Surface.ASPHALT: return profile.asphalt_grip
		Surface.SHOULDER: return profile.shoulder_grip
	return profile.offroad_grip

## Road surface under a point. Without a world field everything counts as asphalt.
static func surface(field: WorldField, point: Vector3) -> Surface:
	if field == null: return Surface.ASPHALT
	var road := field.road_query(point.x, point.z)
	var edge: float = road.width * 0.5
	if road.distance <= edge and absf(point.y - float(road.height)) < 1.5: return Surface.ASPHALT
	if road.distance <= edge + field.profile.road_shoulder: return Surface.SHOULDER
	return Surface.OFFROAD

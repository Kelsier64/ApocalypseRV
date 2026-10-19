extends Resource
class_name DarkAdaptationProfile
## Display configuration, independent of simulation time and native lighting.
const DEFAULT_CURVE: Curve = preload("res://world/night_vision_curve.tres")

@export_group("Distance")
@export_range(0.0, 500.0, 0.5, "or_greater", "suffix:m") var distance_begin := 0.0:
	set(value):
		if not is_finite(value): return
		distance_begin = maxf(0.0, value)
		emit_changed()
@export_range(0.01, 500.0, 0.5, "or_greater", "suffix:m") var distance_end := 60.0:
	set(value):
		if not is_finite(value): return
		distance_end = maxf(0.01, value)
		emit_changed()
## X is normalized distance, Y retains gray fill. Never rewritten at runtime.
@export var curve: Curve = DEFAULT_CURVE:
	set(value):
		if curve != null and curve.changed.is_connected(emit_changed): curve.changed.disconnect(emit_changed)
		curve = value
		_watch_curve()
		emit_changed()

@export_group("Brightness")
## Neutral material reference energy; does not change the world's ambient light.
@export_range(0.0, 1.0, 0.001) var reference_energy := 0.06:
	set(value):
		if not is_finite(value): return
		reference_energy = clampf(value, 0.0, 1.0)
		emit_changed()
## Native/reference luminance ratios. Gray fill fades smoothly between these.
@export_range(0.0, 1.0, 0.01) var dark_ratio := 0.1:
	set(value):
		if not is_finite(value): return
		dark_ratio = clampf(value, 0.0, 1.0)
		emit_changed()
@export_range(0.01, 2.0, 0.01) var lit_ratio := 1.0:
	set(value):
		if not is_finite(value): return
		lit_ratio = clampf(value, 0.01, 2.0)
		emit_changed()

func _init() -> void:
	_watch_curve()

func _watch_curve() -> void:
	if curve != null and not curve.changed.is_connected(emit_changed): curve.changed.connect(emit_changed)

func effective_curve() -> Curve:
	return curve if curve != null and curve.point_count > 0 else DEFAULT_CURVE

class_name RVWindLoad
extends RefCounted
## The weather wind pushing the RV sideways. Only the component across the
## body counts: there is no general air drag, so top speed and fuel use stay
## as they are. The force acts above and behind the centre of mass, so a
## crosswind also leans the body and yaws the nose into the wind. Nothing is
## saved and no RNG is touched: the wind is WorldClock.wind_at() at the RV.

const CLOCK_RETRY_SECONDS := 1.0
const SHAKE_RESPONSE := 6.0

## Tests and playgrounds: a world wind velocity in m/s that replaces the clock.
var velocity_override := Vector3.INF
## Last side force in newtons, world space; zero in calm air.
var force := Vector3.ZERO
## 0 to 1: how hard the side force is changing; drives the steering wheel shake.
var shake := 0.0
var _clock: WorldClock
var _clock_retry := 0.0


## Side force in newtons, world space, for a wind velocity on a body basis.
static func side_force(profile: RVHandlingProfile, wind: Vector3, basis: Basis) -> Vector3:
	var across := basis.x.slide(Vector3.UP)
	if across.length_squared() < 0.0001: return Vector3.ZERO
	across = across.normalized()
	var crossing := wind.dot(across)
	var magnitude := 0.5 * profile.air_density * profile.crosswind_coefficient * profile.crosswind_side_area * crossing * crossing
	return across * signf(crossing) * minf(magnitude, profile.crosswind_max_force)


## Pushes the body for one physics step; called from Chassis._integrate_forces.
func apply(chassis: Chassis, state: PhysicsDirectBodyState3D) -> void:
	var wind := velocity_override if velocity_override.is_finite() else _wind_at(chassis, state.transform.origin, state.step)
	var profile := chassis.handling_profile
	var next := side_force(profile, wind, state.transform.basis)
	var change := (next - force).length() / maxf(state.step, 0.0001)
	shake = lerpf(shake, clampf(change / profile.crosswind_shake_rate, 0.0, 1.0), 1.0 - exp(-state.step * SHAKE_RESPONSE))
	force = next
	if force != Vector3.ZERO:
		state.apply_force(force, state.transform.basis * profile.crosswind_center)


func _wind_at(chassis: Chassis, origin: Vector3, step: float) -> Vector3:
	if not is_instance_valid(_clock) or _clock.is_queued_for_deletion():
		_clock = null
		_clock_retry -= step
		if _clock_retry > 0.0: return Vector3.ZERO
		_clock_retry = CLOCK_RETRY_SECONDS
		var domain := WorldActorSnapshot.domain(chassis)
		_clock = domain.get_node_or_null("WorldClock") as WorldClock if domain else null
	if _clock == null or not _clock.is_node_ready() or _clock.wind.weather == null: return Vector3.ZERO
	return _clock.wind_at(origin)

extends RefCounted
class_name RVCrashDamage

var _occupant: WeakRef
var _seated := false
var _offset := Vector3.ZERO
var _incoming := Vector3.ZERO
var _result := Vector3.ZERO
var _peak := 0.0
var _settle_at := -INF
var _last_contact_at := -INF
var _event := 0

func sample(vehicle: Chassis, clock: float, state: PhysicsDirectBodyState3D, before: Vector3, before_spin: Vector3, contact_loss: float) -> void:
	if _occupant == null:
		if contact_loss < 0.75 or clock - _last_contact_at < VehicleImpact.SEPARATION_SECONDS:
			if contact_loss >= 0.75: _last_contact_at = clock
			return
		var centre := state.transform.origin + state.center_of_mass
		for player in vehicle.get_tree().get_nodes_in_group(Groups.PLAYER):
			if not player.has_method("apply_crash_hit") or player.is_player_dead: continue
			_seated = is_instance_valid(player.seated_in) and ClimbMath.find_rv_ancestor(player.seated_in) == vehicle
			if not _seated and player.rv_support.rv != vehicle and player.active_climb_rv != vehicle: continue
			_occupant = weakref(player)
			var point: Vector3 = player.seated_in.global_position if _seated else player.global_position
			_offset = state.transform.basis.inverse() * (point - centre)
			_incoming = before + before_spin.cross(point - centre)
			_peak = 0.0
			_result = Vector3.ZERO
			_settle_at = clock + VehicleImpact.EPISODE_SECONDS
			_event += 1
			break
		if _occupant == null: return
	if contact_loss >= 0.75:
		_last_contact_at = clock
		var change := _incoming - (state.linear_velocity + state.angular_velocity.cross(state.transform.basis * _offset))
		if change.length() > _peak:
			_peak = change.length()
			_result = change
	if clock < _settle_at: return
	var player := _occupant.get_ref() as Node3D
	_occupant = null
	if is_instance_valid(player):
		player.apply_crash_hit(vehicle, _event, _result.length(), _incoming, _seated)

func reset() -> void:
	_occupant = null
	_last_contact_at = -INF

static func injury(profile: RVHandlingProfile, speed_change: float, seated: bool) -> Dictionary:
	if speed_change < profile.crash_injury_speed: return {}
	var span := maxf(0.1, profile.crash_lethal_speed - profile.crash_injury_speed)
	var severity := (speed_change - profile.crash_injury_speed) / span
	var damage := (3.0 + (profile.crash_damage_at_lethal_speed - 3.0) * severity ** 1.4)
	var sever_chance := smoothstep(profile.crash_sever_speed, profile.crash_lethal_speed * 1.25, speed_change)
	return {
		"damage": damage * (profile.crash_seated_damage_scale if seated else 1.0),
		"sever_chance": sever_chance * (profile.crash_seated_sever_scale if seated else 1.0),
		"stun": profile.crash_stun_seconds if speed_change >= profile.crash_stun_speed else 0.0,
	}

static func apply(vehicle: Chassis, amount: float, slot: String, wheel: int) -> void:
	if wheel >= 0:
		vehicle.damage_tire(wheel, amount)
		return
	if slot.is_empty():
		vehicle.take_damage(amount)
		return
	var slots := vehicle.get_node_or_null("StructureSlots") as RVStructureSlots
	var part := slots.occupant(slot) if slots else null
	var engine_share := 0.5 if slot == "front" else 0.0
	if engine_share > 0.0: vehicle.take_damage(amount * engine_share)
	if part: part.take_damage(amount * (1.0 - engine_share))

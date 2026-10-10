extends RefCounted
class_name SlenderSpeakerEncounter
## One encounter identity and observed memory. Never samples transforms or seats.
## The controller supplies only sight-confirmed facts, including RV-local frames.
var decision: Dictionary = {}
var _player: Node3D
var _vehicle: Node3D
var _player_id := 0
var _vehicle_id := 0
var _mode := "none"
var _point := Vector3.ZERO
var _player_local := Vector3.ZERO
var _motion_sample_time := -1.0
var _search_offset_local := Vector3.ZERO
var _has_local := false
var _vehicle_frame := Transform3D.IDENTITY
var _remaining := 0.0
var _low_seconds := 0.0
var _high_seconds := 0.0
var _generation := 0
var _reason := "reset"
var _pending_observation: Dictionary = {}
var _pending_remaining := 0.0
var _suppressed_vehicle: Node3D
var _rearm_seconds := 0.0

func _init() -> void:
	reset()

func reset() -> void:
	_player = null
	_vehicle = null
	_player_id = 0
	_vehicle_id = 0
	_mode = "none"
	_point = Vector3.ZERO
	_motion_sample_time = -1.0
	_search_offset_local = Vector3.ZERO
	_has_local = false
	_vehicle_frame = Transform3D.IDENTITY
	_remaining = 0.0
	_low_seconds = 0.0
	_high_seconds = 0.0
	_generation = 0
	_reason = "reset"
	_pending_observation.clear()
	_pending_remaining = 0.0
	_suppressed_vehicle = null
	_rearm_seconds = 0.0
	_publish({}, false)

func update(observation: Dictionary, delta: float, settings: Resource, action_locked: bool = false) -> Dictionary:
	var elapsed := maxf(delta, 0.0)
	_cleanup_invalid()
	if _mode != "none":
		_remaining = maxf(0.0, _remaining - elapsed)
	if not _pending_observation.is_empty():
		_pending_remaining = maxf(0.0, _pending_remaining - elapsed)
	_update_suppression(observation, elapsed, settings)
	if not action_locked and not _pending_observation.is_empty():
		var same_identity := _observed_player(_pending_observation) == _player and _valid_node(_pending_observation.get("player_vehicle", _pending_observation.get("vehicle"))) == _vehicle
		var retained_remaining := _remaining if same_identity else 0.0
		_observe(_pending_observation, settings)
		_remaining = maxf(retained_remaining, minf(_remaining, _pending_remaining))
		_pending_observation.clear()
	if action_locked:
		_remember_locked(observation, settings)
	else:
		_observe(observation, settings)
	_update_speed_timers(observation, elapsed, settings)
	if not action_locked:
		if _mode == "pursuit" and _low_seconds >= settings.cabin_enter_seconds:
			_set_mode("cabin", "sustained_low_speed")
			if _observed_player(observation) != _player or _player == null:
				_remaining = settings.search_seconds
		elif _mode == "cabin" and _high_seconds >= settings.pursuit_enter_seconds:
			_set_mode("pursuit", "sustained_high_speed")
	# A visibly escaping RV is direct vehicle evidence, even if its cabin hides
	# the survivor. Cabin/ground searches require survivor sight to refresh.
	if _mode == "pursuit" and _observed_vehicle(observation) == _vehicle and _vehicle != null:
		_remaining = settings.search_seconds
	# Direct roof sight sustains an unknown-occupant inspection. A known
	# survivor keeps a bounded search before falling back to that inspection.
	if _mode == "cabin" and _player == null and _vehicle != null \
		and _observed_vehicle(observation) == _vehicle and observation.get("roof_visible", false):
		_remaining = settings.search_seconds
	if not action_locked:
		if _mode != "none" and _remaining <= 0.0:
			if _mode == "cabin" and _player != null and _vehicle != null and _observed_vehicle(observation) == _vehicle:
				_begin_unknown_roof_inspection(observation, settings)
			else:
				_suppressed_vehicle = _vehicle
				_rearm_seconds = 0.0
				_clear("search_expired")
	_publish(observation, action_locked)
	return decision.duplicate()

func _begin_unknown_roof_inspection(observation: Dictionary, settings: Resource) -> void:
	# Forget the lost survivor, not the still-observed RV. The controller now
	# uses its ordinary unknown-occupant roof plan instead of the old cabin area.
	# This supplies no hidden position, grab permission or chassis assault.
	_player = null
	_player_id = 0
	_player_local = Vector3.ZERO
	_has_local = false
	_motion_sample_time = -1.0
	_search_offset_local = Vector3.ZERO
	_point = observation.get("vehicle_point", _vehicle_frame.origin)
	_remaining = settings.search_seconds
	_pending_observation.clear()
	_pending_remaining = 0.0
	_suppressed_vehicle = null
	_rearm_seconds = 0.0
	_generation += 1
	_reason = "survivor_search_expired_roof_inspection"

func record_roof_damage(vehicle: Node3D, settings: Resource) -> void:
	# The controller validates positive damage to the committed, observed roof.
	# Progress buys another bounded inspection window, without survivor sight,
	# a new target identity, a changed search point or permission for a grab.
	if _mode == "cabin" and _valid_node(vehicle) != null and vehicle == _vehicle:
		_remaining = settings.search_seconds

func _observe(observation: Dictionary, settings: Resource) -> void:
	var seen_player := _observed_player(observation)
	var seen_vehicle := _observed_vehicle(observation)
	if seen_player != null and (_player == null or seen_player == _player or _remaining <= 0.0):
		var associated := _valid_node(observation.get("player_vehicle", observation.get("vehicle")))
		var changed := _player != seen_player or _vehicle != associated
		if changed:
			var keep_vehicle_mode := associated != null and associated == _vehicle and _mode in ["cabin", "pursuit"]
			_player = seen_player
			_vehicle = associated
			_player_id = seen_player.get_instance_id()
			_vehicle_id = associated.get_instance_id() if associated != null else 0
			_has_local = false
			if not keep_vehicle_mode:
				_low_seconds = 0.0
				_high_seconds = 0.0
			_generation += 1
			if associated == null:
				_set_mode("ground", "visible_ground_survivor")
			elif not keep_vehicle_mode:
				# Initial entry uses the upper boundary; later changes need dwell time.
				var associated_speed := absf(float(observation.get("road_speed", 0.0))) if seen_vehicle == associated else 0.0
				_set_mode("pursuit" if associated_speed > settings.pursuit_enter_speed else "cabin", "visible_vehicle_survivor")
			else:
				_reason = "visible_vehicle_survivor"
		_suppressed_vehicle = null
		_rearm_seconds = 0.0
		_remaining = settings.search_seconds
		_remember_player(observation)
	elif _mode == "none" and seen_vehicle != null and seen_vehicle != _suppressed_vehicle:
		_vehicle = seen_vehicle
		_player = null
		_player_id = 0
		_vehicle_id = seen_vehicle.get_instance_id()
		_has_local = false
		_generation += 1
		_remaining = settings.search_seconds
		_point = observation.get("vehicle_point", Vector3.ZERO)
		_low_seconds = 0.0
		_high_seconds = 0.0
		_set_mode("pursuit" if absf(float(observation.get("road_speed", 0.0))) > settings.pursuit_enter_speed else "cabin", "visible_unknown_vehicle")
	if seen_vehicle != null and seen_vehicle == _vehicle:
		_remember_vehicle(observation)

func _remember_locked(observation: Dictionary, settings: Resource) -> void:
	var seen_player := _observed_player(observation)
	var seen_vehicle := _observed_vehicle(observation)
	if seen_player != null and (_player == null or seen_player == _player or _remaining <= 0.0):
		_pending_observation = observation.duplicate()
		_pending_remaining = settings.search_seconds
		if seen_player == _player:
			_remaining = settings.search_seconds
			# A visible disembark is buffered; it cannot move the locked action's identity.
			if _valid_node(observation.get("player_vehicle", observation.get("vehicle"))) == _vehicle:
				_remember_player(observation)
	elif _mode == "none" and seen_vehicle != null and seen_vehicle != _suppressed_vehicle:
		_pending_observation = observation.duplicate()
		_pending_remaining = settings.search_seconds
	if seen_vehicle != null and seen_vehicle == _vehicle:
		_remember_vehicle(observation)

func _remember_player(observation: Dictionary) -> void:
	_point = observation.get("player_point", _point)
	if _vehicle != null and _observed_vehicle(observation) == _vehicle:
		var frame: Transform3D = observation.get("vehicle_frame", Transform3D.IDENTITY)
		var local_point := frame.affine_inverse() * _point
		var sample_time := float(observation.get("sample_time", -1.0))
		var sample_delta := sample_time - _motion_sample_time
		if observation.get("player_motion_local") is Vector3:
			# A survivor can be visible through a hatch for only one sensor sample.
			# Its sight-confirmed locomotion is still usable motion evidence.
			_search_offset_local = (Vector3(observation.player_motion_local).slide(Vector3.UP) * .5).limit_length(3.0)
		elif not _has_local or sample_time < 0.0 or sample_delta > .3:
			_search_offset_local = Vector3.ZERO
		elif sample_delta > .000001:
			# Use only successive visible positions in the observed RV frame.
			# A short bounded lead searches the next cabin area when a walking
			# survivor passes beneath its roof. It never becomes a grab target,
			# refreshes the search deadline or reads the hidden survivor's state.
			_search_offset_local = ((local_point - _player_local).slide(Vector3.UP) / sample_delta * .5).limit_length(3.0)
		_motion_sample_time = sample_time
		_player_local = local_point
		_has_local = true
	else:
		_has_local = false
		_motion_sample_time = -1.0
		_search_offset_local = Vector3.ZERO

func _remember_vehicle(observation: Dictionary) -> void:
	_vehicle_frame = observation.get("vehicle_frame", Transform3D.IDENTITY)
	if _has_local:
		_point = _vehicle_frame * _player_local
	elif _player == null:
		_point = observation.get("vehicle_point", _point)

func _update_speed_timers(observation: Dictionary, delta: float, settings: Resource) -> void:
	if _vehicle == null or _observed_vehicle(observation) != _vehicle:
		_low_seconds = 0.0
		_high_seconds = 0.0
		return
	var speed := absf(float(observation.get("road_speed", 0.0)))
	_low_seconds = _low_seconds + delta if speed < settings.cabin_enter_speed else 0.0
	_high_seconds = _high_seconds + delta if speed > settings.pursuit_enter_speed else 0.0

func _update_suppression(observation: Dictionary, delta: float, settings: Resource) -> void:
	if not is_instance_valid(_suppressed_vehicle):
		_suppressed_vehicle = null
		_rearm_seconds = 0.0
		return
	if _observed_player(observation) != null:
		_suppressed_vehicle = null
		_rearm_seconds = 0.0
		return
	if _observed_vehicle(observation) == _suppressed_vehicle and absf(float(observation.get("road_speed", 0.0))) > settings.pursuit_enter_speed:
		_rearm_seconds += delta
		if _rearm_seconds >= settings.pursuit_enter_seconds:
			_suppressed_vehicle = null
			_rearm_seconds = 0.0
	else:
		_rearm_seconds = 0.0

func _cleanup_invalid() -> void:
	if _player_id != 0 and _valid_player(_player) == null:
		_suppressed_vehicle = _vehicle
		_clear("invalid_survivor")
	elif _vehicle_id != 0 and _valid_node(_vehicle) == null:
		_vehicle = null
		_vehicle_id = 0
		_has_local = false
		_generation += 1
		if _player != null:
			_set_mode("ground", "invalid_vehicle")
		else:
			_clear("invalid_vehicle")

func _clear(reason: String) -> void:
	if _player != null or _vehicle != null or _mode != "none":
		_generation += 1
	_player = null
	_vehicle = null
	_player_id = 0
	_vehicle_id = 0
	_mode = "none"
	_has_local = false
	_remaining = 0.0
	_motion_sample_time = -1.0
	_search_offset_local = Vector3.ZERO
	_low_seconds = 0.0
	_high_seconds = 0.0
	_pending_observation.clear()
	_pending_remaining = 0.0
	_reason = reason

func _set_mode(mode: String, reason: String) -> void:
	if _mode != mode:
		_mode = mode
		_generation += 1
	_reason = reason

func _publish(observation: Dictionary, locked: bool) -> void:
	var player_visible := _player != null and _observed_player(observation) == _player
	var vehicle_visible := _vehicle != null and _observed_vehicle(observation) == _vehicle
	var search_point := _vehicle_frame * (_player_local + _search_offset_local) if _has_local and not player_visible else _point
	var intent := "none"
	if _mode == "ground":
		intent = "ground" if player_visible else "search"
	elif _mode == "cabin":
		intent = "cabin" if player_visible or (_player == null and vehicle_visible) else "search"
	elif _mode == "pursuit":
		intent = "vehicle_assault" if vehicle_visible else "search"
	decision = {"mode": _mode, "intent": intent, "player": _player, "vehicle": _vehicle,
		"player_visible": player_visible, "vehicle_visible": vehicle_visible,
		"roof_inspection": _mode == "cabin" and vehicle_visible and observation.get("roof_visible", false) and _remaining > 0.0,
		"point": _point, "search_point": search_point, "vehicle_frame": _vehicle_frame,
		"reason": "action_locked" if locked and _mode != "none" else _reason,
		"generation": _generation}

func _observed_player(observation: Dictionary) -> Node3D:
	return _valid_player(observation.get("player"))

func _observed_vehicle(observation: Dictionary) -> Node3D:
	return _valid_node(observation.get("vehicle")) if observation.get("vehicle_visible", false) else null

func _valid_player(value: Variant) -> Node3D:
	var node := _valid_node(value)
	return node if node != null and node.get("is_player_dead") != true else null

func _valid_node(value: Variant) -> Node3D:
	return value as Node3D if is_instance_valid(value) and value is Node3D and not value.is_queued_for_deletion() else null

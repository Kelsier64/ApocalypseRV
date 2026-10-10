extends RefCounted
## Swept contact volumes follow the accepted heel, sole and five toes.
## Offsets use imported skeleton rest axes, relative to the 0.48 m ankle.
const PROBES := [
	Vector4(0, -.18, .02, .16),
	Vector4(0, -.35, -.15, .12),
	Vector4(0, -.28, .25, .17),
	Vector4(-.15, -.32, .55, .14),
	Vector4(.15, -.32, .55, .14),
	Vector4(-.25, -.37, .93, .08),
	Vector4(-.09, -.37, .92, .07),
	Vector4(.035, -.37, .86, .06),
	Vector4(.15, -.37, .77, .055),
	Vector4(.25, -.37, .68, .05),
]
var _previous: Dictionary = {}
var _contacts: Dictionary = {}
var _previous_origin := Vector3.INF

func reset() -> void:
	_previous.clear()
	_contacts.clear()
	_previous_origin = Vector3.INF

func samples(actor: SlenderSpeaker) -> Dictionary:
	var result: Dictionary = {}
	if actor.visual == null or actor.visual.get("available") != true: return result
	var skeleton: Skeleton3D = actor.visual.skeleton
	for side in ["R", "L"]:
		var index := skeleton.find_bone("foot." + side)
		if index < 0: continue
		var foot: Transform3D = actor.visual.bone_world("foot." + side)
		var axes := foot.basis * skeleton.get_bone_global_rest(index).basis.inverse()
		var points: Array[Vector3] = []
		for probe in PROBES:
			var offset := Vector3(probe.x * (-1.0 if side == "R" else 1.0), probe.y, probe.z)
			points.append(foot.origin + axes * offset)
		result[side] = points
	return result

func update(actor: SlenderSpeaker, delta: float) -> void:
	var current := samples(actor)
	if current.is_empty():
		reset()
		return
	# Restores and teleports establish a new origin, never a damaging chord.
	if _previous_origin.is_finite() and actor.global_position.distance_to(_previous_origin) > maxf(3.0, actor.settings.chase_speed * delta * 3.0):
		reset()
	var touching: Dictionary = {}
	var next_samples: Dictionary = {}
	for side in current:
		var points: Array[Vector3] = current[side]
		var before: Array[Vector3] = _previous.get(side, points)
		var safe_points: Array[Vector3] = points.duplicate()
		next_samples[side] = safe_points
		if not _near_player(actor, points, before): continue
		for index in points.size():
			# The same first-contact ordering as hand impacts preserves vehicle,
			# furniture and terrain shielding, including posed seated survivors.
			var hit := actor._player_contact_sweep(before[index], points[index], PROBES[index].w)
			var player: Node = hit.get("collider")
			if not is_instance_valid(player): continue
			if not player.is_in_group(Groups.PLAYER):
				# A visual foot may swing through a wall after its body stops.
				# Keep the last reachable probe so later frames cannot originate
				# beyond that shield. A foot initially intersecting the ground
				# may lift outward, while downward contact stays at its surface.
				var normal := Vector3(hit.get("normal", Vector3.ZERO))
				var lifting_out := normal.y > .5 and (points[index] - before[index]).dot(normal) >= 0.0
				if not lifting_out or player is RVStructurePanel or player is Item or player is Chassis:
					var motion := before[index].distance_to(points[index])
					var safe := maxf(0.0, float(hit.get("safe_fraction", 0.0)) - .002 / maxf(motion, .002))
					safe_points[index] = before[index].lerp(points[index], safe)
				continue
			if not actor._is_smash_damage_target(player): continue
			var key: String = String(side) + ":" + str(player.get_instance_id())
			touching[key] = player
	for key in touching:
		if _contacts.has(key): continue
		var player: Node = touching[key]
		var health: float = player.current_player_health
		player.take_damage(actor.settings.foot_player_damage)
		if player.current_player_health < health:
			actor.attack_landed.emit(player, "slender_speaker_foot")
	_contacts = touching
	_previous = next_samples
	_previous_origin = actor.global_position

func _near_player(actor: SlenderSpeaker, points: Array[Vector3], before: Array[Vector3]) -> bool:
	for player in actor.get_tree().get_nodes_in_group(Groups.PLAYER):
		if not player is Node3D or not actor._is_smash_damage_target(player): continue
		for index in points.size():
			if player.global_position.distance_squared_to(points[index]) < 16.0 or player.global_position.distance_squared_to(before[index]) < 16.0:
				return true
	return false

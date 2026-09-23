extends Node
## Authoritative grab clock and outcome. Player owns only input/camera lock.
enum Phase { NONE, REACH, HOLD, BITE, RELEASE, ESCAPE, MISS }
var actor: Raker
var victim: CharacterBody3D
var phase := Phase.NONE
var elapsed := 0.0
var variant := "stand"
var outcome := 0 # 0 escaped, 1 wounded, 2 fatal
var resolved := false
var support: Node3D
var seat: Node3D
var had_support := false
var was_seated := false
var contact_failure := ""
var rng := RandomNumberGenerator.new()
const DURATIONS := {Phase.REACH: .6, Phase.HOLD: 2.0, Phase.BITE: .38, Phase.RELEASE: .35, Phase.ESCAPE: 1.0, Phase.MISS: .45}
const CLIPS := {Phase.REACH: "reach", Phase.HOLD: "hold", Phase.BITE: "bite", Phase.RELEASE: "release", Phase.ESCAPE: "escape", Phase.MISS: "miss"}
const BITE_CONTACT := .38

func _ready() -> void:
	actor = get_parent()
	rng.randomize()

func busy() -> bool:
	return phase != Phase.NONE

func start(target: CharacterBody3D) -> bool:
	if busy() or not target.can_be_grabbed(): return false
	victim = target
	variant = "seat" if is_instance_valid(target.seated_in) else ("low" if actor.crouched else "stand")
	_change(Phase.REACH)
	return true

func _change(next: Phase) -> void:
	phase = next
	elapsed = 0
	if next != Phase.NONE:
		actor.attack_started.emit("grab_" + variant + "_" + CLIPS[next], DURATIONS[next])

static func classify(presses: int, required: int) -> int:
	if presses >= required: return 0
	return 1 if presses * 5 >= required * 4 else 2

func tick(delta: float) -> void:
	if not busy(): return
	if phase in [Phase.HOLD, Phase.BITE] and not valid_contact(true):
		cancel("contact_lost")
		return
	elapsed += delta
	match phase:
		Phase.REACH:
			if elapsed >= .6:
				if not valid_contact(false) or not victim.begin_grab(actor, rng.randi_range(6, 10)):
					victim = null
					_change(Phase.MISS)
					return
				support = actor.rv_support.rv
				had_support = is_instance_valid(support)
				seat = victim.seated_in
				was_seated = is_instance_valid(seat)
				_change(Phase.HOLD)
		Phase.HOLD:
			victim.grab_control.update_progress(2.0 - elapsed)
			if elapsed >= 2.0:
				victim.grab_control.accepting = false
				outcome = classify(victim.grab_control.presses, victim.grab_control.required)
				resolved = false
				_change(Phase.BITE)
		Phase.BITE:
			if not resolved and elapsed >= BITE_CONTACT:
				resolved = true
				victim.apply_grab_bite(actor, outcome == 2)
				# Damage can re-enter cleanup through player death. Survivors regain
				# control on this same contact tick; only the monster recovers.
				if phase == Phase.BITE:
					_release("bitten")
					_change(Phase.RELEASE)
		_:
			if elapsed >= DURATIONS[phase]: _change(Phase.NONE)

func escape() -> void:
	if phase != Phase.HOLD: return
	_release("escaped")
	actor.reaction_remaining = 1.0
	_change(Phase.ESCAPE)

func _release(reason: String) -> void:
	var target := victim
	victim = null # Break both sides before callback (death/removal can re-enter).
	if is_instance_valid(target): target.end_grab(actor, reason)
	support = null
	seat = null

func cancel(reason: String = "interrupted") -> void:
	_release(reason)
	_change(Phase.NONE)
	if is_instance_valid(actor):
		actor.attack_timer = maxf(actor.attack_timer, .5)
		var visual := actor.get_node_or_null("BodyMesh")
		if visual: visual.locked = 0

func valid_contact(captured: bool) -> bool:
	return contact_possible(victim, captured)

func contact_possible(target: CharacterBody3D, captured: bool = false) -> bool:
	contact_failure = ""
	return _contact_possible(target, captured)

func _contact_possible(victim: CharacterBody3D, captured: bool) -> bool:
	if not is_instance_valid(victim) or victim.is_queued_for_deletion() or actor.is_dead:
		contact_failure = "participant_removed"
		return false
	if not WorldEntities.same_world(actor, victim) or victim.is_player_dead:
		contact_failure = "world_or_death"
		return false
	if actor.locomotion_state != Monster.LocomotionState.NORMAL or victim.locomotion_state != victim.LocomotionState.NORMAL:
		contact_failure = "climbing"
		return false
	if not captured and not victim.can_be_grabbed():
		contact_failure = "immune_or_owned"
		return false
	if captured and victim.grab_control.captor != actor:
		contact_failure = "owner_changed"
		return false
	var target_support: Node3D = ClimbMath.find_rv_ancestor(victim.seated_in) if is_instance_valid(victim.seated_in) else victim.rv_support.rv
	if actor.rv_support.rv != target_support:
		contact_failure = "different_support"
		return false
	if captured:
		if had_support and (not is_instance_valid(support) or actor.rv_support.rv != support):
			contact_failure = "support_lost"
			return false
		if was_seated and (not is_instance_valid(seat) or victim.seated_in != seat):
			contact_failure = "seat_lost"
			return false
	var offset := (victim.global_position - actor.global_position).slide(Vector3.UP)
	if offset.length() > (1.65 if actor.crouched else 1.25):
		contact_failure = "distance"
		return false
	if offset.length() > .1 and (-actor.global_basis.z).dot(offset.normalized()) < cos(deg_to_rad(65)):
		contact_failure = "facing"
		return false
	return reach_clear_from(actor.global_position, actor.global_basis, victim)

func approach_clear(origin: Vector3, target: CharacterBody3D) -> bool:
	var offset := (target.global_position - origin).slide(Vector3.UP)
	var facing := Basis.looking_at(offset.normalized()) if offset.length() > .01 else actor.global_basis
	return reach_clear_from(origin, facing, target)

func reach_clear_from(origin: Vector3, facing: Basis, target: CharacterBody3D) -> bool:
	# The same two shoulder corridors constrain both path goals and capture.
	# A reachable route must go around a seatback, never grab through it.
	for side in [-1, 1]:
		var local := actor.to_local(actor.grab_shoulder_position(side))
		var start := origin + facing * local
		var contact: Vector3 = target.grab_contact_origin() - Vector3.UP * (.16 if is_instance_valid(target.seated_in) else .23) + facing.x * float(side) * .23
		var lengths: Vector2 = actor.get_node("BodyMesh").arm_lengths(side)
		if start.distance_to(contact) > lengths.x + lengths.y - .005:
			contact_failure = "arm_reach"
			return false
		var pole := (Vector3.UP if is_instance_valid(target.seated_in) else Vector3.DOWN) + facing.x * float(side) * .25
		var elbow := solve_elbow(start, contact, lengths, pole)
		for segment in [[start, elbow], [elbow, contact]]:
			var query := PhysicsRayQueryParameters3D.create(segment[0], segment[1], 1, [actor.get_rid(), target.get_rid()])
			var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				contact_failure = "blocked:" + str(hit.collider.name)
				return false
	return true

static func solve_elbow(shoulder: Vector3, wrist: Vector3, lengths: Vector2, pole: Vector3) -> Vector3:
	var direction := (wrist - shoulder).normalized()
	var distance := clampf(wrist.distance_to(shoulder), .02, lengths.x + lengths.y - .001)
	var along := (lengths.x * lengths.x - lengths.y * lengths.y + distance * distance) / (2 * distance)
	var height := sqrt(maxf(0, lengths.x * lengths.x - along * along))
	return shoulder + direction * along + pole.slide(direction).normalized() * height

func _exit_tree() -> void:
	_release("monster_removed")

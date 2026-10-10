extends SceneTree
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func head_yaw() -> float:
	return (-giant.global_basis.z).signed_angle_to(giant.visual.bone_world("socket_focus").basis.y.slide(Vector3.UP).normalized(), Vector3.UP)
func track(point: Vector3, count := 90) -> void:
	giant.phase = SlenderSpeaker.Phase.CHASE
	giant._visible_target = true
	giant.last_seen_position = point
	for tick in count:
		var before: float = giant._head_look.yaw
		giant._sample("idle_play", 0.0)
		giant._update_head_look(1.0 / 60.0)
		check(absf(giant._head_look.yaw - before) <= deg_to_rad(2.001), "Neck tracking respects its 120 degree/second slew")
		check(absf(head_yaw()) <= deg_to_rad(75.1), "Actual speaker yaw stays within the 75 degree neck range")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	await physics_frame
	await process_frame
	var body := giant.global_transform
	var hand_r: Vector3 = giant.visual.bone_world("hand.R").origin
	var hand_l: Vector3 = giant.visual.bone_world("hand.L").origin
	var right_target := Node3D.new()
	world.add_child(right_target)
	right_target.position = Vector3(40, 13, 0)
	check(not giant.can_see(right_target, right_target.global_position), "A target 90 degrees sideways starts outside the actual speaker cone")
	track(right_target.global_position)
	check(head_yaw() < deg_to_rad(-74.0), "Speaker cluster turns right without turning the torso")
	check(giant.can_see(right_target, right_target.global_position), "The turned real speaker socket can see the previously off-cone target")
	check(giant.global_transform.is_equal_approx(body), "Head look cannot rotate or translate the actor root")
	check(giant.visual.bone_world("hand.R").origin.distance_to(hand_r) < .001 and giant.visual.bone_world("hand.L").origin.distance_to(hand_l) < .001, "Neck look preserves both authored arm/hand positions")
	track(Vector3(-40, 13, 0), 120)
	check(head_yaw() > deg_to_rad(74.0), "The same rig turns left across the neutral pose smoothly")
	track(Vector3(40, -40, 0), 120)
	var forward: Vector3 = giant.visual.bone_world("socket_focus").basis.y.normalized()
	check(absf(rad_to_deg(atan2(forward.y, forward.slide(Vector3.UP).length())) + 20.0) < .15, "Actual pitch is clamped to 20 degrees downward")
	# The eye socket sits ahead of the neck. Using its pre-turn position as
	# the aim pivot made a nearby ground target slip behind the turned eye.
	for side in [-1.0, 1.0]:
		giant.rotation.y = deg_to_rad(-37.5 * side)
		right_target.position = Vector3(1.943 * side, 1.5, -.877)
		track(right_target.global_position, 120)
		check(giant.can_see(right_target, right_target.global_position), "A close ground player remains in the actual eye cone while the body catches up")
	giant.global_transform = body
	right_target.position = Vector3(40, 13, 0)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 40, 50)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(20, 15, 0)
	world.add_child(wall)
	await physics_frame
	await process_frame
	track(right_target.global_position)
	check(not giant.can_see(right_target, right_target.global_position), "Head turning does not bypass an actual wall")
	giant.phase = SlenderSpeaker.Phase.SEARCH
	giant._visible_target = false
	giant.target_player = right_target
	var remembered := giant.last_seen_position
	right_target.position = Vector3(-40, 13, 0)
	for tick in 30:
		giant._sample("idle_play", 0.0)
		giant._update_head_look(1.0 / 60.0)
	check(giant.last_seen_position == remembered and head_yaw() < deg_to_rad(-74.0), "Lost target look follows only the last observed point, not the hidden player's live position")
	giant.phase = SlenderSpeaker.Phase.GRAB
	giant._sample("grab", .4)
	var authored: Transform3D = giant.visual.bone_world("socket_focus")
	for tick in 30:
		giant._sample("grab", .4)
		giant._update_head_look(1.0 / 60.0)
	check(giant._head_look.weight == 0.0 and giant.visual.bone_world("socket_focus").is_equal_approx(authored), "Tracking fades out to the unchanged authored grab head pose")
	giant.reset_after_restore()
	check(giant._head_look.weight == 0.0 and giant._head_look.yaw == 0.0, "Restore resets tracking state")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: actual neck yaw/pitch, slew, body/hand isolation, socket vision, occlusion and authored grab return")
	quit(0 if failures.is_empty() else 1)

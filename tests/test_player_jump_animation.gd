extends SceneTree
## Uses real controller input and collisions; the visual never drives movement.
const PLAYER = preload("res://player/player.tscn")
var failures: Array[String] = []
var arena: Node3D
var actor: CharacterBody3D
var driver: Node
var traces: Array = []
var handoffs: Array = []

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value and note not in failures: failures.append(note)
func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame
func box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	body.position = at
	arena.add_child(body)
	return body
func press_jump() -> void:
	Input.action_press("jump")
	await steps(1)
	Input.action_release("jump")
func wait_clip(clip: String, limit: int = 120) -> bool:
	for frame in limit:
		if driver.current_clip == clip: return true
		await steps(1)
	return false
func trace_jump(label: String, speed: float) -> void:
	actor.current_stamina = 100
	actor.stamina_exhausted = false
	var start_y := actor.position.y
	var camera_pose: Transform3D = actor.camera.transform
	await press_jump()
	check(driver.current_clip == "jump_rise" and actor.velocity.y > 4, label + ": real jump selects ascent immediately")
	check(actor.current_stamina <= 85.0, label + ": existing jump stamina cost applies")
	var seen: Array[String] = []
	var peak := 0.0
	for frame in 90:
		var clip: String = driver.current_clip
		if clip not in seen: seen.append(clip)
		peak = maxf(peak, actor.position.y - start_y)
		check(is_equal_approx(Vector2(actor.velocity.x, actor.velocity.z).length(), speed), label + ": horizontal speed remains controller-owned")
		check(actor.camera.transform.is_equal_approx(camera_pose), label + ": animation does not move local camera")
		await steps(1)
	check(seen.slice(0, 3) == ["jump_rise", "jump_fall", "jump_land"], label + ": rise, fall, landing sequence")
	check(absf(peak - actor.JUMP_VELOCITY * actor.JUMP_VELOCITY / (2 * actor.gravity)) < .12, label + ": ballistic jump height preserved")
	check(actor.is_on_floor() and not String(driver.current_clip).begins_with("jump_"), label + ": ground locomotion resumes")
	traces.append({"case": label, "clips": seen, "peak_height_m": peak})

func jump_deaths() -> void:
	actor.queue_free()
	await steps(2)
	for gait in ["standing", "jog", "run"]:
		for delay in [4, 15, 30, 45, 56]:
			actor = PLAYER.instantiate()
			arena.add_child(actor)
			driver = actor.get_node("Visuals/Locomotion")
			await steps(25)
			if gait != "standing": Input.action_press("move_forward")
			if gait == "run": Input.action_press("sprint")
			await press_jump()
			await steps(delay)
			var clip: String = driver.current_clip
			var height := actor.position.y
			var vertical := actor.velocity.y
			actor.take_damage(1000)
			Input.action_release("move_forward")
			Input.action_release("sprint")
			await steps(2)
			var peak := 0.0
			var peak_bone := ""
			for frame in 90:
				await steps(1)
				for link: Dictionary in actor.ragdoll_control.links:
					var gap: float = (link.parent.global_transform * link.parent_frame).origin.distance_to((link.child.global_transform * link.child.joint_offset).origin)
					if gap > peak:
						peak = gap
						peak_bone = link.child.get("bone_name")
			check(peak < .025, "%s jump death at %d frames retains joints" % [gait, delay])
			await steps(70)
			check(not actor.is_player_dead and driver.current_clip == "idle", "Real jump death recovers control and idle")
			handoffs.append({"gait": gait, "delay_frames": delay, "clip": clip, "height_m": height, "vertical_speed": vertical, "peak_gap_m": peak, "peak_bone": peak_bone})
			actor.queue_free()
			await steps(2)

func run() -> void:
	check(Engine.physics_ticks_per_second == 60, "Physics stays at 60 Hz")
	arena = Node3D.new()
	root.add_child(arena)
	box(Vector3(0, -.1, 0), Vector3(200, .2, 200))
	actor = PLAYER.instantiate()
	arena.add_child(actor)
	driver = actor.get_node("Visuals/Locomotion")
	await steps(30)
	await trace_jump("standing", 0)
	Input.action_press("move_forward")
	await steps(4)
	await trace_jump("jogging", 5)
	Input.action_press("sprint")
	await steps(4)
	await trace_jump("sprinting", 8)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await steps(20)
	actor.current_stamina = 14
	actor.stamina_recovery_delay_remaining = 10
	await press_jump()
	check(actor.is_on_floor() and driver.current_clip == "idle", "Rejected jump does not play a fake takeoff")
	actor.current_stamina = 100
	await press_jump()
	await steps(8)
	actor.enter_ui_mode()
	var at: Vector3 = actor.position
	var time: float = driver.animation.current_animation_position
	await steps(12)
	check(actor.position.is_equal_approx(at) and is_equal_approx(driver.animation.current_animation_position, time), "Airborne UI freezes pose alongside existing controller pause")
	actor.exit_ui_mode()
	check(await wait_clip("jump_land"), "Closing airborne UI resumes through landing")
	await press_jump()
	check(driver.current_clip == "jump_rise" and actor.velocity.y > 4, "New jump interrupts landing without input delay")
	await steps(90)
	var platform := box(Vector3(0, 1.1, -12), Vector3(1, .2, 2))
	actor.position = Vector3(0, 1.22, -12)
	actor.velocity = Vector3.ZERO
	await steps(20)
	check(actor.is_on_floor(), "Ledge fixture supports player")
	Input.action_press("move_right")
	await steps(16)
	Input.action_release("move_right")
	check(driver.current_clip == "jump_fall", "Walking off a ledge uses falling pose without takeoff")
	check(await wait_clip("jump_land"), "Ledge fall lands")
	await steps(25)
	platform.queue_free()
	actor.position = Vector3.ZERO
	actor.velocity = Vector3.ZERO
	var ceiling := box(Vector3(0, 1.95, 0), Vector3(3, .2, 3))
	await steps(5)
	actor.current_stamina = 100
	await press_jump()
	check(await wait_clip("jump_fall", 30), "Ceiling contact transitions to falling pose")
	check(await wait_clip("idle"), "Short ceiling-blocked jump returns to idle")
	ceiling.queue_free()
	await steps(2)
	await jump_deaths()
	print("PLAYER_JUMP_METRICS ", JSON.stringify(traces))
	print("PLAYER_JUMP_HANDOFFS ", JSON.stringify(handoffs))
	for failure in failures: push_error(failure)
	arena.queue_free()
	await steps(2)
	if failures.is_empty(): print("PASS: jump poses follow ascent, descent, landing, ledges, ceilings, UI and repeated input without changing physics")
	quit(0 if failures.is_empty() else 1)

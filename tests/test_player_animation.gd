extends SceneTree
const PLAYER = preload("res://player/player.tscn")
var failures: Array[String] = []
var arena: Node3D
var metrics: Array = []

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value and note not in failures: failures.append(note)
func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func run() -> void:
	check(Engine.physics_ticks_per_second == 60, "Acceptance remains at 60 Hz")
	arena = Node3D.new()
	root.add_child(arena)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	var actor: CharacterBody3D = PLAYER.instantiate()
	arena.add_child(actor)
	await steps(40)
	var visual: PlayerModelVisual = actor.get_node("Visuals")
	var driver: Node = visual.get_node("Locomotion")
	var animation: AnimationPlayer = driver.animation
	check(driver.current_clip == "idle", "Grounded actor starts idle")
	check(animation.get_animation_library("locomotion").get_animation_list().size() == 17, "Nine ground, three jump and five climb clips are preserved")
	check(animation.get_animation_library("injury").get_animation_list().size() == 6, "Six authored prone and crawl cycles are installed")
	for name in animation.get_animation_list():
		var clip := animation.get_animation(name)
		var one_shot := String(name).get_file().begins_with("jump_") or String(name).get_file() == "climb_exit"
		check(clip.loop_mode == (Animation.LOOP_NONE if one_shot else Animation.LOOP_LINEAR), "Jump and top-out recovery are one-shot clips")
		for track in clip.get_track_count():
			var path := clip.track_get_path(track)
			check(String(path).begins_with("PLAYER_Rig/Skeleton3D:"), "No actor, camera or control-bone animation tracks")
			check(visual.skeleton.find_bone(path.get_subname(0)) >= 0, "Every track maps to an accepted deform bone")
			var first = clip.track_get_key_value(track, 0)
			var last = clip.track_get_key_value(track, clip.track_get_key_count(track) - 1)
			if not one_shot: check(first.is_equal_approx(last), "Loop endpoint is seamless: " + name)
	for gait in ["jog", "run"]:
		for direction in ["forward", "back", "left", "right"]:
			actor.current_stamina = 100
			actor.stamina_exhausted = false
			Input.action_press("move_" + direction)
			if gait == "run": Input.action_press("sprint")
			await steps(20)
			check(driver.current_clip == gait + "_" + direction, "Real input selects " + gait + "_" + direction)
			check(absf(actor.velocity.length() - (8 if gait == "run" else 5)) < .01, "Animation does not change controller speed")
			Input.action_release("move_" + direction)
			Input.action_release("sprint")
			await steps(20)
			check(driver.current_clip == "idle", "Stopping returns to idle")
	Input.action_press("move_forward")
	await steps(10)
	actor.enter_ui_mode()
	await steps(12)
	check(driver.current_clip == "idle", "Opening UI while running does not animate stale velocity")
	Input.action_release("move_forward")
	actor.exit_ui_mode()
	actor.queue_free()
	await steps(2)
	# Fresh body creation at several non-neutral poses must retain rest joint frames.
	for clip in ["jog_forward", "run_forward", "jog_left", "run_back", "jog_back_air"]:
		for phase in [0.0, .25, .5, .75]:
			actor = PLAYER.instantiate()
			arena.add_child(actor)
			await steps(30)
			driver = actor.get_node("Visuals/Locomotion")
			animation = driver.animation
			var source_clip: String = clip.trim_suffix("_air")
			animation.play("locomotion/" + source_clip, 0)
			animation.seek(animation.get_animation("locomotion/" + source_clip).length * phase, true)
			if clip.ends_with("_air"): actor.position.y = 1.8
			var travel := Vector3.BACK if source_clip.ends_with("back") else (Vector3.LEFT if source_clip.ends_with("left") else Vector3.FORWARD)
			actor.velocity = travel * (5 if clip.begins_with("jog") else 8)
			actor.take_damage(1000)
			await steps(2)
			var peak := 0.0
			var peak_bone := ""
			var speed := 0.0
			for frame in 90:
				await steps(1)
				for link: Dictionary in actor.ragdoll_control.links:
					var gap: float = (link.parent.global_transform * link.parent_frame).origin.distance_to((link.child.global_transform * link.child.joint_offset).origin)
					if gap > peak:
						peak = gap
						peak_bone = link.child.get("bone_name")
				for body: PhysicalBone3D in actor.ragdoll_control.bodies.values():
					speed = maxf(speed, body.linear_velocity.length())
			check(peak < .025 and speed < 12, "%s %.2f physical handoff stays connected" % [clip, phase])
			metrics.append({"clip": clip, "phase": phase, "peak_gap_m": peak, "peak_bone": peak_bone, "peak_speed": speed})
			await steps(60)
			check(not actor.is_player_dead and driver.current_clip == "idle" and animation.is_playing(), "Respawn resumes locomotion")
			actor.queue_free()
			await steps(2)
	print("PLAYER_ANIMATION_METRICS ", JSON.stringify(metrics))
	for failure in failures: push_error(failure)
	arena.queue_free()
	await steps(2)
	if failures.is_empty(): print("PASS: authored locomotion mapping, loops, input, unchanged speed and 20 animated death handoffs at 60 Hz")
	quit(0 if failures.is_empty() else 1)

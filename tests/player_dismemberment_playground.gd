extends "res://tests/player_animation_playground.gd"
## Production player and bite clock, with explicit isolated inspection controls.
var raker: Raker
var bite_result := 1
var replay_motion := 0.0
var first_person := false
var review_head: Node3D
var review_offset := Vector3(.52, .32, .46)
var arm_captures: Dictionary = {}
var prone_review := false

func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Dismemberment Acceptance"
	capture_directory = "res://docs/validation/player-dismemberment/"
	DirAccess.make_dir_recursive_absolute(capture_directory)
	observer.fov = 52

func _process(_delta: float) -> void:
	if not is_instance_valid(actor): return
	var center := actor.global_position + Vector3(0, .9 if not actor.is_crawling() else .5, 0)
	if actor.is_player_dead and actor.ragdoll_control.active: center = actor.ragdoll_control.bodies["pelvis"].global_position
	observer.global_position = center + Vector3(-2.2, .9, -2.6)
	if is_instance_valid(raker):
		center = actor.global_position.lerp(raker.global_position, .35) + Vector3(0, 1.35, 0)
		observer.global_position = center + Vector3(-3.4, .6, .5)
	observer.look_at(center)
	if prone_review:
		center = actor.global_position + Vector3(0, .44, .12)
		observer.global_position = center + Vector3(-2.2, .35, .15)
		observer.look_at(center)
	if is_instance_valid(review_head) and review_head.builder != null:
		center = review_head.builder.bodies["head"].global_position
		observer.global_position = center + review_offset
		observer.look_at(center)
		observer.make_current()
	label.text = "DISMEMBERMENT | " + str(actor.current_player_health) + " HP | " + actor.get_node("Visuals/Locomotion").current_clip
	label.text += "\n1 head / 2 left arm / 3 right arm / 4 left leg / 5 right leg"
	label.text += "\nF1 view / F6 arm bite / F7 fatal bite / F8 crawl replay / R reset / Esc close"
	if actor.is_player_dead and not first_person: observer.make_current()

func _physics_process(delta: float) -> void:
	if is_instance_valid(raker) and raker.grab.busy():
		if raker.grab.phase == raker.grab.Phase.HOLD and bite_result == 1:
			actor.grab_control.presses = ceili(actor.grab_control.required * .8)
		raker.grab.tick(delta)
	if replay_motion > 0:
		replay_motion -= delta
		Input.action_press("move_forward")
		if replay_motion <= 0: Input.action_release("move_forward")

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_1: actor.sever_part(&"head")
		KEY_2: actor.sever_part(&"left_arm")
		KEY_3: actor.sever_part(&"right_arm")
		KEY_4: actor.sever_part(&"left_leg")
		KEY_5: actor.sever_part(&"right_leg")
		KEY_F1:
			first_person = not first_person
			if first_person: actor.camera.make_current()
			else: observer.make_current()
		KEY_F6: setup_bite(1)
		KEY_F7: setup_bite(2)
		KEY_F8: replay_motion = 3.0
		KEY_R: reset_actor()
		KEY_ESCAPE: get_tree().quit()

func _unhandled_key_input(_event: InputEvent) -> void:
	pass

func reset_actor() -> void:
	Input.action_release("move_forward")
	replay_motion = 0
	if is_instance_valid(raker): raker.free()
	if is_instance_valid(actor): actor.free()
	for node in get_tree().get_nodes_in_group("player_detached_parts"): node.queue_free()
	actor = PLAYER.instantiate()
	add_child(actor)
	actor.position.y = .1
	first_person = false
	observer.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func setup_bite(result: int) -> void:
	if actor.is_player_dead or actor.is_grabbed(): return
	if is_instance_valid(raker): raker.free()
	raker = preload("res://enemies/raker.tscn").instantiate()
	raker.position = actor.position + actor.basis * Vector3(0, 0, -1)
	add_child(raker)
	raker.look_at(actor.global_position)
	raker.set_physics_process(false)
	raker.target_player = actor
	bite_result = result
	actor.grab_control.immunity = 0
	raker.grab.start(actor)

func replay() -> void:
	if "--prone-review" in OS.get_cmdline_user_args():
		await replay_prone()
		return
	if "--head-pov" in OS.get_cmdline_user_args():
		await replay_head_pov()
		return
	if "--arm-pov" in OS.get_cmdline_user_args():
		await replay_arm_pov()
		return
	if "--gore-review" in OS.get_cmdline_user_args():
		await replay_gore()
		return
	replaying = true
	await wait_seconds(.5)
	await capture("intact")
	actor.sever_part(&"left_leg")
	await wait_seconds(.6)
	replay_motion = 2
	await wait_seconds(.5)
	await capture("crawl_one_leg")
	await wait_seconds(.7)
	await capture("crawl_one_leg_phase2")
	replay_motion = 0; Input.action_release("move_forward")
	actor.sever_part(&"right_leg")
	await wait_seconds(.2)
	replay_motion = 1
	await wait_seconds(.5)
	await capture("crawl_no_legs")
	actor.sever_part(&"left_arm")
	await wait_seconds(.4)
	await capture("crawl_one_arm")
	reset_actor()
	await wait_seconds(.5)
	setup_bite(1)
	await wait_for_sever(&"left_arm")
	await capture("arm_bite_contact")
	await wait_seconds(.8)
	await capture("arm_bite_aftermath")
	actor.camera.make_current()
	actor.camera.rotation.x = deg_to_rad(-65)
	await capture("missing_arm_first_person")
	observer.make_current()
	setup_bite(1)
	await wait_for_sever(&"head")
	await capture("second_bite_head")
	await wait_seconds(.6)
	await capture("headless_ragdoll")
	await wait_seconds(2)
	observer.make_current()
	await capture("respawn")
	print("PASS: dismemberment visual replay completed")
	replaying = false
	if "--replay" in OS.get_cmdline_user_args(): get_tree().quit()

func replay_prone() -> void:
	replaying = true
	prone_review = true
	capture_directory += "prone/"
	DirAccess.make_dir_recursive_absolute(capture_directory)
	for variant in ["left_leg", "right_leg", "no_legs", "onearm_L", "onearm_R"]:
		reset_actor()
		await wait_seconds(.5)
		actor.sever_part(&"right_leg" if variant == "right_leg" else &"left_leg")
		if variant in ["no_legs", "onearm_L", "onearm_R"]: actor.sever_part(&"right_leg")
		if variant.begins_with("onearm_"): actor.sever_part(&"right_arm" if variant == "onearm_L" else &"left_arm")
		await wait_seconds(.7)
		# Keep detached parts from occluding the low-angle contact inspection.
		for part in get_tree().get_nodes_in_group("player_detached_parts"): part.queue_free()
		await wait_seconds(.05)
		await capture(variant + "_idle")
		replay_motion = 3.0
		await wait_seconds(.35)
		for frame in 5:
			await capture(variant + "_%02d" % frame)
			await wait_seconds(.14)
		if variant == "left_leg":
			first_person = true
			actor.camera.make_current()
			await capture("first_person")
			print("PRONE_EYE_HEIGHT ", actor.camera.global_position.y)
			observer.make_current()
	for name in arm_captures: arm_captures[name].save_png(capture_directory + name + ".png")
	Input.action_release("move_forward")
	print("PASS: prone idle and moving limb variants captured")
	get_tree().quit()

func wait_for_sever(part: StringName) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while actor.body_state.has_part(part) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	if actor.body_state.has_part(part):
		push_error("Bite failed to sever " + part)
		get_tree().quit(1)
	await wait_seconds(.03)

func replay_arm_pov() -> void:
	replaying = true
	capture_directory += "arm-observer/" if "--arm-observer" in OS.get_cmdline_user_args() else "arm-pov/"
	var grab_prop := "--grab-prop" in OS.get_cmdline_user_args()
	if grab_prop: capture_directory += "held-prop/"
	DirAccess.make_dir_recursive_absolute(capture_directory)
	await wait_seconds(.5)
	first_person = not "--arm-observer" in OS.get_cmdline_user_args()
	if first_person: actor.camera.make_current()
	label.hide()
	if grab_prop:
		actor.add_item("Scrap", false, "res://props/scrap.tscn")
		await wait_seconds(.3)
	setup_bite(1)
	await wait_seconds(.85)
	await capture("00_face")
	await wait_seconds(.65)
	print("ARM_ACTORS ", actor.global_transform, " monster ", raker.global_transform)
	await capture("01_struggle")
	while raker.grab.phase == raker.grab.Phase.HOLD and raker.grab.elapsed < 1.9: await get_tree().physics_frame
	await capture("01b_before_bite")
	while raker.grab.phase != raker.grab.Phase.BITE: await get_tree().physics_frame
	await wait_seconds(.05)
	await capture("02_approach")
	while raker.grab.phase == raker.grab.Phase.BITE and raker.grab.elapsed < .18: await get_tree().physics_frame
	await capture("03_contact")
	await wait_for_sever(&"left_arm")
	await capture("04_severed")
	await wait_seconds(.12)
	await capture("05_pull_away")
	await wait_seconds(.20)
	await capture("06_drop")
	await wait_seconds(.5)
	await capture("07_recovered")
	print("ARM_POV_BODY_YAW ", actor.rotation.y)
	for name in arm_captures: arm_captures[name].save_png(capture_directory + name + ".png")
	print("PASS: first-person arm bite approach, severance, drop and recovery captured")
	get_tree().quit()

func replay_head_pov() -> void:
	replaying = true
	capture_directory += "head-pov/" + ("before/" if "--before" in OS.get_cmdline_user_args() else "after/")
	DirAccess.make_dir_recursive_absolute(capture_directory)
	await wait_seconds(.5)
	first_person = true
	actor.camera.make_current()
	label.hide()
	setup_bite(2)
	await wait_seconds(1.4)
	await capture("00_face")
	while raker.grab.phase != raker.grab.Phase.BITE: await get_tree().physics_frame
	await wait_seconds(.17)
	await capture("01_approach")
	await wait_for_sever(&"head")
	await capture("02_severed")
	await wait_seconds(.12)
	await capture("03_held")
	await wait_seconds(.4)
	await capture("04_falling")
	await wait_seconds(.6)
	await capture("05_ground")
	await wait_seconds(1.2)
	await capture("06_respawn")
	for name in arm_captures: arm_captures[name].save_png(capture_directory + name + ".png")
	print("PASS: first-person fatal head bite and recovery captured")
	get_tree().quit()

func capture(name: String) -> void:
	if prone_review:
		await RenderingServer.frame_post_draw
		arm_captures[name] = get_viewport().get_texture().get_image()
	elif "--arm-pov" not in OS.get_cmdline_user_args() and "--head-pov" not in OS.get_cmdline_user_args():
		await super.capture(name)
	else:
		# Buffer frames so PNG encoding cannot skip the brief contact sequence.
		await RenderingServer.frame_post_draw
		arm_captures[name] = get_viewport().get_texture().get_image()
		var visual: Node3D = raker.get_node("BodyMesh")
		var mouth: Vector3 = visual.bone_world_position("mouth")
		var wound: Vector3 = actor.get_node("Visuals").bite_contact(&"left_arm").origin
		print("ARM_FRAME ", name, " phase=", raker.grab.phase, " t=", raker.grab.elapsed, " eye=", actor.camera.global_position, " rot=", actor.camera.rotation_degrees, " wound=", wound, " mouth=", mouth, " screen=", actor.camera.unproject_position(mouth))
		for node in get_tree().get_nodes_in_group("player_detached_parts"):
			print("DETACHED ", node.skeleton.to_global(node.skeleton.get_bone_global_pose(node.anchor_bone).origin))
			if node.builder != null:
				for body: PhysicalBone3D in node.builder.bodies.values(): print("PHYS_PART ", body.name, " sim=", body.is_simulating_physics(), " pos=", body.global_position, " vel=", body.linear_velocity)

func replay_gore() -> void:
	replaying = true
	capture_directory += "gore-review/" + ("before/" if "--before" in OS.get_cmdline_user_args() else "after/")
	DirAccess.make_dir_recursive_absolute(capture_directory)
	await wait_seconds(.5)
	actor.sever_part(&"head")
	review_head = get_tree().get_nodes_in_group("player_detached_parts").back()
	await wait_seconds(3.5)
	actor.get_node("Visuals").hide()
	await capture("head_ground")
	review_offset = Vector3(-.4, .18, -.48)
	await capture("head_reverse")
	review_head = null
	actor.position = Vector3(0, 0, 0)
	actor.get_node("Visuals").hide()
	for x in [-1.0, 0.0, 1.0]:
		preload("res://player/player_gore.gd").spawn(actor, Vector3(x, .4, -1.7), {})
	await wait_seconds(2)
	set_process(false)
	observer.position = Vector3(0, 2.6, .5)
	observer.look_at(Vector3(0, 0, -1.6))
	observer.make_current()
	await capture("blood_daylight")
	for node in get_children():
		if node is DirectionalLight3D: node.light_energy = .18
		if node is WorldEnvironment: node.environment.ambient_light_energy = .24
	await capture("blood_dim")
	print("PASS: ground head and blood surface review captured")
	get_tree().quit()

extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value and note not in failures: failures.append(note)
func steps(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func check_fingers(skeleton: Skeleton3D, side: String, note: String) -> void:
	var hand := skeleton.find_bone("hand_" + side)
	var rest := skeleton.get_bone_global_rest(hand)
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
	var index := skeleton.get_bone_global_rest(skeleton.find_bone("index_01_" + side)).origin
	var pinky := skeleton.get_bone_global_rest(skeleton.find_bone("pinky_01_" + side)).origin
	var forward := (middle - rest.origin).normalized()
	var radial := index - pinky
	radial = (radial - forward * radial.dot(forward)).normalized()
	var palm := forward.cross(radial) * (1.0 if side == "L" else -1.0)
	var to_current := skeleton.get_bone_global_pose(hand).basis * rest.basis.inverse()
	forward = to_current * forward
	palm = to_current * palm
	for finger in ["index", "middle", "ring", "pinky"]:
		var proximal := skeleton.get_bone_global_pose(skeleton.find_bone(finger + "_01_" + side)).basis.y.normalized()
		var distal := skeleton.get_bone_global_pose(skeleton.find_bone(finger + "_02_" + side)).basis.y.normalized()
		var first := atan2(proximal.dot(palm), proximal.dot(forward))
		var second := atan2(distal.dot(palm), distal.dot(forward))
		check(first > .1 and first < 1.4, note + " " + finger + " flexes toward palm, not back of hand")
		check(second > first + .1 and second < 2.7, note + " " + finger + " distal joint curls inward without folding through palm")

func check_thumb_forward(actor: Node3D, skeleton: Skeleton3D, side: String, note: String) -> void:
	var front := -actor.global_basis.z
	for segment in ["01", "02"]:
		var thumb := skeleton.global_basis * skeleton.get_bone_global_pose(skeleton.find_bone("thumb_" + segment + "_" + side)).basis.y.normalized()
		check(thumb.dot(front) > .1, note + " thumb " + segment + " points forward, not toward the player (%.3f)" % thumb.dot(front))

func check_small_hold_height(actor: Node3D, skeleton: Skeleton3D, note: String) -> void:
	var shoulder := actor.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("upper_arm_R")).origin)
	var wrist := actor.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_R")).origin)
	var elbow := actor.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("forearm_R")).origin)
	check(wrist.y < shoulder.y, note + " keeps the holding wrist below the shoulder")
	check(elbow.y < shoulder.y, note + " keeps the holding elbow below the shoulder")

func check_box_contact(actor: Node3D, skeleton: Skeleton3D, side: String, note: String) -> void:
	var carry: Node = actor.get_node("Visuals/Carry")
	var box: AABB = carry.bounds.grow(-.006)
	for finger in ["index", "middle", "ring", "pinky"]:
		for segment in ["01", "02"]:
			var bone := skeleton.find_bone(finger + "_" + segment + "_" + side)
			var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			var local: Vector3 = actor.held_item_node.get_parent().to_local(world)
			check(not box.has_point(local), note + " " + finger + segment + " stays outside the solid box")

func check_flashlight_grip(actor: Node3D, skeleton: Skeleton3D) -> void:
	var held: Node3D = actor.held_item_node
	var body := held.get_node("Body") as MeshInstance3D
	var cylinder := body.mesh as CylinderMesh
	var radius := maxf(cylinder.top_radius, cylinder.bottom_radius)
	var beam := held.get_node("Beam") as SpotLight3D
	check((-beam.global_basis.z).normalized().dot(-actor.camera.global_basis.z) > .95, "Flashlight beam stays aimed ahead while the hand grips")
	for finger in ["index", "middle", "ring", "pinky"]:
		for segment in ["01", "02"]:
			var bone := skeleton.find_bone(finger + "_" + segment + "_R")
			var joint := body.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)
			var distance := Vector2(joint.x, joint.z).length()
			check(distance >= radius, "Flashlight " + finger + segment + " stays outside the barrel")
			if segment == "02":
				check(distance < radius + .025, "Flashlight " + finger + " wraps close to the barrel")
				var direction := body.global_basis.inverse() * skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis.y
				var radial_direction := Vector2(direction.x, direction.z)
				var closest := maxf(0.0, -Vector2(joint.x, joint.z).dot(radial_direction) / maxf(radial_direction.length_squared(), .000001))
				check((Vector2(joint.x, joint.z) + radial_direction * closest).length() >= radius, "Flashlight " + finger + " distal direction clears the solid barrel")

func palm_position(skeleton: Skeleton3D, side: String) -> Vector3:
	var hand := skeleton.find_bone("hand_" + side)
	var rest := skeleton.get_bone_global_rest(hand)
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
	var index := skeleton.get_bone_global_rest(skeleton.find_bone("index_01_" + side)).origin
	var pinky := skeleton.get_bone_global_rest(skeleton.find_bone("pinky_01_" + side)).origin
	var palm := (middle - rest.origin).normalized().cross((index - pinky).normalized()).normalized() * (1.0 if side == "L" else -1.0)
	var center := rest.origin.lerp(middle, .72) + palm * .014
	return skeleton.global_transform * skeleton.get_bone_global_pose(hand) * (rest.affine_inverse() * center)

func check_grab_palm(actor: Node3D, skeleton: Skeleton3D, side: String, note: String) -> void:
	var target := actor.to_global(Vector3(.28 if side == "R" else -.28, 1.53, -.49))
	var error := palm_position(skeleton, side).distance_to(target)
	check(error < .035, "%s %s palm reaches original grab height (%.3fm)" % [note, side, error])

func capture_for_pose(actor: CharacterBody3D, raker: Raker) -> void:
	actor.grab_control.immunity = 0.0
	raker.position = actor.position + actor.basis * Vector3(0, 0, -1)
	raker.grab.victim = actor
	raker.grab._change(raker.grab.Phase.HOLD)
	check(actor.begin_grab(raker, 10), "Carry pose fixture enters actual player grab")
	await steps(24)

func release_pose(actor: CharacterBody3D, raker: Raker) -> void:
	raker.grab.cancel()
	actor.set_physics_process(false)
	actor.camera.rotation = Vector3.ZERO
	await steps(20)

func check_grab_hand_selection(arena: Node3D, actor: CharacterBody3D, skeleton: Skeleton3D, carry: Node) -> void:
	# Freeze actor motion and the Raker's grab clock; keep real pose overlays running.
	actor.set_physics_process(false)
	actor.velocity = Vector3.ZERO
	var raker := preload("res://enemies/raker.tscn").instantiate()
	arena.add_child(raker)
	raker.set_physics_process(false)
	await capture_for_pose(actor, raker)
	check_grab_palm(actor, skeleton, "L", "Empty hands")
	check_grab_palm(actor, skeleton, "R", "Empty hands")
	await release_pose(actor, raker)
	for key in ["scrap", "flashlight", "oil_barrel"]:
		actor.inventory.items.clear()
		actor.inventory.active_slot = 0
		var large: bool = key == "oil_barrel"
		var state := {"flashlight": {"charge": 100.0, "on": false}} if key == "flashlight" else {}
		actor.add_item(key, large, "res://props/" + key + ".tscn", state)
		await steps(20)
		await capture_for_pose(actor, raker)
		check(actor.held_item_node.is_visible_in_tree(), key + " remains visible during grab")
		check(carry.right_weight == 1.0 and carry.left_weight == 0.0, key + " keeps holding arm and frees only left arm")
		check(palm_position(skeleton, "R").distance_to(carry.grip_right) < .035, key + " holding palm keeps contacting prop during grab")
		check_grab_palm(actor, skeleton, "L", key + " free hand")
		if key == "flashlight":
			check(not actor.grab_control.keep_flashlight and not actor.held_item_node.get_node("Beam").is_visible_in_tree(), "Unlit flashlight still occupies holding hand without activating beam")
		await release_pose(actor, raker)
		if large:
			check(carry.right_weight == 1.0 and carry.left_weight == 1.0, "Release restores ordinary two-arm large carry")
			check(palm_position(skeleton, "L").distance_to(carry.grip_left) < .035, "Released left palm returns to large prop grip")
	actor.inventory.items.clear()
	actor.inventory.active_slot = 0
	actor.body_state.sever(&"right_arm")
	actor._apply_body_capabilities()
	actor.add_item("scrap", false, "res://props/scrap.tscn")
	await steps(20)
	await capture_for_pose(actor, raker)
	check(actor.held_item_node.is_visible_in_tree() and carry.active_hand == "L", "Missing right arm keeps prop in surviving left hand")
	check(carry.left_weight == 1.0 and carry.right_weight == 0.0, "Missing right arm has no free hand to raise")
	check(palm_position(skeleton, "L").distance_to(carry.grip_left) < .035, "Surviving holding hand keeps contacting prop during grab")
	check(not carry.base_rotations.has(skeleton.find_bone("upper_arm_R")), "Grab never poses nonexistent right arm")
	await release_pose(actor, raker)
	raker.queue_free()

func run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	var actor = preload("res://player/player.tscn").instantiate()
	arena.add_child(actor)
	await steps(30)
	var carry: Node = actor.get_node("Visuals/Carry")
	var skeleton: Skeleton3D = actor.get_node("Visuals").skeleton
	var driver: Node = actor.get_node("Visuals/Locomotion")
	for key in ["flashlight", "scrap", "battery", "engine_repair_kit", "oil_barrel", "engine_standard"]:
		actor.inventory.items.clear()
		actor.inventory.active_slot = 0
		var large: bool = key in ["oil_barrel", "engine_standard"]
		actor.add_item(key, large, "res://props/" + key + ".tscn")
		await steps(20)
		check(carry.right_weight == 1.0 and carry.left_weight == (1.0 if large else 0.0), key + " chooses correct arms")
		check(large or not carry.base_rotations.has(skeleton.find_bone("upper_arm_L")), "Small props leave the left arm to locomotion")
		carry.clear_pose()
		driver.animation.advance(0)
		var natural_rotations: Dictionary = {}
		for side in (["R", "L"] if large else ["R"]):
			for part in ["hand_"]:
				var bone := skeleton.find_bone(part + side)
				natural_rotations[bone] = skeleton.get_bone_pose_rotation(bone)
		carry._physics_process(0.0)
		for bone: int in natural_rotations:
			check(skeleton.get_bone_pose_rotation(bone).is_equal_approx(natural_rotations[bone]), key + " preserves authored wrist rotation")
			check(not carry.base_rotations.has(bone), key + " never writes the wrist")
		for side in (["R", "L"] if large else ["R"]):
			check_fingers(skeleton, side, key + " " + side)
			check_thumb_forward(actor, skeleton, side, key + " idle " + side)
			if key in ["scrap", "battery", "engine_repair_kit"]: check_box_contact(actor, skeleton, side, key)
		if not large: check_small_hold_height(actor, skeleton, key + " idle")
		if key == "flashlight": check_flashlight_grip(actor, skeleton)
		for pitch in [-.45, 0.0, .45]:
			actor.camera.rotation.x = pitch
			Input.action_press("move_forward")
			await steps(20)
			check(driver.current_clip == "jog_forward", "Holding preserves locomotion")
			if not large: check_small_hold_height(actor, skeleton, key + " moving at pitch " + str(pitch))
			if key == "flashlight": check_flashlight_grip(actor, skeleton)
			for side in (["R", "L"] if large else ["R"]):
				check_thumb_forward(actor, skeleton, side, key + " moving " + side)
				var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side)).origin
				var grip: Vector3 = carry.grip_right if side == "R" else carry.grip_left
				check(wrist.distance_to(grip) < .12, "%s %s wrist reaches prop at pitch %.2f (%.3fm)" % [key, side, pitch, wrist.distance_to(grip)])
				var contact_error := palm_position(skeleton, side).distance_to(grip)
				check(contact_error < .035, "%s %s palm contacts prop at pitch %.2f (%.3fm)" % [key, side, pitch, contact_error])
			check(absf(actor.velocity.length() - 5.0) < .01, "Carry does not alter speed")
			Input.action_release("move_forward")
			await steps(4)
		actor.enter_ui_mode()
		await steps(10)
		check(carry.right_weight == 1 and driver.current_clip == "idle", "UI keeps held pose without stale running")
		actor.exit_ui_mode()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await steps(15)
	check(driver.current_clip == "run_forward" and carry.left_weight == 1, "Two-hand carry preserves running")
	Input.action_press("jump")
	await steps(8)
	check(driver.current_clip == "jump_rise" and carry.left_weight == 1, "Two-hand carry preserves jumping")
	Input.action_release("jump")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await steps(70)
	actor.camera.rotation.x = 0
	actor.locomotion_state = actor.LocomotionState.CLIMBING
	actor.set_physics_process(false)
	await steps(3)
	check(carry.right_weight == 0 and carry.left_weight == 0 and not actor.held_item_node.visible, "Climbing frees arms and hides prop")
	actor.locomotion_state = actor.LocomotionState.NORMAL
	actor.set_physics_process(true)
	await steps(20)
	check(actor.held_item_node.visible and carry.left_weight == 1, "Leaving climb restores two-hand carry")
	var equipment := Node3D.new()
	arena.add_child(equipment)
	actor.placement.placing_equipment = equipment
	actor.set_physics_process(false)
	await steps(3)
	check(carry.right_weight == 0 and not actor.held_item_node.visible, "Placement releases held arms")
	actor.placement.placing_equipment = null
	actor.set_physics_process(true)
	await steps(20)
	actor.take_damage(1000)
	await steps(160)
	check(not actor.is_player_dead and carry.left_weight == 1, "Death and respawn restore carry")
	actor.consume_active_item()
	await steps(30)
	check(carry.right_weight == 0 and carry.left_weight == 0 and carry.base_rotations.is_empty(), "Empty hands restore clean locomotion")
	await check_grab_hand_selection(arena, actor, skeleton, carry)
	arena.queue_free()
	await steps(2)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: one/two hand carry, grip reach, locomotion, UI, climbing, death, empty hands and grabbed hand selection")
	quit(0 if failures.is_empty() else 1)

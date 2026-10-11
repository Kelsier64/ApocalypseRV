extends SceneTree
## Imported body budgets and actual shared-skeleton grip contact, not pose proxies.
var failures: Array[String] = []
var actor: CharacterBody3D
var skeleton: Skeleton3D

func _init() -> void: run.call_deferred()

func check(value: bool, note: String) -> void:
	if not value: failures.append(note)

func steps(count := 20) -> void:
	for index in count:
		await physics_frame
		await process_frame

func inspect_body(path: String, budget: int, minimum: Vector3, maximum: Vector3) -> void:
	var item: Item = load(path).instantiate()
	item.presentation_only = true
	root.add_child(item)
	var visuals: Node3D = item.get_node("Visuals")
	var meshes := visuals.find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var bounds := AABB()
	var first := true
	for instance: MeshInstance3D in meshes:
		if instance.mesh == null: continue
		for surface in instance.mesh.get_surface_count():
			check(instance.mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES, "%s uses triangulated body surfaces" % path)
			var arrays := instance.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
		var local: Transform3D = item.global_transform.affine_inverse() * instance.global_transform
		var box: AABB = local * instance.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	print("PISTOL_VISUAL_ASSET path=", path, " triangles=", triangles, " dimensions=", bounds.size)
	check(not first and triangles > 0 and triangles <= budget, "%s body stays within %d triangles (actual %d)" % [path, budget, triangles])
	for axis in 3:
		check(bounds.size[axis] >= minimum[axis] and bounds.size[axis] <= maximum[axis], "%s axis %d has gameplay-sized dimensions (%.4fm)" % [path, axis, bounds.size[axis]])
	check(item.basis.get_scale().is_equal_approx(Vector3.ONE), "%s world Item retains authored full size" % path)
	item.free()

func palm_position(side: String) -> Vector3:
	# Same anatomical palm definition as test_player_carry.gd. Measure from the
	# real rest knuckles and evaluated hand bone, independently of carry.grip_*.
	var hand := skeleton.find_bone("hand_" + side)
	var rest := skeleton.get_bone_global_rest(hand)
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
	var index := skeleton.get_bone_global_rest(skeleton.find_bone("index_01_" + side)).origin
	var pinky := skeleton.get_bone_global_rest(skeleton.find_bone("pinky_01_" + side)).origin
	var palm := (middle - rest.origin).normalized().cross((index - pinky).normalized()).normalized() * (1.0 if side == "L" else -1.0)
	var center := rest.origin.lerp(middle, .72) + palm * .014
	return skeleton.global_transform * skeleton.get_bone_global_pose(hand) * (rest.affine_inverse() * center)

func finger_direction(bone_name: String) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	return actor.held_item_node.global_basis.inverse() * skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis.y.normalized()

func check_fingers(side: String, note: String) -> void:
	var inward := Vector3.LEFT if side == "R" else Vector3.RIGHT
	for finger in ["index", "middle", "ring", "pinky"]:
		var first := finger_direction(finger + "_01_" + side).normalized()
		var second := finger_direction(finger + "_02_" + side).normalized()
		var bend := rad_to_deg(first.angle_to(second))
		check(first.dot(Vector3.FORWARD) > 0.7, "%s %s proximal finger faces down the pistol without twisting backward" % [note, finger])
		check(second.dot(inward) > 0.45 and absf(second.y) < 0.45, "%s %s distal finger curls toward grip without pointing through wrist" % [note, finger])
		check(bend > 30.0 and bend < 120.0, "%s %s has bounded finger bend (%.1f degrees)" % [note, finger, bend])
	for segment in ["01", "02"]:
		check(finger_direction("thumb_" + segment + "_" + side).normalized().dot(Vector3.FORWARD) > 0.65, "%s thumb %s points forward along pistol" % [note, segment])

func check_wrist(side: String, note: String) -> void:
	# Measure anatomical axes from the evaluated rig, independently of carry's
	# desired wrist orientation. Grip contact alone cannot detect a folded wrist.
	var hand := skeleton.find_bone("hand_" + side)
	var lower := skeleton.find_bone("forearm_" + side)
	var rest := skeleton.get_bone_global_rest(hand)
	var lower_rest := skeleton.get_bone_global_rest(lower)
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
	var index := skeleton.get_bone_global_rest(skeleton.find_bone("index_01_" + side)).origin
	var pinky := skeleton.get_bone_global_rest(skeleton.find_bone("pinky_01_" + side)).origin
	var forward := (middle - rest.origin).normalized()
	var radial := (index - pinky).slide(forward).normalized()
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var hand_delta := hand_pose.basis * rest.basis.inverse()
	var current_forward := (hand_delta * forward).normalized()
	var lower_axis := (hand_pose.origin - lower_pose.origin).normalized()
	var bend := rad_to_deg(lower_axis.angle_to(current_forward))
	check(bend < 75.0, "%s wrist bends less than 75 degrees (%.1f)" % [note, bend])
	# Transport the anatomical radial axis along each forearm. Comparing these
	# transverse directions isolates pronation from ordinary wrist flexion.
	var rest_lower_axis := (rest.origin - lower_rest.origin).normalized()
	var rest_radial := Basis(Quaternion(forward, rest_lower_axis)) * radial
	var actual_radial := (lower_pose.basis * lower_rest.basis.inverse() * rest_radial).slide(lower_axis).normalized()
	var palm_radial := (Basis(Quaternion(current_forward, lower_axis)) * hand_delta * radial).slide(lower_axis).normalized()
	var pronation := rad_to_deg(actual_radial.angle_to(palm_radial))
	check(pronation < 15.0, "%s forearm carries palm rotation without wrist twist (%.1f degrees)" % [note, pronation])

func grip_contact(side: String) -> Vector3:
	# The surviving left hand changes from support to trigger grip.
	if side == "L" and not actor.body_state.has_part(&"right_arm"):
		return actor.held_item_node.to_global(Vector3(-.025, -.023, .047))
	return actor.held_item_node.get_node("GripRight" if side == "R" else "GripLeft").global_position

func arm_snapshot() -> Dictionary:
	var result := {}
	for side in ["R", "L"]:
		if not actor.body_state.has_part(&"right_arm" if side == "R" else &"left_arm"): continue
		for part in ["upper_arm_", "forearm_", "hand_"]:
			var bone := skeleton.find_bone(part + side)
			result[part + side] = skeleton.get_bone_global_pose(bone)
	return result

func check_turn_frame(previous: Dictionary, note: String) -> Dictionary:
	var current := arm_snapshot()
	for name: String in current:
		var before: Transform3D = previous[name]
		var after: Transform3D = current[name]
		var angle := rad_to_deg(before.basis.get_rotation_quaternion().angle_to(after.basis.get_rotation_quaternion()))
		check(angle < 30.0, "%s %s changes smoothly between small mouse steps (%.1f degrees)" % [note, name, angle])
		if name.begins_with("forearm_"):
			check(before.origin.distance_to(after.origin) < .09, "%s %s elbow does not jump between frames" % [note, name])
	for side in ["R", "L"]:
		if not actor.body_state.has_part(&"right_arm" if side == "R" else &"left_arm"): continue
		check(palm_position(side).distance_to(grip_contact(side)) < .035, note + " " + side + " keeps palm contact during motion")
		check_wrist(side, note + " " + side)
	return current

func mouse_turn(yaw: float, pitch: float) -> void:
	var sensitivity: float = actor.MOUSE_SENSITIVITY * float(actor.game_settings.get_setting(&"sensitivity"))
	var invert := -1.0 if bool(actor.game_settings.get_setting(&"invert_y")) else 1.0
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(-yaw / sensitivity, -pitch / (sensitivity * invert))
	event.position = root.get_visible_rect().size * .5
	if DisplayServer.get_name() == "headless":
		# Dummy display cannot capture a mouse. Still exercise the same pose
		# sweep; a native run uses production input routing instead.
		actor.rotate_y(yaw)
		actor.camera.rotate_x(pitch)
		actor.camera.rotation.x = clampf(actor.camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	else:
		Input.parse_input_event(event)
	await steps(1)

func check_mouse_turns() -> void:
	await check_grips("two-arm", false)
	var previous := arm_snapshot()
	for direction in [-1.0, 1.0]:
		var start := actor.rotation.y
		for frame in 120:
			await mouse_turn(deg_to_rad(direction * 3.0), 0.0)
			previous = check_turn_frame(previous, "yaw direction=%.0f frame=%d" % [direction, frame])
			if frame == 0:
				check(absf(wrapf(actor.rotation.y - start, -PI, PI) - deg_to_rad(direction * 3.0)) < .001, "Turn input changes body yaw by the requested amount")
		check(absf(wrapf(actor.rotation.y - start, -PI, PI)) < .001, "A complete mouse turn returns to its starting heading")
	for walking in [false, true]:
		actor.set_physics_process(walking)
		if walking: Input.action_press("move_forward")
		await steps(24)
		if walking:
			check(actor.get_node("Visuals/Locomotion").current_clip == "jog_forward", "Turn regression exercises the production walking pose")
		previous = arm_snapshot()
		for target in [-80.0, 80.0, 0.0]:
			if target == 80.0: Input.action_press("weapon_aim")
			else: Input.action_release("weapon_aim")
			var start: float = actor.camera.rotation.x
			var count := maxi(1, int(ceil(absf(deg_to_rad(target) - start) / deg_to_rad(2.5))))
			var increment := (deg_to_rad(target) - start) / count
			for frame in count:
				await mouse_turn(deg_to_rad(.5), increment)
				previous = check_turn_frame(previous, "%s pitch target=%.0f frame=%d" % ["walking" if walking else "standing", target, frame])
			check(absf(actor.camera.rotation.x - deg_to_rad(target)) < .001, "Mouse sweep reaches full controller pitch endpoint")
		Input.action_release("move_forward")
		Input.action_release("weapon_aim")
		actor.set_physics_process(false)
		actor.velocity = Vector3.ZERO

func check_grips(mode: String, aiming: bool, pitch := 0.0, crawling := false) -> void:
	actor.body_state.reset()
	if mode == "left-only": actor.body_state.sever(&"right_arm")
	if mode == "right-only": actor.body_state.sever(&"left_arm")
	if crawling: actor.body_state.sever(&"left_leg")
	actor._apply_body_capabilities()
	actor.set_physics_process(false)
	actor.velocity = Vector3.ZERO
	actor.camera.rotation = Vector3(pitch, 0, 0)
	actor.refresh_inventory()
	if aiming: Input.action_press("weapon_aim")
	else: Input.action_release("weapon_aim")
	await steps(48 if crawling else 24)
	check(actor.held_item_node.is_visible_in_tree(), "%s keeps production pistol visible" % mode)
	for side in ["R", "L"]:
		if not actor.body_state.has_part(&"right_arm" if side == "R" else &"left_arm"): continue
		var contact := grip_contact(side)
		var error := palm_position(side).distance_to(contact)
		var note := "%s %s %s pitch=%.2f %s" % [mode, "ADS" if aiming else "hip", side, pitch, "crawl" if crawling else "standing"]
		print("PISTOL_VISUAL_CONTACT ", note, " error=", snappedf(error, .0001), " palm=", palm_position(side), " grip=", contact)
		check(error < .035, "%s real palm contacts authored pistol grip (%.4fm)" % [note, error])
		check_fingers(side, note)
		check_wrist(side, note)
	var muzzle: Node3D = actor.held_item_node.get_node("Muzzle")
	check((-muzzle.global_basis.z).dot(-actor.camera.global_basis.z) > .995, "%s barrel follows actual camera aim" % mode)
	check(actor.held_item_node.global_basis.get_scale().is_equal_approx(Vector3.ONE), "%s held pistol preserves world dimensions" % mode)

func run() -> void:
	if DisplayServer.get_name() == "headless": print("NOTE: Dummy display uses pose rotations; native run verifies captured mouse routing.")
	else: root.title = "ApocalypseRV - Pistol Turn Regression"
	inspect_body("res://props/pistol.tscn", 3000, Vector3(.025, .09, .15), Vector3(.10, .23, .30))
	inspect_body("res://props/pistol_ammo.tscn", 500, Vector3(.05, .025, .035), Vector3(.15, .09, .12))
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	world.add_child(floor_body)
	actor = load("res://player/player.tscn").instantiate()
	world.add_child(actor)
	await steps(30)
	check(actor.is_on_floor(), "Visual fixture settles on a real floor before freezing motion")
	actor.set_physics_process(false)
	actor.camera.get_node("InteractRay").set_physics_process(false)
	check(actor.add_item("Pistol", false, "res://props/pistol.tscn"), "Production player holds asset under test")
	skeleton = actor.get_node("Visuals").skeleton
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for mode in ["two-arm", "left-only", "right-only"]:
		for pitch in [deg_to_rad(-80.0), -1.1, -.35, 0.0, .35, 1.1, deg_to_rad(80.0)]:
			await check_grips(mode, false, pitch)
			await check_grips(mode, true, pitch)
		await check_grips(mode, false, 0.0, true)
		await check_grips(mode, true, 0.0, true)
	await check_mouse_turns()
	Input.action_release("weapon_aim")
	actor.body_state.reset()
	actor._apply_body_capabilities()
	actor.set_physics_process(false)
	var carry: Node = actor.get_node("Visuals/Carry")
	for action in ["empty-slot", "drop", "consume"]:
		if actor.inventory.items.is_empty(): actor.add_item("Pistol", false, "res://props/pistol.tscn")
		actor._set_active_slot(0)
		await steps(20)
		check(carry.right_weight == 1.0 and carry.left_weight == 1.0, action + " starts with both arms holding the pistol")
		if action == "empty-slot": actor._set_active_slot(4)
		elif action == "drop": actor.drop_item()
		else: actor.consume_active_item()
		await steps(2)
		check(not is_instance_valid(actor.held_item_node), action + " removes the held preview")
		check(carry.grip_kind != "pistol", action + " clears pistol wrist ownership during arm fade")
		await steps(20)
		check(carry.right_weight == 0.0 and carry.left_weight == 0.0 and carry.base_rotations.is_empty(), action + " restores clean locomotion after preview is freed")
	world.free()
	if failures.is_empty():
		print("PASS: pistol body budgets, dimensions, actual palm contacts and bounded finger poses")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

extends SceneTree
## Production inventory, weapon timing, input edges and capability boundaries.
const PISTOL := "res://props/pistol.tscn"
const AMMO := "res://props/pistol_ammo.tscn"
var failures: Array[String] = []
var world: Node3D
var actor: CharacterBody3D
var serial := 0

func _init() -> void: run.call_deferred()

func check(value: bool, note: String) -> void:
	if not value: failures.append(note)

func rounds() -> int:
	return int(actor.inventory.active_item().get("state", {}).get("pistol", {}).get("loaded_rounds", -1))

func total_ammo() -> int:
	var total := 0
	for record: Dictionary in actor.inventory.items:
		if record.scene_path == PISTOL: total += int(record.state.pistol.loaded_rounds)
		if record.scene_path == AMMO: total += int(record.state.ammo.rounds)
	return total

func add_pistol(count: int) -> void:
	serial += 1
	check(actor.add_item("Pistol", false, PISTOL, {"id": "test-pistol-%d" % serial, "condition": 100.0, "pistol": {"loaded_rounds": count}}), "Grant pistol with exact round count")

func add_ammo(count: int) -> void:
	serial += 1
	check(actor.add_item("Pistol ammunition", false, AMMO, {"id": "test-ammo-%d" % serial, "condition": 100.0, "ammo": {"rounds": count}}), "Grant ammunition with exact round count")

func clear_bag() -> void:
	actor.weapon.cancel_actions()
	actor.weapon.advance(2.0)
	actor.inventory.items.clear()
	actor.inventory.active_slot = 0
	actor.refresh_inventory()

func mouse(button: int, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event

func steps(count: int = 2) -> void:
	for index in count:
		await physics_frame
		await process_frame

func check_animated_copies(view: Node, source_root: Node3D, note: String) -> void:
	check(source_root != null, "Pistol has animated source: " + note)
	if source_root == null: return
	var count := 0
	for entry: Dictionary in view.item_meshes:
		if entry.source != source_root and not source_root.is_ancestor_of(entry.source): continue
		for copy: MeshInstance3D in entry.copies:
			if copy.layers != 1 << 21: continue
			count += 1
			check(copy.global_transform.is_equal_approx(entry.source.global_transform) and copy.visible == entry.source.visible, "Viewmodel follows animated source transform and visibility: " + note)
	check(count > 0, "Animated pistol source has a rendered viewmodel copy: " + note)

func check_pistol_viewmodel() -> void:
	clear_bag()
	var view: Node = actor.get_node("Visuals/FirstPersonCarry")
	var observer := Camera3D.new()
	world.add_child(observer)
	observer.make_current()
	var competing_lights: Array[OmniLight3D] = []
	for index in 4:
		var light := OmniLight3D.new()
		world.add_child(light)
		light.global_position = actor.camera.global_position
		competing_lights.append(light)
	add_pistol(4)
	add_ammo(20)
	await steps(20)
	view.update_view()
	var pistol: Pistol = actor.held_item_node
	pistol.set_process(false)
	var held_pose := pistol.global_transform
	var muzzle_pose: Transform3D = pistol.get_node("Muzzle").global_transform
	var camera_pose: Transform3D = actor.camera.global_transform
	var baseline: float = actor.camera.fov
	actor.camera.make_current()
	view.update_view()
	check(view.active and view.arm_meshes["R"].is_visible_in_tree() and view.arm_meshes["L"].is_visible_in_tree(), "Pistol viewmodel renders both surviving arms")
	check(pistol.global_transform.is_equal_approx(held_pose) and pistol.get_node("Muzzle").global_transform.is_equal_approx(muzzle_pose), "Pistol view activation preserves the authoritative held and muzzle transforms")
	check(actor.camera.global_transform.is_equal_approx(camera_pose) and is_equal_approx(actor.camera.fov, baseline), "Pistol view activation preserves gameplay camera pose and FOV")
	var muzzle_light: Light3D = pistol.get_node("Muzzle/Light")
	check(view.held_light_copies.has(muzzle_light.get_instance_id()), "Invisible muzzle light is bound before firing")
	if view.held_light_copies.has(muzzle_light.get_instance_id()):
		var light_copy: Light3D = view.held_light_copies[muzzle_light.get_instance_id()].copy
		check(not light_copy.visible, "Unfired muzzle copy remains dark")
		check(actor.weapon.try_fire() and rounds() == 3, "Viewmodel firing spends one canonical round")
		pistol._process(.01)
		view.update_view()
		check(muzzle_light.visible and light_copy.visible and light_copy.layers == 1 << 21 and light_copy.global_transform.is_equal_approx(muzzle_light.global_transform), "Muzzle copy lights immediately at the real emitter transform")
		var slide := pistol.find_child("Slide", true, false) as Node3D
		check(slide != null and slide.position.z > .001, "Firing animates the real slide")
		check_animated_copies(view, slide, "recoiling slide")
		check_animated_copies(view, pistol.get_node("Muzzle/Flash"), "visible muzzle flash")
		pistol._process(.10)
		view.update_view()
		check(view.held_light_copies[muzzle_light.get_instance_id()].copy == light_copy and not light_copy.visible, "The persistent muzzle copy switches off immediately after the flash")
		check_animated_copies(view, pistol.get_node("Muzzle/Flash"), "hidden muzzle flash")
	check(actor.weapon.start_reload(), "Viewmodel pistol starts its normal reload")
	actor.weapon.advance(.6)
	var magazine := pistol.find_child("Magazine", true, false) as Node3D
	check(magazine != null and magazine.position.y < -.01, "Reload moves the real magazine")
	view.update_view()
	check_animated_copies(view, magazine, "reload magazine")
	actor.weapon.cancel_actions()
	Input.action_press("weapon_aim")
	actor.weapon.advance(.16)
	for pitch: float in [0.0, -.65, .65]:
		actor.camera.rotation.x = pitch
		await steps(20)
		view.update_view()
		check(actor.weapon.aim_weight > .99 and is_equal_approx(view.camera.fov, actor.camera.fov), "Full ADS viewmodel retains the gameplay FOV at pitch " + str(pitch))
		for point: Vector3 in [pistol.muzzle_position(), pistol.muzzle_position() + pistol.global_basis.x * .08]:
			var gameplay: Vector2 = actor.camera.unproject_position(point) / root.get_visible_rect().size
			var rendered: Vector2 = view.camera.unproject_position(point) / Vector2(view.viewport.size)
			check(gameplay.distance_to(rendered) < .0001, "Full ADS projection matches the gameplay sight line at pitch " + str(pitch))
	Input.action_release("weapon_aim")
	actor.weapon.advance(.16)
	actor.camera.rotation = Vector3.ZERO
	actor.body_state.sever(&"right_arm")
	actor._apply_body_capabilities()
	await steps(20)
	view.update_view()
	check(view.active and view.arm_meshes["L"].is_visible_in_tree() and not view.arm_meshes["R"].is_visible_in_tree(), "Pistol viewmodel supports the surviving left arm without a ghost right arm")
	actor.body_state.reset()
	actor._apply_body_capabilities()
	clear_bag()
	for light: OmniLight3D in competing_lights: light.queue_free()
	observer.queue_free()
	await steps()

func run() -> void:
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	actor = load("res://player/player.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.weapon.set_physics_process(false)
	actor.camera.get_node("InteractRay").set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await physics_frame
	await process_frame
	await check_pistol_viewmodel()
	add_pistol(4)
	check(actor.weapon.can_use(), "Normal player can use held pistol")
	var identity: String = actor.inventory.active_item().state.id
	check(actor.weapon.try_fire() and rounds() == 3, "Firing spends exactly one canonical round")
	check(actor.held_item_node.loaded_rounds == 3, "Held presentation follows canonical round count")
	check(not actor.weapon.try_fire() and rounds() == 3, "Immediate repeat respects 0.3-second cooldown")
	actor.weapon.advance(0.299)
	check(not actor.weapon.try_fire(), "Shot interval rejects just below the boundary")
	actor.weapon.advance(0.0011)
	check(actor.weapon.try_fire() and rounds() == 2, "Shot interval permits the next shot at the boundary")
	check(actor.inventory.active_item().state.id == identity, "Shots preserve pistol identity")
	actor.add_item("Scrap", false, "res://props/scrap.tscn")
	actor._set_active_slot(1)
	actor._set_active_slot(0)
	check(not actor.weapon.try_fire() and rounds() == 2, "Switching away and back cannot reset shot cooldown")
	actor.weapon.advance(0.31)
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true))
	check(rounds() == 1, "Production left-click dispatch fires once")
	actor.weapon.advance(1.0)
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true))
	check(rounds() == 1, "Held click and elapsed time never create automatic shots")
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, false))
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true))
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, false))
	actor.weapon.advance(0.31)
	check(not actor.weapon.try_fire() and rounds() == 0, "Empty pistol refuses a shot without negative ammunition")

	clear_bag()
	add_ammo(3)
	add_pistol(4)
	add_ammo(9)
	actor._set_active_slot(1)
	identity = actor.inventory.active_item().state.id
	var total := total_ammo()
	check(actor.weapon.start_reload(), "Partly loaded pistol begins reload across two boxes")
	check(not actor.weapon.start_reload() and not actor.weapon.try_fire(), "Reload blocks duplicate reload and fire")
	check(total_ammo() == total and rounds() == 4, "Starting reload reserves no consumable rounds")
	actor.weapon.advance(1.49)
	check(rounds() == 4 and total_ammo() == total, "Before completion all magazine and box ownership is unchanged")
	actor.weapon.advance(0.02)
	check(rounds() == 12 and total_ammo() == total, "Completion fills magazine and conserves ammunition")
	check(actor.inventory.active_item().state.id == identity and actor.inventory.active_slot == 0, "Removing an earlier exhausted box preserves selected pistol by ID")
	check(actor.inventory.items.size() == 2 and actor.inventory.items[1].state.ammo.rounds == 4, "Reload removes empty first box and retains partial second box")
	check(not actor.weapon.start_reload(), "Full magazine rejects reload")
	check(actor.held_item_node.loaded_rounds == 12, "Reload refreshes held presentation")
	check(actor.enter_equipment_placement(), "Pistol retains normal Item placement")
	var placement_mode: int = actor.placement.placement_mode
	var reload_key := InputEventKey.new()
	reload_key.physical_keycode = KEY_R
	reload_key.pressed = true
	actor._unhandled_input(reload_key)
	check(actor.placement.placement_mode != placement_mode and actor.weapon.reload_remaining == 0.0, "R remains placement rotation mode while preview is active")
	actor.cancel_equipment_placement()

	clear_bag()
	add_pistol(0)
	check(not actor.weapon.start_reload(), "Empty magazine without reserve cannot reload")
	add_ammo(2)
	check(actor.weapon.start_reload(), "Partial reserve reload is allowed")
	actor.weapon.advance(1.51)
	check(rounds() == 2 and total_ammo() == 2, "Insufficient reserve loads available rounds without invention")
	check(actor.inventory.items.size() == 1, "Exhausted partial reserve box is removed exactly once")

	for interruption in ["switch", "placement", "ui", "settings", "seat", "death", "ladder", "arm", "sprint", "crawl"]:
		clear_bag()
		actor.body_state.reset()
		actor.velocity = Vector3.ZERO
		add_pistol(1)
		add_ammo(20)
		check(actor.weapon.start_reload(), "Reload begins before %s interruption" % interruption)
		actor.weapon.advance(0.6)
		total = total_ammo()
		var seat: Node3D
		match interruption:
			"switch": actor._set_active_slot(1)
			"placement": check(actor.enter_equipment_placement(), "Production placement begins while a reload is pending")
			"ui": actor.in_ui_mode = true
			"settings": actor.set_settings_open(true)
			"seat":
				seat = Node3D.new()
				world.add_child(seat)
				actor.seated_in = seat
			"death": actor.is_player_dead = true
			"ladder": actor.locomotion_state = actor.LocomotionState.CLIMBING
			"arm": actor.body_state.sever(&"left_arm")
			"sprint":
				actor.velocity = Vector3(8, 0, 0)
				Input.action_press("sprint")
			"crawl":
				actor.body_state.sever(&"left_leg")
				actor.velocity = Vector3(0.5, 0, 0)
		actor.weapon.advance(2.0)
		check(total_ammo() == total and actor.inventory.items[0].state.pistol.loaded_rounds == 1, "%s interruption spends no ammunition" % interruption)
		check(actor.weapon.reload_remaining <= 0.0, "%s interruption cancels pending completion" % interruption)
		actor.in_ui_mode = false
		actor.cancel_equipment_placement()
		actor.set_settings_open(false)
		actor.seated_in = null
		actor.is_player_dead = false
		actor.locomotion_state = actor.LocomotionState.NORMAL
		actor.body_state.reset()
		actor.velocity = Vector3.ZERO
		Input.action_release("sprint")
		if seat: seat.free()
		actor._set_active_slot(0)
		actor.refresh_inventory()

	clear_bag()
	add_pistol(6)
	add_ammo(20)
	actor.body_state.sever(&"left_arm")
	check(actor.weapon.can_use() and actor.weapon.try_fire(), "One surviving arm can fire")
	check(not actor.weapon.start_reload(), "Reload requires two arms")
	actor.body_state.sever(&"right_arm")
	check(not actor.weapon.can_use() and not actor.weapon.try_fire(), "No surviving arms blocks pistol")
	actor.body_state.reset()
	actor.body_state.sever(&"left_leg")
	actor.velocity = Vector3.ZERO
	actor.weapon.advance(1.0)
	check(actor.weapon.can_use(), "Stationary crawl can use pistol")
	actor.velocity = Vector3(0.1, 0, 0)
	check(not actor.weapon.can_use(), "Moving crawl blocks pistol")
	actor.body_state.reset()
	actor.velocity = Vector3.ZERO
	actor.current_stamina = 0.0
	actor.stamina_exhausted = true
	Input.action_press("sprint")
	actor.velocity = Vector3(8, 0, 0)
	check(not actor.weapon.can_use() and not actor.weapon.try_fire(), "Sprint-speed frame blocks pistol even as stamina becomes exhausted")
	actor.velocity = Vector3(5, 0, 0)
	check(actor.weapon.can_use(), "Walking with exhausted Shift held still permits pistol")
	actor.velocity = Vector3.ZERO
	check(actor.weapon.can_use(), "Stationary Shift held permits pistol")
	Input.action_release("sprint")
	actor.current_stamina = actor.MAX_STAMINA
	actor.stamina_exhausted = false

	var baseline: float = actor.camera.fov
	Input.action_press("weapon_aim")
	actor.weapon.advance(0.16)
	check(actor.weapon.aim_weight > 0.99 and is_equal_approx(actor.camera.fov, baseline * 0.8), "Held right aim reaches intended 0.15-second FOV")
	Input.action_release("weapon_aim")
	actor.weapon.advance(0.16)
	check(is_equal_approx(actor.camera.fov, baseline), "Aim release restores baseline FOV")
	Input.action_press("weapon_aim")
	actor.weapon.advance(0.16)
	actor.in_ui_mode = true
	var before := rounds()
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true))
	actor.weapon.advance(0.5)
	check(rounds() == before and is_equal_approx(actor.camera.fov, baseline), "UI blocks shooting and restores aimed FOV")
	Input.action_release("weapon_aim")
	actor.in_ui_mode = false
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, false))
	actor.set_settings_open(true)
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true))
	check(rounds() == before and not actor.weapon.start_reload(), "Settings protects gameplay input and reload")
	actor.set_settings_open(false)
	actor._unhandled_input(mouse(MOUSE_BUTTON_LEFT, false))
	world.free()
	if failures.is_empty():
		print("PASS: pistol ammunition conservation, reload interruption, input, cooldown and capability gates")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

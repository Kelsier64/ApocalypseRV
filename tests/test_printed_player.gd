extends SceneTree
## Real crafting, persistent idle bodies and the single-controller E transfer contract.
var failures: Array[String] = []
const BODY_SCENE := "res://props/printed_player.tscn"

func _init() -> void:
	_run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(10, 3, 2)
	await process_frame
	await physics_frame
	var station: CraftingStation = rv.get_node("CraftingStation")
	station.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(10, 3, -3)), rv)
	var recipe := RecipeCatalog.find("printed_player")
	check(recipe != null and recipe.scene_path == BODY_SCENE, "Official catalog contains the playable printed body recipe")
	check(not station.request_craft("printed_player"), "Body cannot fabricate without materials")
	rv.inventory = {}
	rv.deposit_materials(recipe.costs)
	rv.current_power = 50.0
	var power_before: float = rv.current_power
	check(station.request_craft("printed_player"), "Exact funded materials queue the official body recipe")
	for material in recipe.costs:
		check(rv.get_item_count(material) == 0, "Body inputs are reserved exactly once: " + material)
	station.step_work(recipe.duration)
	var body: PrintedPlayerBody
	for item in WorldEntities.get_container(world).get_children():
		if item is PrintedPlayerBody: body = item
	check(body != null and station.jobs.is_empty(), "Completion creates one persistent body and consumes the queue")
	check(is_equal_approx(power_before - rv.current_power, recipe.power_cost), "Body fabrication consumes the configured power exactly once")
	if body == null:
		world.queue_free()
		await process_frame
		_finish()
		return
	body.freeze = true
	check(body.get_node("Model").scale.is_equal_approx(Vector3.ONE), "Body model is full scale")
	check(not body.get_node("Model").find_children("*", "MeshInstance3D", true, false).is_empty(), "Body has the actual player mesh")
	check(is_equal_approx(body.get_node("CollisionShape3D").shape.height, 1.6), "Body collision is full standing height")
	check(not body.can_pickup(player), "Idle bodies cannot duplicate ownership through inventory")
	var active_id := player.get_instance_id()
	var active_camera: Camera3D = player.camera
	var active_ui: Node = player.health_bar
	var stored_id := body.persistent_id
	player.current_player_health = 47.0
	player.current_stamina = 23.0
	player.stamina_exhausted = true
	player.stamina_recovery_delay_remaining = 1.25
	player.body_state.sever(&"left_arm")
	player._apply_body_capabilities()
	var scrap: Item = load("res://props/scrap.tscn").instantiate()
	world.add_child(scrap)
	check(player.add_prop_item(scrap, scrap.scene_file_path), "Fixture inventory owns one Item")
	scrap.queue_free()
	var inventory_before: Array = player.inventory.items.duplicate(true)
	var old_origin := player.global_position
	var printed_feet := body.global_position
	body.linear_velocity = Vector3(1.0, 0.0, 2.0)
	player.velocity = Vector3(3.0, 0.0, 1.0)
	await physics_frame
	# Frozen body velocities can be overwritten by Jolt; set immediately before transfer.
	body.linear_velocity = Vector3(1.0, 0.0, 2.0)
	var ray := active_camera.get_node("InteractRay")
	check(ray.get_prompt(body).contains("切換控制"), "Actual interaction ray advertises E control transfer")
	ray._step_buttons(body, true, false, 0.0)
	var transferred_origin := player.global_position
	ray._step_buttons(body, true, false, .5)
	check(player.global_position == transferred_origin, "Holding E cannot repeatedly swap bodies")
	ray._step_buttons(body, false, false, 0.0)
	check(player.get_instance_id() == active_id and player.camera == active_camera and player.health_bar == active_ui, "E transfer retains the production controller, camera and HUD identity")
	check(player.global_position.is_equal_approx(printed_feet - Vector3.UP * .25), "E transfers the playable actor to the standing body boot origin")
	check(body.global_position.is_equal_approx(old_origin + Vector3.UP * .25), "The abandoned body remains at the old player's boot origin")
	check(is_equal_approx(player.current_player_health, 100) and is_equal_approx(body.current_health, 47), "Health swaps between bodies")
	check(player.body_state.has_part(&"left_arm") and not body.body_state.has_part(&"left_arm"), "Limb state follows physical bodies")
	check(not body.get_node("Model").visible, "Injured surrogate replaces complete standing model with anatomical pieces")
	var wounds := body.find_children("Wound_left_arm*", "MeshInstance3D", true, false)
	check(not wounds.is_empty() and wounds[0].visible, "Abandoned injured body shows its missing-arm wound")
	for piece in body.find_children("Part_left_arm*", "MeshInstance3D", true, false):
		check(not piece.visible, "Abandoned injured body hides severed limb geometry")
	check(is_equal_approx(player.current_stamina, 100) and is_equal_approx(body.stamina, 23) and body.stamina_exhausted and is_equal_approx(body.recovery_delay, 1.25), "Stamina and exhaustion swap without regenerating the old body")
	check(player.inventory.items == inventory_before and body.persistent_id == stored_id, "Equipment travels with consciousness without new inventory or idle body identities")
	check(player.velocity.is_equal_approx(Vector3(1, 0, 2)) and body.linear_velocity.is_equal_approx(Vector3(3, 0, 1)), "Each destination inherits its previous physical velocity")
	check(root.find_children("*", "CharacterBody3D", true, false).size() == 1, "Switching creates no second active actor")
	var saved := WorldActorSnapshot.capture(body)
	check(WorldActorSnapshot.validation_error(saved, "body").is_empty(), "Printed body has a valid complete world snapshot")
	check(ItemState.valid(BODY_SCENE, body.capture_item_state()), "Idle body's health, limbs and stamina satisfy canonical Item schema")
	var invalid: Dictionary = saved.state.duplicate(true)
	invalid.printed_body.stamina = NAN
	check(not ItemState.valid(BODY_SCENE, invalid), "Nonfinite fabricated-body stamina is rejected")
	invalid = saved.state.duplicate(true)
	invalid.printed_body.body.present.head = false
	check(not ItemState.valid(BODY_SCENE, invalid), "A living headless fabricated body is rejected")
	var ordinary := load("res://props/scrap.tscn").instantiate() as Item
	var spoof := ordinary.capture_item_state()
	spoof.printed_body = saved.state.printed_body
	check(not ItemState.valid("res://props/scrap.tscn", spoof), "Body payload cannot attach to ordinary Item scenes")
	ordinary.free()
	body.queue_free()
	await process_frame
	body = WorldActorSnapshot.restore(saved, WorldEntities.get_container(world)) as PrintedPlayerBody
	check(body != null and body.capture_item_state() == saved.state, "World save/load restores the abandoned body exactly")
	await physics_frame
	check(body.transfer_control(player), "Restored abandoned body supports switching back")
	check(is_equal_approx(player.current_player_health, 47) and not player.body_state.has_part(&"left_arm") and is_equal_approx(player.current_stamina, 23) and is_equal_approx(player.stamina_recovery_delay_remaining, 1.25), "Switch-back restores the old body's physiology")
	check(player.inventory.items == inventory_before and body.current_health == 100, "Switch-back preserves equipment and leaves the newer healthy body behind")
	await _check_refusals(world, player, body)
	await _check_carrier(world, rv, player, body)
	body.body_state.sever(&"left_leg")
	body._apply_body_visual()
	check(body.transfer_control(player), "Leg-injured stored body can receive control in clear space")
	check(player.is_crawling() and absf(player.body_collision_shape.basis.y.dot(Vector3.UP)) < .001, "Transferred leg injuries restore actual crawling capability and collision")
	world.queue_free()
	await process_frame
	_finish()

func _check_refusals(world: Node3D, player: CharacterBody3D, body: PrintedPlayerBody) -> void:
	var original := player.global_transform
	player.in_ui_mode = true
	check(not body.transfer_control(player), "UI blocks body switch")
	player.in_ui_mode = false
	player.settings_open = true
	check(not body.transfer_control(player), "Settings blocks body switch")
	player.settings_open = false
	var operation := Node3D.new()
	world.add_child(operation)
	player.placement.placing_equipment = operation
	check(not body.transfer_control(player), "Equipment placement blocks body switch")
	player.placement.placing_equipment = null
	player.grab_control.captor = operation
	check(not body.transfer_control(player), "Captor ownership blocks body switch")
	player.grab_control.captor = null
	operation.queue_free()
	player.is_player_dead = true
	check(not body.transfer_control(player), "Dead controller cannot switch bodies")
	player.is_player_dead = false
	player.locomotion_state = player.LocomotionState.CLIMBING
	check(not body.transfer_control(player), "Climbing cannot switch bodies")
	player.locomotion_state = player.LocomotionState.NORMAL
	var seat := Node3D.new()
	world.add_child(seat)
	player.seated_in = seat
	check(not body.transfer_control(player), "Seated controller cannot switch bodies")
	player.seated_in = null
	seat.queue_free()
	body.current_health = 0
	check(not body.transfer_control(player), "Dead fabricated body cannot receive control")
	body.current_health = 100
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(2, 2, 2)
	obstacle.add_child(collision)
	world.add_child(obstacle)
	obstacle.global_position = body.global_position + Vector3.UP * .8
	await physics_frame
	check(not body.transfer_control(player) and player.global_transform == original, "Destination obstruction blocks transfer without mutation")
	obstacle.queue_free()
	await physics_frame
	body.presentation_only = true
	check(not body.transfer_control(player), "Presentation-only body cannot be activated")
	body.presentation_only = false

func _check_carrier(world: Node3D, rv: Chassis, player: CharacterBody3D, body: PrintedPlayerBody) -> void:
	var deck := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, .2, 4)
	collision.shape = box
	deck.add_child(collision)
	rv.add_child(deck)
	deck.global_position = Vector3(20, 4, 0)
	body.global_position = deck.global_position + Vector3.UP * .1
	player.global_position = Vector3(20, 4, 5)
	await physics_frame
	rv.linear_velocity = Vector3(2, 0, 0)
	rv.angular_velocity = Vector3(0, .1, 0)
	var expected := ClimbMath.point_velocity(rv, body.global_position - Vector3.UP * .25)
	body.linear_velocity = expected
	check(body.transfer_control(player), "Body on a moving RV accepts clear transfer: " + body.last_transfer_error)
	check(player.rv_support.rv == rv and player.rv_support.surface == deck and player.velocity.length() < .001, "New controller tracks the destination carrier without adding its velocity twice")
	check(player.rv_support.carrier_velocity.is_equal_approx(expected), "Destination inherits the RV point velocity including rotation")
	deck.queue_free()
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	await process_frame

func _finish() -> void:
	if failures.is_empty(): print("PASS: official full-size player fabrication, E control transfer, single actor ownership, physiology, persistence and safety")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

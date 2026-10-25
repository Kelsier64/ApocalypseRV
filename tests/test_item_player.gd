extends SceneTree
## Item ownership transitions through production player inventory and gestures.
var failures: Array[String] = []
var world: Node3D
var actor: CharacterBody3D
var ray: RayCast3D
var entities: Node3D

func _init() -> void: run.call_deferred()

func check(value: bool, note: String) -> void:
	if not value: failures.append(note)

func steps(count: int = 2) -> void:
	for index in count:
		await physics_frame
		await process_frame

func find_item(id: String) -> Item:
	for child in entities.get_children():
		if child is Item and child.persistent_id == id and not child.presentation_only and not child.is_queued_for_deletion(): return child
	return null

func make_item(path: String, at: Vector3) -> Item:
	var item := load(path).instantiate() as Item
	item.position = at
	entities.add_child(item)
	return item

func clear_bag() -> void:
	actor.cancel_equipment_placement()
	actor.inventory.items.clear()
	actor.inventory.active_slot = 0
	actor.refresh_inventory()

func food_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	actor._input(event)

func check_survival() -> void:
	var whole := PlayerSurvival.new()
	var split := PlayerSurvival.new()
	check(whole.advance(1200.0) == 0 and whole.hunger == 0.0, "Full food lasts exactly 20 simulation minutes")
	check(whole.advance(4.99) == 0 and whole.advance(.01) == 1, "Starvation first damages at five seconds")
	var split_ticks := 0
	for step in 12050: split_ticks += split.advance(.1)
	check(split.hunger == 0.0 and split_ticks == 1 and is_zero_approx(split.starvation_elapsed), "Frame partition preserves zero crossing and starvation boundary")
	var crossed := PlayerSurvival.new()
	crossed.hunger = PlayerSurvival.DRAIN_PER_SECOND * 2.0
	check(crossed.advance(13.0) == 2 and is_equal_approx(crossed.starvation_elapsed, 1.0), "Only the post-zero portion of a frame counts toward starvation")
	for invalid: Variant in [{}, {"hunger": NAN, "starvation_elapsed": 0.0}, {"hunger": -1.0, "starvation_elapsed": 0.0}, {"hunger": 101.0, "starvation_elapsed": 0.0}, {"hunger": true, "starvation_elapsed": 0.0}, {"hunger": 0.0, "starvation_elapsed": 5.0}, {"hunger": 1.0, "starvation_elapsed": .1}]:
		check(not PlayerSurvival.valid_state(invalid), "Malformed survival state is refused: " + str(invalid))
	var saved := crossed.capture()
	whole.restore(saved)
	whole.restore({"hunger": 999.0})
	check(whole.capture() == saved, "Validated survival restore is exact and refuses malformed replacement")
	whole.nourish(200.0)
	check(whole.hunger == 100.0 and whole.starvation_elapsed == 0.0, "Nutrition caps hunger and clears starvation progress")
	actor.survival.hunger = 40.0
	actor.current_stamina = 0.0
	actor._update_stamina(1.0, false)
	check(actor.current_stamina == 18.0, "Hunger 40 retains full stamina recovery")
	actor.survival.hunger = 39.99
	actor.current_stamina = 0.0
	actor._update_stamina(1.0, false)
	check(actor.current_stamina == 9.0, "Below 40 halves stamina recovery")
	Input.action_press("sprint")
	actor.survival.hunger = 20.01
	check(actor._can_sprint(true), "Hunger above 20 permits sprint")
	actor.survival.hunger = 20.0
	check(not actor._can_sprint(true), "Hunger exactly 20 blocks sprint immediately")
	Input.action_release("sprint")
	var start := StartRun.new()
	start.name = "StartRun"
	world.add_child(start)
	actor.survival.reset()
	actor._advance_survival(60.0)
	check(actor.survival.hunger == 100.0, "Preparing tutorial stops hunger")
	start.phase = "started"
	actor.in_ui_mode = true
	actor.settings_open = true
	actor._advance_survival(60.0)
	check(is_equal_approx(actor.survival.hunger, 95.0), "World simulation continues hunger through UI and settings")
	actor.in_ui_mode = false
	actor.settings_open = false
	var manager := PoiInstanceManager.new()
	manager.name = "PoiInstances"
	world.add_child(manager)
	manager.busy = true
	actor._advance_survival(60.0)
	check(is_equal_approx(actor.survival.hunger, 95.0), "Outdoor POI transition stops hunger before reparent")
	var indoor := Node3D.new()
	manager.add_child(indoor)
	actor.reparent(indoor)
	actor._advance_survival(60.0)
	check(is_equal_approx(actor.survival.hunger, 95.0), "Owning POI transition stops hunger after reparent")
	manager.busy = false
	actor._advance_survival(60.0)
	check(is_equal_approx(actor.survival.hunger, 90.0), "Indoor exploration continues the same player survival state")
	actor.reparent(world)
	world.set_meta("checkpoint_staging", true)
	actor._advance_survival(60.0)
	check(is_equal_approx(actor.survival.hunger, 90.0), "Checkpoint staging cannot simulate hunger")
	world.remove_meta("checkpoint_staging")
	var checkpoint := root.get_node("Checkpoint")
	checkpoint.loading = true
	actor._advance_survival(60.0)
	check(is_equal_approx(actor.survival.hunger, 90.0), "Checkpoint loading stops hunger")
	checkpoint.loading = false
	actor.survival.restore({"hunger": 0.0, "starvation_elapsed": 4.0})
	actor.damage_cooldown = .4
	actor.current_player_health = 100.0
	actor._advance_survival(1.0)
	check(actor.current_player_health == 99.0 and actor.damage_cooldown == .4, "Starvation bypasses combat cooldown without changing immunity")
	actor.is_player_dead = true
	actor._advance_survival(10.0)
	check(actor.current_player_health == 99.0 and actor.survival.starvation_elapsed == 0.0, "Dead player stops hunger and starvation")
	actor.is_player_dead = false
	actor.damage_cooldown = 0.0
	actor.current_player_health = 100.0
	actor.current_stamina = 100.0
	actor.survival.reset()
	start.free()
	manager.free()

func check_eating() -> void:
	clear_bag()
	var path: String = FoodCatalog.SCENES[0]
	check(actor.add_item("Renamed meal", false, path), "Food scene receives canonical inventory identity")
	food_button(false)
	food_button(true)
	check(not actor.consumables.eating, "Full hunger refuses eating")
	actor.survival.hunger = 80.0
	actor.current_player_health = 67.0
	actor.current_stamina = 53.0
	food_button(false)
	food_button(true)
	actor.crouching = true
	actor.consumables.advance(actor, 1.99)
	check(actor.consumables.eating and actor.inventory.items.size() == 1, "Crouching allows hold progress without early consumption")
	actor.consumables.advance(actor, .01)
	check(actor.inventory.items.is_empty() and actor.survival.hunger == 100.0 and actor.current_player_health == 67.0 and actor.current_stamina == 53.0, "Two-second eat consumes exactly one and caps nutrition without healing")
	actor.crouching = false
	actor.add_item("Meal", false, path)
	actor.survival.hunger = 50.0
	food_button(true)
	check(not actor.consumables.eating, "Held button cannot repeat after completion")
	food_button(false)
	food_button(true)
	actor.consumables.advance(actor, 1.0)
	actor.damage_cooldown = .1
	actor.take_damage(1.0)
	check(actor.consumables.eating, "Rejected combat hit does not cancel eating")
	actor.damage_cooldown = 0.0
	actor.take_damage(1.0)
	check(not actor.consumables.eating and actor.inventory.items.size() == 1, "Actual damage cancels eating without consuming")
	actor.consumables.advance(actor, 5.0)
	food_button(true)
	check(not actor.consumables.eating, "Interrupted hold needs a fresh release and press")
	for reason: String in ["sprint", "jump", "settings", "ui", "climb", "seat", "dead", "arm", "slot", "identity", "remove", "placement"]:
		clear_bag()
		actor.add_item("Meal", false, path)
		actor.add_item("Second meal", false, path)
		food_button(false)
		food_button(true)
		actor.consumables.advance(actor, 1.0)
		match reason:
			"sprint", "jump":
				var event := InputEventAction.new()
				event.action = reason
				event.pressed = true
				actor._input(event)
			"settings": actor.set_settings_open(true)
			"ui": actor.enter_ui_mode()
			"climb": actor.locomotion_state = actor.LocomotionState.CLIMBING
			"seat": actor.seated_in = world
			"dead": actor.is_player_dead = true
			"arm":
				actor.body_state.sever(&"left_arm")
				actor.body_state.sever(&"right_arm")
			"slot": actor._set_active_slot(1)
			"identity": actor.inventory.items[0].state.id = "replacement-id"
			"remove": actor.inventory.items.remove_at(0)
			"placement": actor.enter_equipment_placement()
		actor.consumables.advance(actor, 2.0)
		check(not actor.consumables.eating and actor.survival.hunger == 50.0, "Eating interruption is atomic: " + reason)
		actor.is_player_dead = false
		actor.locomotion_state = actor.LocomotionState.NORMAL
		actor.seated_in = null
		actor.in_ui_mode = false
		actor.set_settings_open(false)
		actor.body_state.reset()
		actor.cancel_equipment_placement()
		actor.damage_cooldown = 0.0
	clear_bag()
	actor.add_item("One-arm meal", false, path)
	actor.body_state.sever(&"left_arm")
	food_button(false)
	food_button(true)
	check(actor.consumables.eating, "One available arm can eat")
	food_button(false)
	check(not actor.consumables.eating and actor.inventory.items.size() == 1, "Release cancels an unfinished meal")
	actor.body_state.reset()
	for food_path in FoodCatalog.SCENES:
		clear_bag()
		actor.survival.restore({"hunger": 0.0, "starvation_elapsed": 4.0})
		actor.add_item("Renamed food", false, food_path)
		food_button(false)
		food_button(true)
		actor.consumables.advance(actor, 2.0)
		var nutrition: float = FoodCatalog.definition_for(food_path).nutrition
		check(actor.survival.hunger == nutrition and actor.survival.starvation_elapsed == 0.0 and actor.inventory.items.is_empty(), "Food restores trusted nutrition and clears starvation: " + food_path)
		actor.current_stamina = 0.0
		actor.stamina_recovery_delay_remaining = 0.0
		actor._update_stamina(1.0, false)
		check(actor.current_stamina == (18.0 if nutrition >= 40.0 else 9.0), "Eating across 40 immediately restores the correct recovery rate")
		Input.action_press("sprint")
		check(actor._can_sprint(true) == (nutrition > 20.0), "Eating across 20 immediately updates sprint permission")
		Input.action_release("sprint")
	actor.current_player_health = 100.0
	actor.current_stamina = 100.0
	actor.survival.reset()
	clear_bag()

func check_new_grants() -> void:
	check(actor.add_item(ItemNames.GAS_CAN_EMPTY, false, "res://props/gas_can_empty.tscn"), "Sparse new grant receives canonical Item state")
	var granted: Dictionary = actor.inventory.active_item().state.duplicate(true)
	check(ItemState.valid("res://props/gas_can_empty.tscn", granted), "New grant is immediately valid for v5 persistence")
	check(actor.add_item("Scrap", false, "res://props/scrap.tscn"), "Second new grant can fill another slot")
	actor._set_active_slot(1)
	actor._set_active_slot(0)
	check(actor.held_item_node.persistent_id == granted.id and actor.inventory.active_item().state == granted, "Re-equipping preserves inventory-owned new grant identity")
	var save_path := "res://.godot/test-item-grant.save"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_var(actor.inventory.items, false)
	file.close()
	file = FileAccess.open(save_path, FileAccess.READ)
	var restored: Array = file.get_var(false)
	file.close()
	DirAccess.remove_absolute(save_path)
	check(restored[0].state == granted and ItemState.unique_ids(restored), "Disk serialization retains canonical granted identity and condition")
	actor.drop_item()
	var dropped := find_item(granted.id)
	check(dropped != null and dropped.capture_item_state() == granted, "Dropping a new grant preserves its complete Item state")
	if dropped: dropped.queue_free()
	clear_bag()
	check(not actor.add_item("Scrap", false, "res://props/scrap.tscn", {"id": "", "condition": 100}), "Grant boundary refuses malformed complete state")
	check(actor.inventory.items.is_empty(), "Malformed state refusal does not insert inventory record")
	var battery := BatteryState.new({"id": "grant-battery", "capacity": 160.0, "charge": 21.0, "weight": 18.0, "condition": 37.0})
	check(actor.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"battery": battery.snapshot()}), "Sparse battery grant accepts existing subtype data")
	check(actor.inventory.active_item().state.id == battery.id and actor.inventory.active_item().state.battery == battery.snapshot() and actor.inventory.active_item().state.condition == 37.0, "Battery grant retains embedded ID, charge and durability")
	clear_bag()
	var authored_battery := {"id": "authored-battery", "capacity": 100.0, "charge": 19.0, "weight": 15.0}
	check(actor.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"battery": authored_battery}), "Authored sparse battery payload defaults missing condition")
	check(actor.inventory.active_item().state.id == authored_battery.id and actor.inventory.active_item().state.battery.charge == 19.0 and actor.inventory.active_item().state.condition == 100.0, "Authored battery grant preserves charge and ID with full default durability")
	check(not authored_battery.has("condition"), "Grant initialization leaves caller-authored sparse data unchanged")
	clear_bag()
	check(not actor.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"id": authored_battery.id, "condition": 100.0, "battery": authored_battery}), "Complete saved-style state with missing subtype durability is refused, not repaired")
	var engine := EngineState.new({"id": "grant-engine", "model": "standard", "health": 217.0})
	check(actor.add_item(engine.definition().display_name, true, "res://props/engine_standard.tscn", {"engine": engine.snapshot()}), "Sparse engine grant accepts existing subtype data")
	check(actor.inventory.active_item().state.id == engine.id and actor.inventory.active_item().state.engine == engine.snapshot(), "Engine grant retains embedded ID and health")
	clear_bag()
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(100, 1, 100)
	world.add_child(shell)
	var rv := shell.get_node("Chassis") as Chassis
	rv.freeze = true
	rv.set_physics_process(false)
	await steps()
	rv.current_fuel = 0.0
	check(actor.add_item(ItemNames.GAS_CAN, false, "res://props/gas_can.tscn"), "Gas-can grant receives canonical state")
	var full_id: String = actor.inventory.active_item().state.id
	var fuel_port := rv.get_node("FuelPort") as Item
	check(fuel_port.interact(actor).contains("空罐"), "Fuel-port conversion produces empty can through grant boundary")
	var empty: Dictionary = actor.inventory.active_item().state.duplicate(true)
	check(actor.inventory.active_item().scene_path == "res://props/gas_can_empty.tscn" and ItemState.valid("res://props/gas_can_empty.tscn", empty) and empty.id != full_id, "Converted empty can owns one valid new identity")
	file = FileAccess.open(save_path, FileAccess.WRITE)
	file.store_var(actor.inventory.items, false)
	file.close()
	file = FileAccess.open(save_path, FileAccess.READ)
	restored = file.get_var(false)
	file.close()
	DirAccess.remove_absolute(save_path)
	check(restored[0].scene_path == "res://props/gas_can_empty.tscn" and restored[0].state == empty, "Refueled empty-can disk save retains its scene path, ID and complete state")
	actor.inventory.items.assign(restored)
	actor.refresh_inventory()
	check(actor.held_item_node.scene_file_path == "res://props/gas_can_empty.tscn" and actor.held_item_node.get_node("gas_can").scene_file_path == "res://assets/models/gas_can/gas_can.glb", "Reloaded converted empty can instantiates its gameplay scene and shared visual")
	check(actor.held_item_node.persistent_id == empty.id, "Converted empty-can identity survives held-model refresh")
	actor.drop_item()
	dropped = find_item(empty.id)
	check(dropped != null and dropped.capture_item_state() == empty, "Converted empty-can throw retains canonical state")
	if dropped: dropped.queue_free()
	shell.queue_free()
	clear_bag()
	await steps()

func triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var ac := c - a
	var normal := ab.cross(ac)
	var area_squared := normal.length_squared()
	if area_squared > 1e-14:
		var projected := point - normal * normal.dot(point - a) / area_squared
		var ap := projected - a
		var d00 := ab.dot(ab)
		var d01 := ab.dot(ac)
		var d11 := ac.dot(ac)
		var v := (d11 * ap.dot(ab) - d01 * ap.dot(ac)) / area_squared
		var w := (d00 * ap.dot(ac) - d01 * ap.dot(ab)) / area_squared
		if v >= 0.0 and w >= 0.0 and v + w <= 1.0: return point.distance_to(projected)
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)), minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)), point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))))

func visible_surface_distance(held: Node3D, palm: Vector3) -> float:
	var nearest := INF
	for mesh: MeshInstance3D in held.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree() or mesh.is_queued_for_deletion(): continue
		if mesh.has_meta(&"first_person_render_copy") or mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		# World-space triangles account for nested model scale and authored hold rotation.
		var faces := mesh.mesh.get_faces()
		var pose := mesh.global_transform
		for index in range(0, faces.size(), 3):
			nearest = minf(nearest, triangle_distance(palm, pose * faces[index], pose * faces[index + 1], pose * faces[index + 2]))
	return nearest

func carry_hand(side: String) -> Transform3D:
	var skeleton: Skeleton3D = actor.get_node("Visuals/Carry").skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side))

func carry_palm(side: String) -> Vector3:
	var carry: Node = actor.get_node("Visuals/Carry")
	var skeleton: Skeleton3D = carry.skeleton
	var hand := skeleton.find_bone("hand_" + side)
	var rest := skeleton.get_bone_global_rest(hand)
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_" + side)).origin
	var frame: Basis = carry.hand_frames[side]
	var normal := frame.y.cross(frame.x) * (1.0 if side == "L" else -1.0)
	var offset := rest.basis.inverse() * ((middle - rest.origin) * .72 + normal * .014)
	return carry_hand(side) * offset

func carry_gap(sides: Array[String]) -> float:
	var carry: Node = actor.get_node("Visuals/Carry")
	var gap := 0.0
	for side in sides: gap = maxf(gap, carry_palm(side).distance_to(carry.grip_right if side == "R" else carry.grip_left))
	return gap

func check_carry_motion() -> void:
	clear_bag()
	var original_pose := actor.global_transform
	actor.camera.rotation = Vector3.ZERO
	# Ground the real controller before freezing it, so this samples jog rather
	# than an airborne fallback animation.
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, .2, 10)
	collision.shape = box
	floor.add_child(collision)
	world.add_child(floor)
	var capsule: CollisionShape3D = actor.get_node("CollisionShape3D")
	floor.global_position = Vector3(actor.global_position.x, capsule.global_position.y - (capsule.shape as CapsuleShape3D).height * .5 - .1, actor.global_position.z)
	await steps()
	actor.velocity = Vector3.DOWN
	actor.move_and_slide()
	check(actor.is_on_floor(), "Carry motion fixture establishes real grounded locomotion")
	var carry: Node = actor.get_node("Visuals/Carry")
	for record: Array in [["radio", "res://props/scavenge_loot/broken_shortwave_radio.tscn", false], ["scrap", "res://props/scrap.tscn", false], ["motor", "res://props/scavenge_loot/salvaged_motor.tscn", true], ["flashlight", "res://props/flashlight.tscn", false]]:
		clear_bag()
		actor.velocity = Vector3.ZERO
		await steps(15)
		actor.add_item(record[0], record[2], record[1])
		var held: Node3D = actor.held_item_node
		var sides: Array[String] = ["R"]
		if record[2]: sides.append("L")
		check(held.is_visible_in_tree() and carry.item == held and carry_gap(sides) <= .001, "First visible equip is already solved against its hands: " + record[0])
		var maximum_gap := carry_gap(sides)
		for frame in 10:
			await steps(1)
			maximum_gap = maxf(maximum_gap, carry_gap(sides))
		check(maximum_gap <= .001, "Every visible equip frame remains seated within one millimeter: " + record[0] + " gap=" + str(maximum_gap))
		actor.velocity = actor.global_basis * Vector3(0, 0, -3)
		for frame in 20:
			await steps(1)
			maximum_gap = maxf(maximum_gap, carry_gap(sides))
		var reference: Dictionary = {}
		for side in sides: reference[side] = carry_hand(side).affine_inverse() * held.global_transform
		var drift := 0.0
		var angle := 0.0
		for frame in 120:
			actor.rotation.y += .008
			actor.velocity = actor.global_basis * Vector3(0, 0, -3)
			await steps(1)
			maximum_gap = maxf(maximum_gap, carry_gap(sides))
			for side in sides:
				var relative := carry_hand(side).affine_inverse() * held.global_transform
				drift = maxf(drift, reference[side].origin.distance_to(relative.origin))
				angle = maxf(angle, reference[side].basis.orthonormalized().get_rotation_quaternion().angle_to(relative.basis.orthonormalized().get_rotation_quaternion()))
		check(actor.get_node("Visuals/Locomotion").current_clip == "jog_forward", "Carry regression samples a full grounded jog cycle: " + record[0])
		check(maximum_gap < .035, "Visible equip and jogging preserve palm contact: " + record[0] + " gap=" + str(maximum_gap))
		check(drift < .002 and angle < deg_to_rad(1.0), "Jogging and turning preserve the hand-relative item transform: " + record[0] + " drift=" + str(drift) + " angle=" + str(rad_to_deg(angle)))
		actor.refresh_inventory()
		held = actor.held_item_node
		check(held.is_visible_in_tree() and carry.item == held and carry_gap(sides) <= .001, "Equipping during a jog is already seated before the next physics tick: " + record[0])
		await steps(1)
		check(carry_gap(sides) <= .001, "The first moving equip frame keeps both contacts seated: " + record[0])
		var held_pose := held.global_transform
		var hand_pose := carry_hand("R")
		actor.camera.rotation.x = .20
		actor.get_node("Visuals/FirstPersonCarry").update_view()
		check(held.global_transform.is_equal_approx(held_pose) and carry_hand("R").is_equal_approx(hand_pose), "Mouse pitch between physics frames cannot move the item apart from its hand: " + record[0])
		actor.camera.rotation.x = 0.0
	clear_bag()
	actor.velocity = Vector3.ZERO
	actor.global_transform = original_pose
	floor.queue_free()
	await steps(15)

func check_carry_frame(note: String, large: bool = false, require_world_frame: bool = true) -> void:
	var carry: Node = actor.get_node("Visuals/Carry")
	var held: Node3D = actor.held_item_node
	var center: Vector3 = held.get_parent().to_global(carry.bounds.get_center())
	var screen: Vector2 = actor.camera.unproject_position(center) / root.get_visible_rect().size
	check(not carry.bounds.has_point(held.get_parent().to_local(actor.camera.global_position)), "Held mesh bounds stay clear of the eye: " + note)
	var left: bool = carry.active_hand == "L"
	var min_x := .35 if large else (.05 if left else .60)
	var max_x := .65 if large else (.40 if left else .95)
	check(not require_world_frame or (not actor.camera.is_position_behind(center) and screen.x > min_x and screen.x < max_x and screen.y > .30 and screen.y < .95), "Carry center stays visible on its holding side: " + note + " screen=" + str(screen) + " fov=" + str(actor.camera.fov))
	for side: String in (["R", "L"] if large else [carry.active_hand]):
		var palm := carry_palm(side)
		var grip: Vector3 = carry.grip_right if side == "R" else carry.grip_left
		check(palm.distance_to(grip) < .035, "Visible carry retains palm contact on " + side + ": " + note)
		var surface_gap := visible_surface_distance(held, palm)
		check(surface_gap <= .025, "Palm reaches actual visible item surface on " + side + ": " + note + " gap=" + str(surface_gap))

func check_viewmodel_frame(note: String, large: bool = false) -> void:
	var view: Node = actor.get_node("Visuals/FirstPersonCarry")
	var carry: Node = actor.get_node("Visuals/Carry")
	var crouch_drop: float = actor.get_node("Visuals/Locomotion").crouch_eye_drop
	if actor.camera.rotation.x < -.35 or is_equal_approx(actor.camera.rotation.x, -.35) or crouch_drop > .16 or is_equal_approx(crouch_drop, .16):
		check(not view.active and actor.get_node("Visuals").local_body.mesh == view.original_body, "Body-view posture restores the complete local body: " + note)
		for arm: MeshInstance3D in view.arm_meshes.values():
			check(not arm.visible, "Body-view posture hides every separate viewmodel arm: " + note)
		for mesh: MeshInstance3D in actor.held_item_node.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.has_meta(&"first_person_render_copy") or mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
			check(mesh.layers & actor.camera.cull_mask != 0, "Body-view posture restores held source rendering with the body: " + note)
		return
	check(view.active, "Ordinary carry enables the first-person view: " + note)
	if not view.active: return
	var camera: Camera3D = view.camera
	var viewport: SubViewport = view.viewport
	var center: Vector3 = actor.held_item_node.get_parent().to_global(carry.bounds.get_center())
	var screen := camera.unproject_position(center) / Vector2(viewport.size)
	var left: bool = carry.active_hand == "L"
	var min_x := .465 if large else (.02 if left else .50)
	var max_x := .535 if large else (.50 if left else .98)
	check(not camera.is_position_behind(center) and screen.x > min_x and screen.x < max_x and screen.y > .20 and screen.y < .98, "Viewmodel item stays on its holding side: " + note + " screen=" + str(screen))
	var skeleton: Skeleton3D = carry.skeleton
	var forearms: Dictionary = {}
	for side: String in (["R", "L"] if large else [carry.active_hand]):
		var wrist: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side)).origin
		var elbow: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("forearm_" + side)).origin
		forearms[side] = camera.unproject_position(elbow.lerp(wrist, .5)) / Vector2(viewport.size)
		for point: Vector3 in [wrist, elbow.lerp(wrist, .5)]:
			var projected := camera.unproject_position(point) / Vector2(viewport.size)
			check(not camera.is_position_behind(point) and Rect2(Vector2.ZERO, Vector2.ONE).has_point(projected), "Viewmodel shows wrist and forearm on " + side + ": " + note + " screen=" + str(projected))

	if large:
		var left_x: float = forearms["L"].x
		var right_x: float = forearms["R"].x
		check(left_x < screen.x and screen.x < right_x and absf((left_x + right_x) * .5 - .5) < .04 and right_x - left_x >= (.22 if actor.is_crouching() else .28), "Two-hand forearms bracket the centered item with balanced spacing: " + note + " left=" + str(left_x) + " right=" + str(right_x))

func check_first_person_carry() -> void:
	clear_bag()
	var view: Node = actor.get_node_or_null("Visuals/FirstPersonCarry")
	check(view != null, "Production player owns the first-person carry component")
	if view == null: return
	actor.camera.rotation = Vector3.ZERO
	var observer := Camera3D.new()
	world.add_child(observer)
	observer.make_current()
	actor.add_item("Scrap", false, "res://props/scrap.tscn")
	await steps(20)
	view.update_view()
	var held: Node3D = actor.held_item_node
	var original_layers: Dictionary = {}
	for mesh: MeshInstance3D in held.find_children("*", "MeshInstance3D", true, false):
		original_layers[mesh] = mesh.layers
	var local_body: MeshInstance3D = actor.get_node("Visuals").local_body
	var original_body_mesh := local_body.mesh
	check(not view.active, "An observer camera leaves the world carry authoritative")
	var held_pose := held.global_transform
	var camera_pose: Transform3D = actor.camera.global_transform
	var camera_fov: float = actor.camera.fov
	actor.camera.make_current()
	view.update_view()
	check_viewmodel_frame("right-hand scrap")
	check(held.global_transform.is_equal_approx(held_pose), "Activating viewmodel preserves the world-held transform")
	check(actor.camera.global_transform.is_equal_approx(camera_pose) and is_equal_approx(actor.camera.fov, camera_fov), "Viewmodel leaves the gameplay lens and transform unchanged")
	check(is_equal_approx(view.camera.fov, 70.0) and view.camera.cull_mask == 1 << 21 and actor.camera.cull_mask & (1 << 21) == 0, "The independent 70-degree camera alone renders layer 22")
	check(local_body.mesh != original_body_mesh, "Local body removes its original arms while the viewmodel draws them")
	for mesh: MeshInstance3D in original_layers:
		check(mesh.layers & actor.camera.cull_mask == 0 and mesh.layers & observer.cull_mask != 0, "Held mesh renders once locally and remains available to observers")
	# Cross the handoff synchronously to isolate view changes from carry animation.
	for sample: Array in [[-.30, true], [-.35, false], [-.32, false], [-.30, false], [-.29, true], [0.0, true]]:
		actor.camera.rotation.x = sample[0]
		var before_view := held.global_transform
		view.update_view()
		check(view.active == sample[1], "Lookdown handoff hysteresis at pitch " + str(sample[0]) + " active=" + str(sample[1]))
		check(held.global_transform.is_equal_approx(before_view), "Lookdown handoff preserves the world-held pose")
		if sample[0] == -.30 and sample[1]:
			check(view.camera.global_transform.is_equal_approx(actor.camera.get_camera_transform()) and is_equal_approx(view.camera.fov, actor.camera.fov), "The active handoff camera exactly joins the gameplay body camera")
		if not sample[1]:
			check(local_body.mesh == original_body_mesh, "Lookdown handoff restores the original local skin")
			for arm: MeshInstance3D in view.arm_meshes.values(): check(not arm.visible, "Lookdown handoff hides separate arms")
			for mesh: MeshInstance3D in original_layers: check(mesh.layers == original_layers[mesh], "Lookdown handoff restores exact source layers")
	actor.crouching = true
	actor._apply_body_collision()
	await steps(45)
	view.update_view()
	check(actor.get_node("Visuals/Locomotion").crouch_eye_drop >= .16 and not view.active and local_body.mesh == original_body_mesh, "Settled crouch restores the contiguous original local body")
	for arm: MeshInstance3D in view.arm_meshes.values(): check(not arm.visible, "Crouching hides separate viewmodel arms")
	for mesh: MeshInstance3D in original_layers: check(mesh.layers == original_layers[mesh], "Crouching restores exact held source layers")
	actor.crouching = false
	actor._apply_body_collision()
	await steps(45)
	view.update_view()
	check(actor.get_node("Visuals/Locomotion").crouch_eye_drop < .14 and view.active, "Standing restores the viewmodel after the crouch handoff")
	check_viewmodel_frame("standing after crouch handoff")
	# Moving a live actor between worlds does not rerun the component's _ready.
	var interior := SubViewport.new()
	interior.own_world_3d = true
	interior.size = Vector2i(1280, 720)
	root.add_child(interior)
	var host := Node3D.new()
	interior.add_child(host)
	actor.reparent(host)
	actor.camera.make_current()
	await steps()
	view.update_view()
	check(view.active and view.viewport.world_3d == actor.get_world_3d(), "Reparented carry rebinds to the interior World3D without reinitializing")
	var light := OmniLight3D.new()
	world.add_child(light)
	light.global_position = actor.camera.global_position
	var adaptation := preload("res://world/night_vision_effect.gd").new()
	adaptation.name = "DarkAdaptation"
	adaptation.profile = adaptation.profile.duplicate()
	adaptation.profile.ambient_gate_enabled = false
	world.add_child(adaptation)
	actor.reparent(world)
	actor.camera.make_current()
	await steps()
	adaptation._prepare_views()
	view.update_view()
	check(view.active and view.viewport.world_3d == actor.get_world_3d(), "Returning carry rebinds to its original World3D")
	check(light.layers == NightVisionEffect.LIGHT_LAYER, "Night adaptation routes the real world light to its lighting layer")
	check(view.light_copies.has(light.get_instance_id()), "Returning carry discovers and copies the real world light")
	for entry: Dictionary in view.light_copies.values():
		check(entry.copy.layers == 1 << 21 and entry.copy.has_meta(&"first_person_light_copy"), "Night adaptation leaves cosmetic carry lights on layer 22")
	check(root.get_node("GameSettings").viewport_effect(view.viewport) == null, "Carry viewport does not receive a second fullscreen display effect")
	adaptation.queue_free()
	light.queue_free()
	interior.queue_free()
	await steps()
	view.update_view()
	# Change ownership synchronously so a generic fixture never enters grab animation.
	actor.grab_control.captor = world
	view.update_view()
	check(not view.active and local_body.mesh == original_body_mesh, "Grab ownership immediately restores the normal world presentation")
	actor.grab_control.captor = null
	view.update_view()
	check(view.active, "Releasing grab ownership restores first-person carry")
	observer.make_current()
	view.update_view()
	check(not view.active and local_body.mesh == original_body_mesh, "Observer takeover removes the overlay and restores the original local skin")
	for mesh: MeshInstance3D in original_layers:
		check(mesh.layers == original_layers[mesh], "Observer fallback restores exact held-mesh layers")
	actor.camera.make_current()
	view.update_view()
	check(actor.enter_equipment_placement(), "Ordinary viewmodel item can enter placement")
	view.update_view()
	check(not view.active and not held.visible and local_body.mesh == original_body_mesh, "Placement hides the overlay and original held model together")
	actor.cancel_equipment_placement()
	view.update_view()
	check(view.active and actor.held_item_node == held, "Cancelling placement restores the same held item and viewmodel")
	actor.add_item("Scrap", false, "res://props/scrap.tscn")
	actor._set_active_slot(1)
	await steps(20)
	view.update_view()
	check(view.active and actor.held_item_node != held, "Slot switching follows the new ordinary held item")
	actor._set_active_slot(2)
	view.update_view()
	check(not view.active and local_body.mesh == original_body_mesh, "An empty slot clears the previous viewmodel immediately")
	clear_bag()
	actor.add_item("Scrap", false, "res://props/scrap.tscn")
	await steps(20)
	view.update_view()
	var state: Dictionary = actor.inventory.active_item().state.duplicate(true)
	held_pose = actor.held_item_node.global_transform
	actor.drop_item()
	view.update_view()
	var dropped := find_item(state.id)
	check(not view.active and local_body.mesh == original_body_mesh, "Dropping clears the viewmodel and restores the local body")
	check(dropped != null and dropped.global_transform.is_equal_approx(held_pose), "Viewmodel release drops from the unchanged world-held pose")
	if dropped: dropped.queue_free()
	clear_bag()
	for path: String in ["res://props/scavenge_loot/salvaged_motor.tscn", "res://props/oil_barrel.tscn"]:
		var name := path.get_file().get_basename()
		actor.add_item(name, true, path)
		for pitch: float in [0.0, -.35, .35]:
			actor.camera.rotation.x = pitch
			await steps(20)
			view.update_view()
			check_carry_frame(name + " pitch=" + str(pitch), true, name != "oil_barrel")
			check_viewmodel_frame(name + " pitch=" + str(pitch), true)
		actor.camera.rotation.x = 0.0
		if name == "salvaged_motor":
			actor.crouching = true
			actor._apply_body_collision()
			await steps(45)
			view.update_view()
			check_carry_frame("crouched motor", true)
			check_viewmodel_frame("crouched motor", true)
			actor.crouching = false
			actor._apply_body_collision()
		clear_bag()
	actor.add_item("Scrapper", true, "res://equipment/scrapper.tscn")
	await steps(20)
	view.update_view()
	check(not view.active, "Service machinery retains world carry instead of receiving a viewmodel")
	clear_bag()
	observer.queue_free()
	await steps()

func check_flashlight_viewmodel() -> void:
	clear_bag()
	var view: Node = actor.get_node("Visuals/FirstPersonCarry")
	var observer := Camera3D.new()
	world.add_child(observer)
	observer.make_current()
	check(actor.add_item("Flashlight", false, "res://props/flashlight.tscn", {"flashlight": {"charge": 30.0, "on": false}}), "Grant flashlight with known battery charge")
	await steps(20)
	var held: Flashlight = actor.held_item_node
	var beam: SpotLight3D = held.get_node("Beam")
	var held_pose := held.global_transform
	var beam_pose := beam.global_transform
	actor.camera.make_current()
	view.update_view()
	check(view.active and held.global_transform.is_equal_approx(held_pose) and beam.global_transform.is_equal_approx(beam_pose), "Flashlight view activation preserves its real body and beam transforms")
	check(view.held_light_copies.has(beam.get_instance_id()), "Flashlight beam has a persistent copy while switched off")
	if view.held_light_copies.has(beam.get_instance_id()):
		var light_copy: Light3D = view.held_light_copies[beam.get_instance_id()].copy
		check(not light_copy.visible, "Off flashlight does not illuminate the viewmodel")
		actor._toggle_flashlight()
		view.update_view()
		check(beam.visible and light_copy.visible and light_copy.layers == 1 << 21 and light_copy.global_transform.is_equal_approx(beam.global_transform), "Flashlight copy switches on immediately at the authoritative beam transform")
		actor._advance_flashlight(3.0)
		actor._advance_flashlight(0.0)
		var charge: float = actor.inventory.active_item().state.flashlight.charge
		view.update_view()
		view.update_view()
		check(is_equal_approx(charge, 29.0) and is_equal_approx(actor.inventory.active_item().state.flashlight.charge, charge) and is_equal_approx(held.charge, charge), "Only the flashlight authority drains charge; view updates do not consume battery")
		actor._toggle_flashlight()
		view.update_view()
		check(not beam.visible and not light_copy.visible and view.held_light_copies[beam.get_instance_id()].copy == light_copy, "The same flashlight copy switches off immediately")
		actor._toggle_flashlight()
		actor.grab_control.captor = world
		actor.grab_control.keep_flashlight = true
		actor._advance_flashlight(0.0)
		view.update_view()
		check(not view.active and beam.visible and not light_copy.visible and beam.global_transform.is_equal_approx(beam_pose), "Grab fallback preserves the real flashlight beam while hiding its cosmetic copy")
		actor.grab_control.captor = null
		actor.grab_control.keep_flashlight = false
		view.update_view()
		check(view.active, "Flashlight returns to its viewmodel after grab ownership ends")
	clear_bag()
	observer.queue_free()
	await steps()

func check_carry_postures() -> void:
	clear_bag()
	actor.camera.rotation = Vector3.ZERO
	for key: String in ["gas_can", "gas_can_empty", "battery", "engine_repair_kit"]:
		actor.add_item(key, false, "res://props/" + key + ".tscn")
		await steps(20)
		check_carry_frame(key)
		clear_bag()
	actor.add_item("Wheel", false, "res://props/wheel.tscn")
	await steps(20)
	check_carry_frame("intact wheel", false, false)
	actor.held_item_node.condition = 0.0
	await steps(20)
	check_carry_frame("flat wheel", false, false)
	clear_bag()
	actor.add_item("Scrap", false, "res://props/scrap.tscn")
	actor.crouching = true
	actor._apply_body_collision()
	await steps(45)
	check_carry_frame("crouched scrap")
	actor.get_node("Visuals/FirstPersonCarry").update_view()
	check_viewmodel_frame("crouched scrap")
	actor.crouching = false
	actor._apply_body_collision()
	await steps(45)
	actor.body_state.sever(&"right_arm")
	actor._apply_body_capabilities()
	await steps(20)
	check_carry_frame("left-hand fallback")
	actor.get_node("Visuals/FirstPersonCarry").update_view()
	check_viewmodel_frame("left-hand fallback")
	actor.body_state.reset()
	actor._apply_body_capabilities()
	clear_bag()
	await steps(20)

func check_scavenge_loot() -> void:
	var loot := ["copper_wire_spool", "broken_shortwave_radio", "salvaged_motor", "medical_tin", "industrial_valve", "enamel_kettle"]
	var save_path := "res://.godot/test-scavenge-loot.save"
	var camera_pose: Transform3D = actor.camera.transform
	ray.set_physics_process(true)
	for slug in loot:
		var path: String = "res://props/scavenge_loot/" + slug + ".tscn"
		check(InventoryItemIcons.texture_for(path) != InventoryItemIcons.FALLBACK, "Scavenge loot has its own inventory icon: " + slug)
		var scene := load(path) as PackedScene
		check(scene != null, "Scavenge loot scene loads: " + slug)
		if scene == null: continue
		var item := scene.instantiate() as Item
		check(item != null, "Scavenge loot uses the production Item contract: " + slug)
		if item == null: continue
		item.freeze = true
		entities.add_child(item)
		item.global_position = actor.camera.global_position + Vector3(1.5, -0.2, 0)
		actor.camera.look_at(item.global_position, Vector3.UP)
		var large: bool = slug == "salvaged_motor"
		check(item.is_large == large, "Only the salvaged motor requires the large-item slot: " + slug)
		check(not item.scrap_yields.is_empty(), "Scavenge loot has recycling output outside the tutorial: " + slug)
		item.condition = 47.0
		item.set_meta("recycle_result", {ItemNames.METAL_PARTS: 3})
		var state := item.capture_item_state()
		check(ItemState.valid(path, state), "Scavenge loot state is accepted by the save catalog: " + slug)
		await steps()
		ray.force_raycast_update()
		check(ray.get_collider() == item, "Native interaction ray hits the loot collision: " + slug)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		key.pressed = true
		Input.parse_input_event(key)
		await steps()
		key.pressed = false
		Input.parse_input_event(key)
		await steps()
		var owned: Dictionary = actor.inventory.active_item()
		check(owned.get("scene_path") == path and owned.get("is_large") == large and owned.get("state") == state, "Physical E input through the native interaction ray preserves loot scene, size, identity and recycling state: " + slug)
		if owned.is_empty():
			if is_instance_valid(item): item.queue_free()
			continue
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		file.store_var(actor.inventory.items, false)
		file.close()
		file = FileAccess.open(save_path, FileAccess.READ)
		var inventory: Array = file.get_var(false)
		file.close()
		actor.inventory.items.assign(inventory)
		actor.refresh_inventory()
		check(actor.held_item_node != null and actor.held_item_node.scene_file_path == path and actor.held_item_node.capture_item_state() == state, "Saved loot inventory recreates the same held Item: " + slug)
		actor.camera.transform = camera_pose
		for pitch in [0.0, -.35, .35]:
			actor.camera.rotation.x = pitch
			await steps(20)
			check_carry_frame(slug + " pitch=" + str(pitch), large)
		var held_pose: Transform3D = actor.held_item_node.global_transform
		actor.drop_item()
		var dropped := find_item(state.id)
		check(dropped != null and dropped.global_transform.is_equal_approx(held_pose), "Drop starts at the visible held transform: " + slug)
		check(dropped != null and dropped.scene_file_path == path and dropped.is_large == large and dropped.capture_item_state() == state, "Native drop preserves the saved loot Item: " + slug)
		if dropped != null:
			var snapshot := WorldActorSnapshot.capture(dropped)
			check(WorldActorSnapshot.validation_error(snapshot, slug).is_empty(), "Dropped loot forms a valid checkpoint actor: " + slug)
			dropped.free()
			var restored := WorldActorSnapshot.restore(snapshot, entities) as Item
			check(restored.scene_file_path == path and restored.is_large == large and restored.capture_item_state() == state, "World restoration preserves loot scene and state: " + slug)
			restored.queue_free()
		clear_bag()
		await steps()
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	ray.set_physics_process(false)
	actor.camera.transform = camera_pose

func check_hud_toggle() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.pressed = true
	Input.parse_input_event(key)
	await steps()
	actor.refresh_inventory()
	check(HUDVisibility.hud_hidden and actor.get_player_mode() == actor.PlayerMode.NORMAL, "F12 hides HUD without changing gameplay mode")
	for gate in get_nodes_in_group(HUDVisibility.GROUP):
		check(gate.color.a == 0.0, "HUD stays hidden across display refreshes: " + str(gate.get_path()))
	key.echo = true
	Input.parse_input_event(key)
	await steps()
	check(HUDVisibility.hud_hidden, "Holding F12 does not repeatedly toggle HUD")
	var later_layer := CanvasLayer.new()
	world.add_child(later_layer)
	HUDVisibility.attach(later_layer)
	check(later_layer.get_node("HUDVisibility").color.a == 0.0, "New HUD inherits hidden state across scene creation")
	later_layer.hide()
	var menu := actor.get_node("SettingsMenu")
	check(menu.open_menu(), "Settings remain accessible with HUD hidden")
	key.echo = false
	Input.parse_input_event(key)
	await steps()
	check(not HUDVisibility.hud_hidden and menu.visible, "F12 restores HUD while settings retain visibility")
	for gate in get_nodes_in_group(HUDVisibility.GROUP):
		check(gate.color.a == 1.0, "F12 restores HUD presentation: " + str(gate.get_path()))
	check(not later_layer.visible, "Restoring HUD preserves locally hidden layers")
	menu.close_menu()
	later_layer.queue_free()
	key.pressed = false
	Input.parse_input_event(key)
	await steps()

func run() -> void:
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	actor = load("res://player/player.tscn").instantiate()
	actor.position = Vector3(20, 1, 20)
	world.add_child(actor)
	actor.set_physics_process(false)
	ray = actor.camera.get_node("InteractRay")
	ray.set_physics_process(false)
	entities = WorldEntities.get_container(actor)
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.2, 4, 4)
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	wall.position = Vector3(0, 2, 0)
	await steps()
	check_survival()
	check_eating()
	await check_hud_toggle()
	await check_new_grants()
	await check_scavenge_loot()
	await check_carry_postures()
	await check_first_person_carry()
	await check_flashlight_viewmodel()
	await check_carry_motion()

	# Capacity rejection leaves real fixed ownership and service state intact.
	var scrapper := make_item("res://equipment/scrapper.tscn", Vector3(2, 2, 0))
	await steps()
	scrapper.confirm_placement(scrapper.global_transform, entities, wall)
	check(scrapper.is_fixed and scrapper.mount_support == wall, "Scrapper fixes to wall")
	scrapper.condition = 41.0
	var scrapper_id := scrapper.persistent_id
	for index in PlayerInventory.MAX_SLOTS:
		actor.inventory.add_item("Scrap", false, "res://props/scrap.tscn")
	check(not actor.add_prop_item(scrapper, scrapper.scene_file_path), "Full inventory refuses fixed equipment")
	check(scrapper.is_fixed and scrapper.mount_support == wall and is_equal_approx(scrapper.condition, 41), "Rejected pickup preserves support and durability")
	clear_bag()
	actor.body_state.sever(&"left_arm")
	check(not actor.add_prop_item(scrapper, scrapper.scene_file_path), "One arm cannot carry equipment")
	check(scrapper.is_fixed, "Missing-arm refusal does not detach equipment")
	actor.body_state.reset()
	actor.refresh_inventory()
	var service_before := scrapper.capture_service_state()
	check(not actor.add_prop_item(scrapper, "res://equipment/not_registered.tscn"), "Unregistered Item scene fails pickup before service cleanup")
	check(scrapper.is_fixed and scrapper.mount_support == wall and not scrapper._service_stopped and scrapper.capture_service_state() == service_before, "Invalid-scene pickup retains support and service state")

	# F hold picks up; releasing that same gesture must not start a ghost.
	ray._step_buttons(scrapper, false, true, 2.1)
	check(actor.inventory.items.size() == 1 and actor.inventory.active_item().is_large, "F hold transfers equipment to large-item inventory")
	check(actor.inventory.active_item().state.id == scrapper_id and is_equal_approx(float(actor.inventory.active_item().state.condition), 41), "F hold retains identity and condition")
	ray._step_buttons(null, false, false, 0.0)
	check(not actor.is_placing_equipment(), "Successful F hold suppresses placement tap")
	check(actor.held_item_node is Item and actor.held_item_node.presentation_only, "Held equipment is presentation only")
	check(not actor.can_drive() and not actor._can_use_ladder(), "Two-handed equipment blocks driving and climbing")
	await steps()
	var held: Node3D = actor.held_item_node
	ray._step_buttons(null, false, true, .1)
	ray._step_buttons(null, false, false, 0.0)
	check(actor.is_placing_equipment(), "F tap with inventory starts independent preview")
	check(actor.placement.placing_equipment != held and not held.visible, "Preview hides the separate held equipment model immediately")
	check(actor.placement.placing_equipment.presentation_only, "Preview cannot activate services")
	check(actor.inventory.items.size() == 1, "Preview retains inventory ownership")
	await steps()
	check(not held.is_visible_in_tree(), "Carry updates cannot reveal the held model during preview")
	var slot_icon: TextureRect = actor.inventory_ui.slots_container.get_child(0).get_node("ItemIcon")
	check(slot_icon.is_visible_in_tree() and slot_icon.texture == InventoryItemIcons.texture_for(actor.inventory.active_item().scene_path), "Preview keeps the Item icon visible in the inventory bar")
	check(actor.inventory_ui.selected_name.text == actor.inventory.active_item().name, "Preview retains the selected Item name")
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	actor.placement.handle_input(actor, cancel)
	check(actor.inventory.items.size() == 1 and actor.held_item_node == held and held.visible, "Right-click cancellation restores the same held model and inventory ownership")
	check(actor.enter_equipment_placement(), "Preview can reopen after right-click cancellation")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	actor.placement.handle_input(actor, escape)
	check(not actor.is_placing_equipment() and held.visible and actor.inventory.active_item().state.id == scrapper_id, "Esc restores the held model without removing the inventory Item")
	check(actor.enter_equipment_placement(), "Preview can reopen")
	actor.drop_item()
	var dropped := find_item(scrapper_id)
	check(not actor.is_placing_equipment() and actor.inventory.items.is_empty(), "G cancels preview and consumes inventory once")
	check(dropped != null and not dropped.is_fixed and not dropped.freeze, "G creates a loose pickup with physical motion")
	if dropped:
		check(is_equal_approx(dropped.condition, 41), "Equipment throw retains condition")
		dropped.queue_free()
	await steps()

	# Small props also fix, and support loss restores physical pickup behavior.
	actor.position = Vector3(3, 1, 0)
	await steps()
	var scrap := make_item("res://props/scrap.tscn", Vector3(5, 3, 5))
	var scrap_id := scrap.persistent_id
	check(actor.add_prop_item(scrap, scrap.scene_file_path), "Small prop enters unified inventory")
	scrap.queue_free()
	check(actor.enter_equipment_placement(), "Small item supports placement mode")
	actor.placement.target_support = wall
	actor.placement.can_place_equipment = true
	actor.placement.placing_equipment.global_transform = Transform3D(Basis.IDENTITY, actor.global_position + Vector3.UP)
	check(not actor.placement.commit(actor) and actor.inventory.items.size() == 1, "Fresh actor-overlap rejection retains inventory and preview")
	actor.placement.placing_equipment.global_transform = Transform3D(Basis.IDENTITY, Vector3(1, 2, 0))
	check(actor.placement.commit(actor), "Placement commits inventory into fixed world Item")
	var fixed := find_item(scrap_id)
	check(actor.inventory.items.is_empty() and not actor.is_placing_equipment(), "Placement consumes once and exits preview")
	check(fixed != null and fixed.is_fixed and fixed.mount_support == wall, "Ordinary prop is fixed to named support")
	check(not actor.placement.commit(actor), "Repeated commit cannot duplicate item")
	var loose := make_item("res://props/scrap.tscn", Vector3(8, 3, 8))
	check(not PlacementRules.valid_target(loose, loose), "Item cannot support itself")
	if fixed:
		check(PlacementRules.valid_target(loose, fixed), "Fixed Item supports another Item")
		check(not PlacementRules.valid_target(fixed, loose), "Loose Item cannot support a fixed placement")
		var upper := make_item("res://props/scrap.tscn", Vector3(10, 3, 10))
		upper.confirm_placement(upper.global_transform, entities, fixed)
		check(PlacementRules.valid_target(loose, upper), "Intact fixed Item support chain accepts placement")
		for field in ["processing_owner", "_support_release_pending", "support_lost"]:
			fixed.set(field, world if field == "processing_owner" else true)
			check(not PlacementRules.valid_target(loose, fixed), "Placement rejects direct support with " + field)
			check(not PlacementRules.valid_target(loose, upper), "Placement rejects support chain with " + field)
			fixed.set(field, null if field == "processing_owner" else false)
		check(PlacementRules.valid_target(loose, upper), "Restored usable support chain accepts placement again")
		upper.queue_free()
		check(not PlacementRules.valid_target(loose, upper), "Queued support deletion immediately rejects placement")
	wall.queue_free()
	await steps()
	if fixed:
		check(not fixed.is_fixed and not fixed.freeze, "Wall removal drops attached Item")
		check(fixed.persistent_id == scrap_id, "Support drop preserves identity")
		clear_bag()
		check(actor.add_prop_item(fixed, fixed.scene_file_path), "Dropped attached Item can be picked up again")
		fixed.queue_free()
	loose.queue_free()
	world.queue_free()
	await steps()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: unified Item player preflight, F gestures, preview ownership, commit/drop and support pickup")
	quit(0 if failures.is_empty() else 1)

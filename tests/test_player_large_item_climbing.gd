extends SceneTree

var failures: Array[String] = []
var world: Node3D
var rv: Node3D
var player: CharacterBody3D
var interaction: RayCast3D
var step_delta := 1.0 / Engine.physics_ticks_per_second
const LARGE_PATH := "res://props/oil_barrel.tscn"
const SMALL_PATH := "res://props/scrap.tscn"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(vehicle)
	rv = vehicle.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	player = load("res://player/player.tscn").instantiate()
	player.set_physics_process(false)
	world.add_child(player)
	interaction = player.get_node("Camera3D/InteractRay")
	interaction.set_physics_process(false)
	await _reset_at_wall()
	Input.action_press("move_forward")
	_expect(player.add_item("Unfamiliar cargo", true, LARGE_PATH, {"id": "blocked-cargo", "condition": 37.0}), "Large cargo is accepted.")
	var original: Dictionary = player.inventory.active_item().duplicate(true)
	var before: Transform3D = player.global_transform
	player._try_start_climb()
	_expect(player.locomotion_state == player.LocomotionState.NORMAL, "A real RV wall cannot start climbing with active large cargo.")
	_expect(player.global_transform.is_equal_approx(before), "Refused climb does not teleport the player.")
	_expect(interaction.feedback_label.text == player.LARGE_ITEM_CLIMB_MESSAGE, "HUD explains the large-item restriction.")
	interaction.feedback_time = 1.25
	for index in range(10):
		player._try_start_climb()
	_expect(is_equal_approx(interaction.feedback_time, 1.25), "Holding W does not restart the feedback timer every tick.")
	interaction.show_feedback("Another interaction result")
	player._try_start_climb()
	_expect(interaction.feedback_label.text == "Another interaction result", "Held W does not overwrite later interaction feedback.")
	Input.action_release("move_forward")
	player._try_start_climb()
	Input.action_press("move_forward")
	player._try_start_climb()
	_expect(interaction.feedback_label.text == player.LARGE_ITEM_CLIMB_MESSAGE, "A new W attempt can show the reason again.")
	_expect(player.inventory.items.size() == 1 and player.inventory.active_item() == original, "Repeated rejection preserves the sole item's identity and state.")

	player.consume_active_item()
	player._try_start_climb()
	_expect(player.locomotion_state == player.LocomotionState.CLIMBING, "Consuming large cargo restores real-wall climbing.")
	# Sample the same translating and turning carrier path as ordinary climbing.
	rv.position.z -= 4.8 * step_delta
	rv.rotate_y(0.18 * step_delta)
	await physics_frame
	player._apply_rv_delta_compensation()
	var carrier: Vector3 = player.climb_carrier_velocity
	_expect(carrier.length() > 0.1, "Moving RV fixture supplies a nonzero carrier velocity.")
	var pickup: Prop = load(LARGE_PATH).instantiate()
	pickup.persistent_id = "picked-up-cargo"
	pickup.condition = 43.0
	pickup.freeze = true
	world.add_child(pickup)
	pickup.position = Vector3(30, 3, 0)
	var pickup_state: Dictionary = pickup.capture_item_state()
	before = player.global_transform
	pickup.interact(player)
	_expect_detached(before, carrier, "World pickup")
	_expect(pickup.is_queued_for_deletion(), "Successful pickup relinquishes the world source exactly once.")
	_expect(player.inventory.items.size() == 1 and player.inventory.active_item().state == pickup_state, "Pickup keeps one inventory record with the original ID and condition.")
	_expect(player.held_item_node.persistent_id == "picked-up-cargo", "Held presentation keeps the original item identity after detach.")

	_expect(rv.store_player_item(player, player.inventory.active_slot), "Large cargo can be stored after detaching.")
	_expect(player.inventory.items.is_empty() and rv.stored_items.back().state == pickup_state, "Storage transfers the original record without loss or duplication.")
	await _reset_at_wall()
	player._try_start_climb()
	_expect(player.locomotion_state == player.LocomotionState.CLIMBING, "Storage releases the large-item climb gate.")
	carrier = Vector3(2.0, 0.5, -6.0)
	player.climb_carrier_velocity = carrier
	before = player.global_transform
	var storage_count: int = rv.stored_items.size()
	_expect(rv.take_stored_item(player, storage_count - 1), "Warehouse withdrawal succeeds while climbing.")
	_expect_detached(before, carrier, "Warehouse withdrawal")
	_expect(rv.stored_items.size() == storage_count - 1 and player.inventory.items.size() == 1, "Withdrawal removes one warehouse record and adds one inventory record.")
	_expect(player.inventory.active_item().state == pickup_state, "Withdrawal preserves the cargo ID and condition.")

	player.drop_item()
	_expect(player.inventory.items.is_empty(), "Dropping removes the large item from the inventory.")
	var dropped_count := 0
	for node in world.find_children("*", "RigidBody3D", true, false):
		if node is Prop and not node.is_queued_for_deletion() and not player.is_ancestor_of(node) and node.persistent_id == "picked-up-cargo":
			dropped_count += 1
			_expect(is_equal_approx(node.condition, 43.0), "Dropped cargo retains its condition.")
			node.queue_free()
	_expect(dropped_count == 1, "Drop creates exactly one world item with the same identity.")
	await _reset_at_wall()
	player._try_start_climb()
	_expect(player.locomotion_state == player.LocomotionState.CLIMBING, "Drop restores real-wall climbing after the ordinary reentry cooldown.")
	_expect(player.add_item("Small cargo", false, SMALL_PATH), "Small pickup succeeds during climbing.")
	_expect(player.locomotion_state == player.LocomotionState.CLIMBING, "Small pickup does not detach the climber.")
	for index in range(PlayerInventory.MAX_SLOTS - 1):
		player.add_item("Small cargo", false, SMALL_PATH)
	_expect(not player.add_item("Overflow cargo", true, LARGE_PATH), "A full backpack rejects large cargo.")
	_expect(player.locomotion_state == player.LocomotionState.CLIMBING, "Rejected acquisition does not detach a climber.")
	_expect(player.inventory.items.size() == PlayerInventory.MAX_SLOTS, "Rejected acquisition leaves inventory count unchanged.")

	# A direct/restored inventory mutation must also be handled before climbing.
	player.inventory.items.clear()
	player.inventory.active_slot = 0
	player.inventory.add_item("Restored cargo", true, LARGE_PATH, {"id": "restored-cargo"})
	carrier = Vector3(1.0, -0.5, -4.0)
	player.climb_carrier_velocity = carrier
	before = player.global_transform
	player._process_climbing(step_delta)
	_expect_detached(before, carrier, "Direct inventory mutation")
	_expect(player.inventory.active_item().state.id == "restored-cargo", "The safety guard leaves the restored item intact.")

	Input.action_release("move_forward")
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: large-item climbing, feedback, pickup, storage, drop and carrier handoff")
	quit(0 if failures.is_empty() else 1)

func _reset_at_wall() -> void:
	# Reset fixture position and model expiry of the existing reentry cooldown.
	player._exit_climb_to_normal()
	player.climb_reenter_cooldown_remaining = 0.0
	player.released_carrier_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.rv_support.clear()
	rv.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
	player.position = Vector3(2.65, 1.0, 0)
	player.rotation = Vector3(0, PI / 2.0, 0)
	await physics_frame
	player.climb_wall_probe.force_raycast_update()
	_expect(player.climb_wall_probe.is_colliding(), "Fixture ray must hit the actual RV wall.")

func _expect_detached(before: Transform3D, carrier: Vector3, context: String) -> void:
	_expect(player.locomotion_state == player.LocomotionState.NORMAL, context + " safely exits climbing.")
	_expect(player.active_climb_rv == null and player.active_wall_normal == Vector3.ZERO, context + " clears attachment state.")
	_expect(player.global_transform.is_equal_approx(before), context + " does not teleport or rotate the player.")
	_expect(player.velocity.is_equal_approx(carrier) and player.released_carrier_velocity.is_equal_approx(carrier), context + " inherits the carrier velocity.")
	_expect(not player.body_collision_shape.disabled, context + " keeps body collision enabled.")
	_expect(player.climb_reenter_cooldown_remaining > 0.0, context + " preserves the ordinary reentry cooldown.")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

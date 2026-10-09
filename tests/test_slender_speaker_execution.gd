extends SceneTree
## Production Player ownership, swept extraction, cuts and recovery.
const PLAYER := preload("res://player/player.tscn")
class SaveManagerStub extends Node:
	var busy := false
	var active_id := ""
class SaveGeneratorStub extends Node:
	var building := false
class NoDiskStorage extends CheckpointFiles:
	var writes := 0
	func write(_path: String, _data: Dictionary) -> Dictionary:
		writes += 1
		return {"ok": false, "code": "test_no_disk"}
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var captor: Node3D
var anchor: Node3D
var face: Node3D
var reasons: Array[String] = []
var body_events := 0

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func frames(count: int = 2) -> void:
	for i in count:
		await physics_frame
		await process_frame
func reset() -> void:
	if player.is_grabbed(): player.grab_control.end("test_reset")
	player.ragdoll_control.stop()
	player.is_player_dead = false
	player.grab_control.immunity = 0.0
	player.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0, "transform": Transform3D(Basis.IDENTITY, Vector3(0, .05, 0))})
	player.set_physics_process(false)
	anchor.global_position = player.execution_contact_position()
	face.global_position = Vector3(0, 13.8, -2)
	reasons.clear()

func capture() -> bool:
	anchor.global_position = player.execution_contact_position()
	return player.begin_execution(captor, anchor, face)

func test_ownership_lift_cancel() -> void:
	reset()
	player.add_item("Scrap", false, "res://props/scrap.tscn")
	var inventory_before: Array = player.inventory.items.duplicate(true)
	var held_before: Node3D = player.held_item_node
	var slot_before: int = player.inventory.active_slot
	check(not inventory_before.is_empty() and is_instance_valid(held_before), "Inventory preservation exercise uses a real held Item")
	var near_before: float = player.camera.near
	check(capture(), "Ground capture obtains execution ownership")
	check(player.is_grabbed() and player.is_executing() and player.grab_control.captor == captor, "Shared grab mode has unique giant owner")
	check(not player.submit_struggle() and player.grab_control.presses == 0 and not player.grab_control.hud.visible, "Execution has no SPACE escape or struggle HUD")
	var stranger := Node3D.new()
	world.add_child(stranger)
	check(not player.begin_execution(stranger, anchor, face), "Second captor cannot steal active ownership")
	player.cancel_execution(stranger)
	check(player.is_executing(), "Foreign owner cannot cancel execution")
	var before: Vector3 = player.global_position
	anchor.global_position += Vector3.UP * 8.0
	player._physics_process(1.0 / 60.0)
	player.grab_control._process(.1)
	check(player.global_position.is_equal_approx(before + Vector3.UP * 8.0), "Player body follows chest anchor without extra gravity drift")
	var direction: Vector3 = (face.global_position - player.camera.global_position).normalized()
	check((-player.camera.global_basis.z).dot(direction) > .999, "First-person view faces the central speaker")
	var view_before: Transform3D = player.camera.global_transform
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 100)
	player._unhandled_input(motion)
	check(player.camera.global_transform.is_equal_approx(view_before), "Execution rejects mouse look")
	check(player.inventory.items == inventory_before, "Lift preserves inventory and held item state")
	check(player.inventory.active_slot == slot_before and player.held_item_node == held_before, "Lift preserves active slot and the actual held Item instance")
	player.cancel_execution(captor)
	check(not player.is_grabbed() and not player.is_player_dead and player.grab_control.camera == null, "Cancellation safely releases controller and camera")
	check(is_equal_approx(player.camera.near, near_before), "Cancellation restores camera clipping distance")
	check(reasons == ["cancelled"], "One cancellation event reaches music/controller owner")
	check(player.inventory.items == inventory_before and player.held_item_node == held_before, "Cancellation retains inventory and held Item identity")
	stranger.queue_free()

func test_save_guard() -> void:
	reset()
	check(capture(), "Checkpoint guard begins a real shared execution owner")
	var manager := SaveManagerStub.new()
	manager.name = "PoiInstances"
	world.add_child(manager)
	var generator := SaveGeneratorStub.new()
	generator.name = "WorldGenerator"
	world.add_child(generator)
	var checkpoint := load("res://rv/checkpoint.gd").new() as Node
	world.add_child(checkpoint)
	var storage := NoDiskStorage.new()
	checkpoint.file_operations = storage
	check(not checkpoint.save_world(world, "res://.godot/execution-must-not-save.save"), "Actual checkpoint entry rejects captured player before serialization")
	check(checkpoint.last_error.get("code") == "motion" and checkpoint.last_error.get("field") == "player", "Save rejection comes from the shared grabbed-player guard")
	check(storage.writes == 0, "Rejected execution never invokes checkpoint storage")
	player.cancel_execution(captor)
	checkpoint.queue_free()
	manager.queue_free()
	generator.queue_free()
	await frames()

func test_blocked_lift() -> void:
	reset()
	var ceiling := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, .3, 8)
	collision.shape = box
	ceiling.add_child(collision)
	world.add_child(ceiling)
	ceiling.position = Vector3(0, 3, 0)
	await frames()
	check(capture(), "Capture below ceiling starts at real contact")
	anchor.global_position += Vector3.UP * 10.0
	player._physics_process(1.0 / 60.0)
	check(not player.is_grabbed() and not player.is_player_dead, "Blocked capsule sweep releases player alive")
	check(player.global_position.y < 1.5, "Swept lift never teleports through the ceiling")
	check(reasons == ["execution_path_blocked"], "Blocked path reports precise cancellation reason")
	ceiling.queue_free()
	await frames()

func test_mode_cleanup() -> void:
	reset()
	var ladder: RVLadder = load("res://equipment/side_door_ladder.tscn").instantiate()
	world.add_child(ladder)
	ladder.freeze = true
	ladder.position.x = 10.0
	await frames()
	# Real ladder ownership fields/exceptions are the same ones installed by
	# begin_ladder_climb; contact eligibility belongs to the giant controller.
	player.locomotion_state = player.LocomotionState.CLIMBING
	player.active_climb_ladder = ladder
	player.active_climb_rv = ladder
	player.add_collision_exception_with(ladder)
	ladder.availability_changed.connect(player._validate_active_ladder)
	ladder.tree_exiting.connect(player._active_ladder_removed)
	check(capture(), "Giant can capture climbing player")
	check(player.active_climb_ladder == null and player.active_climb_rv == null and player.locomotion_state == player.LocomotionState.NORMAL, "Capture releases ladder state and carrier")
	check(not player.get_collision_exceptions().has(ladder), "Ladder collision exception is removed")
	player.cancel_execution(captor)
	ladder.queue_free()
	reset()
	var rv: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(rv)
	rv.position = Vector3(20, 0, 0)
	rv.get_node("Chassis").freeze = true
	await frames()
	var seat: Node3D
	for child in rv.find_children("*", "Node3D", true, false):
		if child.has_method("release_for_execution"):
			seat = child
			break
	check(seat != null, "Production RV has execution-aware driver seat")
	if seat != null:
		check(player.enter_seat_mode(seat), "Driver enters normal seat mode")
		seat.current_driver = player
		seat.seat_camera.make_current()
		rv.get_node("Chassis").set_driving_state(true)
		var before: Vector3 = player.global_position
		var overlapping_roof := StaticBody3D.new()
		var roof_collision := CollisionShape3D.new()
		var roof_shape := BoxShape3D.new()
		roof_shape.size = Vector3(3, .3, 3)
		roof_collision.shape = roof_shape
		overlapping_roof.add_child(roof_collision)
		world.add_child(overlapping_roof)
		overlapping_roof.global_position = before + Vector3.UP * 1.15
		await frames()
		check(not capture(), "Disabled seated capsule overlapping intact roof cannot bypass a sweep")
		check(player.seated_in == seat and seat.current_driver == player and not player.is_grabbed(), "Rejected overlapping source preserves driver ownership")
		overlapping_roof.queue_free()
		await frames()
		check(capture(), "Exposed driver transfers ownership to execution")
		check(player.global_position.is_equal_approx(before), "Seat extraction starts without forced-exit teleport")
		check(player.seated_in == null and seat.current_driver == null and player.camera.current and not player.body_collision_shape.disabled, "Capture clears both seat owners and restores full-body collider/view")
		player.cancel_execution(captor)
	# A moving roof carrier must not add its velocity/transform to the lift.
	reset()
	var chassis: Node3D = rv.get_node("Chassis")
	player.rv_support.rv = chassis
	player.rv_support.surface = chassis.get_node("RoofFront")
	player.rv_support.previous = chassis.global_transform
	player.rv_support.carrier_velocity = Vector3(12, 0, -20)
	player.released_carrier_velocity = Vector3(4, 0, -8)
	player.velocity = Vector3(1, 2, 3)
	check(capture(), "Roof-supported player's shared owner can transfer")
	check(player.rv_support.rv == null and player.rv_support.surface == null and player.rv_support.carrier_velocity == Vector3.ZERO, "Capture clears moving RV support ownership and velocity")
	check(player.released_carrier_velocity == Vector3.ZERO and player.velocity == Vector3.ZERO, "Capture removes inherited carrier motion from the execution path")
	player.cancel_execution(captor)
	rv.queue_free()
	await frames()

func test_crush_and_respawn() -> void:
	reset()
	check(player.add_item("Scrap", false, "res://props/scrap.tscn", {"condition": 37.0}), "Crush inventory uses damaged real Item state")
	var inventory_before: Array = player.inventory.items.duplicate(true)
	var slot_before: int = player.inventory.active_slot
	player.sever_part(&"left_arm")
	player.sever_part(&"left_leg")
	await frames()
	var effects_before := get_nodes_in_group("player_detached_parts").size()
	var changes_before := body_events
	check(player.is_crawling() and capture(), "Giant supports already-dismembered crawling target")
	# Production keeps player physics enabled through death. Earlier cases
	# disable automatic ticks only so their explicit swept steps are repeatable.
	player.set_physics_process(true)
	check(player.complete_execution(captor), "Execution completes once")
	check(not player.complete_execution(captor), "Repeated crush cannot replay death/cuts")
	check(player.is_player_dead and player.current_player_health == 0.0 and not player.is_grabbed(), "Crush releases ownership and enters ordinary death")
	for part: StringName in PlayerBodyState.PARTS:
		check(not player.body_state.has_part(part), "Crush separates surviving part " + String(part))
	check(get_nodes_in_group("player_detached_parts").size() == effects_before + 3, "Missing parts are not detached twice")
	check(body_events == changes_before + 1, "Batch crush applies body capabilities once")
	check(reasons == ["death"], "Crush and duplicate completion emit exactly one death release")
	check(player.inventory.items == inventory_before and player.inventory.active_slot == slot_before, "Fatal crush preserves Item identity, condition and backpack slot")
	await frames()
	check(player.ragdoll_control.active, "Execution uses existing live ragdoll")
	var detached_head: Node3D = player.ragdoll_control.detached_head
	check(player.ragdoll_control.following_detached_head and is_instance_valid(detached_head), "Death camera follows the actual separated head")
	check((player.camera.cull_mask & PlayerModelVisual.FULL_BODY_LAYER) == 0, "First-person camera excludes its separated head layer")
	if is_instance_valid(detached_head):
		for mesh: MeshInstance3D in detached_head.meshes:
			check(mesh.layers == PlayerModelVisual.FULL_BODY_LAYER, "Separated head remains observer-visible but excluded from local death camera")
	check(not player.get_node("Visuals").local_body.visible, "Local torso stays hidden during stable-view ragdoll death")
	var corpses_before := world.find_children("*", "Node3D", true, false).filter(func(node): return node is CorpseProp and node.kind == "player").size()
	player._respawn()
	check(not player.is_player_dead and player.can_drive() and player.camera.current, "Existing respawn restores all parts and input")
	check(player.body_state.has_part(&"head") and player.usable_arms() == 2, "Respawn restores head and both arms")
	check(not player.ragdoll_control.following_detached_head and player.get_node("Visuals").local_body.visible, "Revival restores local torso and clears separated-head camera ownership")
	if is_instance_valid(detached_head):
		for mesh: MeshInstance3D in detached_head.meshes:
			check(mesh.layers == 1, "Old separated head returns to ordinary world visibility after revival")
	check(player.inventory.items == inventory_before and player.inventory.active_slot == slot_before and is_instance_valid(player.held_item_node), "Revival retains saved inventory and restores held preview")
	check(player.is_physics_processing() and player.is_processing_unhandled_input() and not player.is_grabbed(), "Revival restores physics and ordinary input without stale ownership")
	var corpses := world.find_children("*", "Node3D", true, false).filter(func(node): return node is CorpseProp and node.kind == "player")
	check(corpses.size() == corpses_before + 1, "Real ragdoll revival leaves one persistent player corpse")
	if not corpses.is_empty():
		for part: StringName in PlayerBodyState.PARTS:
			check(not corpses.back().body_state.has_part(part), "Player corpse preserves execution cut state for " + String(part))

func test_world_and_anchor_cleanup() -> void:
	reset()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 16)
	world.add_child(viewport)
	var owner := Node3D.new()
	viewport.add_child(owner)
	var owner_anchor := Node3D.new()
	owner.add_child(owner_anchor)
	owner_anchor.global_position = player.execution_contact_position()
	var owner_face := Node3D.new()
	owner.add_child(owner_face)
	owner_face.global_position = Vector3(0, 13, -2)
	check(player.begin_execution(owner, owner_anchor, owner_face), "Shared World3D owner can begin execution")
	viewport.own_world_3d = true
	player.grab_control._physics_process(1.0 / 60.0)
	check(not player.is_grabbed() and reasons == ["world_changed"] and player.grab_control.camera == null, "Actual World3D switch clears control and camera without requiring world-transition helper")
	player.grab_control.immunity = 0.0
	check(not player.begin_execution(owner, owner_anchor, owner_face), "Cross-world owner cannot capture player")
	viewport.queue_free()
	await frames()
	reset()
	check(capture(), "Anchor removal cleanup setup")
	anchor.queue_free()
	await frames()
	player._physics_process(1.0 / 60.0)
	check(not player.is_grabbed() and reasons == ["execution_anchor_removed"] and player.grab_control.camera == null, "Removed grip anchor releases execution without leaving camera ownership")
	anchor = Node3D.new()
	captor.add_child(anchor)

func test_owner_and_world_cleanup() -> void:
	reset()
	check(capture(), "World transition cleanup setup")
	player.complete_world_transition(Transform3D(Basis.IDENTITY, Vector3(12, .05, 0)))
	check(not player.is_grabbed() and player.grab_control.camera == null and reasons == ["world_transition"], "World transition removes execution and camera state")
	reset()
	check(capture(), "Owner removal cleanup setup")
	captor.queue_free()
	await frames()
	check(not player.is_grabbed() and player.grab_control.camera == null and reasons.has("owner_removed"), "Removing giant safely releases player and broadcasts audio cleanup")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.body_state_changed.connect(func(): body_events += 1)
	player.grab_control.released.connect(func(reason: String): reasons.append(reason))
	captor = Node3D.new()
	world.add_child(captor)
	anchor = Node3D.new()
	captor.add_child(anchor)
	face = Node3D.new()
	captor.add_child(face)
	await frames()
	test_ownership_lift_cancel()
	await test_save_guard()
	await test_blocked_lift()
	await test_mode_cleanup()
	await test_crush_and_respawn()
	await frames()
	await test_world_and_anchor_cleanup()
	await test_owner_and_world_cleanup()
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: execution ownership, swept lift, first-person camera, input/held-item inventory, isolated no-disk save rejection, climbing/driver/RV-support transfer, missing-limb single death, persistent corpse/revival, actual World3D/anchor/owner cleanup and cancellation")
	quit(0 if failures.is_empty() else 1)

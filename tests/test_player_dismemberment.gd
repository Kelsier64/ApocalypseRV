extends SceneTree
## Exercise the production Player's persistent cuts, input, effects and recovery.
const PLAYER := preload("res://player/player.tscn")
const RAKER := preload("res://enemies/raker.tscn")
const PARTS: Array[StringName] = [&"head", &"left_arm", &"right_arm", &"left_leg", &"right_leg"]
var failures: Array[String] = []
var arena: Node3D
var actor: CharacterBody3D
var body_changes := 0

func _init() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func _body_changed(_state: Variant = null) -> void:
	body_changes += 1

func restore_fresh(body: Dictionary = {}) -> void:
	if actor.is_grabbed(): actor.grab_control.end("test_reset")
	actor.ragdoll_control.stop()
	actor.is_player_dead = false
	actor.grab_control.immunity = 0.0
	actor.damage_cooldown = 0.0
	var state := {"items": [], "slot": 0, "health": 100.0, "transform": Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0))}
	if not body.is_empty(): state["body"] = body
	actor.restore_checkpoint_state(state)

func effects_for(part: StringName) -> int:
	return get_nodes_in_group("player_detached_parts").filter(func(node: Node):
		return node.get_meta("player_detached_part", &"") == part and arena.is_ancestor_of(node)).size()

func clear_effects() -> void:
	for node: Node in get_nodes_in_group("player_detached_parts"):
		if arena.is_ancestor_of(node): node.queue_free()
	await steps(2)

func test_cuts() -> void:
	check(actor.body_state.capture().present.size() == 5, "Only the five supported parts are persisted")
	check(not actor.sever_part(&"tail", {}), "Unknown part is rejected")
	for part: StringName in PARTS:
		restore_fresh()
		var count_before := effects_for(part)
		var changes_before := body_changes
		check(actor.sever_part(part, {"source": "behavior_test"}), "First cut succeeds: " + String(part))
		check(not actor.body_state.has_part(part), "Part presence changes: " + String(part))
		check(body_changes == changes_before + 1, "One body change signal: " + String(part))
		check(effects_for(part) == count_before + 1, "One detached physical part: " + String(part))
		var health_after: float = actor.current_player_health
		check(not actor.sever_part(part, {"source": "duplicate_test"}), "Duplicate cut is rejected: " + String(part))
		check(actor.current_player_health == health_after and body_changes == changes_before + 1, "Duplicate cut cannot damage or emit: " + String(part))
		check(effects_for(part) == count_before + 1, "Duplicate cut cannot spawn an effect: " + String(part))
		if part == &"head":
			check(actor.is_player_dead and actor.current_player_health == 0.0, "Head loss immediately enters death")
		else:
			check(not actor.is_player_dead, "An isolated limb cut is survivable: " + String(part))

func test_capabilities() -> void:
	restore_fresh()
	check(actor.usable_arms() == 2 and actor.can_use_hands(2) and actor.can_drive(), "Intact player has all hand and driving capabilities")
	var large_prop: Prop = load("res://props/engine_standard.tscn").instantiate()
	arena.add_child(large_prop)
	large_prop.freeze = true
	check(actor.add_prop_item(large_prop, "res://props/engine_standard.tscn"), "Intact player can pick up a large prop")
	actor.add_item("Scrap", false, "res://props/scrap.tscn")
	var retained_items: Array = actor.inventory.items.duplicate(true)
	large_prop.queue_free()
	actor.sever_part(&"left_arm", {})
	check(actor.usable_arms() == 1 and actor.can_use_hands() and not actor.can_use_hands(2), "One arm keeps one-hand actions and blocks two-hand actions")
	check(actor.inventory.items == retained_items and actor.held_item_node == null, "Arm loss preserves large item identity/state and removes its unusable held preview")
	actor._set_active_slot(1)
	check(actor.inventory.active_slot == 1 and actor.held_item_node != null, "An unusable large item does not lock selection of a small item")
	check(not actor._can_begin_climb(false, true, true, true, true), "One arm cannot begin a climb")
	var prop: Prop = load("res://props/scrap.tscn").instantiate()
	arena.add_child(prop)
	prop.freeze = true
	check(actor.add_prop_item(prop, "res://props/scrap.tscn"), "One arm can pick up a small prop")
	prop.is_large = true
	var item_count: int = actor.inventory.items.size()
	check(not actor.add_prop_item(prop, "res://props/scrap.tscn") and actor.inventory.items.size() == item_count, "One arm cannot pick up a large prop")
	actor.sever_part(&"right_arm", {})
	check(actor.usable_arms() == 0 and not actor.can_use_hands() and not actor.can_drive(), "No arms block hands and driving")
	prop.is_large = false
	check(not actor.add_prop_item(prop, "res://props/scrap.tscn") and actor.inventory.items.size() == item_count, "No arms cannot pick up a small prop")
	prop.queue_free()
	check(actor.is_processing_unhandled_input(), "Arm loss retains the mouse input handler")
	if DisplayServer.get_name() != "headless":
		var yaw: float = actor.rotation.y
		var pitch: float = actor.camera.rotation.x
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(80, 25)
		actor._unhandled_input(motion)
		check(absf(actor.rotation.y - yaw) > 0.01 and absf(actor.camera.rotation.x - pitch) > 0.01, "Arm loss retains mouse look")
	check(actor.enter_ui_mode(), "Arm loss retains UI access")
	actor.exit_ui_mode()
	restore_fresh()
	await steps(2)
	var standing_height: float = actor.body_collision_shape.shape.height
	var standing_camera: float = actor.camera.position.y
	actor.sever_part(&"left_leg", {})
	await steps(2)
	check(actor.is_crawling() and not actor.can_drive(), "One missing leg forces crawling and blocks driving")
	check(not actor.can_be_grabbed(), "Crawling posture cannot enter the standing head grab")
	check(not actor._can_begin_climb(false, true, true, true, true), "Crawling cannot begin a climb")
	check(actor.body_collision_shape.shape.height < standing_height and actor.camera.position.y < standing_camera, "Crawling lowers collision volume and view")
	actor.position.x = 10.0
	actor.set_physics_process(true)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await steps(35)
	var crawl_speed := Vector2(actor.velocity.x, actor.velocity.z).length()
	check(crawl_speed > 0.0 and crawl_speed < actor.SPEED, "Crawling still moves at reduced speed with sprint held")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_press("jump")
	await steps(2)
	check(actor.velocity.y <= 0.01, "Crawling cannot jump")
	Input.action_release("jump")
	actor.set_physics_process(false)
	actor.sever_part(&"right_leg", {})
	check(actor.is_crawling() and actor.can_use_hands(), "Both missing legs preserve available hands and crawling")

func test_persistence() -> void:
	var saved: Dictionary = actor.body_state.capture()
	restore_fresh()
	check(not actor.is_crawling() and actor.body_state.has_part(&"left_leg"), "Legacy state without body restores an intact player")
	restore_fresh(saved)
	check(actor.body_state.capture() == saved and actor.is_crawling(), "Checkpoint restore reapplies missing legs and crawling")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var indoor := Node3D.new()
	viewport.add_child(indoor)
	actor.reparent(indoor)
	actor.complete_world_transition(Transform3D.IDENTITY)
	check(actor.body_state.capture() == saved and actor.is_crawling(), "Entering another World3D preserves the same body state")
	actor.reparent(arena)
	actor.complete_world_transition(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	check(actor.body_state.capture() == saved and actor.is_crawling(), "Returning outdoors preserves the same body state")
	viewport.queue_free()

func test_safe_return() -> void:
	var manager := PoiInstanceManager.new()
	arena.add_child(manager)
	manager._home = arena
	manager._player = actor
	manager._return_transform = Transform3D.IDENTITY
	# Offset from the downward ray, but overlapping the standing capsule's side.
	# A clear crawling volume should not be moved to the high fallback spawn.
	var obstruction := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.4, 20.0)
	collision.shape = box
	obstruction.add_child(collision)
	arena.add_child(obstruction)
	obstruction.position = Vector3(0.3, 1.3, 0.0)
	await steps(2)
	var crawling_return: Transform3D = manager._safe_return_transform()
	check(crawling_return.origin.is_equal_approx(Vector3(0, 0.05, 0)), "POI return tests the actual crawling collider and offset")
	restore_fresh()
	await steps(2)
	var standing_return: Transform3D = manager._safe_return_transform()
	check(standing_return.origin.y > 2.0, "The same return obstacle blocks an intact standing body")
	obstruction.queue_free()
	manager.queue_free()

func test_bite_and_respawn() -> void:
	restore_fresh()
	var captor: Raker = RAKER.instantiate()
	arena.add_child(captor)
	captor.set_physics_process(false)
	captor.loot_drops = {}
	captor.position = Vector3(0, 0, -1)
	check(actor.begin_grab(captor, 10), "Real captor begins wounded-bite test")
	actor.damage_cooldown = 1.0
	actor.apply_grab_bite(captor, false)
	check(actor.current_player_health == 50.0 and not actor.body_state.has_part(&"left_arm") and not actor.is_player_dead, "Wounded bite cuts the left arm and pays exactly 50 despite hurt cooldown")
	var wounded: Dictionary = actor.body_state.capture()
	actor.end_grab(captor, "test_first_bite")
	restore_fresh(wounded)
	check(actor.begin_grab(captor, 10), "Player with missing left arm can be captured again")
	actor.apply_grab_bite(captor, false)
	check(actor.is_player_dead and actor.current_player_health == 0.0 and not actor.body_state.has_part(&"head"), "Repeated wounded bite promotes missing-left-arm target to fatal head loss")
	await steps(2)
	check(not actor.is_grabbed(), "Fatal bite releases grab ownership")
	# The recovery method must restore all limbs together with health and input.
	actor.ragdoll_control.stop()
	# Use a clear floor volume, away from the intentionally spawned limbs/captor.
	actor.global_position = Vector3(10, 0.05, 0)
	actor._respawn()
	check(not actor.is_player_dead and actor.current_player_health == 100.0 and not actor.is_crawling(), "Respawn restores health and standing")
	for part: StringName in PARTS:
		check(actor.body_state.has_part(part), "Respawn restores " + String(part))
	check(actor.usable_arms() == 2 and actor.can_drive(), "Respawn restores hands and driving")
	captor.queue_free()

func run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	current_scene = arena
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	actor = PLAYER.instantiate()
	arena.add_child(actor)
	actor.set_physics_process(false)
	actor.body_state_changed.connect(_body_changed)
	await steps(2)
	test_cuts()
	await clear_effects()
	await test_capabilities()
	test_persistence()
	await clear_effects()
	await test_safe_return()
	await test_bite_and_respawn()
	arena.queue_free()
	await steps(2)
	if failures.is_empty(): print("PASS: five player cuts, duplicate rejection, physical effects, capabilities, checkpoint/World3D state, wounded/fatal bite and full respawn")
	quit(0 if failures.is_empty() else 1)

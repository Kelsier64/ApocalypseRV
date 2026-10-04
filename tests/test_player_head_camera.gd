extends SceneTree
## Follow the actual severed head through grab release, physics and recovery.
const PLAYER := preload("res://player/player.tscn")
const RAKER := preload("res://enemies/raker.tscn")
var failures: Array[String] = []
var arena: Node3D
var actor: CharacterBody3D

func _init() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok and detail not in failures:
		failures.append(detail)
		push_error("FAIL: " + detail)

func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func fresh(at := Vector3(0, 4, 0)) -> void:
	actor.ragdoll_control.stop()
	actor.is_player_dead = false
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0, "transform": Transform3D(Basis.IDENTITY, at)})
	actor.grab_control.immunity = 0.0
	actor.set_physics_process(false)
	actor.camera.rotation = Vector3.ZERO
	actor.camera.position = actor.get_node("Visuals/Locomotion").camera_rest_position
	for part: Node in get_nodes_in_group("player_detached_parts"):
		part.queue_free()
	await steps(2)

func tracked_head() -> Node3D:
	var head: Node3D = actor.ragdoll_control.detached_head
	check(is_instance_valid(head), "Fatal sever tracks the spawned detached head")
	return head

func check_hidden(head: Node3D, mask: int) -> void:
	check(not head.meshes.is_empty(), "Detached head includes rendered meshes")
	for mesh: MeshInstance3D in head.meshes:
		check(mesh.visible and (mesh.layers & mask) == 0, "Tracked head remains available to other views but cannot occlude its own camera")
	check(actor.camera.cull_mask == mask, "Following the head preserves the player's existing camera cull mask")

func check_restored(head: Node3D) -> void:
	check(actor.ragdoll_control.detached_head == null, "Stopping death clears detached head ownership")
	for mesh: MeshInstance3D in head.meshes:
		check(mesh.layers == 1, "Stopping death returns the dropped head to normal world rendering")

func test_grabbed_fatal_bite() -> void:
	await fresh()
	var captor: Node3D = RAKER.instantiate()
	arena.add_child(captor)
	captor.set_physics_process(false)
	captor.loot_drops = {}
	captor.position = Vector3(0, 4, -1.2)
	check(actor.begin_grab(captor, 10), "Production grab begins before fatal head bite")
	# Deliberately frame away from the rest eye. Cleanup normally resets this.
	actor.camera.position += Vector3(.17, .11, -.19)
	actor.camera.rotation = Vector3(-.13, .32, .09)
	var view: Transform3D = actor.camera.global_transform
	var camera: Camera3D = actor.camera
	var mask: int = camera.cull_mask
	actor.apply_grab_bite(captor, true)
	var head := tracked_head()
	if head == null:
		captor.queue_free()
		return
	var eye_offset: Vector3 = view.origin - head.camera_anchor_position()
	check(actor.is_player_dead and not actor.body_state.has_part(&"head") and not actor.is_grabbed(), "Fatal bite removes the head and releases grab ownership")
	check(actor.ragdoll_control.eye_offset.is_equal_approx(eye_offset), "Head sever captures the pulled eye offset before grab cleanup")
	check(actor.ragdoll_control.camera_basis.is_equal_approx(view.basis.orthonormalized()), "Head sever captures the complete world viewing basis before grab cleanup")
	check_hidden(head, mask)
	head.set_physics_process(false)
	await steps(2)
	var control: Node = actor.ragdoll_control
	control.remaining = 100.0
	check(control.active and not control.bodies.has("head"), "Headless torso runs its own physical death without retaining a second head")
	check(actor.camera == camera and camera.current, "Death keeps the original first-person camera node")
	var held_anchor: Vector3 = head.camera_anchor_position()
	head._release()
	check(head.simulated and head.camera_anchor_position().distance_to(held_anchor) < .001, "Held-to-physical handoff keeps the same head collider center")
	control._update_camera()
	check(camera.global_position.distance_to(view.origin) < .02, "First death camera update preserves the eye position before grab cleanup")
	# Real physical motion must carry the view while the head tumbles independently.
	var start_anchor: Vector3 = head.camera_anchor_position()
	var start_basis: Basis = head.builder.bodies["head"].global_basis
	head.builder.bodies["head"].linear_velocity = Vector3(2.0, -.2, 0)
	head.builder.bodies["head"].angular_velocity = Vector3(2, 1, -3)
	for frame in ceili(.5 * Engine.physics_ticks_per_second):
		await steps(1)
		check(camera.global_transform.is_finite(), "Falling severed-head camera remains finite")
		check(camera.global_basis.is_equal_approx(view.basis.orthonormalized()), "Head tumbling cannot add camera roll or change the captured viewing direction")
		check(camera.global_position.distance_to(head.camera_anchor_position() + eye_offset) < .03, "First-person eye follows the detached physical head rather than torso")
	check(head.camera_anchor_position().distance_to(start_anchor) > .5, "Detached head physically falls and translates")
	check(not head.builder.bodies["head"].global_basis.is_equal_approx(start_basis), "Physical head actually tumbles during the stable-view sample")
	# Moving only the torso cannot move a camera that belongs to the dropped head.
	var before: Vector3 = camera.global_position
	control.bodies["spine_02"].global_position += Vector3(6, 0, 0)
	control._update_camera()
	check(camera.global_position.distance_to(before) < .001, "Torso movement cannot take the view away from the severed head")
	control.stop()
	check_restored(head)
	actor.global_position = Vector3(10, .05, 0)
	actor._respawn()
	check(not actor.is_player_dead and actor.body_state.has_part(&"head"), "Respawn restores the player's own head")
	check(actor.camera.position.distance_to(actor.get_node("Visuals/Locomotion").camera_rest_position) < .001, "Respawn restores the ordinary first-person eye anchor")
	captor.queue_free()

func test_seated_cut() -> void:
	await fresh(Vector3(8, .05, 0))
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	arena.add_child(vehicle)
	var chassis: VehicleBody3D = vehicle.get_node("Chassis")
	chassis.freeze = true
	chassis.position = Vector3(8, 1, 0)
	await steps(5)
	var seat: Node = chassis.get_node("DriverSeat")
	seat.interact_hold(actor)
	check(actor.seated_in == seat, "Production driver seat entered before decapitation")
	seat.seat_camera.position += Vector3(.12, .06, -.08)
	seat.seat_camera.rotation = Vector3(-.2, .45, .07)
	var view: Transform3D = seat.seat_camera.global_transform
	actor.sever_part(&"head", {})
	var head := tracked_head()
	if head != null:
		check(actor.ragdoll_control.eye_offset.is_equal_approx(view.origin - head.camera_anchor_position()), "Seated cut captures seat eye origin before forced exit relocates the body")
		check(actor.ragdoll_control.camera_basis.is_equal_approx(view.basis.orthonormalized()), "Seated cut retains the seat camera's exact pre-exit world direction")
		head.set_physics_process(false)
		await steps(2)
		actor.ragdoll_control.remaining = 100.0
		check(actor.seated_in == null and seat.current_driver == null and actor.camera.current, "Seated decapitation releases seat ownership and returns to the first-person camera")
		check(actor.camera.global_basis.is_equal_approx(view.basis.orthonormalized()), "Seat cleanup does not overwrite the detached-head viewing basis")
		actor.ragdoll_control.stop()
		check_restored(head)
	vehicle.queue_free()
	await steps(2)

func test_missing_and_transferred_target() -> void:
	await fresh()
	actor.sever_part(&"head", {})
	var head := tracked_head()
	if head == null: return
	await steps(2)
	var control: Node = actor.ragdoll_control
	control.remaining = 100.0
	control._update_camera()
	var last: Transform3D = actor.camera.global_transform
	head.free()
	control.bodies["spine_02"].global_position += Vector3(8, 0, 0)
	control._update_camera()
	check(actor.camera.global_transform.is_finite() and actor.camera.global_transform.is_equal_approx(last), "Removed detached head freezes the last view safely instead of jumping to the torso")
	await fresh()
	actor.sever_part(&"head", {})
	head = tracked_head()
	if head == null: return
	await steps(2)
	control.remaining = 100.0
	control._update_camera()
	last = actor.camera.global_transform
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	head.reparent(viewport)
	head.global_position += Vector3(100, 100, 100)
	control._update_camera()
	check(actor.camera.global_transform.is_finite() and actor.camera.global_transform.is_equal_approx(last), "Head moved into another World3D cannot drag the original-world camera")
	control.stop()
	check_restored(head)
	viewport.queue_free()
	await steps(2)
	# A legacy headless state has no detached target; its body fallback is valid.
	await fresh()
	actor.body_state.sever(&"head")
	actor.take_damage(1000)
	await steps(2)
	control.remaining = 100.0
	control._update_camera()
	check(control.active and control.detached_head == null and actor.camera.global_transform.is_finite(), "Death from an already-headless state retains a finite body fallback")

func test_respawn_while_following() -> void:
	await fresh(Vector3(20, .05, 0))
	actor.sever_part(&"head", {})
	var head := tracked_head()
	if head == null: return
	await steps(5)
	check(actor.ragdoll_control.active, "Respawn fixture begins with active detached-head tracking")
	actor._respawn()
	check(not actor.is_player_dead and not actor.ragdoll_control.active and actor.body_state.has_part(&"head"), "Respawn itself stops physical death and restores the player's head")
	check_restored(head)
	check(actor.camera.position.distance_to(actor.get_node("Visuals/Locomotion").camera_rest_position) < .001, "Active tracking respawn restores the ordinary eye anchor")

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
	await steps(2)
	await test_grabbed_fatal_bite()
	await test_seated_cut()
	await test_respawn_while_following()
	await test_missing_and_transferred_target()
	arena.queue_free()
	await steps(2)
	if failures.is_empty(): print("PASS: severed-head first-person physics, stable view, grab/seat handoff, visibility and target lifecycle")
	quit(0 if failures.is_empty() else 1)

extends "res://tests/test_slender_speaker_acquisition.gd"
## Palm panel removal, solid equipment and independently clear fingers.
## Reuses production rig/player contact fixtures; all captures use real sweeps.

class SmashServiceItem extends Item:
	var events := {"stops": 0, "removals": 0, "availability": 0}
	func _on_service_stopped() -> void:
		events.stops += 1

class SmashRV extends Node3D:
	func add_item(_item: String, _amount: int) -> void: pass
	func deduct_materials(_cost: Dictionary) -> bool: return true

func smash_equipment_damage() -> void:
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	pose_giant(Vector3(0, 0, 2.1))
	var support := SmashRV.new()
	world.add_child(support)
	support.add_to_group(Groups.RV)
	var equipment := SmashServiceItem.new()
	var wall := StaticBody3D.new()
	var behind := Item.new()
	var collateral := Item.new()
	var objects: Array[Node3D] = [equipment, wall, behind, collateral]
	for index in objects.size():
		var body := objects[index]
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.15, .3, .15)
		collision.shape = shape
		body.add_child(collision)
		if body is RigidBody3D: body.freeze = true
		world.add_child(body)
		body.global_position = Vector3(40, 3, float(index + 1))
	collateral.global_position = Vector3(42, 3, 1)
	equipment.confirm_placement(equipment.global_transform, support)
	# Ordinary damage immunity and zero-health retention do not disable the
	# explicit giant route; surviving equipment keeps its mounted service.
	equipment.can_be_destroyed = false
	equipment.destroy_on_zero_health = false
	var events := equipment.events
	equipment.availability_changed.connect(func() -> void: events.availability += 1)
	equipment.removing.connect(func() -> void: events.removals += 1)
	await frames()
	check(equipment.can_operate() and equipment.current_health == 100.0, "Smash fixture starts with an operating mounted 100 HP item")
	equipment.take_damage(60.0)
	check(equipment.current_health == 100.0, "Ordinary damage remains blocked for the immune equipment fixture")
	var start := Vector3(40, 3, 0)
	var end := Vector3(40, 3, 5)
	giant._begin_smash()
	check(giant.settings.smash_equipment_damage == 60.0 and giant._smash_sweep(start, end, .24).get("collider") == equipment,
		"Equipment smash defaults to 60 damage and begins with actual first contact")
	var hit := giant._clear_smash_equipment_path(start, end, .24)
	check(hit.get("collider") == equipment and equipment.current_health == 40.0 and not equipment.is_destroyed,
		"First swept smash subtracts 60 HP and surviving equipment blocks the hand")
	check(equipment.collision_layer != 0 and equipment.visible and equipment.can_operate() and events.stops == 0 and events.removals == 0,
		"Surviving equipment retains collider, appearance, mounted service and removal lifecycle")
	for repeat in 3:
		hit = giant._clear_smash_equipment_path(start, end, .24)
	check(hit.get("collider") == equipment and equipment.current_health == 40.0 and events.availability == 1,
		"Repeated queries from the same smash do not charge equipment again")
	check(behind.current_health == 100.0 and collateral.current_health == 100.0 and giant._smash_cleared_items.is_empty(),
		"A nonlethal first contact protects blocked and untouched equipment")
	giant._begin_smash()
	hit = giant._clear_smash_equipment_path(start, end, .24)
	check(equipment.current_health == 0.0 and equipment.is_destroyed and equipment.is_queued_for_deletion(),
		"A later swing destroys the same equipment despite its ordinary damage flags")
	check(equipment.collision_layer == 0 and equipment.collision_mask == 0 and not equipment.visible and hit.get("collider") == wall,
		"Lethal contact opens the same swept path immediately and stops at the next solid wall")
	check(events.stops == 1 and events.removals == 1 and events.availability == 2,
		"Equipment notifies damage twice and stops/removes its service exactly once at death")
	check(not equipment.damage_from_giant_smash(60.0) and events.stops == 1 and events.removals == 1,
		"Already destroyed equipment rejects repeated lifecycle processing")
	check(behind.current_health == 100.0 and collateral.current_health == 100.0 and wall.collision_layer != 0,
		"The opened smash path still preserves equipment behind a solid wall and nearby untouched equipment")
	await frames()
	check(events.stops == 1 and events.removals == 1, "Deferred equipment deletion does not stop services a second time")
	print("SMASH_EQUIPMENT_DAMAGE first=40 final=0 service_stops=", events.stops, " next_contact=", hit.get("collider"))
	for body in objects:
		if is_instance_valid(body) and not body.is_queued_for_deletion(): body.queue_free()
	support.queue_free()
	giant._cancel_execution("fixture_reset")
	await frames()

func palm_contacts_in_same_grab() -> void:
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	giant._begin_grab()
	for tick in 20:
		giant.phase_elapsed = float(tick + 1) / 60.0
		giant._advance_grab()
	check(giant.phase == SlenderSpeaker.Phase.GRAB, "Palm contact fixture inserts obstacles during a still-live actual reach")
	var palm := giant._grab_palm_position("R")
	var panel := RVStructurePanel.new()
	var equipment := Item.new()
	var collateral := Item.new()
	var objects: Array[RigidBody3D] = [panel, equipment, collateral]
	for index in objects.size():
		var body := objects[index]
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * .025
		collision.shape = shape
		body.add_child(collision)
		body.freeze = true
		world.add_child(body)
		body.global_position = palm + Vector3.RIGHT * (.05 if index == 0 else -.05)
	collateral.global_position = palm + Vector3.RIGHT * 3.0
	await frames()
	giant.phase_elapsed = 21.0 / 60.0
	giant._advance_grab()
	check(not equipment.is_destroyed and equipment.current_health == equipment.max_health and equipment.collision_layer != 0,
		"Actual moving palm leaves contacted equipment intact and physically solid")
	check(giant.phase == SlenderSpeaker.Phase.GRAB and not collateral.is_destroyed,
		"Contacted equipment preserves the unfinished reach and untouched equipment")
	# Move the intact obstacle out of the actual hand path before continuing.
	# Panel contact remains separately covered by the ordered sweep fixture.
	equipment.global_position += Vector3.RIGHT * 20.0
	await frames()
	for tick in range(21, 60):
		giant.phase_elapsed = float(tick + 1) / 60.0
		giant._advance_grab()
		if giant.phase != SlenderSpeaker.Phase.GRAB: break
	check(player.is_executing() and capture_path_clear(), "That same grab continues to clear standing capture after intact equipment moves aside")
	print("GRAB_PALM_CONTACT_CAPTURE cleared=", giant._grab_cleared_obstacles, " captured=", player.is_executing())
	for body in objects:
		if is_instance_valid(body) and not body.is_queued_for_deletion(): body.queue_free()
	giant._cancel_execution("fixture_reset")
	await frames()

func palm_clearance_chain() -> void:
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	giant._begin_grab()
	# Real colliders in swept order: a removable panel, intact equipment, an
	# ordinary wall and a protected panel. An offset Item is untouched collateral.
	var panel := RVStructurePanel.new()
	var equipment := Item.new()
	var wall := StaticBody3D.new()
	var behind := RVStructurePanel.new()
	var collateral := Item.new()
	var objects: Array[Node3D] = [panel, equipment, wall, behind, collateral]
	for index in objects.size():
		var body := objects[index]
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.15, .3, .15)
		collision.shape = shape
		body.add_child(collision)
		if body is RigidBody3D: body.freeze = true
		world.add_child(body)
		body.global_position = Vector3(40, 3, float(index + 1))
	collateral.global_position = Vector3(42, 3, 2)
	await frames()
	var start := Vector3(40, 3, 0)
	var end := Vector3(40, 3, 5)
	check(giant._grab_sweep(start, end, .24).get("collider") == panel, "Palm chain starts with an actual first-panel physical hit")
	var hit := giant._clear_grab_palm_path(start, end, .24)
	check(panel.is_destroyed and panel.current_health == 0.0 and not equipment.is_destroyed and equipment.current_health == equipment.max_health,
		"One real palm sweep removes its contacted panel and preserves the next equipment")
	check(panel.collision_layer == 0 and equipment.collision_layer != 0 and giant._grab_sweep(start, end, .24).get("collider") == equipment,
		"Destroyed panel stops blocking while intact equipment remains first contact")
	check(hit.get("collider") == equipment and giant.phase == SlenderSpeaker.Phase.GRAB,
		"Palm chain stops at intact equipment without beginning another grab")
	check(giant._grab_cleared_obstacles.size() == 1 and not behind.is_destroyed and not collateral.is_destroyed,
		"Palm removes only its contacted panel, preserving objects behind equipment and nearby untouched Item")
	equipment.global_position.x += 10.0
	await frames()
	check(giant._clear_grab_palm_path(start, end, .24).get("collider") == wall and not equipment.is_destroyed,
		"Moving intact equipment aside exposes the next actual solid wall")
	var floor_hit := giant._clear_grab_palm_path(Vector3(40, 1, 0), Vector3(40, -1, 0), .24)
	check(not floor_hit.is_empty() and floor_hit.get("collider") is StaticBody3D and giant._grab_cleared_obstacles.size() == 1,
		"Actual world-boundary ground remains a physical blocker for the palm")
	# The actual player capsule is also a first contact: removal must not
	# continue past the prospective capture and damage equipment behind them.
	var contact: Vector3 = player.execution_contact_position()
	collateral.global_position = contact - Vector3(0, 0, 1)
	await frames()
	var player_hit := giant._clear_grab_palm_path(contact + Vector3(0, 0, 1), contact - Vector3(0, 0, 2), .24)
	check(player_hit.get("collider") == player and not collateral.is_destroyed and giant._grab_cleared_obstacles.size() == 1,
		"Actual player contact ends palm removal before equipment behind the survivor")
	print("GRAB_PALM_CHAIN cleared=", giant._grab_cleared_obstacles, " wall=", hit.get("collider"))
	for body in objects:
		if is_instance_valid(body) and not body.is_queued_for_deletion(): body.queue_free()
	giant._cancel_execution("fixture_reset")
	await frames()

func finger_brush(side: String) -> void:
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	giant._begin_grab()
	giant.phase_elapsed = .8
	giant._pose_grab_reach()
	var other := "L" if side == "R" else "R"
	var palm := giant._bone_position("hand." + side)
	var outward := (palm - giant._bone_position("hand." + other)).slide(Vector3.UP).normalized()
	var chest_offset: Vector3 = player.execution_contact_position() - player.global_position
	var blocker: RigidBody3D = Item.new() if side == "R" else RVStructurePanel.new()
	blocker.freeze = true
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * .025
	collision.shape = shape
	blocker.add_child(collision)
	world.add_child(blocker)
	blocker.global_position = Vector3.ONE * 1000
	var blocked_bone := ""
	for distance in [.12, .22, .30, .38]:
		player.global_position = palm + outward * distance - chest_offset
		await frames()
		if giant._grab_sweep(palm, palm, .13).get("collider") != player or giant._hand_currently_touches_player(other): continue
		var bones := giant._hand_contact_bones(side)
		for index in range(bones.size() - 1, 0, -1):
			var point := giant._bone_position(bones[index])
			var away: Vector3 = (point - player.execution_contact_position()).normalized()
			for offset in [Vector3.ZERO, away * .08, Vector3.UP * .08, Vector3.DOWN * .08]:
				blocker.global_position = point + offset
				await frames()
				var palm_center := giant._grab_palm_position(side)
				var palm_clear := giant.sweep_hand(palm_center, palm_center, .24, [player.get_rid()]).is_empty()
				if palm_clear and giant._grab_sweep(palm, palm, .13).get("collider") == player and giant._grab_sweep(point, point, .13).get("collider") == blocker and not giant._hand_currently_touches_player(other):
					blocked_bone = bones[index]
					break
			if not blocked_bone.is_empty(): break
		if not blocked_bone.is_empty(): break
	check(not blocked_bone.is_empty(), side + " destructible obstruction isolates one real finger outside both palm sweeps")
	if not blocked_bone.is_empty():
		for hand in ["R", "L"]:
			for bone in giant._hand_contact_bones(hand): giant._previous_hands[bone] = giant._bone_position(bone)
			giant._previous_palms[hand] = giant._grab_palm_position(hand)
			giant._remember_grab_hand(hand)
		giant._advance_grab()
		check(player.is_executing() and giant._grab_hands_touched.has(side) and capture_path_clear(), side + " clear real palm probe captures despite its separate blocked finger")
		check(not blocker.get("is_destroyed") and blocker.get("current_health") == blocker.get("max_health") and blocker.collision_layer != 0,
			side + " fingers-only brush neither destroys the equipment/panel nor disables its collider")
		check(giant._grab_cleared_obstacles.is_empty(), side + " no object outside the actual palm volume is destroyed")
		print("GRAB_FINGER_BRUSH side=", side, " bone=", blocked_bone, " captured=", player.is_executing(), " blockers=", giant._grab_blocking_hits)
	blocker.queue_free()
	giant._cancel_execution("fixture_reset")
	await frames()

func solid_wall() -> void:
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, 30, .3)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.position = Vector3(0, 10, -1.2)
	await frames()
	giant._begin_grab()
	for tick in 60:
		giant.phase_elapsed = float(tick + 1) / 60.0
		giant._advance_grab()
		check(not player.is_executing(), "Persistent solid wall blocks every retry of the real hand sweeps")
		for side in ["R", "L"]:
			check(giant._grab_palm_position(side).z >= -1.0501, "Persistent wall keeps the actual palm on its approach side")
	check(giant._grab_blocked and giant.phase == SlenderSpeaker.Phase.RECOVER, "Persistent wall produces an ordinary uncaptured miss")
	check(giant._grab_cleared_obstacles.is_empty() and wall.collision_layer != 0, "Ordinary world geometry remains solid and is never destroyed by grab")
	print("GRAB_PERSISTENT_WALL captured=", player.is_executing(), " blockers=", giant._grab_blocking_hits)
	wall.queue_free()
	giant._cancel_execution("fixture_reset")
	await frames()

func late_evade() -> void:
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	giant._begin_grab()
	# Sustained 4m/s CharacterBody movement leaves the bounded reach area.
	# The real physics server sees each move before the next hand sweep.
	var initial := player.global_position
	for tick in 60:
		player.velocity = Vector3(4, 0, 0)
		player.move_and_slide()
		await frames(1)
		giant.phase_elapsed = float(tick + 1) / 60.0
		giant._advance_grab()
	check(player.global_position.distance_to(initial) > 3.0, "Evading fixture continuously moves its real collision body at 4m/s")
	check(not player.is_executing() and giant.phase == SlenderSpeaker.Phase.RECOVER, "A real survivor outside the committed reach still evades without forced capture")
	print("GRAB_EVADE captured=", player.is_executing(), " phase=", giant.phase)
	giant._cancel_execution("fixture_reset")

func rear_stance_matrix() -> void:
	vehicle = load("res://rv/starter_rv.tscn").instantiate()
	vehicle.position.y = 1.226
	world.add_child(vehicle)
	chassis = vehicle.get_node("Chassis")
	chassis.freeze = true
	await frames()
	var roof: RVStructurePanel = chassis.get_node("StructureSlots").panel("roof_2")
	roof.take_damage(roof.current_health)
	await frames(90)
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100, 0, -100), Vector3(-100, 0, 100), Vector3(100, 0, 100), Vector3(100, 0, -100)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	giant.set_giant_navigation_map(map)
	await frames()
	NavigationServer3D.map_force_update(map)
	var captures := 0
	for side in [-1.0, 1.0]:
		for offset in [-.5, -.2, 0.0, .2, .5]:
			reset_player(chassis.to_global(Vector3(0, .55, 4.7)))
			await frames()
			settle_pose()
			giant._parked_attack.reset()
			giant.target_vehicle = chassis
			giant.global_position = Vector3(side * 3.24, 0, 4.7)
			giant.rotation.y = side * PI / 2
			giant._sample("idle_play", 0.0)
			check(giant.can_see_player(player), "Rear matrix planner receives a physically visible production survivor")
			var plan: Dictionary = giant._parked_attack.update(giant, chassis, .6, player)
			check(not plan.is_empty() and plan.get("occupant") == player and plan.get("roof") == null, "Rear matrix uses a genuinely visible production survivor and an open roof planner stance")
			if plan.is_empty() or plan.get("occupant") != player or plan.get("roof") != null: continue
			giant.global_position = plan.standoff_point
			var direction := (Vector3(plan.facing_point) - giant.global_position).slide(Vector3.UP).normalized()
			giant.rotation.y = atan2(-direction.x, -direction.z)
			giant._sample("idle_play", 0.0)
			# Longitudinal motion within the committed .75m area changes only
			# the real survivor, retaining the planner's legal body stance/yaw.
			player.global_position.z += offset
			await frames()
			check(giant.can_see_player(player), "Rear matrix offset remains actually visible before the grab")
			giant._begin_grab()
			for tick in 60:
				giant.phase_elapsed = float(tick + 1) / 60.0
				giant._advance_grab()
				if giant.phase != SlenderSpeaker.Phase.GRAB: break
			var captured: bool = player.is_executing()
			if captured: captures += 1
			print("GRAB_REAR_MATRIX side=", side, " offset=", offset, " captured=", captured, " blockers=", giant._grab_blocking_hits)
			check(captured, "Rear planner stance captures visible stationary offset " + str(side) + "/" + str(offset) + " through actual hand contact")
			giant._cancel_execution("fixture_reset")
	print("GRAB_REAR_MATRIX_TOTAL captures=", captures, "/10")
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	world.add_child(floor_body)
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	await frames()
	await smash_equipment_damage()
	await palm_contacts_in_same_grab()
	await palm_clearance_chain()
	await finger_brush("R")
	await finger_brush("L")
	await solid_wall()
	await late_evade()
	await rear_stance_matrix()
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: equipment smash applies 60 HP once per swing and stops services once at death; palm panel removal and intact equipment blocking; clear independent finger capture; solid wall/continuous movement evade; ten physical RV planner stance offsets capture")
	quit(0 if failures.is_empty() else 1)

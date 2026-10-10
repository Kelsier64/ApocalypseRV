extends SceneTree
var failures: Array[String] = []
var world: Node3D

func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message); push_error("FAIL: " + message)
func step(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func finish_physical_input(recycler: Item, corpse: CorpseProp) -> void:
	for frame in 300:
		if not is_instance_valid(corpse): break
		recycler.step_work(1.0 / 60.0)
		await step(1)
	await step(2)
	if is_instance_valid(corpse):
		var remaining := {}
		for key: String in corpse.bodies:
			var bone: PhysicalBone3D = corpse.bodies[key]
			remaining[key] = {"local": recycler.to_local(bone.global_position), "mask": bone.collision_mask}
		print("CORPSE_FEED_TIMEOUT kind=", corpse.kind, " power=", recycler.get_connected_rv().current_power, " bones=", remaining)

func held_bone(corpse: CorpseProp, key: String) -> Transform3D:
	var data := corpse.capture_item_state().corpse as Dictionary
	var sk := corpse.skeleton
	var bone := sk.find_bone(key)
	var pose: Transform3D = data.poses[bone]
	var parent := sk.get_bone_parent(bone)
	while parent >= 0:
		pose = data.poses[parent] * pose
		parent = sk.get_bone_parent(parent)
	return corpse.global_transform * data.visual_transform * pose

func palm_position(sk: Skeleton3D, side: String) -> Vector3:
	var hand := sk.find_bone("hand_" + side)
	var rest := sk.get_bone_global_rest(hand)
	var middle := sk.get_bone_global_rest(sk.find_bone("middle_01_" + side)).origin
	var index := sk.get_bone_global_rest(sk.find_bone("index_01_" + side)).origin
	var pinky := sk.get_bone_global_rest(sk.find_bone("pinky_01_" + side)).origin
	var palm := (middle - rest.origin).normalized().cross((index - pinky).normalized()).normalized() * (1.0 if side == "L" else -1.0)
	var center := rest.origin.lerp(middle, .72) + palm * .014
	return sk.global_transform * sk.get_bone_global_pose(hand) * (rest.affine_inverse() * center)

func check_limb_feed(recycler: Item, kind: String, restore_power := false) -> void:
	var rv := recycler.get_connected_rv()
	rv.current_power = 20.0
	var saved_power: float = rv.current_power
	if restore_power: rv.current_power = 0
	var corpse: CorpseProp = load("res://props/corpse.tscn").instantiate()
	corpse.kind = kind
	corpse.position = Vector3(60, 4, 0)
	corpse.rotation.z = PI * .5
	WorldEntities.get_container(world).add_child(corpse)
	corpse._initialize()
	# Feed an extremity first, with the pelvis pickup sphere outside the opening.
	var extremity: PhysicalBone3D = corpse.bodies["head" if kind == "raker" else "foot_L"]
	var shift: Vector3 = recycler.to_global(Vector3(0, .85, 0)) - extremity.global_position
	for body: PhysicalBone3D in corpse.bodies.values(): body.global_position += shift
	corpse.global_position += shift
	var pelvis_local := recycler.to_local(corpse.bodies.pelvis.global_position)
	check(absf(pelvis_local.x) > .8, kind + " limb-feed fixture keeps the pickup proxy outside the hopper")
	corpse.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(3, 3)}
	var material_before: int = rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
	await step(24)
	if restore_power:
		check(not is_instance_valid(corpse.processing_owner), "Unpowered scrapper leaves the corpse unclaimed")
		check(recycler.get_node("HopperArea").get_overlapping_bodies().has(extremity), "Limb remains inside the hopper while power is unavailable")
		rv.current_power = saved_power
		recycler.step_work(0)
		await step(2)
		check(corpse.processing and not corpse.physical_feed and not corpse.simulator.is_simulating_physics(), "A zero-duration retry reserves the corpse without restarting paid physical feed")
	check(corpse.processing_owner == recycler and corpse.processing, kind + " extremity-first contact accepts the entire corpse")
	check(recycler.props_being_crushed.size() == 1, kind + " simultaneous limb contacts enqueue only one corpse")
	await finish_physical_input(recycler, corpse)
	check(not is_instance_valid(corpse) and rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == material_before + 3, kind + " limb-fed corpse produces one yield")
	if is_instance_valid(corpse):
		recycler._on_service_stopped()
		corpse.queue_free()
	await step(2)

func check_normal_player_throw(recycler: Item) -> void:
	var rv := recycler.get_connected_rv()
	rv.current_power = 40.0
	var carrier: CharacterBody3D = load("res://player/player.tscn").instantiate()
	carrier.position = Vector3(-8, 0, 0)
	world.add_child(carrier)
	carrier.take_damage(1000)
	await step(180)
	var loose: CorpseProp
	for child in WorldEntities.get_container(world).get_children():
		if child is CorpseProp and child.kind == "player": loose = child
	check(loose != null and not carrier.is_player_dead, "Normal throw fixture obtains the actual player recovery corpse")
	if loose == null:
		carrier.queue_free()
		return
	var identity := loose.persistent_id
	var original := loose.capture_item_state()
	loose.interact(carrier)
	await step(45)
	check(carrier.held_item_node is CorpseProp and carrier.inventory.active_item().state.id == identity, "Normal throw carries the original player corpse")
	carrier.set_physics_process(false)
	# Aim the normal 3m/s G throw. Keep the actual held anatomy and drop velocity.
	carrier.global_position = recycler.to_global(Vector3(0, .45, 1.37))
	carrier.global_rotation = recycler.global_rotation
	carrier.velocity = Vector3.ZERO
	await step(60)
	carrier.drop_item()
	await step(2)
	for child in WorldEntities.get_container(world).get_children():
		if child is CorpseProp and child.persistent_id == identity: loose = child
	check(loose != null and carrier.inventory.items.is_empty(), "G throw transfers one untouched physical corpse out of inventory")
	var before: Dictionary = rv.get_all_items().duplicate(true)
	var admitted := false
	var partial_save := false
	var minimum_bones := 14
	var maximum_distance := 0.0
	for frame in 600:
		recycler.step_work(1.0 / 60.0)
		await step(1)
		if not is_instance_valid(loose): break
		if loose.processing_owner != recycler: continue
		admitted = true
		check(loose.persistent_id == identity and recycler.props_being_crushed.size() == 1, "Normal thrown corpse retains exactly one original processing owner")
		if not partial_save and loose.physical_feed:
			partial_save = true
			var saved := recycler.capture_service_state()
			check(ItemState.valid_service(recycler.scene_file_path, saved) and WorldActorSnapshot.capture(loose).is_empty(), "Normally thrown in-flight corpse retains one valid persistence owner")
			var timer_before: float = recycler.props_being_crushed[0].timer
			var power_before: float = rv.current_power
			rv.current_power = 0
			recycler.step_work(.25)
			check(recycler.props_being_crushed[0].timer == timer_before and rv.get_all_items() == before, "Unpowered normal corpse ingestion preserves progress and grants no yield")
			rv.current_power = power_before
		minimum_bones = mini(minimum_bones, loose.bodies.size())
		var retired_count := 0
		for retired: PhysicalBone3D in loose.visual.find_children("*", "PhysicalBone3D", true, false):
			if not loose.fed_bones.has(String(retired.bone_name)): continue
			retired_count += 1
			check(not retired.is_simulating_physics() and retired.collision_layer == 0 and retired.collision_mask == 0 and retired.joint_type == PhysicalBone3D.JOINT_TYPE_NONE, "Swallowed registered bones retain no simulation, collisions or active joint")
		check(retired_count == loose.fed_bones.size(), "Every swallowed bone remains retained for safe retirement until the entire rig is removed")
		for bone: PhysicalBone3D in loose.bodies.values():
			var local := recycler.to_local(bone.global_position)
			maximum_distance = maxf(maximum_distance, local.length())
			check(local.is_finite() and local.length() < 5.0, "Normal thrown corpse joints remain finite and near the hopper throughout ingestion")
			if bone.collision_mask != 0 or not loose.physical_feed: continue
			for collider: CollisionShape3D in bone.find_children("*", "CollisionShape3D", true, false):
				var box := collider.shape.get_debug_mesh().get_aabb()
				for corner in 8:
					var point := recycler.to_local(collider.to_global(box.get_endpoint(corner)))
					check(absf(point.x) <= recycler.FEED.HALF_OPENING + .02 and absf(point.z) <= recycler.FEED.HALF_OPENING + .02, "A normally thrown collisionless bone cannot cross the hopper frame")
	check(admitted and partial_save, "An untouched normal player G throw is automatically captured and physically fed")
	check(minimum_bones < 14, "Normal throw consumes actual anatomical segments")
	check(not is_instance_valid(loose) and recycler.props_being_crushed.is_empty(), "Normal full player corpse completes instead of jamming or exploding its joints")
	for material: String in original.scrap_yields:
		var range_: Vector2 = original.scrap_yields[material]
		var earned: int = rv.get_item_count(material) - int(before.get(material, 0))
		check(earned >= int(range_.x) and earned <= int(range_.y), "Normal thrown player corpse grants its original " + material + " payload once")
	var after: Dictionary = rv.get_all_items().duplicate(true)
	recycler.step_work(1.0)
	check(rv.get_all_items() == after, "Completed normal throw cannot grant duplicate material")
	print("CORPSE_NORMAL_THROW max_distance=", maximum_distance, " minimum_bones=", minimum_bones)
	if is_instance_valid(loose):
		recycler.enabled = false
		recycler._on_service_stopped()
		loose.queue_free()
		await step(3)
		recycler.enabled = true
	carrier.queue_free()
	await step(3)

func run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	world.add_child(floor_body)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(3, 0, 0)
	world.add_child(player)
	var monster: Raker = load("res://enemies/raker.tscn").instantiate()
	monster.position = Vector3(0, -.25, 0)
	monster.loot_drops = {}
	monster.detection_range = 0
	world.add_child(monster)
	await step(3)
	monster.take_damage(1000)
	await step(8)
	var corpse: CorpseProp = monster.corpse_prop
	check(is_instance_valid(corpse) and corpse.bodies.size() == 15, "Death transfers all monster joints to one persistent prop")
	check(corpse.simulator == monster.ragdoll.simulator, "Death retains existing physical bones and momentum")
	await step(120)
	var state := corpse.capture_item_state()
	check(VehicleSnapshot.valid_prop_state(corpse.scene_file_path, state), "Corpse state validates")
	var bad := state.duplicate(true)
	bad.corpse.poses[0].origin.x = NAN
	check(not VehicleSnapshot.valid_prop_state(corpse.scene_file_path, bad), "Nonfinite corpse pose rejected")
	bad = state.duplicate(true)
	bad.corpse.poses.pop_back()
	check(not VehicleSnapshot.valid_prop_state(corpse.scene_file_path, bad), "Wrong rig topology rejected")
	var before := corpse.global_position
	var query := PhysicsRayQueryParameters3D.create(before + Vector3.UP * 2, before, 3, [player.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider") == corpse, "Production interaction mask sees the corpse pickup proxy")
	var snap := WorldActorSnapshot.capture(corpse)
	check(WorldActorSnapshot.validation_error(snap, "corpse").is_empty(), "Loose corpse snapshot validates")
	# Source AI expires independently; transferred visual and joints survive.
	monster.death_remaining = .01
	await step(3)
	check(not is_instance_valid(monster) and is_instance_valid(corpse) and corpse.simulator.is_simulating_physics(), "Corpse survives original actor timeout")
	corpse.interact(player)
	await step(5)
	check(player.inventory.items.size() == 1 and player.inventory.active_item().is_large, "Corpse pickup occupies the large-item slot")
	check(not player.inventory.select_slot(1), "Carried corpse cannot be stowed via hotbar")
	var held: CorpseProp = player.held_item_node
	check(held.held and held.simulator.is_simulating_physics() and held.collision_layer == 0, "Held torso and limbs retain ragdoll physics")
	await step(30)
	var torso_center: Vector3 = player.to_local((held.bodies.pelvis.global_position + held.bodies.spine_03.global_position) * .5)
	print("CORPSE_SUPPORT center=", torso_center)
	check(absf(torso_center.x) < .06 and torso_center.y > 1.4, "Raised torso is centered in front of the player")
	for frame in 45:
		player.position.x += .05
		await step(1)
	var stop_target: Vector3 = (held.global_transform * held.held_pelvis_rest).origin
	var stop_overshoot := 0.0
	for frame in 90:
		await step(1)
		stop_overshoot = maxf(stop_overshoot, held.bodies.pelvis.global_position.x - stop_target.x)
	print("CORPSE_STOP overshoot=", stop_overshoot)
	check(stop_overshoot < .06, "Abrupt stop does not produce a large forward rebound")
	var initial_relative: Vector3 = held.to_local(held_bone(held, "forearm_L").origin)
	var max_gap := 0.0
	var max_length_error := 0.0
	var max_swing := 0.0
	var palm_error := 0.0
	for frame in 120:
		player.position.x += .1 if frame < 60 else -.1
		player.rotation.y += .06 if frame > 20 else 0.0
		player.camera.rotation.x = sin(frame * .12) * .7
		await step(1)
		var target := held.global_transform * held.held_pelvis_rest
		max_gap = maxf(max_gap, held.bodies.pelvis.global_position.distance_to(target.origin))
		var data: Dictionary = held.capture_item_state().corpse
		for bone in held.skeleton.get_bone_count():
			check(data.poses[bone].is_finite(), "Held pose stays finite")
		for link: Dictionary in held.builder.links:
			var child_anchor: Vector3 = (link.child.global_transform * link.child.joint_offset).origin
			var parent_anchor: Vector3 = (link.parent.global_transform * link.parent_frame).origin
			max_length_error = maxf(max_length_error, child_anchor.distance_to(parent_anchor))
		max_swing = maxf(max_swing, initial_relative.distance_to(held.to_local(held_bone(held, "forearm_L").origin)))
		for side in ["L", "R"]:
			var grip: Marker3D = held.get_node("GripLeft" if side == "L" else "GripRight")
			palm_error = maxf(palm_error, palm_position(player.get_node("Visuals").skeleton, side).distance_to(grip.global_position))
	print("CORPSE_HELD anchor_error=", max_gap, " joint_gap=", max_length_error, " swing=", max_swing, " palm_error=", palm_error)
	check(max_swing > .025 and max_gap < .3 and max_length_error < .04, "Rapid motion retains physical swing with bounded grip lag and joint stretch")
	check(palm_error < .05, "Both palms stay on the live hip and chest supports during movement")
	await step(150)
	var settled_position: Vector3 = held.bodies.pelvis.global_position
	await step(15)
	var settled_speed: float = held.bodies.pelvis.global_position.distance_to(settled_position) / .25
	print("CORPSE_SETTLED pelvis_speed=", settled_speed)
	check(settled_speed < .1, "Physical torso settles after movement stops")
	player.camera.rotation.x = 0
	var release_position: Vector3 = held_bone(held, "pelvis").origin
	player.drop_item()
	await step(5)
	var dropped: CorpseProp
	for child in WorldEntities.get_container(world).get_children():
		if child is CorpseProp: dropped = child
	check(dropped != null and player.inventory.items.is_empty(), "Drop leaves one loose corpse")
	check(dropped.bodies["pelvis"].global_position.distance_to(release_position) < .8, "Drop continues from the visible hand-held physical pose")
	check(dropped.global_position.distance_to(before) > 2, "Dropped pose follows new location instead of old saved world coordinates")
	check(dropped.capture_item_state().id == state.id, "Pickup/drop retains corpse identity")
	# Repositioned load restores local pose in the destination frame.
	snap = WorldActorSnapshot.capture(dropped)
	dropped.queue_free()
	await step(2)
	snap.transform.origin += Vector3(8, 2, 0)
	var restored: CorpseProp = WorldActorSnapshot.restore(snap, WorldEntities.get_container(world))
	await step(3)
	check(restored.global_position.distance_to(snap.transform.origin) < .5, "World restore retains intended placement")
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(20, 0, 0)
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.current_power = 20
	var recycler: Item = rv.get_node("Scrapper")
	await step(2)
	recycler.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0,0,8)), rv, rv)
	await step(2)
	recycler.enabled = false
	var feed_shift := recycler.global_position + Vector3.UP - restored.global_position
	for bone: PhysicalBone3D in restored.bodies.values(): bone.global_position += feed_shift
	restored.global_position += feed_shift
	var lowest := INF
	for bone: PhysicalBone3D in restored.bodies.values():
		for collider: CollisionShape3D in bone.find_children("*", "CollisionShape3D", true, false):
			var box := collider.shape.get_debug_mesh().get_aabb()
			for corner in 8:
				lowest = minf(lowest, recycler.to_local(collider.to_global(box.get_endpoint(corner))).y)
	var above_rim := recycler.global_basis * Vector3.UP * maxf(0.0,.9-lowest)
	for bone: PhysicalBone3D in restored.bodies.values():
		bone.global_position += above_rim
		bone.linear_velocity = Vector3.ZERO
		bone.angular_velocity = Vector3.ZERO
	restored.global_position += above_rim
	recycler.enabled = true
	recycler.recycle_prop(restored)
	await step(2)
	check(restored.processing and not restored.simulator.is_simulating_physics(), "Recycler stops every physical bone")
	var processing_state := restored.capture_item_state()
	restored.restore_item_state(processing_state)
	await step(3)
	check(restored.processing and not restored.simulator.is_simulating_physics(), "Restoring an existing recycler input keeps every bone stopped")
	var device_snapshot := VehicleSnapshot.device_state(recycler)
	check(VehicleSnapshot.valid_device(device_snapshot), "Recycler snapshot validates a corpse input")
	var restored_recycler: Item = load("res://equipment/scrapper.tscn").instantiate()
	world.add_child(restored_recycler)
	restored_recycler.position = Vector3(40, 1, 0)
	VehicleSnapshot.restore_device(restored_recycler, device_snapshot, rv)
	await step(3)
	var restored_input: CorpseProp = restored_recycler.props_being_crushed[0].prop
	check(restored_input.processing and not restored_input.simulator.is_simulating_physics(), "Saved recycler input restores all physical bones stopped")
	check(restored_input.capture_item_state().id == processing_state.id, "Saved recycler input preserves corpse identity")
	restored_recycler._on_service_stopped()
	restored_input.queue_free()
	restored_recycler.queue_free()
	await step(3)
	restored.interact(player)
	check(player.inventory.items.is_empty(), "Processing corpse rejects pickup")
	recycler.enabled = false
	recycler._on_service_stopped()
	await step(3)
	check(not restored.processing and restored.simulator.is_simulating_physics() and restored.collision_layer == 2, "Cancelled recycling restores articulated loose corpse")
	restored.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(3, 3)}
	recycler.enabled = true
	check(restored.initialized and not restored.processing, "Callback-order fixture starts with the actual initialized loose corpse")
	recycler.recycle_prop(restored)
	# Service work may run in this frame before the deferred claim callback.
	# Deliberately do not yield between claiming this real corpse and feeding it.
	recycler.step_work(1.0 / 60.0)
	await step(2)
	check(restored.processing and restored.physical_feed and restored.simulator.is_simulating_physics(), "Deferred claim after immediate paid work cannot stop active corpse physics")
	var material_before := rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
	await finish_physical_input(recycler, restored)
	check(not is_instance_valid(restored) and rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == material_before + 3, "Completed recycling grants one fixed yield and removes all corpse physics")
	if is_instance_valid(restored):
		recycler._on_service_stopped()
		restored.queue_free()
		await step(2)
	# Real Area3D contact must discover layer-2 proxy without a direct recycle call.
	var hopper_corpse: CorpseProp = load("res://props/corpse.tscn").instantiate()
	hopper_corpse.restore_item_state(state)
	WorldEntities.get_container(world).add_child(hopper_corpse)
	hopper_corpse.global_position = recycler.global_position + Vector3.UP * .7
	await step(12)
	check(hopper_corpse.processing_owner == recycler and hopper_corpse.processing, "Hopper body_entered accepts the corpse automatically")
	recycler.enabled = false
	recycler._on_service_stopped()
	await step(3)
	hopper_corpse.queue_free()
	await step(2)
	recycler.enabled = true
	recycler.step_work(0)
	await check_limb_feed(recycler, "raker")
	await check_limb_feed(recycler, "player")
	await check_limb_feed(recycler, "player", true)
	for repetition in 3:
		await check_normal_player_throw(recycler)
	# Player recovery leaves a separate corpse, preserving absent limbs.
	player.global_position = Vector3(-8, 0, 0)
	player.body_state.sever(&"left_arm")
	player.get_node("Visuals").apply_body_state()
	player.take_damage(1000)
	await step(180)
	check(not player.is_player_dead and player.body_state.has_part(&"left_arm"), "Player respawns with restored body")
	var player_corpse: CorpseProp
	for child in WorldEntities.get_container(world).get_children():
		if child is CorpseProp and child.kind == "player": player_corpse = child
	check(player_corpse != null and not player_corpse.body_state.has_part(&"left_arm") and player_corpse.bodies.size() == 12, "Player corpse preserves missing limb and proper physical bone count")
	check(VehicleSnapshot.valid_prop_state(player_corpse.scene_file_path, player_corpse.capture_item_state()), "Player corpse saves with player topology")
	player_corpse.interact(player)
	await step(4)
	check(player.held_item_node is CorpseProp and player.held_item_node.kind == "player", "Player corpse uses same pickup and held-ragdoll flow")
	var transfer := player.global_transform
	transfer.origin += Vector3(50, 0, 0)
	player.complete_world_transition(transfer)
	await step(8)
	check(held_bone(player.held_item_node, "pelvis").origin.distance_to(player.global_position) < 3, "Transition rebuilds held pose at the new grip")
	world.queue_free()
	await step(2)
	if failures.is_empty(): print("PASS: persistent monster/player corpses, articulated carrying, dropping, restore and recycling")
	quit(0 if failures.is_empty() else 1)

extends "res://tests/test_training_completion.gd"
## One original v11 world and RV: wheel forces carry every bay and the exit.
## Player positions/camera and interaction calls are controlled test inputs.
## Player locomotion pauses during those scripted parked-work inputs and resumes
## for seated travel; capsule teleports release native contacts first.
## The RV is never frozen, repositioned, or assigned velocities; production
## gates, placement validation, ownership and service evidence remain active.
const BAY_CENTERS := [-362.0, -302.0, -262.0, -218.0, -174.0, -134.0, -94.0, -54.0, -10.0]
var crossed_gates: Array[int] = []
var vehicle_instance := 0
var world_instance := 0
var journey_distance := 0.0
var last_position := Vector3.ZERO
var minimum_door_clearance := INF
var maximum_lane_offset := 0.0

func _bind_fixture() -> void:
	run_owner = world.get_node("StartRun")
	tutorial = run_owner.get_node("Tutorial")
	workshop = tutorial.workshop
	vehicle = tutorial.designated_rv()
	player = world.get_node("Player")
	vehicle.allow_test_controls = true

func _run() -> void:
	root.size = Vector2i(1280, 720)
	checkpoint = root.get_node("Checkpoint")
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = 11
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not check(await world.wait_for_play() and await WAIT.generator_idle(self, generator), "Original v11 journey world becomes playable"):
		await finish(); return
	tutorial = world.get_node("StartRun/Tutorial")
	if not check(await WAIT.until(self, func(): return tutorial.initialized() and not tutorial.entry_snapshot.is_empty(), 60000, true), "Fresh journey has its independent first-stage entry"):
		await finish(); return
	_bind_fixture()
	vehicle_instance = vehicle.get_instance_id()
	world_instance = world.get_instance_id()
	last_position = vehicle.global_position
	print("TRAINING_JOURNEY_INPUTS: real wheel pedals/steering; controlled player positions, camera aim and production interaction/work calls; no vehicle transforms or progress writes")
	if not await driving_lesson(): await finish(); return
	if not await stage_ready(2): await finish(); return
	if not await battery_lesson(): await finish(); return
	if not await console_lesson(): await finish(); return
	if not await placement_lesson(): await finish(); return
	if not await recycling_lesson(): await finish(); return
	if not await manufacturing_lesson(): await finish(); return
	if not await maintenance_lesson(): await finish(); return
	if not await refueling_lesson(): await finish(); return
	if not await departure_lesson(): await finish(); return
	check(world.get_instance_id() == world_instance and vehicle.get_instance_id() == vehicle_instance, "All nine lessons retain the original production world and RV")
	check(crossed_gates == [1, 2, 3, 4, 5, 6, 7, 8], "The original RV physically crosses all eight real inner doorways in order")
	check(journey_distance > 440.0, "Wheel-powered journey covers induction, reversal, eight bays and full exit")
	print("TRAINING_JOURNEY_METRICS: distance=", journey_distance, " forward_peak=", forward_peak,
		" reverse_peak=", reverse_peak, " maximum_lane_offset=", maximum_lane_offset,
		" minimum_door_clearance=", minimum_door_clearance, " gates=", crossed_gates)
	await finish()

func driving_lesson() -> bool:
	var terminal: TrainingTerminal = tutorial.designated_terminal()
	if not check(terminal != null and terminal.can_operate(), "Original mounted terminal is usable"): return false
	player.global_position = terminal.global_position + vehicle.global_basis.x
	terminal.interact_hold(player)
	if not check(await WAIT.until(self, func(): return tutorial.flags.viewed, 5000), "Actual Conditions presentation records the first lesson"): return false
	terminal._close_ui()
	var flashlight: Item = workshop.by_id(tutorial.flashlight_id)
	if not check(flashlight != null, "Original flashlight exists"): return false
	player.global_position = flashlight.global_position + Vector3.RIGHT
	flashlight.interact(player)
	await frames()
	if not check(tutorial.flags.flashlight and select_item(tutorial.flashlight_id), "Real flashlight pickup transfers its identity"): return false
	if not await board(): return false
	if not check(await drive_to_local_z(-337.0, 1, 2.0), "Original wheel forces cross both ordered lane markers"): return false
	if not check(tutorial.flags.marker_index == 2, "Both induction markers are sampled by production physics"): return false
	if not check(await drive_to_local_z(-362.0, -1, 1.6), "Original wheel forces reverse into the marked bay"): return false
	if not check(await stop_and_park(true), "Real engine-off handbraked parking completes induction"): return false
	if not await leave_seat(): return false
	return check(tutorial.flags.viewed and tutorial.flags.flashlight and tutorial.flags.reversed and tutorial.flags.parked, "First lesson evidence comes from its actual transactions and physics")

func board() -> bool:
	var seat: Item = vehicle.get_node("DriverSeat")
	player.global_position = seat.global_position + vehicle.global_basis.z
	seat.interact_hold(player)
	player.set_physics_process(true)
	if tutorial.stage == 5: print_physical_state("after mounted-machine lesson")
	return check(player.seated_in == seat and vehicle.is_player_driving, "Production driver seat owns each physical travel leg")

func leave_seat() -> bool:
	var seat: Item = vehicle.get_node("DriverSeat")
	# Parked lessons use controlled actor poses. Keep normal locomotion from
	# overriding the capsule handoff or following a stale platform after a jump.
	# Boarding resumes the real player physics for every wheel-driven leg.
	player.set_physics_process(false)
	seat.exit_seat()
	vehicle.control_override.clear()
	await physics_seconds(0.1)
	return check(player.seated_in == null and not vehicle.is_player_driving, "Normal seat exit releases driving before parked work")

func stand_beside_rv() -> void:
	var local: Vector3 = run_owner.shelter.to_local(vehicle.global_position)
	# An actual floor position outside the RV and its carried-item volume. The
	# frozen transaction fixture's front-cabin pose intersects live hardware.
	# Controlled relocation also releases the previous floor's transform cache.
	await relocate_player(run_owner.shelter.to_global(Vector3(local.x + 4.5, 0.06, local.z - 2.5)))
	await physics_seconds(0.1)

func relocate_player(position: Vector3) -> void:
	# Scripted relocation is not kinematic travel. Release native contacts before
	# moving the capsule, or Jolt transfers that jump to the touching live RV.
	player.set_physics_process(false)
	player.body_collision_shape.disabled = true
	await physics_frame
	player.rv_support.clear()
	player.released_carrier_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.global_position = position
	await physics_frame
	player.body_collision_shape.disabled = false

func pickup(key: String) -> bool:
	var item: Item = workshop.item(key)
	if not check(item != null, "Designated " + key + " exists before pickup"): return false
	var identity: String = item.persistent_id
	var local: Vector3 = vehicle.to_local(item.global_position)
	if absf(local.x) < 3.0 and absf(local.z) < 7.0: await stand_beside_rv()
	else:
		await relocate_player(item.global_position + vehicle.global_basis.x * 1.2)
	var message: String = item.pickup(player)
	await frames()
	return check(select_item(identity), "Actual " + key + " pickup transfers original identity: " + message)

func mount(key: String, local: Vector3) -> bool:
	await stand_beside_rv()
	print_physical_state("before " + key + " preview")
	if not check(player.enter_equipment_placement(), "Inventory " + key + " opens its actual placement preview"): return false
	if key == "scrapper": local.z = 5.0
	for adjustment in [Vector3.ZERO, Vector3(-0.15, 0, 0), Vector3(0, 0, 0.3), Vector3(-0.15, 0, 0.3)]:
		var target: Vector3 = local + adjustment
		await physics_frame
		player.camera.global_position = vehicle.to_global(target + Vector3(0, 1.4, -0.8))
		player.camera.look_at(vehicle.to_global(target), vehicle.global_basis.y)
		player.placement.update_ghost(player)
		if player.placement.can_place_equipment and RVConnection.resolve(player.placement.target_support) == vehicle: break
	if not check(player.placement.can_place_equipment and RVConnection.resolve(player.placement.target_support) == vehicle, "Real RV deck ray validates " + key + " placement: " + player.placement.message):
		player.cancel_equipment_placement()
		return false
	if not check(player.placement.commit(player), "Validated " + key + " preview commits through inventory ownership"): return false
	await physics_frame
	await frames()
	print_physical_state("after " + key + " commit")
	var installed: Item = workshop.item(key)
	return check(installed != null and installed.can_operate() and installed.get_connected_rv() == vehicle, "Committed " + key + " retains designated RV service")

func stage_ready(expected: int) -> bool:
	if not check(await WAIT.until(self, func(): return tutorial.stage == expected, 10000, true), "Real transactions advance to stage %d" % expected): return false
	var gate: ShelterGarageGate = run_owner.shelter.get_node("Gates").get_child(expected - 2)
	if not check(await WAIT.until(self, func(): return gate.is_open() and gate.stable(), 10000, true), "Completed lesson opens real gate %d before travel" % (expected - 1)): return false
	if not await board(): return false
	if not check(await drive_to_local_z(BAY_CENTERS[expected - 1], 1, 5.0) and await stop_and_park(), "Wheel forces drive and park in bay %d" % expected): return false
	if not await leave_seat(): return false
	# Stage seven creates its exercise only after the entire physical RV is parked
	# and the player leaves the seat. Earlier stage entries may predate travel.
	if not check(await WAIT.until(self, func(): return not tutorial.entry_snapshot.is_empty() and run_owner.save_block_reason().is_empty(), 15000, true), "Bay %d retains a stable genuine stage entry" % expected): return false
	if expected == 7 and not check(tutorial.service.configured and tutorial._fully_inside(vehicle, TutorialService.PARKING), "Entire wheel-driven RV parks within the actual maintenance bounds"): return false
	var saved: Dictionary = checkpoint.capture_world(world)
	if not check(not saved.is_empty() and checkpoint.validation_error(saved).is_empty(), "Bay %d produces a valid current and retry checkpoint" % expected): return false
	print("TRAINING_JOURNEY_BAY: stage=", expected, " local=", run_owner.shelter.to_local(vehicle.global_position), " entry_stage=", tutorial.entry_snapshot.start_state.tutorial.stage)
	if "--journey-review" in OS.get_cmdline_user_args(): await physics_seconds(3.0)
	return true

func drive_to_local_z(target: float, gear: int, speed_limit: float) -> bool:
	if not vehicle.set_gear(gear) or not vehicle.set_engine_running(true): return false
	vehicle.set_handbrake(false)
	var direction := 1.0 if gear > 0 else -1.0
	var deadline := Time.get_ticks_msec() + 120000
	var previous_z: float = run_owner.shelter.to_local(vehicle.global_position).z
	var last_progress_z := previous_z
	var last_progress_time := Time.get_ticks_msec()
	var printed_stall := false
	while Time.get_ticks_msec() < deadline:
		var local: Vector3 = run_owner.shelter.to_local(vehicle.global_position)
		journey_distance += vehicle.global_position.distance_to(last_position)
		last_position = vehicle.global_position
		maximum_lane_offset = maxf(maximum_lane_offset, absf(local.x))
		for index in 8:
			var gate: ShelterGarageGate = run_owner.shelter.get_node("Gates").get_child(index)
			var gate_z: float = run_owner.shelter.to_local(gate.global_position).z
			if previous_z < gate_z and local.z >= gate_z and index + 1 not in crossed_gates:
				if not check(gate.is_open() and gate.stable() and run_owner.bay_unlocked(index), "Physical crossing uses open unlocked gate %d" % (index + 1)): return false
				crossed_gates.append(index + 1)
				minimum_door_clearance = minf(minimum_door_clearance, 3.5 - absf(local.x))
		previous_z = local.z
		var remaining: float = (target - local.z) * direction
		var speed: float = planar_speed()
		if absf(local.z - last_progress_z) >= 0.5:
			last_progress_z = local.z
			last_progress_time = Time.get_ticks_msec()
			printed_stall = false
		elif Time.get_ticks_msec() - last_progress_time > 5000 and not printed_stall:
			print_physical_state("five seconds without wheel travel")
			printed_stall = true
		elif Time.get_ticks_msec() - last_progress_time > 20000:
			print_physical_state("blocked physical travel")
			vehicle.control_override = {"brake": 1.0}
			return false
		if gear > 0: forward_peak = maxf(forward_peak, speed)
		else: reverse_peak = maxf(reverse_peak, speed)
		if remaining <= 0.35:
			vehicle.control_override = {"brake": 1.0}
			if speed <= 0.1 and vehicle.angular_velocity.length() <= 0.04:
				return absf(local.z - target) < 1.5 and absf(local.x) < 1.5
		else:
			var forward: Vector3 = run_owner.shelter.global_basis.inverse() * -vehicle.global_basis.z
			var heading: float = atan2(forward.x, forward.z)
			var desired_heading: float = atan2(-local.x, 12.0)
			var steering: float = clampf(wrapf(desired_heading - heading, -PI, PI) * 2.0 * direction, -0.35, 0.35)
			var desired: float = minf(speed_limit, maxf(0.4, sqrt(maxf(0.0, remaining - 0.2) * 1.2)))
			if speed > desired + 0.08:
				vehicle.control_override = {"brake": clampf((speed - desired) * 0.7, 0.04, 1.0), "steering": steering}
			else:
				vehicle.control_override = {"throttle": clampf((desired - speed) * 0.8, 0.0, 0.65), "steering": steering}
		if not check(local.y >= -1.0 and absf(local.x) < 2.5 and vehicle.global_basis.y.y > 0.8 and not vehicle.freeze and vehicle.is_physics_processing(), "Live RV remains upright inside the door lane"):
			print("TRAINING_JOURNEY_DRIVE: target=", target, " local=", local, " velocity=", vehicle.linear_velocity, " controls=", vehicle.control_override)
			return false
		await physics_frame
	vehicle.control_override = {"brake": 1.0}
	print("TRAINING_JOURNEY_TIMEOUT: target=", target, " local=", run_owner.shelter.to_local(vehicle.global_position), " velocity=", vehicle.linear_velocity, " engine=", vehicle.energy.engine_running, " gear=", vehicle.gear)
	return false

func print_physical_state(label: String) -> void:
	print("TRAINING_JOURNEY_PHYSICS: ", label, " stage=", tutorial.stage,
		" local=", run_owner.shelter.to_local(vehicle.global_position), " basis=", vehicle.global_basis,
		" velocity=", vehicle.linear_velocity, " force=", vehicle.engine_force, " brake=", vehicle.brake,
		" blocked=", vehicle.drive_blocked(), " driver_locked=", vehicle.driver_controls_locked(),
		" throttle=", vehicle.throttle_input, " driver=", vehicle.is_player_driving,
		" seated=", player.seated_in, " player_local=", vehicle.to_local(player.global_position),
		" player_mask=", player.collision_mask, " player_shape_disabled=", player.body_collision_shape.disabled)
	for wheel: VehicleWheel3D in vehicle.installed_wheels:
		if wheel == null: continue
		var body: Node3D = wheel.get_contact_body()
		print("TRAINING_JOURNEY_WHEEL: ", wheel.name, " local=", vehicle.to_local(wheel.global_position),
			" contact=", wheel.is_in_contact(), " point_local=", vehicle.to_local(wheel.get_contact_point()),
			" body=", body.get_path() if is_instance_valid(body) else NodePath())
	for key in ["scrapper", "workbench"]:
		var item: Item = workshop.item(key)
		if item == null: continue
		print("TRAINING_JOURNEY_MOUNT: ", key, " local=", vehicle.to_local(item.global_position),
			" bounds=", item.get_placement_bounds(), " fixed=", item.is_fixed,
			" parent=", item.get_parent().get_path(), " support=", item.mount_support,
			" physics_local=", vehicle.global_transform.affine_inverse() * PhysicsServer3D.body_get_state(item.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM))

func recycling_lesson() -> bool:
	var recycler: Item = workshop.item("scrapper")
	if not await recycle_scrap("scrap_a") or not await recycle_scrap("scrap_b"): return false
	if not await pickup("barrel"): return false
	await stand_beside_rv()
	recycler.accept_held_item(player)
	recycler.step_work(recycler.crush_time)
	if not check(workshop.recycled_ids.size() == 3 and vehicle.get_item_count(ItemNames.UNREFINED_FUEL) >= 10, "Marked physical stock commits through real recycler work"): return false
	return await stage_ready(6)

func recycle_scrap(key: String) -> bool:
	if not await pickup(key): return false
	var identity: String = workshop.targets[key]
	var recycler: Item = workshop.item("scrapper")
	await stand_beside_rv()
	player.drop_item()
	await frames()
	var input: Item = workshop.by_id(identity)
	if not check(input != null and not select_item(identity), "Actual drop creates one physical " + key + " input"): return false
	# Feed-position automation is explicit; only the real machine's committed
	# material deposit can satisfy the controller's marked-stock ledger.
	input.global_position = recycler.to_global(Vector3(0, 1.5, 0))
	recycler.recycle_prop(input)
	recycler.step_work(recycler.crush_time)
	return check(identity in workshop.recycled_ids, "Real scrapper work commits " + key + " materials")

func manufacturing_lesson() -> bool:
	var bench: CraftingStation = workshop.item("workbench")
	var recipe := RecipeCatalog.find("gasoline")
	await stand_beside_rv()
	if not check(bench.request_craft("gasoline"), "Actual recipe accepts the recycled materials: " + bench.last_error): return false
	bench.step_work(recipe.duration)
	await physics_frame
	if not check(workshop.output_ids.size() == 1, "Workbench creates one actual manufactured gasoline output"): return false
	var identity: String = workshop.output_ids[0]
	var gasoline: Item = workshop.by_id(identity)
	if not check(gasoline != null, "Physical manufactured gasoline exists before pickup"): return false
	await stand_beside_rv()
	gasoline.interact(player)
	if not check(workshop.gasoline_id == identity and select_item(identity), "Actual manufactured gasoline pickup retains identity"): return false
	return await stage_ready(7)

func maintenance_lesson() -> bool:
	var service: TutorialService = tutorial.service
	var bay: Node = vehicle.engine_bay
	var hatch: Node = bay.get_node("Hatch")
	await stand_beside_rv()
	var hatch_message: String = hatch.interact(player)
	if not check(await WAIT.until(self, func(): return hatch.stable() and hatch.opened, 5000, true), "Real maintenance hatch opens: " + hatch_message):
		print_hatch_blockers(hatch)
		return false
	if not await take_service_item(service.kit_id): return false
	RepairOperation.new().step(player, bay, true, 3.0)
	if not check(service.flags.engine and service.engine_ready(), "Real repair-kit consumption repairs the original engine"): return false
	var socket: Node = vehicle.get_node("WheelSocket0")
	player.global_position = socket.global_position + vehicle.global_basis.x * 2.0
	socket.interact_hold(player)
	if not check(service.flags.removed and vehicle.installed_wheels[0] == null, "Real socket removal releases the original damaged wheel"): return false
	if not await take_service_item(service.spare_id): return false
	socket.interact_hold(player)
	if not check(service.flags.wheel and service.wheel_ready(), "Real spare insertion owns the designated replacement wheel"): return false
	var tablet: Item = workshop.item("tablet")
	player.global_position = tablet.global_position + vehicle.global_basis.x
	tablet.interact_hold(player)
	var construction: RVStructureConstruction = vehicle.get_node("StructureSlots").construction
	if not check(construction.begin(tablet, "left_0", "repair").is_empty(), "Real tablet begins original side-wall repair"): return false
	construction._physics_process(2.0)
	tablet._close_ui()
	if not check(service.flags.wall and service.wall_ready(), "Committed structure work repairs the wall with actual materials"): return false
	hatch.interact(player)
	if not check(await WAIT.until(self, func(): return hatch.stable() and not hatch.opened, 5000, true), "Actual maintenance hatch closes before further driving"): return false
	return await stage_ready(8)

func print_hatch_blockers(hatch: Node) -> void:
	var collider: CollisionShape3D = hatch.get_node("Collision")
	var query := PhysicsShapeQueryParameters3D.new()
	var shape: BoxShape3D = collider.shape.duplicate()
	shape.size += Vector3.ONE * 0.02
	query.shape = shape
	query.exclude = [hatch.get_rid(), hatch.bay().get_rid(), vehicle.get_rid()]
	query.collision_mask = 1
	var blockers: Array[String] = []
	for degree in range(106):
		var orientation := Basis(Vector3.RIGHT, deg_to_rad(degree))
		var pose := Transform3D(orientation, hatch.HINGE + orientation * (hatch.CLOSED - hatch.HINGE))
		query.transform = hatch.bay().global_transform * pose * collider.transform
		for hit in world.get_world_3d().direct_space_state.intersect_shape(query, 8):
			var path := str(hit.collider.get_path())
			if path not in blockers: blockers.append(path)
	print("TRAINING_JOURNEY_HATCH: blockers=", blockers, " progress=", hatch.progress,
		" requested=", hatch.requested_open, " message=", hatch.blocked_message,
		" player=", player.global_position, " vehicle=", vehicle.global_transform)

func refueling_lesson() -> bool:
	var service: TutorialService = tutorial.service
	var port: Item = vehicle.get_node("FuelPort")
	if not check(select_item(workshop.gasoline_id), "Manufactured gasoline survives all physical travel legs"): return false
	var before: float = vehicle.current_fuel
	player.global_position = port.global_position + vehicle.global_basis.x
	port.interact(player)
	if not check(service.flags.refueled and service.fuel_amount > 0 and vehicle.current_fuel > before and select_item(service.empty_can_id), "Actual fuel-port transfer consumes gasoline and returns an empty can"): return false
	return await stage_ready(9)

func departure_lesson() -> bool:
	var button: Node3D = run_owner.shelter.get_node("GarageButton")
	await relocate_player(button.global_position + Vector3.RIGHT)
	# Stage-entry saving accepts 0.25 m/s; departure requires 0.2 m/s. Let the
	# live suspension settle after seat exit before using the actual button.
	if not check(await WAIT.until(self, tutorial.can_departure, 5000, true), "Nine real lessons permit departure: " + tutorial.departure_block_reason()):
		print_physical_state("departure blocked")
		return false
	button.interact(player)
	if not check(tutorial.service.flags.departure and run_owner.phase == "opening" and world.get_node("WorldClock").running, "Actual departure button starts the world simulation"): return false
	if not check(await WAIT.until(self, func(): return run_owner.phase == "started" and run_owner.gate.is_open(), 10000, true), "Physical exit gate opens before the RV moves"): return false
	if not await board(): return false
	if not check(await drive_to_local_z(19.0, 1, 3.0), "Actual wheels carry the RV partly through the real exit doorway"): return false
	check(not run_owner.vehicle_clear(vehicle) and tutorial.status == "active", "Rear RV collision keeps training active during partial physical exit")
	if not check(await drive_to_local_z(42.0, 1, 3.0) and await stop_and_park(), "Actual wheels carry the entire RV through the exit"): return false
	if not check(run_owner.vehicle_clear(vehicle), "Every installed RV collision clears the exit threshold"): return false
	if not await leave_seat(): return false
	if not check(await WAIT.until(self, func(): return run_owner.phase == "sealed", 10000, true), "Whole RV and player departure physically seals the original exit"): return false
	var terminal: TrainingTerminal = tutorial.designated_terminal()
	check(tutorial.status == "completed" and tutorial.entry_snapshot.is_empty() and terminal.manual_unlocked and terminal.completion == "completed", "Physical sealing completes training and unlocks the original Manual")
	player.global_position = terminal.global_position + vehicle.global_basis.x
	terminal.interact_hold(player)
	check(terminal.ui_instance.visible and terminal.ui_instance.current_page == "manual", "Original completed terminal opens its actual Manual")
	terminal._close_ui()
	var gate: ShelterGarageGate = run_owner.gate
	var ray := PhysicsRayQueryParameters3D.create(gate.to_global(Vector3(-1.75, 1, -1)), gate.to_global(Vector3(-1.75, 1, 1)), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == gate.left, "Physically sealed exit leaf blocks return")
	var saved: Dictionary = checkpoint.capture_world(world)
	return check(not saved.is_empty() and checkpoint.validation_error(saved).is_empty(), "Continuous completed journey captures a valid persistent checkpoint")

func finish() -> void:
	if is_instance_valid(world):
		if is_instance_valid(vehicle):
			vehicle.control_override.clear()
			vehicle.set_handbrake(true)
			vehicle.set_engine_running(false)
		if is_instance_valid(player) and is_instance_valid(player.seated_in): player.seated_in.exit_seat()
		world.get_node("WorldGenerator").set_process(false)
		await WAIT.generator_idle(self, world.get_node("WorldGenerator"))
		await WAIT.navigation_bakes_finished(self, world)
		world.queue_free()
		for tick in 4:
			await physics_frame
			await process_frame
	if failures.is_empty(): print("PASS: original RV wheel-driven journey through all nine production lessons, eight physical inner doors, whole exit, sealed gate and Manual")
	quit(0 if failures.is_empty() else 1)

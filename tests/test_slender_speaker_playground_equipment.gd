extends SceneTree
## Actual free-play scene, live chassis suspension and autonomous AI callbacks.
const Wait := preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []
var removed_at := -1.0
var removed_phase := -1
var removed_by_damage := false
var entered_grab := false
var grab_equipment_removed := false
var equipment_hits: Array[Dictionary] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	var stage: Node3D = load("res://tests/slender_speaker_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	var ready := await Wait.until(self, func() -> bool: return stage.running, 60000, true)
	check(ready, "Production free play is ready")
	if not ready:
		await finish(stage)
		return
	var rv: Chassis = stage.rv
	var giant: SlenderSpeaker = stage.giant
	var player: CharacterBody3D = stage.player
	var equipment: Item = rv.get_node("Generator")
	var roof: RVStructurePanel = rv.get_node("StructureSlots").panel("roof_0")
	var untouched: RVStructurePanel = rv.get_node("StructureSlots").panel("roof_2")
	# A valid player-mounted roof item used to make every roof-removal strike
	# stop harmlessly forever. Do not prebreak panels or force combat phases.
	# Leave the front roof's solid approach surface visible, with the device
	# on the hand arc. Covering that surface makes the autonomous planner
	# choose another exposed roof; support loss would then drop an intact item.
	var pose := rv.global_transform
	pose.origin = rv.to_global(Vector3(-1.7, 3.03, -2.85))
	equipment.confirm_placement(pose, rv, roof)
	var initial_health := equipment.current_health
	check(initial_health > 60.0, "Mounted roof equipment has enough health to survive a 60 HP strike")
	equipment.availability_changed.connect(func() -> void:
		equipment_hits.append({"health": equipment.current_health, "time": stage.elapsed,
			"phase": giant.phase, "solid": equipment.collision_layer != 0,
			"operating": equipment.can_operate(), "destroyed": equipment.is_destroyed})
	)
	equipment.removing.connect(func() -> void:
		removed_at = stage.elapsed
		removed_phase = giant.phase
		removed_by_damage = equipment.is_destroyed and equipment.current_health == 0.0 and not equipment.support_lost
	)
	check(not rv.freeze and player.seated_in != null, "Live suspension and actual seated driver remain enabled")
	stage.set_giant_enabled(true)
	var captured_at := -1.0
	var start_frame := Engine.get_physics_frames()
	for tick in 2400:
		if Engine.get_physics_frames() - start_frame >= 2400: break
		await physics_frame
		await process_frame
		entered_grab = entered_grab or giant.phase == SlenderSpeaker.Phase.GRAB
		if player.is_executing():
			captured_at = stage.elapsed
			break
	check(removed_at > 0 and removed_phase == SlenderSpeaker.Phase.SMASH and removed_by_damage, "Roof equipment is destroyed by actual roof-removal hand contact before grabbing")
	check(equipment_hits.size() == ceili(initial_health / 60.0) and equipment_hits[0].health == initial_health - 60.0 and equipment_hits[-1].health == 0.0,
		"Autonomous roof strikes deal 60 HP each, preserving equipment after the first contact")
	for index in equipment_hits.size():
		check(equipment_hits[index].health == maxf(0.0, initial_health - float(index + 1) * 60.0),
			"Every autonomous equipment contact applies one 60 HP hit")
	if not equipment_hits.is_empty():
		var first := equipment_hits[0]
		check(first.phase == SlenderSpeaker.Phase.SMASH and first.solid and first.operating and not first.destroyed and first.time < removed_at,
			"Actual first nonlethal equipment strike keeps its physical blocker and mounted service before a later smash destroys it")
	check(not is_instance_valid(equipment) or equipment.is_destroyed, "Contacted equipment uses real destruction lifecycle")
	check(roof.is_destroyed and not untouched.is_destroyed, "Repeated roof strikes open the contacted panel without destroying the rear roof")
	check(entered_grab and captured_at > removed_at and player.is_executing(), "Autonomous AI continues from equipment removal through roof break to real driver capture")
	if player.is_executing():
		var lift_frame := Engine.get_physics_frames()
		while Engine.get_physics_frames() - lift_frame < 90:
			await physics_frame
			await process_frame
		check(player.is_executing() and player.global_position.y > 9.0, "Captured driver lifts clear under real engine callbacks")
	print("PLAYGROUND_EQUIPMENT hits=", equipment_hits, " removed=", removed_at, " phase=", removed_phase, " capture=", captured_at, " lifted=", player.global_position.y)
	await grab_equipment_blocks(stage)
	await finish(stage)

func grab_equipment_blocks(stage: Node3D) -> void:
	# Restart the production encounter. The obstacle enters only after the
	# autonomous roof smash has finished and an actual grab has begun.
	await stage.select_mode(0)
	var giant: SlenderSpeaker = stage.giant
	var player: CharacterBody3D = stage.player
	var rv: Chassis = stage.rv
	stage.set_giant_enabled(true)
	var started := Engine.get_physics_frames()
	while Engine.get_physics_frames() - started < 2400 and giant.phase != SlenderSpeaker.Phase.GRAB:
		await physics_frame
		await process_frame
	check(giant.phase == SlenderSpeaker.Phase.GRAB and not player.is_executing(), "Equipment blocker fixture observes an autonomous grab before contact")
	if giant.phase != SlenderSpeaker.Phase.GRAB or player.is_executing(): return
	var equipment := Item.new()
	equipment.item_name = "Grab path equipment"
	equipment.freeze = true
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.3, 30, 20)
	collision.shape = shape
	equipment.add_child(collision)
	stage.actors.add_child(equipment)
	var pose := rv.global_transform
	pose.origin = rv.to_global(Vector3(-2.5, 8, -4))
	equipment.global_transform = pose
	equipment.removing.connect(func() -> void: grab_equipment_removed = true)
	var equipment_path := String(equipment.get_path())
	var blocked_ticks := 0
	var equipment_contact := false
	var missed := false
	var phantom_capture := false
	started = Engine.get_physics_frames()
	while Engine.get_physics_frames() - started < 120:
		await physics_frame
		await process_frame
		phantom_capture = phantom_capture or player.is_executing()
		if giant._grab_blocked: blocked_ticks += 1
		for hit in giant._grab_blocking_hits:
			if hit.get("node") == equipment_path: equipment_contact = true
		if giant.phase == SlenderSpeaker.Phase.RECOVER:
			missed = true
			break
	check(missed and blocked_ticks > 0 and equipment_contact and not phantom_capture, "Intact equipment blocks the actual grab path without capturing the driver behind it")
	check(is_instance_valid(equipment) and not equipment.is_destroyed and equipment.current_health == equipment.max_health
		and equipment.collision_layer != 0 and not grab_equipment_removed, "Grab contact keeps equipment health, collider and removal lifecycle intact")
	if not is_instance_valid(equipment): return
	equipment.global_position += Vector3.RIGHT * 100.0
	started = Engine.get_physics_frames()
	var captured := false
	var lifted := false
	var capture_height := 0.0
	while Engine.get_physics_frames() - started < 1800:
		await physics_frame
		await process_frame
		if player.is_executing() and not captured:
			captured = true
			capture_height = player.global_position.y
		if player.is_executing() and giant.phase == SlenderSpeaker.Phase.HOLD:
			lifted = player.global_position.y > capture_height + 5.0
			break
	check(captured and lifted, "Moving intact equipment aside permits autonomous real contact and a complete driver lift")
	check(not equipment.is_destroyed and equipment.current_health == equipment.max_health and not grab_equipment_removed,
		"Successful retry preserves the same intact equipment instance")
	print("PLAYGROUND_GRAB_EQUIPMENT blocked_ticks=", blocked_ticks, " equipment_contact=", equipment_contact, " missed=", missed, " phantom_capture=", phantom_capture,
		" captured=", captured, " lifted=", lifted, " removed=", grab_equipment_removed)
	equipment.queue_free()

func finish(stage: Node) -> void:
	stage.queue_free()
	await process_frame
	await process_frame
	for message in failures: push_error("FAIL: " + message)
	if failures.is_empty(): print("PASS: live playground equipment survives the first 60 HP smash and is removed by a later strike; grab retains blocking equipment and captures/lifts after it moves aside")
	quit(0 if failures.is_empty() else 1)

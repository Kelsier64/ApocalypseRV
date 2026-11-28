extends SceneTree

const SCENE := "res://tests/playgrounds/promo/promo_world.tscn"
const Perception := preload("res://core/apparition_perception.gd")
const RAIL := preload("res://tests/playgrounds/promo/promo_rail.gd")
const TIMELINE := preload("res://tests/playgrounds/promo/promo_timeline.gd")
const BROADCAST := preload("res://tests/playgrounds/promo/promo_broadcast.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _wait_for_take(id: String, previous: Node = null) -> Node:
	var deadline := Time.get_ticks_msec() + 65000
	while Time.get_ticks_msec() < deadline:
		var world := current_scene
		if world != null and (not is_instance_valid(previous) or world != previous) and world.shot_id == id and world.take_ready:
			return world
		await process_frame
	_check(false, id + " became ready")
	return null

func _run() -> void:
	_check_rail_math()
	_check_timelines()
	change_scene_to_file(SCENE)
	var world := await _wait_for_take("R2")
	if world != null:
		var generator := world.get_node("WorldGenerator")
		var first_unloaded_band := int(generator.restore_bands.max()) + 1
		var horizon_start := -first_unloaded_band * float(generator.profile.chunk_length)
		_check(is_instance_valid(generator.horizon) and is_equal_approx(generator.horizon.mesh.get_aabb().end.z, horizon_start),
			"On a cold launch the distant terrain starts past the whole preloaded window")
		var initial: Dictionary = world.rv.inventory.duplicate(true)
		var initial_position: Vector3 = world.actor.global_position
		var initial_hour: float = world.get_node("WorldClock").hour_of_day()
		_check(world.actor.is_on_floor() and world.rv.handbrake, "R2 begins standing inside the parked workshop RV")
		_check(world.get_node("StartRun").phase == "sealed" and not world.get_node("StartRun").tutorial_enabled(), "R2 bypasses tutorial")
		_check(is_equal_approx(initial_hour, world.shot.hour), "R2 has its configured start time")
		_check(world.trigger_take(), "R2 opens the production tablet at Crafting")
		var tablet: Node = world.rv.get_node("TabletScreen")
		await process_frame
		await process_frame
		_check(tablet.ui_instance.current_page == "crafting" and tablet.ui_instance.selected_recipe == world.shot.recipes[0], "The Crafting page opens on the intended recipe")
		world.director.set_clean(true)
		_check(HUDVisibility.hud_hidden and tablet.ui_instance.visible, "Clean view preserves the deliberately opened tablet")
		var outputs := {}
		world.station.output_committed.connect(func(_rv_id, item_id, recipe_id): outputs[recipe_id] = item_id)
		tablet.ui_instance._craft()
		_check(world.station.jobs.size() == 1 and world.rv.inventory != initial, "The real tablet reserves materials and queues a print")
		tablet._close_ui()
		var recipe := RecipeCatalog.find(world.shot.recipes[0])
		world.station.step_work(recipe.duration)
		var container := WorldEntities.get_container(world)
		_check(world.station.jobs.is_empty() and _output(container, outputs.get(recipe.recipe_id, "")) != null, "Production station printed a real item")
		for next_id in world.shot.recipes.slice(1):
			var previous_item := _output(container, outputs.get(recipe.recipe_id, ""))
			if previous_item != null:
				previous_item.queue_free()
				await physics_frame
				await physics_frame
			recipe = RecipeCatalog.find(next_id)
			_check(world.station.request_craft(next_id), "Workshop can queue " + next_id)
			world.station.step_work(recipe.duration)
			_check(_output(container, outputs.get(next_id, "")) != null, "Workshop can print " + next_id + " (" + world.station.last_error + ")")
		await _check_director(world)
		world.reload_take("R2")
		world = await _wait_for_take("R2", world)
		if world != null:
			_check(world.rv.inventory == initial and world.station.jobs.is_empty(), "Restart restores spent materials and clears the queue")
			_check(_output(WorldEntities.get_container(world), outputs.get(recipe.recipe_id, "")) == null, "Restart removes the printed item")
			_check(world.actor.global_position.distance_to(initial_position) < 0.08 and is_equal_approx(world.get_node("WorldClock").hour_of_day(), initial_hour), "Restart restores placement and lighting")
			world.reload_take("B2")
			world = await _wait_for_take("B2", world)
			if world != null: await _check_bunker(world)
			if current_scene != null and failures.is_empty(): await _check_remaining_takes()
	unload_current_scene()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: promo stages, production actions, rails and resets")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_rail_math() -> void:
	var rail = RAIL.new()
	# Uneven spacing: progress must follow distance, not keyframe count.
	for x in [0.0, 2.0, 20.0]: rail.add(Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), 60.0)
	_check(absf(rail.sample(0.5).transform.origin.x - 10.0) < 0.3, "Rail progress follows arc length")
	var forward := true
	for step in 100: forward = forward and rail.sample((step + 1) / 100.0).transform.origin.x >= rail.sample(step / 100.0).transform.origin.x - 0.0001
	_check(forward, "Rail never doubles back between unevenly spaced keys")
	_check(rail.sample(0.0).transform.origin.is_equal_approx(Vector3.ZERO) and rail.sample(1.0).transform.origin.distance_to(Vector3(20, 0, 0)) < 0.01, "Rail starts and ends on its keys")
	var cruise: float = rail.sample(0.47).transform.origin.distance_to(rail.sample(0.45).transform.origin)
	var at_key: float = rail.sample(0.11).transform.origin.distance_to(rail.sample(0.09).transform.origin)
	_check(cruise > 0.0 and at_key > 0.0, "Rail keeps moving through an inner keyframe")
	var middle: float = rail.sample(0.51).transform.origin.distance_to(rail.sample(0.49).transform.origin)
	_check(absf(middle / cruise - 1.0) < 0.05, "Rail cruises at constant speed between the eased ends")
	var path := "res://.godot/promo-test/rail.json"
	_check(rail.save_file(path) == OK, "Rail saves")
	var loaded = RAIL.new()
	_check(loaded.load_file(path) and loaded.size() == 3 and loaded.authored() and loaded.sample(0.5).transform.origin.is_equal_approx(rail.sample(0.5).transform.origin), "Saved rail loads back identically")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check_timelines() -> void:
	for sample in [[], [{"at": 1.0, "do": "drive", "speed": 50}, {"at": 0.5, "do": "end"}],
		[{"at": 0.0, "do": "fly"}], [{"at": 0.0, "do": "line"}], [{"do": "end"}],
		[{"at": 0.0, "do": "look", "target": "road", "seconds": 1.0}]]:
		_check(not TIMELINE.check(sample).is_empty(), "Timeline check rejects %s" % JSON.stringify(sample))
	var world_script: Script = load(SCENE.get_basename() + ".gd")
	var shots: Array = world_script.SHOTS
	for id in shots:
		var shot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(world_script.SHOT_PATH % id))
		for entry in [shot] + shot.get("variants", []):
			if entry.has("timeline"): _check(TIMELINE.check(entry.timeline).is_empty(), "%s timeline: %s" % [id, TIMELINE.check(entry.timeline)])
			for cue in entry.get("timeline", []):
				if cue.do == "line": _check(BROADCAST.narration().has(str(int(cue.id))), "%s plays an existing narration line" % id)
	var bank: WordBank = load("res://assets/audio/dispatch_voice/word_bank.tres")
	var lines := BROADCAST.narration()
	_check(not lines.is_empty(), "Trailer narration loads")
	for id in lines:
		_check(bank.missing(BROADCAST.tokens(BROADCAST.text(lines[id]))).is_empty(), "Narration line %s uses only word-bank words: %s" % [id, bank.missing(BROADCAST.tokens(BROADCAST.text(lines[id])))])

func _check_director(world: Node) -> void:
	var director: Node = world.director
	director.open_panel()
	_check(paused, "The director panel pauses the take")
	director.close_panel_and(func(): pass)
	_check(not paused, "Closing the panel resumes the take")
	_check(director.use_free_camera() and world.actor.is_gameplay_input_blocked(), "Free camera takes the keyboard from the player")
	_check(director.follow_preset("chase", world.rv) and not world.actor.is_gameplay_input_blocked(), "Follow camera leaves the player in control")
	var original: Basis = world.rv.global_basis
	world.rv.global_basis = original.rotated(original.z, deg_to_rad(60))
	for frame in 30: director.view._process(1.0 / 30.0)
	_check(absf(director.view.global_basis.x.y) < 0.05, "Follow camera ignores the roll of its target")
	world.rv.global_basis = original
	director.clear_rail()
	_check(director.use_free_camera(), "R2 returns to free camera")
	director.add_keyframe()
	director.view.global_position.x += 0.4
	director.add_keyframe()
	_check(director.rail.source == RAIL.Source.EDITED and director.play_rail(), "Rail plays from recorded keys")
	director.view._process(float(director.rail.duration) + 0.01)
	_check(director.view.global_position.is_equal_approx(director.rail.keys.back().position), "Rail reaches the last keyframe")
	director.use_player_camera()
	_check(not world.actor.is_gameplay_input_blocked() and director.view == null, "Player view restores control")

func _output(container: Node, id: String) -> Item:
	if id.is_empty(): return null
	for child in container.get_children():
		if child is Item and child.persistent_id == id: return child
	return null

func _check_bunker(world: Node) -> void:
	var manager: PoiInstanceManager = world.get_node("PoiInstances")
	_check(manager.state == PoiInstanceManager.State.INDOOR and world.actor.is_on_floor(), "B2 settles on the production bunker floor")
	_check(world.trigger_take(), "B2 triggers once the bunker is ready")
	if not is_instance_valid(world.apparition): return
	_check(not world.trigger_take(), "B2 cannot spawn a second apparition")
	world.actor._toggle_flashlight()
	var original: Camera3D = world.actor.camera
	_check(world.director.use_free_camera() and world.director.view.get_viewport() == manager.viewport, "Free camera renders in the bunker viewport")
	_check(Perception.player_camera(world.apparition, world.actor) == original, "Apparition keeps the player's view for perception while filming")
	var initial: Vector3 = world.apparition.global_position
	for frame in 90:
		await physics_frame
		if world.apparition.phase == BlackApparition.Phase.FRENZIED and world.apparition.global_position.distance_to(initial) > 0.1: break
	_check(world.apparition.phase == BlackApparition.Phase.FRENZIED and world.apparition.global_position.distance_to(initial) > 0.1,
		"Flashlight triggers a real chase during detached filming (phase %d at %.2f m, light %s)" % [world.apparition.phase, initial.distance_to(world.actor.global_position), world.actor._active_flashlight_state()])
	world.director.use_player_camera()
	_check(manager.viewport.get_camera_3d() == original, "Switching back restores the player camera")
	world.actor.invulnerable = true
	world.actor.kill()
	_check(not world.actor.is_player_dead, "Invulnerability protects against lethal contact")
	await manager.leave()
	_check(manager.state == PoiInstanceManager.State.OUTDOOR and world.actor.get_viewport() == root, "Leaving the bunker restores the outdoor viewport")
	_check(world.director.use_free_camera() and world.director.view.get_viewport() == root, "The free camera can return to the outdoor viewport")
	world.reload_take("B2")
	var restarted := await _wait_for_take("B2", world)
	if restarted != null:
		_check(not restarted.actor.invulnerable and restarted.apparition == null, "B2 restarts without the previous encounter or invulnerability")
		_check(restarted.trigger_take() and restarted.apparition.global_position.is_equal_approx(initial), "B2 triggers again at the same mark")

func _check_remaining_takes() -> void:
	var ids: Array = current_scene.SHOTS if "--all-takes" in OS.get_cmdline_user_args() else ["B5", "O3", "D2", "R3", "W2", "D6", "T1", "T2", "T3", "T4", "T5", "T6"]
	for id in ids:
		if id in ["B2", "R2"]: continue
		var previous := current_scene
		previous.reload_take(id)
		var world := await _wait_for_take(id, previous)
		if world == null: return
		var clock := world.get_node("WorldClock") as WorldClock
		var weather := Vector3(float(world.shot.weather[0]), float(world.shot.weather[1]), float(world.shot.weather[2]))
		_check(world.actor.is_on_floor() or is_instance_valid(world.actor.seated_in), id + " has a grounded or seated operator")
		_check(is_equal_approx(clock.hour_of_day(), world.shot.hour) and clock.weather.sample().is_equal_approx(weather), id + " starts with configured lighting and weather")
		_check(world.trigger_take(), id + " F3 performs the configured action")
		await _verify_action(world)
		print("PROMO TEST: ", id)

func _verify_action(world: Node) -> void:
	if world.shot.has("timeline"):
		await _verify_timeline(world)
		return
	match world.shot_id:
		"B1":
			var cache: BunkerCache = world.staged[0]
			world.actor.global_position = cache.global_position + Vector3.BACK * 1.2
			_check(cache.interact_hold(world.actor).begins_with("Collected"), "B1 cache is searchable")
		"B3", "B4", "O1":
			for frame in 180:
				await physics_frame
				if not is_instance_valid(world.subject): break
				if world.shot_id == "B3" and world.actor.is_grabbed(): break
				if world.subject is BarrelMan and world.subject.phase >= BarrelMan.Phase.CHASE: break
			_check(world.actor.is_grabbed() if world.shot_id == "B3" else not is_instance_valid(world.subject) or world.subject.phase >= BarrelMan.Phase.CHASE, world.shot_id + " performs a real approach to the player")
		"B5", "W1", "W2", "W3":
			_check(world.director.rail.size() >= 2 and is_instance_valid(world.director.view), world.shot_id + " plays an authored or generated rail")
			if world.shot_id == "W3":
				var clock := world.get_node("WorldClock") as WorldClock
				var start := clock.elapsed_seconds
				for frame in 60: await physics_frame
				_check(clock.elapsed_seconds - start > 3600.0, "W3 advances time faster than a normal take")
		"B6":
			_check(is_instance_valid(world.actor.held_item_node), "B6 carries the real upgraded engine")
		"O3":
			if not is_instance_valid(world.subject): return
			_check(world.director.use_free_camera() and Perception.player_camera(world.subject, world.actor) == world.actor.camera, "O3 keeps player perception during detached filming")
			var san: float = world.actor.survival.san
			for frame in 150:
				world._aim_at(world.subject.global_position + WhiteApparition.CHEST)
				await physics_frame
				if world.actor.survival.san < san: break
			_check(world.actor.survival.san < san, "O3 real white apparition confirms gaze and drains SAN")
		"O4", "O5":
			_check(world.subject is SlenderSpeaker and world.subject.giant_navigation_map.is_valid(), world.shot_id + " stages the giant on production navigation")
		"O2", "D1", "D2", "D3":
			_check(world.rv.energy.engine_running and not world.rv.handbrake, world.shot_id + " starts a driveable RV")
			if world.shot_id != "D3": await _verify_road_contact(world)
		"D4":
			_check(not world.rv.freeze and world.actor.get_active_item_name() == "Recovery Jack", "D4 releases the RV and supplies the recovery jack")
		"D5":
			var mark: Vector3 = world.rv.global_position
			for frame in 240:
				await physics_frame
				if world.rv.global_position.distance_to(mark) >= 1.0: break
			_check(world.rv.global_position.distance_to(mark) >= 1.0 and not world.rv.energy.engine_running, "D5 free RV rolls under gravity")
		"R1":
			var recycler: Node = world.stage.recycler
			var inventory: Dictionary = world.rv.inventory.duplicate(true)
			for frame in 360:
				await physics_frame
				if world.rv.inventory != inventory: break
			_check(world.rv.inventory != inventory, "R1 production hopper converts staged scrap into materials")
		"R3":
			var tablet: Node = world.rv.get_node("TabletScreen")
			await process_frame
			await process_frame
			var slots: RVStructureSlots = world.rv.get_node("StructureSlots")
			var roof := slots.panel("roof_0")
			var health := roof.current_health
			_check(tablet.ui_instance.current_page == "structure" and slots.panel("right_2").is_destroyed, "R3 opens Structure with staged damage")
			tablet.ui_instance._begin_structure("repair")
			var construction: RVStructureConstruction = slots.construction
			if construction.is_building(): construction._physics_process(float(construction.job.duration) + 0.01)
			_check(roof.current_health > health, "R3 production repair restores roof durability")
			tablet.ui_instance.select_slot("right_2")
			tablet.ui_instance._begin_structure("rebuild")
			if construction.is_building(): construction._physics_process(float(construction.job.duration) + 0.01)
			_check(not slots.panel("right_2").is_destroyed, "R3 production rebuild replaces the missing panel")
			await process_frame
			await process_frame
			tablet._close_ui()
			_check(world.actor.enter_equipment_placement(), "R3 starts the production equipment preview")
			await physics_frame
			world.actor.placement.update_ghost(world.actor)
			_check(world.actor.placement.commit(world.actor), "R3 mount mark accepts installation of the staged item box")

func _verify_timeline(world: Node) -> void:
	var stage = world.stage
	var speaker: DispatchSpeaker = stage.broadcast.speaker
	var first_line := -1.0
	for cue in world.shot.timeline:
		if cue.do == "line":
			first_line = float(cue.at)
			break
	_check(speaker.schedule.process_mode == Node.PROCESS_MODE_DISABLED, world.shot_id + " keeps in-game broadcasts off the speaker")
	if world.shot.has("chase_take"):
		await _verify_chase_take(world)
		return
	if first_line >= 0.0:
		var ticks := int((first_line + 1.0) * Engine.physics_ticks_per_second)
		var heard_ident := false
		for frame in ticks:
			await physics_frame
			if not speaker.speaker.playing: continue
			if stage.timeline.clock >= first_line and speaker.speaker.stream != stage.DISPATCH_IDENT: break
			if speaker.speaker.stream == stage.DISPATCH_IDENT: heard_ident = true
		_check(speaker.speaker.playing and speaker.speaker.stream is AudioStreamWAV, world.shot_id + " plays its narration through the RV's dispatch speaker")
		_check(stage.timeline.clock >= first_line and world.rv.linear_velocity.length() > 0.5, world.shot_id + " is moving when its narration starts")
		if world.shot_id == "T1":
			_check(heard_ident, "T1 plays the dispatch ident before line 1")
			_check(not stage._lid_rect.visible, "T1's eyes are open when line 1 starts")
			while stage.timeline.running:
				await physics_frame
			_check(stage._lids.get_shader_parameter("closure") == 1.0, "T1 closes its eyelids at the briefing cut")
	if world.shot.has("prone"):
		await _verify_execution(world)
		return
	if world.shot.get("live_controls", false):
		await _verify_scripted_drive(world)
		return
	if world.shot.has("wreck"):
		var chassis: Node = stage.wreck.get_node("Chassis")
		_check(stage.wreck.process_mode == Node.PROCESS_MODE_DISABLED and not chassis.is_in_group(Groups.RV),
			world.shot_id + " stages the wreck as scenery, outside the RV group")
	if world.shot.timeline.any(func(cue: Dictionary) -> bool: return cue.do == "giant_wake"): await _verify_chase(world)

func _verify_chase_take(world: Node) -> void:
	var stage = world.stage
	stage.unattended = true
	if world.shot.chase_take == "cabin":
		_check(world.actor.rv_support.rv == world.rv, "T6 begins supported by the crashed RV's floor")
		await _verify_execution(world)
		_check(float(stage._marked_phases.get("roof_open", INF)) < float(stage._marked_phases.get(SlenderSpeaker.Phase.GRAB, -INF)),
			"T6 physically opens the front roof before the grab")
		return
	var framed := 0
	while stage.timeline.running:
		await physics_frame
		if world.shot.chase_take != "exterior" or not is_instance_valid(stage.giant): continue
		var view: Camera3D = world.director.view
		if (view != null and view.is_position_in_frustum(world.rv.global_position)
				and view.is_position_in_frustum(stage._giant_point(0.0))
				and view.is_position_in_frustum(stage._giant_point(0.95))):
			framed += 1
	_check(stage.autoplay_error(world).is_empty(), world.shot_id + " completes the configured chase action: " + stage.autoplay_error(world))
	if world.shot.chase_take == "exterior":
		var camera: Camera3D = world.director.view
		_check(is_instance_valid(camera) and camera.follow_target == world.rv and camera.follow_companion == stage.giant,
			"T4 follows both the RV and the giant")
		if DisplayServer.get_name() != "headless":
			_check(framed >= Engine.physics_ticks_per_second, "T4 keeps the RV and the giant's whole height in frame for at least a second")
		return
	if stage.crash_state.is_empty(): return
	var cabin: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(world.SHOT_PATH % "T6"))
	var stop: Dictionary = stage.crash_state
	for key in ["s", "lateral", "height"]:
		_check(absf(float(stop[key]) - float(cabin.start[key])) < 0.2, "T6 reuses the collision's final " + key)
	for axis in 3:
		_check(absf(float(stop.rotation[axis]) - float(cabin.start.rotation[axis])) < 1.0, "T6 reuses the collision's final rotation")
	_check(stop.panels.keys().size() == cabin.cabin.panels.keys().size(), "T6 restores every damaged panel from the collision")
	for panel in stop.panels:
		_check(is_equal_approx(float(stop.panels[panel]), float(cabin.cabin.panels.get(panel, -1.0))), "T6 restores collision damage on " + panel)

## T2, unattended: the driver looks as they pass the wreck, then hears the giant before seeing it.
func _verify_chase(world: Node) -> void:
	var stage = world.stage
	var speaker: DispatchSpeaker = stage.broadcast.speaker
	var camera: Camera3D = world.actor.seated_in.seat_camera
	var clock := world.get_node("WorldClock") as WorldClock
	var forest := WorldEntities.get_container(world).get_node_or_null("PromoForest")
	var trunks := forest.get_node_or_null("ForestTrunks") as ForestTrunks if forest != null else null
	stage.unattended = true
	var wake := 0.0
	for cue in world.shot.timeline:
		if cue.do == "giant_wake": wake = float(cue.at)
	var road_yaw := camera.rotation.y
	var framed_wreck := false
	var furthest_wreck_yaw := 0.0
	var returned_to_road := false
	var hidden_at_handoff := false
	var still := false
	var trees_felled_before_wake := false
	while stage.timeline.running:
		await physics_frame
		var look: Dictionary = stage._look
		if look.get("subject") == stage.wreck and look.time >= look.seconds:
			var wreck_offset: Vector3 = world.rv.to_local(stage.wreck.global_position)
			framed_wreck = framed_wreck or (wreck_offset.z < 0.0 and camera.is_position_in_frustum(stage.wreck.global_position))
			furthest_wreck_yaw = maxf(furthest_wreck_yaw, absf(angle_difference(road_yaw, camera.rotation.y)))
		if framed_wreck and not is_instance_valid(stage.giant) and look.is_empty():
			returned_to_road = returned_to_road or is_zero_approx(angle_difference(road_yaw, camera.rotation.y))
		if not still and is_instance_valid(stage.giant):
			var giant_depth := -camera.to_local(stage.giant.global_position).z
			hidden_at_handoff = giant_depth > clock.environment.fog_depth_end and not speaker.speaker.playing and not speaker.noise.playing
		if stage.timeline.clock < wake - 0.2 and is_instance_valid(stage.giant):
			still = not stage.giant.is_physics_processing() and stage.giant.patrol_music.playing
		if stage.timeline.clock < wake and trunks != null:
			trees_felled_before_wake = not trunks.broken.is_empty()
	_check(framed_wreck, world.shot_id + " turns toward the wreck before passing it")
	_check(furthest_wreck_yaw < PI * 0.5 and returned_to_road,
		world.shot_id + " releases the wreck glance before looking behind and returns to the road")
	_check(hidden_at_handoff, world.shot_id + " hands off from dispatch to music while the giant is still behind the fog")
	_check(still, world.shot_id + " places a still giant whose loudspeaker plays before it wakes")
	_check(stage._marked_phases.has("chase") and float(stage._marked_phases.chase) - wake < 1.0,
		world.shot_id + " giant chases the RV on its own after waking (%s)" % stage._marked_phases)
	var debris := forest.get_node_or_null("TreeDebris") if forest != null else null
	var removed := false
	if trunks != null:
		for trunk: CollisionShape3D in trunks.broken:
			if not trunk.disabled: continue
			removed = true
			# The headless rendering server has no instance transforms to read back.
			if DisplayServer.get_name() != "headless":
				var entry: Dictionary = trunks.visuals[trunk.get_meta("tree_point")]
				var mesh_pose: Transform3D = entry.node.multimesh.get_instance_transform(entry.index)
				_check(mesh_pose.basis.get_scale().is_zero_approx(), world.shot_id + " hides each felled tree's standing mesh")
	_check(not trees_felled_before_wake and removed and debris != null and debris.get_child_count() > 0,
		world.shot_id + " the chase disables planted trunks and spawns debris")
	_check(not speaker.speaker.playing and not speaker.noise.playing, world.shot_id + " leaves the cab speaker silent after radio_off")

## Memory shots leave driving to the player live; the unattended script must still run.
func _verify_scripted_drive(world: Node) -> void:
	var stage = world.stage
	stage.unattended = true
	var target := 0.0
	for cue in world.shot.timeline:
		if cue.do == "drive": target = float(cue.get("lateral", target))
	for frame in int((stage.timeline.length() + 0.5) * Engine.physics_ticks_per_second):
		await physics_frame
		if not stage.timeline.running: break
	var road: Dictionary = world.field.road_query(world.rv.global_position.x, world.rv.global_position.z)
	var offset: float = (road.frame as Transform3D).basis.x.dot(world.rv.global_position - (road.frame as Transform3D).origin)
	_check(absf(offset - target) < 6.0, world.shot_id + " leaves the road for lateral %.0f m (at %.1f m)" % [target, offset])

## T3, unattended: the giant smashes the roof, grabs the prone survivor and executes them.
## The take stays in the survivor's eyes until the hand closes, then never returns to
## them, and the survivor stands upright in the giant's grip.
func _verify_execution(world: Node) -> void:
	var stage = world.stage
	stage.unattended = true
	_check(world.actor.is_crawling() and world.actor.body_state.has_part(&"left_leg") and world.actor.body_state.has_part(&"right_leg"),
		world.shot_id + " lies in the crawl posture with every limb")
	var contact_chest := -1.0
	var held_chest := -1.0
	var early_cut := ""
	var pov_during_execution := ""
	# Judge the view each frame is drawn with: sample after every node's own _process,
	# where the filming camera takes the picture back from a grab in the physics step.
	var sampler := Node.new()
	var sampler_script := GDScript.new()
	sampler_script.source_code = "extends Node\nsignal sampled\nfunc _process(_delta: float) -> void:\n\tsampled.emit()\n"
	sampler_script.reload()
	sampler.set_script(sampler_script)
	sampler.process_priority = 1 << 30
	root.add_child(sampler)
	while stage.timeline.running:
		await sampler.sampled
		if not is_instance_valid(stage.giant): continue
		var view: Camera3D = world.get_viewport().get_camera_3d()
		var phase: int = stage.giant.phase
		var chest: float = world.actor.to_local(world.actor.execution_contact_position()).y
		if world.actor.is_executing() and contact_chest < 0.0: contact_chest = chest
		if phase == SlenderSpeaker.Phase.HOLD and held_chest < 0.0: held_chest = chest
		if not world.actor.is_executing() and not world.actor.is_player_dead and view != world.actor.camera and early_cut.is_empty():
			early_cut = "%s in %s" % [view.get_path() if view else NodePath(), SlenderSpeaker.Phase.keys()[phase]]
		if phase in [SlenderSpeaker.Phase.LIFT, SlenderSpeaker.Phase.HOLD, SlenderSpeaker.Phase.CRUSH] and view == world.actor.camera and pov_during_execution.is_empty():
			pov_during_execution = SlenderSpeaker.Phase.keys()[phase]
		if stage._marked_phases.has("death"): break
	for name in [SlenderSpeaker.Phase.GRAB, SlenderSpeaker.Phase.HOLD, SlenderSpeaker.Phase.CRUSH, "death"]:
		_check(stage._marked_phases.has(name), world.shot_id + " reaches %s (marked %s)" % [name, stage._marked_phases])
	_check(early_cut.is_empty(), world.shot_id + " stays in the survivor's eyes until the hand closes (%s)" % early_cut)
	var upright: float = world.actor.upright_chest_local().y
	_check(contact_chest >= 0.0 and held_chest > contact_chest and absf(held_chest - upright) < absf(contact_chest - upright) * 0.25,
		world.shot_id + " stands the survivor upright in the grip (chest %.2f m at contact, %.2f m held, %.2f m upright)" % [contact_chest, held_chest, upright])
	_check(stage._cut_away and pov_during_execution.is_empty(), world.shot_id + " cuts to third person for the grab and execution (first person in %s)" % pov_during_execution)
	sampler.queue_free()

func _verify_road_contact(world: Node) -> void:
	world.stage.drive_replay = true
	for frame in 800:
		await physics_frame
		match world.shot_id:
			"O2":
				if not is_instance_valid(world.subject): return
			"D1":
				if world.staged.all(func(tree): return tree.broken): return
			"D2":
				if world.rv.wheel_health.any(func(health): return is_zero_approx(health)): return
	_check(false, world.shot_id + " reaches the staged collision with production RV physics")

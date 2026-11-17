extends SceneTree

const SCENE := "res://tests/playgrounds/promo/promo_world.tscn"
const Perception := preload("res://core/apparition_perception.gd")
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
	change_scene_to_file(SCENE)
	var world := await _wait_for_take("R2")
	if world != null:
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
		world.director.rail.clear()
		world.director.add_keyframe()
		_check(world.director.use_free_camera(), "R2 enters free camera")
		world.director.view.position.x += 0.2
		world.director.add_keyframe()
		_check(world.director.play_rail(), "Rail starts from the recorded view")
		world.director._process(world.director.SEGMENT_SECONDS)
		_check(world.director.view.global_transform.is_equal_approx(world.director.rail.back()), "Rail reaches the last keyframe")
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
	var ids: Array = current_scene.SHOTS if "--all-takes" in OS.get_cmdline_user_args() else ["B5", "O3", "D2", "R3", "W2"]
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
		_check(world.trigger_take(), id + " F10 performs the configured action")
		await _verify_action(world)
		print("PROMO TEST: ", id)

func _verify_action(world: Node) -> void:
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

extends SceneTree

var failures: Array[String] = []
var world := Node3D.new()
var player: CharacterBody3D
var rv: Chassis
var station: CraftingStation
var recipe := RecipeCatalog.find("printed_player")

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	root.add_child(world)
	current_scene = world
	world.set_meta("entity_domain", true)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	world.add_child(floor_body)
	var shell := preload("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	station = rv.get_node("CraftingStation")
	player = preload("res://player/player.tscn").instantiate()
	player.position = Vector3(12, 1, 0)
	world.add_child(player)
	await frames(5)
	rv.inventory.clear()
	var settings := root.get_node("GameSettings")
	var master := AudioServer.get_bus_index("Master")
	settings.set_setting(&"master_volume", 0.75, false)
	player.take_damage(player.current_player_health)
	check(player.is_player_dead and not player.recovery.shade.visible and not AudioServer.is_bus_mute(master), "An ordinary fatal hit starts with an open view and no hard mute")
	await frames(ceili(player.recovery.DEATH_FADE_SECONDS * Engine.physics_ticks_per_second * 0.5))
	var closure: float = player.recovery.shade.material.get_shader_parameter("closure")
	check(player.recovery.shade.visible and closure > 0.0 and closure < 1.0, "An ordinary death gradually closes the view")
	await frames(135)
	check(not player.is_player_dead and station.jobs.is_empty() and player.position.x > 8, "Missing materials allow recovery near the remains")
	check(not AudioServer.is_bus_mute(master), "Ordinary revival keeps audio available")
	await frames(95)
	rv.current_power = rv.max_power
	rv.deposit_materials(recipe.costs)
	player.sever_part(&"head")
	check(player.is_player_dead and player.recovery.shade.visible and player.recovery.shade.material.get_shader_parameter("closure") == 1.0, "Decapitation closes the view before the next frame")
	check(AudioServer.is_bus_mute(master), "Decapitation immediately mutes the Master bus")
	settings.set_setting(&"master_volume", 0.5, false)
	await frames(1)
	check(AudioServer.is_bus_mute(master), "Changing the volume during the blackout preserves the mute")
	await frames(75)
	check(player.recovery.awaiting_print() and station.jobs.size() == 1, "Death places and pays for one body order")
	check(not AudioServer.is_bus_mute(master) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(master)), 0.5), "Watching the print restores the configured volume after decapitation")
	rv.current_power = 0
	station.step_work(.5)
	await frames(3)
	check(player.recovery.stalled and player.recovery.status.text.contains("battery"), "Loss of power explains the stall")
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	root.push_input(interact, true)
	await frames(75)
	check(not player.is_player_dead and station.jobs.is_empty() and rv.has_materials(recipe.costs), "Cancelling refunds this order and revives at the corpse")
	await frames(95)
	await _interior_revival()
	settings.set_setting(&"master_volume", 0.0, false)
	player.sever_part(&"head")
	await frames(2)
	player.free()
	check(AudioServer.is_bus_mute(master), "Removing a dead player preserves a zero-volume preference")
	settings.set_setting(&"master_volume", 1.0, false)
	check(not AudioServer.is_bus_mute(master), "Removing a dead player releases its temporary mute")
	world.queue_free()
	await process_frame
	for message in failures: push_error(message)
	if failures.is_empty(): print("PASS: ordinary death and decapitation, funded, unavailable, stalled and underground body recovery")
	quit(0 if failures.is_empty() else 1)

func _interior_revival() -> void:
	# Use the production viewport transition, corpse snapshot and installed cabin.
	var manager := PoiInstanceManager.new()
	world.add_child(manager)
	var entrance := Node3D.new()
	var marker := Marker3D.new()
	marker.name = "ReturnPoint"
	entrance.add_child(marker)
	world.add_child(entrance)
	manager.interior_factory = func() -> PoiInterior:
		var room := PoiInterior.new()
		room.room_count = 2
		room.target_floors = 1
		room.populate_content = false
		return room
	await manager.enter(player, entrance, "recovery-test", 42)
	if manager.state != PoiInstanceManager.State.INDOOR:
		check(false, "Recovery fixture entered the bunker")
		return
	player.add_item("Scrap", false, "res://props/scrap.tscn")
	var inventory: Array = player.inventory.items.duplicate(true)
	rv.current_power = rv.max_power
	rv.deposit_materials(recipe.costs)
	var prior := station.queue_recipe(recipe.recipe_id)
	player.kill()
	await frames(135)
	check(player.is_player_dead and station.jobs.size() == 2 and player.recovery.job_id != prior, "Queued revival suppresses the old timer and preserves queue order")
	if not player.recovery.awaiting_print(): return
	check(root.get_camera_3d() == player.recovery.observer and not manager._display.visible, "An indoor death shows the exterior bed camera")
	station.step_work(recipe.duration)
	check(player.is_player_dead and station.jobs.size() == 1, "A previous body delivery cannot revive this death")
	await frames(2)
	station.step_work(recipe.duration)
	await frames(2)
	check(player.is_player_dead and player.recovery.stalled, "Occupied bed prevents handoff at full progress")
	_check_print_ceiling_clearance()
	for output in WorldEntities.get_container(station).get_children():
		if output is PrintedPlayerBody: output.free()
	await frames(2)
	station.step_work(.1)
	await frames(2)
	check(not player.is_player_dead and player.recovery.waking_in_printed_body and player.camera.current, "Completed body owns the waking first-person view")
	check(manager.state == PoiInstanceManager.State.OUTDOOR and player.get_parent() == world and player.global_position.distance_to(station.spawn_marker.global_position) < 1, "Bunker revival returns to the exterior bed")
	check(player.inventory.items == inventory and player.current_player_health == player.max_player_health, "The new body has full health and keeps inventory identity")
	var corpses := 0
	for actor in manager.saved_instances.get("recovery-test", {}).get("actors", []):
		if actor.scene == "res://props/corpse.tscn": corpses += 1
	check(corpses == 1 and station.jobs.is_empty(), "The interior snapshot retains exactly one corpse")
	check(player.is_gameplay_input_blocked(), "Opening eyes precedes control")
	await frames(100)
	check(not player.is_gameplay_input_blocked() and not player.recovery.visible, "Normal input and HUD return after waking")

func _check_print_ceiling_clearance() -> void:
	var roof: CollisionShape3D = rv.get_node("RoofMiddle/CollisionRear")
	var roof_box := roof.shape as BoxShape3D
	var to_cabin := rv.global_transform.affine_inverse()
	var roof_underside := (to_cabin * roof.global_transform).origin.y - roof_box.size.y * 0.5
	var highest_mesh := -INF
	for node in station.get_node("Details").find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree(): continue
		var cabin_bounds: AABB = to_cabin * mesh.global_transform * mesh.get_aabb()
		highest_mesh = maxf(highest_mesh, cabin_bounds.end.y)
	check(station.print_visual.progress == 1.0 and highest_mesh < roof_underside,
		"The fabricator fits below the cabin roof at the full Body print height")

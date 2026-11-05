extends RefCounted
## Small deterministic sample plus one real manager visit/revisit.

static func run(tree: SceneTree, arena: Node3D, manager: PoiInstanceManager, player: CharacterBody3D, check: Callable) -> void:
	var profile := InteriorProfiles.get_profile(&"megashelter")
	check.call(profile != null and profile.validate().is_empty(), "Megashelter profile is registered and validates its authored modules")
	check.call(InteriorProfiles.get_profile(&"bunker") != null and InteriorProfiles.get_profile(&"unknown") == null, "Interior registry keeps bunker and rejects unknown profiles")
	if profile == null: return
	_check_layouts(profile, check)
	await _visit(tree, arena, manager, player, check)

static func _check_layouts(profile: InteriorProfile, check: Callable) -> void:
	var areas := {}
	var signatures := {}
	for exterior_area: float in [800.0, 1600.0, 2600.0]:
		areas[exterior_area] = 0.0
		for seed_value in range(16):
			var layout := MegashelterInteriorLayout.generate(seed_value, exterior_area, profile)
			var label := "Megashelter interior %d/%.0f: " % [seed_value, exterior_area]
			check.call(not layout.is_empty() and InteriorLayout.validate(layout, profile).is_empty(), label + "connected socket graph, occupancy and module versions validate")
			if layout.is_empty(): continue
			check.call(layout == MegashelterInteriorLayout.generate(seed_value, exterior_area, profile), label + "seed and exterior area reproduce the manifest")
			check.call(layout.profile == "megashelter" and InteriorLayout.floor_count(layout) == 1 and layout.target_floors == 1, label + "profile has one ground floor")
			check.call(layout.rooms.size() >= 6 and layout.rooms.size() <= 8, label + "layout stays a compact six-to-eight-module visit")
			var entry_count := 0
			var hall_count := 0
			var functional_count := 0
			for index in layout.rooms.size():
				var definition := InteriorLayout.definition(layout, index, profile)
				var group := str(definition.selection_group)
				if definition.role == &"entry": entry_count += 1
				elif group == "hall": hall_count += 1
				elif group not in ["passage", "corridor", "connector"]: functional_count += 1
				var bounds: AABB = definition.describe().bounds
				areas[exterior_area] += bounds.size.x * bounds.size.z
			check.call(entry_count == 1 and hall_count >= 1 and functional_count >= 3 and functional_count <= 5, label + "entry and hall serve only three-to-five functional rooms")
			signatures[str(layout.rooms)] = true
	check.call(areas[800.0] < areas[2600.0], "Larger exteriors select larger interior modules without many extra rooms")
	check.call(signatures.size() >= 8, "Fixed megashelter sample produces varied room arrangements")

static func _visit(tree: SceneTree, arena: Node3D, manager: PoiInstanceManager, player: CharacterBody3D, check: Callable) -> void:
	player.inventory.items.clear()
	player.inventory.active_slot = 0
	player.refresh_inventory()
	manager.interior_factory = Callable()
	var plan := MegashelterPlan.generate(913)
	var site := {"id": "megashelter-persistence", "seed": 913, "definition_id": "modular_megashelter", "placement": "off_road", "building": Transform3D(Basis.IDENTITY, Vector3(250, 0, 0)), "exterior_plan": plan}
	var building := POISpawner.new().spawn_site(site, arena, false)
	check.call(building != null and building.get_meta("poi_interior_profile", &"") == &"megashelter", "Production POI spawner assigns the megashelter interior profile")
	if building == null: return
	await manager.enter(player, building, site.id, site.seed)
	check.call(manager.state == PoiInstanceManager.State.INDOOR and manager.interior != null, "Real megashelter enters through the manager: " + manager.last_error)
	if manager.interior == null: return
	var room := manager.interior
	var adaptation := room.get_node_or_null("DarkAdaptation") as NightVisionEffect
	var interior_environment := room.get_node_or_null("WorldEnvironment") as WorldEnvironment
	check.call(adaptation != null and NightVisionEffect.find_for(room.rooms[0]) == adaptation, "Production megashelter owns dark adaptation in its isolated World3D")
	check.call(room.get_node_or_null("WorldClock") == null, "Production megashelter has no outdoor day/night clock")
	check.call(adaptation != null and adaptation.profile == PoiInterior.DARK_ADAPTATION_PROFILE and adaptation.profile.resource_path == "res://world/instances/interior_dark_adaptation.tres", "Production megashelter uses the dedicated short-range interior adaptation profile")
	if interior_environment == null:
		check.call(false, "Production megashelter creates its dark native environment")
	else:
		var native := interior_environment.environment
		check.call(native.background_mode == Environment.BG_COLOR and native.background_color.is_equal_approx(Color.BLACK) and is_zero_approx(native.ambient_light_energy), "Production megashelter starts with a black background and zero ambient fill")
		check.call(native.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED, "Production megashelter has no environment reflection fill in unlit rooms")
	await tree.physics_frame
	_check_reception_exit(room, player, check)
	var original_layout: Dictionary = room.layout.duplicate(true)
	var first := room.snapshot()
	check.call(first.actors.size() >= 2 and first.actors.size() <= 4 and first.caches.size() == 1, "Fresh megashelter contains only two-to-four loose supplies and one cache")
	check.call(CheckpointSchema.poi_error({site.id: first}).is_empty(), "Checkpoint schema accepts a complete megashelter snapshot")
	var rejected := first.duplicate(true)
	rejected.layout.profile = "unknown"
	check.call(not CheckpointSchema.poi_error({site.id: rejected}).is_empty(), "Checkpoint schema rejects an unknown saved interior profile")
	rejected = first.duplicate(true)
	rejected.layout.profile = "bunker"
	check.call(not CheckpointSchema.poi_error({site.id: rejected}).is_empty(), "Checkpoint schema rejects megashelter modules labelled as bunker")
	var mismatch := PoiInterior.new()
	mismatch.profile_id = &"bunker"
	var mismatch_built: bool = await mismatch.build(site.seed, first)
	check.call(not mismatch_built, "Interior build rejects a saved/requested profile mismatch")
	mismatch.free()
	for actor: Dictionary in first.actors:
		check.call(actor.kind == "item" and actor.scene != "res://props/engine_upgraded.tscn", "Fresh megashelter has no enemies or upgraded-engine reward")
	for cache_state: Dictionary in first.caches:
		for item: Dictionary in cache_state.remaining:
			check.call(item.scene != "res://props/engine_upgraded.tscn", "Megashelter cache excludes the bunker engine objective")
	if room.entities.get_child_count() == 0 or room.caches.size() != 1: return
	var loose := room.entities.get_child(0) as Item
	check.call(loose != null, "Fresh loose megashelter content is a real Item")
	if loose == null: return
	var picked_id := loose.persistent_id
	loose.interact(player)
	await tree.process_frame
	check.call(player.inventory.items.any(func(item): return item.state.id == picked_id), "Loose megashelter supply is picked up through Item interaction")
	var cache := room.caches[0] as BunkerCache
	check.call(is_zero_approx(cache.get_node("Visuals/LidPivot").rotation.x), "Unsearched cache keeps its physical lid closed without a status label")
	player.global_position = cache.global_position + Vector3(0, 0, 1.5)
	var cache_count := cache.remaining.size()
	cache.interact_hold(player)
	check.call(cache.searched and cache.remaining.size() == cache_count - 1, "Real cache search transfers exactly one supply")
	check.call(is_equal_approx(cache.get_node("Visuals/LidPivot").rotation.x, -1.15), "Searching opens the physical cache lid without a status label")
	# Exercise the production drop path, then freeze the prop to isolate persistence.
	var cache_item_id: String = player.inventory.items.back().state.id
	player._set_active_slot(player.inventory.items.size() - 1)
	player.drop_item()
	var dropped: Item
	for actor in room.entities.get_children():
		if actor is Item and actor.persistent_id == cache_item_id: dropped = actor
	check.call(dropped != null, "Cache supply drops into the interior entity domain")
	if dropped != null:
		dropped.freeze = true
		dropped.linear_velocity = Vector3.ZERO
		dropped.global_position = room.navigation_anchor(0) + Vector3.UP
	room.explored.assign([str(room.layout.rooms[0].id), str(room.layout.rooms[1].id)])
	var committed := room.snapshot()
	await manager.leave()
	check.call(manager.state == PoiInstanceManager.State.OUTDOOR and player.get_parent() == arena, "Megashelter exit returns the player outdoors")
	await manager.enter(player, building, site.id, site.seed)
	check.call(manager.state == PoiInstanceManager.State.INDOOR and manager.interior != null, "Megashelter saved visit reopens")
	if manager.interior == null: return
	room = manager.interior
	var revisited := room.snapshot()
	check.call(room.layout == original_layout and room.explored == committed.explored, "Revisit preserves the authoritative layout and explored rooms")
	check.call(revisited.caches == committed.caches, "Revisit preserves searched cache contents without refill")
	var ids: Array[String] = []
	for actor: Dictionary in revisited.actors: ids.append(str(actor.state.id))
	check.call(ids.size() == committed.actors.size() and cache_item_id in ids and picked_id not in ids, "Revisit restores the loose drop once and never respawns the picked supply")
	var saved_drop: Dictionary = {}
	var restored_drop: Dictionary = {}
	for actor: Dictionary in committed.actors:
		if actor.state.id == cache_item_id: saved_drop = actor
	for actor: Dictionary in revisited.actors:
		if actor.state.id == cache_item_id: restored_drop = actor
	check.call(not saved_drop.is_empty() and restored_drop == saved_drop, "Revisited loose drop retains its exact Item, transform and physics state")
	check.call(CheckpointSchema.poi_error({site.id: revisited}).is_empty(), "Revisited cache/drop snapshot remains valid")
	await manager.leave()
	building.queue_free()

static func _check_reception_exit(interior: PoiInterior, player: CharacterBody3D, check: Callable) -> void:
	var reception := interior.rooms[0]
	var large := reception.get_node_or_null("Visuals/EntranceDoors/LargeDoor") as Node3D
	var pedestrian := reception.get_node_or_null("Visuals/EntranceDoors/PedestrianDoor") as Node3D
	check.call(large != null and pedestrian != null and large != pedestrian, "Reception has distinct large and pedestrian door visuals")
	if large != null and pedestrian != null:
		check.call(not large.find_children("*", "MeshInstance3D", true, false).is_empty() and not pedestrian.find_children("*", "MeshInstance3D", true, false).is_empty(), "Both reception doors contain rendered geometry")
	var markers: Array[Marker3D] = []
	var openings: Array[Vector2] = []
	for path in ["Walkway/Exit", "Walkway/PedestrianExit"]:
		var marker := reception.get_node_or_null(path) as Marker3D
		check.call(marker != null, "Reception provides an exit marker for " + path)
		if marker == null: return
		var opening: Vector2 = marker.get_meta("opening", Vector2.ZERO)
		check.call(opening.is_finite() and opening.x >= 0.75 and opening.y >= 2.0, path + " fits a standing player")
		if not opening.is_finite() or opening.x <= 0 or opening.y <= 0: return
		markers.append(marker)
		openings.append(opening)
		var fits := true
		for x in [-opening.x * 0.5, opening.x * 0.5]:
			for y in [0.0, opening.y]:
				var corner := reception.to_local(marker.to_global(Vector3(x, y, 0)))
				fits = fits and reception.occupancy().grow(0.001).has_point(corner)
		check.call(fits, path + " opening stays inside the authored reception footprint and ceiling")
	check.call(openings[0].x > openings[1].x * 2.0, "Reception retains a large loading door beside the smaller pedestrian door")
	var separation := absf((markers[1].global_position - markers[0].global_position).dot(markers[0].global_basis.x))
	check.call(separation > (openings[0].x + openings[1].x) * 0.5, "Reception exit openings have separate unobstructed widths")
	check.call(interior.exit_door != null, "Reception exits share the production PoiEntrance")
	if interior.exit_door == null: return
	var shapes := interior.exit_door.find_children("*", "CollisionShape3D", true, false)
	check.call(shapes.size() == markers.size(), "Shared reception PoiEntrance has one interaction shape per doorway")
	for index in markers.size():
		var marker := markers[index]
		var opening := openings[index]
		var matched := false
		for node in shapes:
			var shape := node as CollisionShape3D
			var box := shape.shape as BoxShape3D
			if shape.disabled or box == null: continue
			var center := marker.to_local(shape.global_position)
			if not center.is_equal_approx(Vector3(0, opening.y * 0.5, 0)): continue
			var facing := marker.global_basis.inverse() * shape.global_basis
			matched = facing.is_equal_approx(Basis.IDENTITY) and is_equal_approx(box.size.x, opening.x) and is_equal_approx(box.size.y, opening.y) and box.size.z > 0
			if matched: break
		check.call(matched, str(marker.name) + " interaction shape matches its full authored opening")
		# Use the actual physics world, including room walls and furnishings: both
		# leaves must be the first E target from a normal standing approach.
		var from := marker.to_global(Vector3(0, 1.5, 1.2))
		var to := marker.to_global(Vector3(0, 1.5, -0.2))
		var ray := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player.get_rid()])
		var hit := interior.get_world_3d().direct_space_state.intersect_ray(ray)
		check.call(not hit.is_empty() and hit.get("collider") == interior.exit_door, str(marker.name) + " standing interaction ray reaches the shared exit before walls or furniture")
	check.call(interior.find_children("*", "Label3D", true, false).is_empty(), "Megashelter rooms, doors and supplies have no model text labels")

extends Node3D
class_name PoiInterior
## Geometry comes from the saved manifest; actors belong to this World3D.
const PROFILE: InteriorProfile = preload("res://world/instances/catalog/bunker.tres")
const WALL = preload("res://world/poi_kit/materials/bunker/concrete.tres")
const DARK_ADAPTATION_PROFILE: DarkAdaptationProfile = preload("res://world/instances/interior_dark_adaptation.tres")
var profile_id: StringName = &"bunker"
var profile: InteriorProfile = PROFILE
var exterior_area := 1000.0
var layout: Dictionary
var rooms: Array[PoiRoom] = []
var entities: Node3D
var exit_door: PoiEntrance
var link_doors: Dictionary = {}
var link_return_transforms: Dictionary = {}
var navigation: NavigationRegion3D
var cancelled := false
var build_timeout_ms := 60000
var room_count := 0
var target_floors := 0
var instance_id := ""
var populate_content := true
var content: Dictionary = {"version": BunkerContent.VERSION, "cargo_id": "", "cargo_room": ""}
var caches: Array[Node3D] = []
var explored: Array[String] = []
var build_msec := 0
var navigation_msec := 0
var rebaking := false
var current_room := 0
var current_floor := 0
var _sample_time := 0.0
var _hud: Label
var _map: Control

func build(seed_value: int, saved: Dictionary = {}) -> bool:
	var started := Time.get_ticks_msec()
	profile = InteriorProfiles.get_profile(profile_id)
	if profile == null or not profile.validate().is_empty(): return false
	if not saved.is_empty() and not CheckpointSchema.poi_error({"interior": saved}).is_empty(): return false
	if saved.has("layout"):
		if saved.layout.profile != str(profile_id): return false
		layout = saved.layout.duplicate(true)
	elif profile_id == &"megashelter":
		layout = MegashelterInteriorLayout.generate(seed_value, exterior_area, profile)
	else:
		layout = InteriorLayout.generate(seed_value, room_count, profile, target_floors)
	if layout.is_empty() or not InteriorLayout.validate(layout, profile).is_empty(): return false
	if saved.has("explored"): explored.assign(saved.explored)
	set_meta("entity_domain", true)
	entities = Node3D.new()
	entities.name = "WorldEntities"
	add_child(entities)
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	environment.environment = BunkerLighting.create_environment()
	add_child(environment)
	var adaptation := NightVisionEffect.new()
	adaptation.name = "DarkAdaptation"
	adaptation.profile = DARK_ADAPTATION_PROFILE
	add_child(adaptation)
	navigation = NavigationRegion3D.new()
	# Static Item supports save paths relative to this root.
	navigation.name = "MegashelterGeometry" if profile_id == &"megashelter" else "BunkerGeometry"
	add_child(navigation)
	var dark_rooms: Array[String] = MegashelterInteriorLighting.dark_room_ids(layout, profile) if profile_id == &"megashelter" else BunkerLighting.dark_room_ids(layout, profile)
	for i in layout.rooms.size():
		var data: Dictionary = layout.rooms[i]
		var definition := InteriorLayout.definition(layout, i, profile)
		var room := definition.scene.instantiate() as PoiRoom
		room.name = data.id
		room.transform = data.transform
		navigation.add_child(room)
		rooms.append(room)
		if profile_id == &"megashelter": MegashelterInteriorLighting.apply(room, definition, str(data.id) in dark_rooms)
		else: BunkerLighting.apply(room, definition, str(data.id) in dark_rooms)
		_set_floor_signs(room, definition)
		for socket in room.get_node("DoorSockets").get_children():
			if not InteriorLayout.used(layout, i, str(socket.socket_id)): _seal(room, socket)
		if profile_id == &"megashelter": room.call("finish_sealed_sockets", data.connections)
		if i % 4 == 3:
			await get_tree().process_frame
			if cancelled or Time.get_ticks_msec() - started > build_timeout_ms: return false
	_add_exit()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	navigation.navigation_mesh = mesh
	if not await _bake(): return false
	# Choose the service door against published geometry before supplies or
	# restored actors can influence placement on a later visit.
	if not _add_links(): return false
	if saved.has("actors"):
		# An existing empty interior stays empty. Never populate on reentry.
		content = saved.content.duplicate(true)
		for state: Dictionary in saved.caches:
			var cache = preload("res://world/instances/bunker_cache.tscn").instantiate()
			cache.restore_state(state)
			navigation.add_child(cache)
			caches.append(cache)
	elif populate_content and profile_id != &"megashelter_stairwell":
		content = MegashelterInteriorContent.populate(self) if profile_id == &"megashelter" else BunkerContent.populate(self)
	if not caches.is_empty() and not await _bake(): return false
	# Restore movable actors only after all async geometry work is complete.
	# Otherwise a saved drop can fall/move while the player is still loading.
	if saved.has("actors"): _restore(saved.actors)
	if not content.is_empty() and profile_id != &"megashelter_stairwell":
		var content_reachable: bool = MegashelterInteriorContent.reachable(self, saved.is_empty()) if profile_id == &"megashelter" else BunkerContent.reachable(self, saved.is_empty())
		if not content_reachable: return false
	for actor in entities.get_children():
		if actor is Monster: actor.process_mode = Node.PROCESS_MODE_INHERIT
	_add_hud()
	build_msec = Time.get_ticks_msec() - started
	print("INTERIOR_READY profile=%s seed=%d rooms=%d/%d floors=%d/%d build_ms=%d nav_ms=%d" % [profile_id, seed_value, rooms.size(), layout.target_rooms, InteriorLayout.floor_count(layout), layout.target_floors, build_msec, navigation_msec])
	return true

func spawn_transform() -> Transform3D:
	return rooms[0].get_node("Walkway/Spawn").global_transform

func _set_floor_signs(room: PoiRoom, definition: InteriorRoomDefinition) -> void:
	if definition.role != &"stairs": return
	var lower_floor := 1 + roundi(-room.position.y / float(layout.floor_spacing))
	var upper := room.get_node_or_null("Visuals/UpperFloorSign") as Label3D
	var lower := room.get_node_or_null("Visuals/LowerFloorSign") as Label3D
	if upper: upper.text = "B%d\nDOWN TO B%d" % [lower_floor - 1, lower_floor]
	if lower: lower.text = "B%d\nUP TO B%d" % [lower_floor, lower_floor - 1]

func _seal(room: PoiRoom, socket: PoiDoorSocket) -> void:
	var holder := Node3D.new()
	holder.name = "Sealed_" + str(socket.socket_id)
	holder.transform = room.get_node("Collision").transform.affine_inverse() * room.socket_transform(socket)
	room.get_node("Collision").add_child(holder)
	# +Z faces inward. The whole wall slab stays in its own room.
	var body := StaticBody3D.new()
	body.name = "Support_0"
	body.position = Vector3(0, socket.opening.y * 0.5, 0.12)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(socket.opening.x, socket.opening.y, 0.24)
	shape.shape = box
	body.add_child(shape)
	holder.add_child(body)
	for path in socket.frame_nodes:
		var frame := socket.get_node_or_null(path)
		if frame != null: frame.queue_free()
	# Shelter finishes are batched in room coordinates with the adjacent walls.
	if profile_id == &"megashelter": return
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	visual.mesh = mesh
	visual.material_override = _room_material(room, "Wall", WALL)
	body.add_child(visual)
	var paint := MeshInstance3D.new()
	var panel := BoxMesh.new()
	panel.size = Vector3(socket.opening.x, 1.1, 0.012)
	paint.mesh = panel
	paint.material_override = _room_material(room, "Paint", preload("res://world/poi_kit/materials/bunker/olive.tres"))
	paint.position = Vector3(0, 0.7, 0.247)
	holder.add_child(paint)

func _room_material(room: PoiRoom, prefix: String, fallback: Material) -> Material:
	for node in room.get_node("Visuals").get_children():
		if node is MeshInstance3D and str(node.name).begins_with(prefix):
			var material: Material = node.get_active_material(0)
			if material != null: return material
	return fallback

func _add_exit() -> void:
	var marker: Marker3D = rooms[0].get_node("Walkway/Exit")
	exit_door = PoiEntrance.new()
	exit_door.name = "Exit"
	exit_door.transform = marker.global_transform
	add_child(exit_door)
	var markers: Array[Marker3D] = [marker]
	var pedestrian := rooms[0].get_node_or_null("Walkway/PedestrianExit") as Marker3D
	if pedestrian != null: markers.append(pedestrian)
	for target in markers:
		var opening: Vector2 = target.get_meta("opening", Vector2(2.35, 2.8))
		var shape := CollisionShape3D.new()
		shape.name = str(target.name) + "Interaction"
		var box := BoxShape3D.new()
		box.size = Vector3(opening.x, opening.y, 0.1)
		shape.shape = box
		exit_door.add_child(shape)
		shape.global_transform = target.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, opening.y*0.5, 0))
	if profile_id in [&"megashelter", &"megashelter_stairwell"]: return
	var sign := Label3D.new()
	sign.name = "ReturnSign"
	sign.text = "[E] EXIT / SURFACE"
	sign.position = Vector3(0, 2.4, 0.10)
	sign.font_size = 40
	sign.pixel_size = 0.006
	exit_door.add_child(sign)

func _add_links() -> bool:
	if profile_id == &"megashelter":
		return _add_stair_access()
	elif profile_id == &"megashelter_stairwell":
		var marker := rooms[0].get_node("Walkway/BunkerExit") as Marker3D
		_add_link(&"bunker", marker.global_transform, marker.get_meta("opening", Vector2(2.8, 3.0)))
		link_return_transforms[&"bunker"] = rooms[0].get_node("Walkway/BunkerSpawn").global_transform
	return true

func _add_stair_access() -> bool:
	var candidates: Array[Dictionary] = []
	for i in range(1, rooms.size()):
		for socket: PoiDoorSocket in rooms[i].get_node("DoorSockets").get_children():
			if InteriorLayout.used(layout, i, str(socket.socket_id)): continue
			var pose := rooms[i].socket_transform(socket) * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.28))
			candidates.append({"room": rooms[i], "pose": pose})
	var rng := RandomNumberGenerator.new()
	rng.seed = ("megashelter-stair-access:v1:%d" % int(layout.seed)).sha256_text().substr(0, 15).hex_to_int()
	var clearance := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.1, 1.5)
	clearance.shape = box
	clearance.collision_mask = 1
	var map := navigation.get_navigation_map()
	var space := get_world_3d().direct_space_state
	while not candidates.is_empty():
		var candidate: Dictionary = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var room: PoiRoom = candidate.room
		var pose: Transform3D = room.global_transform * candidate.pose
		clearance.transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 1.05))
		if not space.intersect_shape(clearance, 1).is_empty(): continue
		var landing := pose * Vector3(0, 0, 1.5)
		var nearest := NavigationServer3D.map_get_closest_point(map, landing)
		if absf(nearest.y - landing.y) > 0.65 or Vector2(nearest.x - landing.x, nearest.z - landing.z).length() > 0.3: continue
		var path := NavigationServer3D.map_get_path(map, navigation_anchor(0), nearest, true)
		if path.size() < 2 or path[-1].distance_to(nearest) > 0.5: continue
		room.call("add_stair_access", candidate.pose)
		_add_link(&"megashelter_stairwell", pose * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.3)), Vector2(1.06, 2.32))
		link_return_transforms[&"megashelter_stairwell"] = pose * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.08, 1.5))
		return true
	return false

func _add_link(destination: StringName, pose: Transform3D, opening: Vector2) -> void:
	var door := PoiEntrance.new()
	door.name = "Link_" + str(destination)
	door.destination_id = destination
	door.transform = pose
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(opening.x, opening.y, 0.12)
	shape.shape = box
	shape.position = Vector3(0, opening.y*0.5, 0)
	door.add_child(shape)
	add_child(door)
	link_doors[destination] = door

func navigation_anchor(index: int) -> Vector3:
	var route := rooms[index].get_node("Walkway").get_child(0) as Marker3D
	return route.global_position

func _bake() -> bool:
	if rebaking: return false
	rebaking = true
	var started := Time.get_ticks_msec()
	await get_tree().process_frame
	if cancelled:
		rebaking = false
		return false
	navigation.bake_navigation_mesh(true)
	while NavigationServer3D.is_baking_navigation_mesh(navigation.navigation_mesh):
		await get_tree().process_frame
		if cancelled or Time.get_ticks_msec() - started > build_timeout_ms:
			rebaking = false
			return false
	var region := navigation.get_region_rid()
	var before := NavigationServer3D.region_get_iteration_id(region)
	# Publish an immutable mesh, then wait for region AND map synchronization.
	navigation.navigation_mesh = navigation.navigation_mesh.duplicate()
	while NavigationServer3D.region_get_iteration_id(region) <= before or NavigationServer3D.region_get_bounds(region).size == Vector3.ZERO:
		await get_tree().physics_frame
		if cancelled or Time.get_ticks_msec() - started > build_timeout_ms:
			rebaking = false
			return false
	var probe := rooms[0].global_position
	while true:
		var map := navigation.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point_owner(map,probe) == region and NavigationServer3D.map_get_closest_point(map,probe).distance_to(probe) < 1.0: break
		await get_tree().physics_frame
		if cancelled or Time.get_ticks_msec() - started > build_timeout_ms:
			rebaking = false
			return false
	navigation_msec = Time.get_ticks_msec() - started
	rebaking = false
	return _navigation_connected()

func _navigation_connected() -> bool:
	var map := navigation.get_navigation_map()
	var start := navigation_anchor(0)
	for i in rooms.size():
		var target := navigation_anchor(i)
		if NavigationServer3D.map_get_closest_point(map, target).distance_to(target) >= 1.0: return false
		if i == 0: continue
		var path := NavigationServer3D.map_get_path(map, start, target, true)
		if path.size() < 2 or path[-1].distance_to(target) >= 1.0: return false
	return true

func snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor in entities.get_children():
		var saved := WorldActorSnapshot.capture(actor)
		if not saved.is_empty(): actors.append(saved)
	var result := {"actors": actors, "layout": layout.duplicate(true), "explored": explored.duplicate(), "content": content.duplicate(true), "caches": []}
	for cache in caches: result.caches.append(cache.capture_state())
	return result

func _restore(actors: Array) -> void:
	var restored: Array = []
	for data: Dictionary in actors:
		var actor := WorldActorSnapshot.restore(data, entities)
		if actor is Monster: actor.process_mode = Node.PROCESS_MODE_DISABLED
		restored.append(actor)
	WorldActorSnapshot.restore_supports(actors, restored, self)
func _add_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	HUDVisibility.attach(layer)
	_hud = Label.new()
	_hud.position = Vector2(24,80)
	if profile_id == &"megashelter":
		_hud.anchor_left = 1.0
		_hud.anchor_right = 1.0
		_hud.offset_left = -500.0
		_hud.offset_right = -24.0
		_hud.offset_top = 62.0
		_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_theme_font_size_override("font_size", 20)
	layer.add_child(_hud)
	_map = preload("res://world/instances/interior_map.gd").new()
	_map.interior = self
	_map.position = Vector2(24,180)
	_map.size = Vector2(600,440)
	_map.hide()
	layer.add_child(_map)

func _process(delta: float) -> void:
	if _hud == null: return
	_sample_time += delta
	if _sample_time < 0.2: return
	_sample_time = 0
	var player := get_node_or_null("Player") as Node3D
	if player == null: return
	current_floor = clampi(roundi(-player.position.y/layout.floor_spacing),0,InteriorLayout.floor_count(layout)-1)
	for i in rooms.size():
		var local := rooms[i].to_local(player.global_position)
		var bounds: AABB = InteriorLayout.definition(layout, i, profile).describe().bounds
		# Sample feet, not the below-floor origin; do not expand into another level.
		if bounds.has_point(local + Vector3.UP * 0.3):
			current_room = i
			var id: String = layout.rooms[i].id
			if id not in explored: explored.append(id)
			break
	if profile_id == &"megashelter_stairwell":
		_hud.text = "SERVICE STAIR"
	elif profile_id == &"megashelter":
		_hud.text = "GROUND FLOOR / %s    %d explored\nM: explored map  |  Return to ENTRY to exit" % [str(layout.rooms[current_room].id).to_upper(), explored.size()]
	else:
		_hud.text = "B%d / %s    %d explored\nM: explored map   Page Up/Down: map floor" % [current_floor+1, str(layout.rooms[current_room].id).to_upper(), explored.size()]
		if not content.is_empty(): _hud.text += "\n" + BunkerContent.objective_text(self, player)
	if _map.visible: _map.queue_redraw()

func _input(event: InputEvent) -> void:
	for actor in get_tree().get_nodes_in_group(Groups.PLAYER):
		if actor.get_viewport() == get_viewport() and actor.has_method("is_gameplay_input_blocked") and actor.is_gameplay_input_blocked(): return
	if not event is InputEventKey or not event.pressed or event.echo or _map == null: return
	if event.keycode == KEY_M:
		_map.visible = not _map.visible
		_map.floor_index = current_floor
		_map.queue_redraw()
	if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		_map.floor_index = clampi(_map.floor_index + (-1 if event.keycode == KEY_PAGEUP else 1), 0, InteriorLayout.floor_count(layout)-1)
		_map.queue_redraw()

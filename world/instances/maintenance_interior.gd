extends PoiInterior
class_name MaintenanceInterior
const PROFILE: InteriorProfile = preload("res://world/instances/catalog/maintenance_v2.tres")
const INTERACTION = preload("res://world/instances/interior_interaction.gd")
# Adjacent authored rooms share boundary colliders. Their visible faces must
# sit slightly inside their own room instead of drawing on the same plane.
const BOUNDARY_VISUAL_INSET := 0.02
var room_count := 0
var objective_claimed := false
var shortcut_open := false
var explored: Array[String] = []
var gate: InteriorInteraction
var depot: InteriorInteraction
var depths: Array[float] = []
var build_msec := 0
var navigation_msec := 0
var rebaking := false
var _sample_time := 0.0
var _hud: Label
var _map: Control
var current_room := 0
var current_floor := 0

func build(seed_value: int, saved: Dictionary = {}) -> bool:
	var started := Time.get_ticks_msec()
	if not saved.is_empty() and not CheckpointSchema.poi_error({"interior": saved}).is_empty(): return false
	if not PROFILE.validate().is_empty(): return false
	layout = saved.layout.duplicate(true) if saved.has("layout") else InteriorLayout.generate(seed_value, room_count)
	if layout.is_empty(): return false
	if saved.has("layout"):
		objective_claimed = saved.objective_claimed
		shortcut_open = saved.shortcut_open
		explored.assign(saved.explored)
	depths = InteriorLayout.distances(layout)
	set_meta("entity_domain", true)
	entities = Node3D.new()
	entities.name = "WorldEntities"
	add_child(entities)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101718")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("9dada9")
	environment.environment.ambient_light_energy = 0.28
	add_child(environment)
	navigation = NavigationRegion3D.new()
	navigation.name = "InteriorGeometry"
	add_child(navigation)
	for i in layout.rooms.size():
		var data: Dictionary = layout.rooms[i]
		var room := PROFILE.room(data.definition).scene.instantiate() as PoiRoom
		room.name = data.id
		room.transform = data.transform
		navigation.add_child(room)
		rooms.append(room)
		_inset_boundary_visuals(room)
		for socket in room.get_node("DoorSockets").get_children():
			if not InteriorLayout.used(layout, i, str(socket.socket_id)):
				_seal(room, socket)
		_decorate(room, i)
		if i % 4 == 3:
			await get_tree().process_frame
			if cancelled or Time.get_ticks_msec() - started > build_timeout_ms: return false
	_add_exit()
	_add_interactions()
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
	if saved.has("actors"): _restore(saved.actors)
	else: _populate(seed_value)
	_add_hud()
	build_msec = Time.get_ticks_msec() - started
	print("INTERIOR_V2_READY seed=%d rooms=%d build_ms=%d nav_ms=%d actors=%d" % [seed_value, rooms.size(), build_msec, navigation_msec, entities.get_child_count()])
	return true

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
	return true

func _seal(room: PoiRoom, socket: PoiDoorSocket) -> void:
	var holder := Node3D.new()
	holder.name = "Sealed_" + str(socket.socket_id)
	holder.transform = socket.transform
	room.get_node("Collision").add_child(holder)
	_box(holder, Vector3(socket.opening.x, socket.opening.y, 0.24), Vector3.UP * socket.opening.y/2, SEAL)
	var body := holder.get_child(0) as StaticBody3D
	var panel := body.get_child(0) as MeshInstance3D
	# Socket +Z faces this room. Move only the rendered panel; its collider,
	# saved layout and the wall on the other side retain their original poses.
	panel.position.z = BOUNDARY_VISUAL_INSET

func _inset_boundary_visuals(room: PoiRoom) -> void:
	var half_size := Vector2(room.size_cells) * 4.5
	for node in room.get_node("Visuals").get_children():
		if not node is MeshInstance3D or not node.mesh is BoxMesh: continue
		var label := str(node.name)
		if not (label.begins_with("Wall") or label.begins_with("Lintel") or label.begins_with("LowerWall")): continue
		if is_equal_approx(absf(node.position.x), half_size.x):
			node.position.x -= signf(node.position.x) * BOUNDARY_VISUAL_INSET
		if is_equal_approx(absf(node.position.z), half_size.y):
			node.position.z -= signf(node.position.z) * BOUNDARY_VISUAL_INSET

func _decorate(room: PoiRoom, index: int) -> void:
	var zone := clampi(int(depths[index] / 45.0), 0, 2)
	var colors := [Color("4c8f91"), Color("b18a48"), Color("ab5d42")]
	var marker := Label3D.new()
	marker.text = "%s / L%d / %s" % [["SERVICE", "OPERATIONS", "RESTRICTED"][zone], roundi(room.position.y/6)+1, str(layout.rooms[index].id).to_upper()]
	marker.position = Vector3(0, 2.7, 3.8)
	marker.rotation.y = PI
	marker.font_size = 42
	marker.pixel_size = 0.008
	marker.modulate = colors[zone]
	room.get_node("Visuals").add_child(marker)
	# Functional clues mark the guaranteed route without exposing unexplored branches.
	if index < 12:
		var clue := Label3D.new()
		clue.text = "PARTS DEPOT / VIA LEVEL 2" if index < 9 else "RETURN HATCH / RECEPTION"
		if index == 2: clue.text = "LEVEL 2  /  UP"
		if index == 7: clue.text = "LEVEL 1  /  DOWN TO DEPOT"
		clue.position = Vector3(0, 2.3, -3.8)
		clue.font_size = 38
		clue.pixel_size = 0.007
		room.get_node("Visuals").add_child(clue)

func _add_interactions() -> void:
	gate = INTERACTION.new()
	gate.kind = "gate"
	gate.name = "ReturnHatch"
	gate.transform = rooms[0].get_socket(&"east").global_transform
	navigation.add_child(gate)
	_interaction_box(gate, Vector3(3,3.5,0.24), "RETURN HATCH / INSIDE RELEASE")
	gate.completed = shortcut_open
	if shortcut_open: _open_gate_geometry()
	gate.activated.connect(func(_player):
		shortcut_open = true
		_open_gate_geometry()
		_refresh_navigation.call_deferred())
	depot = INTERACTION.new()
	depot.name = "PartsDepot"
	depot.position = rooms[9].position + Vector3(2.7,0,-2.7)
	navigation.add_child(depot)
	_interaction_box(depot, Vector3(1.2,1.8,0.8), "ENGINE PARTS / E RELEASE")
	depot.completed = objective_claimed
	depot.activated.connect(func(_player):
		objective_claimed = true
		_spawn_reward())

func _interaction_box(body: StaticBody3D, size: Vector3, text: String) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = SEAL
	visual.position.y = size.y/2
	visual.name = "Visuals"
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = visual.position
	shape.name = "Collision"
	body.add_child(shape)
	var sign := Label3D.new()
	sign.text = text
	sign.position = Vector3(0, size.y+0.2, 0)
	sign.font_size = 36
	sign.pixel_size = 0.007
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.add_child(sign)

func _open_gate_geometry() -> void:
	# Move both collision and visible leaf above the opening. Disabled colliders
	# can still be included by navigation source parsing on some engine paths.
	gate.get_node("Collision").set_deferred("position", Vector3(0,5.4,0))
	gate.get_node("Visuals").position.y = 5.4

func _refresh_navigation() -> void:
	await get_tree().physics_frame
	if not cancelled: await _bake()

func _spawn_reward() -> void:
	for i in 3:
		var path := "res://props/engine_standard.tscn" if i == 0 else "res://props/engine_repair_kit.tscn"
		var prop := load(path).instantiate() as Prop
		entities.add_child(prop)
		prop.position = rooms[9].position + Vector3(-1+i, 0.55, -1.5)
		prop.freeze = true

func _populate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x56324c54
	var candidates: Array[Dictionary] = []
	for i in rooms.size():
		for point in rooms[i].find_children("*", "Marker3D", true, false):
			if point is PoiLootPoint:
				# Stable exponential priorities favour depth, with a fixed total budget.
				candidates.append({"point": point, "room": i, "priority": -log(maxf(rng.randf(), 0.00001)) / (1.0+depths[i]/80.0)})
	candidates.sort_custom(func(a,b): return a.priority < b.priority)
	var per_room: Dictionary = {}
	var spawned := 0
	# Guaranteed near-entry basic supply is part of the same overall budget.
	var fuel: Prop = preload("res://props/gas_can.tscn").instantiate()
	entities.add_child(fuel)
	fuel.position = Vector3(-2,0.4,1.5)
	fuel.freeze = true
	spawned += 1
	for candidate in candidates:
		if spawned >= PROFILE.loot_budget: break
		if per_room.get(candidate.room, 0) >= 2: continue
		var scene: PackedScene = candidate.point.roll_scene(rng)
		if scene == null: continue
		# Deep floor supplies add practical fuel/repair rewards, never reroll on revisit.
		if candidate.point.category == &"metal" and candidate.point.point_id == &"floor_supply" and depths[candidate.room] > 60:
			scene = preload("res://props/engine_repair_kit.tscn") if rng.randf() < 0.4 else preload("res://props/gas_can.tscn")
		var item := scene.instantiate() as Prop
		entities.add_child(item)
		item.global_transform = candidate.point.global_transform
		item.freeze = true
		per_room[candidate.room] = per_room.get(candidate.room,0)+1
		spawned += 1
	var enemy_rooms: Array[int] = []
	rng.seed = seed_value ^ 0x5632454e
	for i in range(12, rooms.size()):
		if depths[i] > 35 and layout.rooms[i].definition != "stairs": enemy_rooms.append(i)
	for i in range(enemy_rooms.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var swap := enemy_rooms[i]
		enemy_rooms[i] = enemy_rooms[j]
		enemy_rooms[j] = swap
	for i in mini(PROFILE.enemy_budget, enemy_rooms.size()):
		var enemy := ZOMBIE.instantiate() as Monster
		entities.add_child(enemy)
		enemy.global_position = rooms[enemy_rooms[i]].get_node("EnemySpawns/Enemy").global_position

func navigation_anchor(index: int) -> Vector3:
	return rooms[index].global_position + (Vector3(0,3,0) if layout.rooms[index].definition == "stairs" else Vector3.ZERO)

func snapshot() -> Dictionary:
	var result := super.snapshot()
	result["layout"] = layout.duplicate(true)
	result["objective_claimed"] = objective_claimed
	result["shortcut_open"] = shortcut_open
	result["explored"] = explored.duplicate()
	return result

func _add_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24,80)
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
	current_floor = clampi(roundi(player.position.y/6.0),0,1)
	for i in rooms.size():
		var local := rooms[i].to_local(player.global_position)
		var bounds: AABB = PROFILE.room(layout.rooms[i].definition).describe().bounds
		# Sample feet, not the below-floor origin; do not expand into another level.
		if bounds.has_point(local + Vector3.UP * 0.3):
			current_room = i
			var id: String = layout.rooms[i].id
			if id not in explored: explored.append(id)
			break
	_hud.text = "L%d / %s    %d explored\n%s | %s\nM: explored map   Page Up/Down: map floor" % [current_floor+1, str(layout.rooms[current_room].id).to_upper(), explored.size(), "Depot released — carry supplies to RV" if objective_claimed else "Find the parts depot via Level 2", "Return hatch OPEN" if shortcut_open else "Return hatch locked from inside"]
	if _map.visible: _map.queue_redraw()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _map == null: return
	if event.keycode == KEY_M:
		_map.visible = not _map.visible
		_map.floor_index = current_floor
		_map.queue_redraw()
	if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		_map.floor_index = 1 if event.keycode == KEY_PAGEUP else 0
		_map.queue_redraw()

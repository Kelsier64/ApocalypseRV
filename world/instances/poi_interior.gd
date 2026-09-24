extends Node3D
class_name PoiInterior
## Bunker assembler. Geometry comes from the saved manifest; actors belong to this World3D.
const PROFILE: InteriorProfile = preload("res://world/instances/catalog/bunker.tres")
const WALL = preload("res://world/poi_kit/materials/bunker/concrete.tres")
var layout: Dictionary
var rooms: Array[PoiRoom] = []
var entities: Node3D
var exit_door: PoiEntrance
var navigation: NavigationRegion3D
var cancelled := false
var build_timeout_ms := 60000
var room_count := 0
var target_floors := 0
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
	if not saved.is_empty() and not CheckpointSchema.poi_error({"interior": saved}).is_empty(): return false
	if not PROFILE.validate().is_empty(): return false
	layout = saved.layout.duplicate(true) if saved.has("layout") else InteriorLayout.generate(seed_value, room_count, PROFILE, target_floors)
	if layout.is_empty() or not InteriorLayout.validate(layout).is_empty(): return false
	if saved.has("explored"): explored.assign(saved.explored)
	set_meta("entity_domain", true)
	entities = Node3D.new()
	entities.name = "WorldEntities"
	add_child(entities)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("111511")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("afb9a3")
	environment.environment.ambient_light_energy = 0.22
	add_child(environment)
	navigation = NavigationRegion3D.new()
	navigation.name = "BunkerGeometry"
	add_child(navigation)
	for i in layout.rooms.size():
		var data: Dictionary = layout.rooms[i]
		var room := InteriorLayout.definition(layout, i).scene.instantiate() as PoiRoom
		room.name = data.id
		room.transform = data.transform
		navigation.add_child(room)
		rooms.append(room)
		for socket in room.get_node("DoorSockets").get_children():
			if not InteriorLayout.used(layout, i, str(socket.socket_id)): _seal(room, socket)
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
	if saved.has("actors"): _restore(saved.actors)
	_add_hud()
	build_msec = Time.get_ticks_msec() - started
	print("BUNKER_READY seed=%d rooms=%d/%d floors=%d/%d build_ms=%d nav_ms=%d" % [seed_value, rooms.size(), layout.target_rooms, InteriorLayout.floor_count(layout), layout.target_floors, build_msec, navigation_msec])
	return true

func spawn_transform() -> Transform3D:
	return rooms[0].get_node("Walkway/Spawn").global_transform

func _seal(room: PoiRoom, socket: PoiDoorSocket) -> void:
	var holder := Node3D.new()
	holder.name = "Sealed_" + str(socket.socket_id)
	holder.transform = room.get_node("Collision").transform.affine_inverse() * room.socket_transform(socket)
	room.get_node("Collision").add_child(holder)
	# +Z faces inward. The whole wall slab stays in its own room.
	_box(holder, Vector3(socket.opening.x, socket.opening.y, 0.24), Vector3(0, socket.opening.y/2, 0.12), WALL)
	for path in socket.frame_nodes:
		var frame := socket.get_node_or_null(path)
		if frame != null: frame.queue_free()
	var paint := MeshInstance3D.new()
	var panel := BoxMesh.new()
	panel.size = Vector3(socket.opening.x, 1.1, 0.012)
	paint.mesh = panel
	paint.material_override = preload("res://world/poi_kit/materials/bunker/olive.tres")
	paint.position = Vector3(0, 0.7, 0.247)
	holder.add_child(paint)

func _add_exit() -> void:
	var marker: Marker3D = rooms[0].get_node("Walkway/Exit")
	exit_door = PoiEntrance.new()
	exit_door.name = "Exit"
	exit_door.transform = marker.global_transform
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.35, 2.8, 0.1)
	shape.shape = box
	shape.position.y = 1.4
	exit_door.add_child(shape)
	add_child(exit_door)
	var sign := Label3D.new()
	sign.text = "[E] EXIT / SURFACE"
	sign.position = Vector3(0, 2.4, 0.10)
	sign.font_size = 40
	sign.pixel_size = 0.006
	exit_door.add_child(sign)

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

func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)

func snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor in entities.get_children():
		if actor.is_queued_for_deletion() or (actor is Monster and actor.is_dead):
			continue
		if not actor is Prop and not actor is Monster:
			continue
		var data := {"scene": actor.scene_file_path, "transform": actor.transform}
		if actor is Monster:
			data["health"] = actor.current_health
		else:
			data["yields"] = actor.scrap_yields.duplicate(true)
			data["state"] = actor.capture_item_state()
			data["name"] = actor.item_name
			data["large"] = actor.is_large
			data["frozen"] = actor.freeze
		actors.append(data)
	return {"actors": actors, "layout": layout.duplicate(true), "explored": explored.duplicate()}

func _restore(actors: Array) -> void:
	for data: Dictionary in actors:
		var actor: Node3D = load(data.scene).instantiate()
		entities.add_child(actor)
		actor.transform = data.transform
		if actor is Monster:
			actor.current_health = data.health
		else:
			actor.scrap_yields = data.yields.duplicate(true)
			actor.restore_item_state(data.get("state", {"scrap_yields": data.yields}))
			actor.item_name = data.name
			actor.is_large = data.large
			actor.freeze = data.frozen

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
	current_floor = clampi(roundi(-player.position.y/layout.floor_spacing),0,InteriorLayout.floor_count(layout)-1)
	for i in rooms.size():
		var local := rooms[i].to_local(player.global_position)
		var bounds: AABB = InteriorLayout.definition(layout, i).describe().bounds
		# Sample feet, not the below-floor origin; do not expand into another level.
		if bounds.has_point(local + Vector3.UP * 0.3):
			current_room = i
			var id: String = layout.rooms[i].id
			if id not in explored: explored.append(id)
			break
	_hud.text = "B%d / %s    %d explored\nM: explored map   Page Up/Down: map floor" % [current_floor+1, str(layout.rooms[current_room].id).to_upper(), explored.size()]
	if _map.visible: _map.queue_redraw()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _map == null: return
	if event.keycode == KEY_M:
		_map.visible = not _map.visible
		_map.floor_index = current_floor
		_map.queue_redraw()
	if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		_map.floor_index = clampi(_map.floor_index + (-1 if event.keycode == KEY_PAGEUP else 1), 0, InteriorLayout.floor_count(layout)-1)
		_map.queue_redraw()

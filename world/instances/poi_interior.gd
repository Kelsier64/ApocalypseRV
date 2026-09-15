extends Node3D
class_name PoiInterior
## One active interior. Geometry is regenerated from seed; only actors are saved.
const SMALL = preload("res://world/poi_kit/rooms/maze_utility.tscn")
const HALL = preload("res://world/poi_kit/rooms/maze_hall.tscn")
const FLOOR = preload("res://world/poi_kit/materials/floor.tres")
const WALL = preload("res://world/poi_kit/materials/concrete.tres")
const SEAL = preload("res://world/poi_kit/materials/paint.tres")
const ZOMBIE = preload("res://enemies/zombie.tscn")
const SIDES := [&"north", &"east", &"south", &"west"]
var layout: Dictionary
var rooms: Array[PoiRoom] = []
var entities: Node3D
var exit_door: PoiEntrance
var navigation: NavigationRegion3D

func build(seed_value: int, saved: Dictionary = {}) -> void:
	set_meta("entity_domain", true)
	entities = Node3D.new()
	entities.name = "WorldEntities"
	add_child(entities)
	layout = MazeLayout.generate(seed_value)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("151d1d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("adbbb0")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	navigation = NavigationRegion3D.new()
	navigation.name = "MazeGeometry"
	add_child(navigation)
	for i in range(layout.rooms.size()):
		var data: Dictionary = layout.rooms[i]
		var room: PoiRoom = (HALL if data.large else SMALL).instantiate()
		room.name = "Room%03d" % i
		room.position = Vector3(data.cell.x, 0, data.cell.y) * MazeLayout.SPACING
		navigation.add_child(room)
		rooms.append(room)
		for d in range(4):
			if not data.doors.has(d):
				var socket := room.get_socket(SIDES[d])
				var size := Vector3(3, 3.5, 0.24) if d % 2 == 0 else Vector3(0.24, 3.5, 3)
				_box(room, size, socket.position + Vector3.UP * 1.75, SEAL)
		var sign := Label3D.new()
		sign.text = "R%03d" % (i + 1)
		sign.position = Vector3(0, 3.1, 1.5)
		sign.font_size = 64
		sign.pixel_size = 0.01
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		room.add_child(sign)
		if i % 8 == 7:
			await get_tree().process_frame
	for edge: Vector2i in layout.edges:
		_connect(rooms[edge.x], rooms[edge.y])
	_add_exit()
	# Bake actual static geometry, including furniture, before adding dynamic actors.
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	navigation.navigation_mesh = mesh
	navigation.bake_navigation_mesh(true)
	await navigation.bake_finished
	await get_tree().physics_frame
	if saved.has("actors"):
		_restore(saved.actors)
	else:
		_populate(seed_value)

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

func _connect(a: PoiRoom, b: PoiRoom) -> void:
	var delta := (b.position - a.position).normalized()
	var door_side := 1 if delta.x > 0.5 else (3 if delta.x < -0.5 else (2 if delta.z > 0.5 else 0))
	var socket_a := a.get_socket(SIDES[door_side])
	var socket_b := b.get_socket(SIDES[(door_side + 2) % 4])
	if not socket_a.can_connect(socket_b):
		push_error("Incompatible maze door interfaces")
		return
	var start := to_local(socket_a.global_position)
	var end := to_local(socket_b.global_position)
	var length := start.distance_to(end)
	var center := (start + end) * 0.5
	var along_x := absf(delta.x) > 0.5
	_box(navigation, Vector3(length, 0.25, 3) if along_x else Vector3(3, 0.25, length), center + Vector3.DOWN * 0.125, FLOOR)
	_box(navigation, Vector3(length, 0.24, 3.24) if along_x else Vector3(3.24, 0.24, length), center + Vector3.UP * 3.62, WALL)
	for side in [-1, 1]:
		var offset := Vector3(0, 1.75, side * 1.62) if along_x else Vector3(side * 1.62, 1.75, 0)
		_box(navigation, Vector3(length, 3.5, 0.24) if along_x else Vector3(0.24, 3.5, length), center + offset, WALL)
	var lamp := OmniLight3D.new()
	lamp.position = center + Vector3.UP * 2.9
	lamp.light_energy = 1.1
	lamp.omni_range = 11
	navigation.add_child(lamp)

func _add_exit() -> void:
	exit_door = PoiEntrance.new()
	exit_door.name = "Exit"
	exit_door.position = Vector3(0, 0, 4.32)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 3.5, 0.1)
	shape.shape = box
	shape.position.y = 1.75
	exit_door.add_child(shape)
	add_child(exit_door)
	var sign := Label3D.new()
	sign.text = "[E] EXIT / HIGHWAY"
	sign.position = Vector3(0, 2.5, 4.2)
	sign.rotation.y = PI
	sign.font_size = 52
	sign.pixel_size = 0.008
	add_child(sign)

func _populate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x4c4f4f54
	for i in range(rooms.size()):
		var points := rooms[i].find_children("*", "Marker3D", true, false)
		for j in range(points.size() - 1, 0, -1):
			var k := rng.randi_range(0, j)
			var swap: Node = points[j]
			points[j] = points[k]
			points[k] = swap
		var spawned := 0
		for point in points:
			if not point is PoiLootPoint or spawned >= 4:
				continue
			var scene: PackedScene = point.roll_scene(rng)
			if scene == null:
				continue
			var item := scene.instantiate() as Prop
			entities.add_child(item)
			item.global_transform = point.global_transform
			# Authored shelf loot stays put until picked up; player drops use physics.
			item.freeze = true
			spawned += 1
		var enemy_points := rooms[i].get_node("EnemySpawns").get_children()
		if i > 2 and i % 7 == 0 and not enemy_points.is_empty():
			var enemy := ZOMBIE.instantiate() as Monster
			entities.add_child(enemy)
			enemy.global_position = enemy_points[rng.randi_range(0, enemy_points.size() - 1)].global_position

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
	return {"actors": actors}

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

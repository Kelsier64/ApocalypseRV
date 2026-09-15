extends SceneTree
## Production scenes: authored contracts, rigid-body placement and traversal.
var failures: Array[String] = []
var world: Node3D

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var small: PoiRoom = load("res://world/poi_kit/rooms/utility_small.tscn").instantiate()
	world.add_child(small)
	var corridor: PoiRoom = load("res://world/poi_kit/rooms/service_corridor.tscn").instantiate()
	world.add_child(corridor)
	_expect(corridor.connect_to(&"south", small.get_socket(&"north")), "Compatible doors connect")
	var hall: PoiRoom = load("res://world/poi_kit/rooms/maintenance_hall.tscn").instantiate()
	world.add_child(hall)
	_expect(hall.connect_to(&"south", corridor.get_socket(&"north")), "Different room sizes connect")
	_expect(hall.position.is_equal_approx(Vector3(0, 0, -22.5)), "Connection uses socket position, not fixed room width")
	for room in [small, corridor, hall]:
		_expect(room.validate().is_empty(), "Room authoring contract: " + str(room.room_id) + str(room.validate()))
		_expect(room.scale.is_equal_approx(Vector3.ONE), "Connecting never scales authored geometry")
	var rotated: PoiRoom = load("res://world/poi_kit/rooms/utility_small.tscn").instantiate()
	world.add_child(rotated)
	_expect(rotated.connect_to(&"south", hall.get_socket(&"east")), "Quarter-turn connection succeeds")
	_expect(rotated.get_socket(&"south").global_position.distance_to(hall.get_socket(&"east").global_position) < 0.001, "Rotated door origins coincide")
	_expect(rotated.get_socket(&"south").global_basis.z.dot(hall.get_socket(&"east").global_basis.z) < -0.999, "Connected doors face opposite ways")
	var original := rotated.global_transform
	rotated.get_socket(&"south").opening.x = 2.0
	_expect(not rotated.connect_to(&"south", hall.get_socket(&"east")), "Mismatched door size is refused")
	_expect(rotated.global_transform.is_equal_approx(original), "Failed connection leaves asset in place")
	rotated.get_socket(&"south").opening.x = 3.0
	for file in ["shelf", "workbench", "cabinet"]:
		var furniture: PoiFurniture = load("res://world/poi_kit/furniture/" + file + ".tscn").instantiate()
		world.add_child(furniture)
		_expect(furniture.validate().is_empty(), "Furniture contract: " + file)
		furniture.free()
	# Loading templates must not automatically mint loot.
	_expect(world.find_children("*", "RigidBody3D", true, false).is_empty(), "Asset scenes do not auto-spawn loot")
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 42
	rng_b.seed = 42
	var point: PoiLootPoint = small.get_node("Furnishings/BenchEast/LootSpawns/WorktopLeft")
	for i in range(20):
		_expect(point.roll_scene(rng_a) == point.roll_scene(rng_b), "Loot uses caller RNG deterministically")
	point.spawn_chance = 0
	_expect(point.roll_scene(rng_a) == null, "Zero-probability marker stays empty")
	point.spawn_chance = 1
	# Support test: real small props settle on all furniture spawn markers.
	var drops: Array[Node3D] = []
	for marker in small.find_children("*", "Marker3D", true, false):
		if marker is PoiLootPoint:
			var prop: Node3D = load("res://props/scrap.tscn").instantiate()
			world.add_child(prop)
			prop.global_transform = marker.global_transform
			drops.append(prop)
	for i in range(90):
		await physics_frame
	for prop in drops:
		_expect(prop.position.y > 0.25, "Loot marker has physical furniture support")
		prop.free()
	# Production player, continuous movement across both seams.
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(0, 0.05, 3)
	world.add_child(player)
	Input.action_press("move_forward")
	for i in range(420):
		await physics_frame
	Input.action_release("move_forward")
	var capsule: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	var feet: float = player.position.y + player.get_node("CollisionShape3D").position.y - capsule.height * 0.5
	_expect(player.position.z < -27 and absf(feet) < 0.05, "Player traverses small room, corridor and hall without falling or snagging: " + str(player.position))
	player.position = hall.position + Vector3(0, 0.05, 0)
	player.rotation.y = -PI / 2
	player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for i in range(150):
		await physics_frame
	Input.action_release("move_forward")
	_expect(player.position.x > 11.0, "Player passes east door and nearby furniture into rotated room: " + str(player.position))
	# Visual swap must not remove support/collision or sockets.
	small.get_node("Visuals").free()
	_expect(small.get_socket(&"south") != null and small.has_node("Collision/Floor"), "Replacing Visuals preserves socket and collision layers")
	var exterior: Node3D = load("res://world/poi_kit/exteriors/service_entrance.tscn").instantiate()
	exterior.position.x = 40
	world.add_child(exterior)
	var requests: Array = []
	exterior.get_node("Entrance").entry_requested.connect(func(actor: Node3D, id: StringName): requests.append([actor, id]))
	player.position = exterior.position + Vector3(0, 0.05, 7)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	for i in range(3):
		await physics_frame
	Input.action_press("interact")
	for i in range(12):
		await physics_frame
	Input.action_release("interact")
	for i in range(36):
		await physics_frame
	_expect(requests.size() == 1 and requests[0][0] == player, "Real interaction ray reaches entrance and emits one request")
	player.enter_ui_mode()
	exterior.get_node("Entrance").interact(player)
	_expect(requests.size() == 1, "UI mode cannot activate entrance")
	player.exit_ui_mode()
	world.free()
	if failures.is_empty():
		print("PASS: POI asset contracts, rotated connections, furniture loot support, player traversal and entrance")
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

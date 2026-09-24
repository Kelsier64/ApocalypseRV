extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for def in InteriorLayout.PROFILE.rooms:
		var room: PoiRoom = def.scene.instantiate()
		check(room.validate().is_empty(), "Authored room " + str(def.id))
		check(room.find_children("*", "RigidBody3D", true, false).is_empty(), "No automatic loot")
		room.free()
	var small: PoiRoom = InteriorLayout.PROFILE.room("small_01").scene.instantiate()
	# Moving an authoring layer must not silently change the generator's socket pose.
	small.get_node("DoorSockets").position.x = 1.25
	for socket in small.get_node("DoorSockets").get_children(): socket.position.x -= 1.25
	check(small.validate().is_empty() and small.socket_transform(small.get_socket(&"north")).origin.is_equal_approx(Vector3(0,0,-3)), "Socket transform includes its authoring layer")
	var corridor: PoiRoom = InteriorLayout.PROFILE.room("corridor_01").scene.instantiate()
	var hall: PoiRoom = InteriorLayout.PROFILE.room("hall_01").scene.instantiate()
	for room in [small,corridor,hall]: world.add_child(room)
	check(corridor.connect_to(&"south", small.get_socket(&"north")),"Connect short room to long corridor")
	check(hall.connect_to(&"south", corridor.get_socket(&"north")),"Connect different-size hall")
	check(hall.position.is_equal_approx(Vector3(0,0,-24)),"Socket-derived distance")
	var rotated: PoiRoom = InteriorLayout.PROFILE.room("small_01").scene.instantiate()
	world.add_child(rotated)
	check(rotated.connect_to(&"south",hall.get_socket(&"east")),"Quarter-turn connection")
	check(rotated.get_socket(&"south").global_position.distance_to(hall.get_socket(&"east").global_position)<0.001,"Door origins coincide")
	var original := rotated.transform
	rotated.get_socket(&"south").opening.x = 2
	check(not rotated.connect_to(&"south",hall.get_socket(&"east")) and rotated.transform == original,"Incompatible doors leave placement unchanged")
	for id in ["shelf","workbench","cabinet"]:
		var furniture: PoiFurniture = load("res://world/poi_kit/furniture/%s.tscn" % id).instantiate()
		check(furniture.validate().is_empty(),"Shared outdoor furniture remains valid")
		furniture.free()
	var player: CharacterBody3D = preload("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(0,0.05,1.5)
	Input.action_press("move_forward")
	for i in 420:
		await physics_frame
		if player.position.z < -27: break
	Input.action_release("move_forward")
	check(player.position.z < -26 and player.position.y > -0.3,"Real player crosses two seams without snagging: " + str(player.position))
	var assembler := PoiInterior.new()
	assembler._seal(small, small.get_socket(&"north"))
	check(small.get_node("Collision/Sealed_north").global_transform.is_equal_approx(small.get_socket(&"north").global_transform), "Sealed wall uses the same full socket pose")
	assembler.free()
	small.get_node("Visuals").free()
	check(small.has_node("Collision") and small.get_socket(&"north") != null,"Replaceable visuals preserve collisions/sockets")
	check(not small.validate().is_empty(), "Missing visuals report authoring errors without crashing")
	world.free()
	if failures.is_empty(): print("PASS: bunker authoring, dimensions, rotated interfaces, shared furniture and real player seams")
	quit(0 if failures.is_empty() else 1)

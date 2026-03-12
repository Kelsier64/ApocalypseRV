extends Node3D
class_name BuildingGenerator

const BASE_UNIT: float = 9.0

@export var max_rooms: int = 20
@export var seed_value: int = -1  # -1 = random

# Occupancy grid: Dictionary[Vector3i, bool]
var occupied_cells: Dictionary = {}
var room_count: int = 0

# Room definitions: scene path, grid_size, doors
# Doors format: {"wall": String, "grid_offset": Vector3i}
var room_defs: Array = []

func _ready():
	_build_room_defs()
	
	if seed_value >= 0:
		seed(seed_value)
	
	generate()

func _build_room_defs():
	room_defs = []
	var path = "res://world/building/rooms/"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				var scene_path = path + file_name
				var scene = load(scene_path)
				if scene:
					var instance = scene.instantiate()
					if "weight" in instance and instance.weight > 0.0:
						room_defs.append({
							"scene": scene_path,
							"name": instance.room_name,
							"grid_size": instance.grid_size,
							"weight": instance.weight,
							"doors": instance.doors.duplicate(true)
						})
					instance.queue_free()
			file_name = dir.get_next()


# --- OCCUPANCY GRID ---
func can_place_room(origin: Vector3i, size: Vector3i) -> bool:
	for x in range(size.x):
		for y in range(size.y):
			for z in range(size.z):
				if occupied_cells.has(origin + Vector3i(x, y, z)):
					return false
	return true

func reserve_cells(origin: Vector3i, size: Vector3i):
	for x in range(size.x):
		for y in range(size.y):
			for z in range(size.z):
				occupied_cells[origin + Vector3i(x, y, z)] = true

# --- GENERATION ---
func generate():
	occupied_cells.clear()
	room_count = 0
	
	# 1. Place the Elevator at grid origin (0,0,0) — occupies 1x4x1 cells (36m tall)
	var elevator_origin = Vector3i(0, 0, 0)
	var elevator_size = Vector3i(1, 4, 1)
	reserve_cells(elevator_origin, elevator_size)
	
	var elevator_scene = load("res://world/building/rooms/elevator.tscn")
	if elevator_scene:
		var elevator = elevator_scene.instantiate()
		elevator.name = "Elevator"
		elevator.position = Vector3(elevator_origin.x, elevator_origin.y, elevator_origin.z) * BASE_UNIT
		add_child(elevator)
	
	room_count += 1
	
	# 2. The top of the elevator is at grid Y=3 (27m up = 36m - 9m for the top cell).
	#    Rooms expand from the elevator's top-level doors.
	#    The top occupies grid cell (0, 3, 0).
	var top_cell = Vector3i(0, 3, 0)
	var open_doors: Array = [
		{"wall": "south", "source_cell": top_cell},
		{"wall": "north", "source_cell": top_cell},
		{"wall": "east", "source_cell": top_cell},
		{"wall": "west", "source_cell": top_cell},
	]
	
	open_doors.shuffle()
	
	var doors_to_seal: Array = []
	
	# 3. BFS expansion
	while open_doors.size() > 0 and room_count < max_rooms:
		var door_info = open_doors.pop_front()
		
		var source_cell: Vector3i = door_info["source_cell"]
		var target_cell = _get_target_cell(source_cell, door_info["wall"])
		
		# Skip if already occupied (and add to seal list)
		if occupied_cells.has(target_cell):
			doors_to_seal.append(door_info)
			continue
		
		# Find a room with a matching door on the opposite wall
		var needed_wall = _opposite_wall(door_info["wall"])
		var placed = false
		
		# Gather all valid placement candidates (template + specific door)
		var candidates: Array = []
		for def in room_defs:
			for door in def["doors"]:
				if door["wall"] == needed_wall:
					candidates.append({
						"def": def,
						"door": door,
						# Weighted random shuffle using the random key technique
						"score": pow(randf(), 1.0 / def.get("weight", 1.0))
					})
		
		# Sort candidates by score descending (higher weight = prioritized)
		candidates.sort_custom(func(a, b): return a["score"] > b["score"])
		
		# Try candidates until one fits
		for candidate in candidates:
			var def = candidate["def"]
			var matching_door = candidate["door"]
			
			var door_offset: Vector3i = matching_door.get("grid_offset", Vector3i.ZERO)
			var room_origin: Vector3i = target_cell - door_offset
			var grid_size: Vector3i = def["grid_size"]
			
			if can_place_room(room_origin, grid_size):
				reserve_cells(room_origin, grid_size)
				
				var scene = load(def["scene"])
				if scene:
					var room = scene.instantiate()
					room.name = def["name"].replace(" ", "_") + "_" + str(room_count)
					room.position = Vector3(room_origin.x, room_origin.y, room_origin.z) * BASE_UNIT
					add_child(room)
				
				room_count += 1
				
				for new_door in def["doors"]:
					var new_offset: Vector3i = new_door.get("grid_offset", Vector3i.ZERO)
					if new_door["wall"] == needed_wall and new_offset == door_offset:
						continue
					
					var new_source_cell = room_origin + new_offset
					open_doors.append({
						"wall": new_door["wall"],
						"source_cell": new_source_cell
					})
				
				open_doors.shuffle()
				placed = true
				break
		
		if not placed:
			doors_to_seal.append(door_info)
	
	for door in open_doors:
		doors_to_seal.append(door)
	
	# 4. Seal any remaining open doors
	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.35, 0.35, 0.35)
	
	for door_info in doors_to_seal:
		var cell: Vector3i = door_info["source_cell"]
		var wall_dir = door_info["wall"]
		
		# Spawn a block to seal the door opening
		var sealer = CSGBox3D.new()
		sealer.name = "DoorSeal_" + wall_dir
		sealer.use_collision = true
		sealer.material = wall_mat
		
		# Size to fully cover a 3x3.5 door
		if wall_dir == "north" or wall_dir == "south":
			sealer.size = Vector3(3.2, 3.7, 0.6)
		else:
			sealer.size = Vector3(0.6, 3.7, 3.2)
			
		# Position logic: Center of the giving grid cell, moved to the edge 
		# Cell world center is (cell.x + 0.5)*9, Y, (cell.z + 0.5)*9
		var cx = (cell.x + 0.5) * BASE_UNIT
		var cy = cell.y * BASE_UNIT + 0.5 + 3.5 / 2.0  # Floor + half door height
		var cz = (cell.z + 0.5) * BASE_UNIT
		
		var offset = BASE_UNIT / 2.0
		match wall_dir:
			"north": cz -= offset
			"south": cz += offset
			"east":  cx += offset
			"west":  cx -= offset
			
		sealer.position = Vector3(cx, cy, cz)
		add_child(sealer)

func _get_target_cell(cell: Vector3i, wall: String) -> Vector3i:
	match wall:
		"north": return cell + Vector3i(0, 0, -1)
		"south": return cell + Vector3i(0, 0, 1)
		"east":  return cell + Vector3i(1, 0, 0)
		"west":  return cell + Vector3i(-1, 0, 0)
	return cell

func _opposite_wall(wall: String) -> String:
	match wall:
		"north": return "south"
		"south": return "north"
		"east": return "west"
		"west": return "east"
	return ""

func _find_matching_door(def: Dictionary, needed_wall: String):
	for door in def["doors"]:
		if door["wall"] == needed_wall:
			return door
	return null

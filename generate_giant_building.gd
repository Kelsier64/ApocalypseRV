extends SceneTree

## Giant Building Generator
## Generates a giant building shell with narrow elevator base and wide residential top.
## Run: godot --headless -s generate_giant_building.gd

# === Building Parameters ===
const FLOOR_HEIGHT := 3.0
const WALL_THICKNESS := 0.5
const FLOOR_SLAB_THICKNESS := 0.3

# Elevator shaft (bottom)
const ELEVATOR_WIDTH := 10.0
const ELEVATOR_DEPTH := 10.0
const ELEVATOR_FLOORS := 5
const ELEVATOR_HEIGHT := ELEVATOR_FLOORS * FLOOR_HEIGHT  # 15m

# Residential block (top)
const RESIDENTIAL_WIDTH := 30.0
const RESIDENTIAL_DEPTH := 30.0
const RESIDENTIAL_FLOORS := 20
const RESIDENTIAL_HEIGHT := RESIDENTIAL_FLOORS * FLOOR_HEIGHT  # 60m

# Colors
const COLOR_EXTERIOR := Color(0.6, 0.6, 0.62, 1.0)
const COLOR_FLOOR_SLAB := Color(0.35, 0.35, 0.37, 1.0)
const COLOR_TRANSITION := Color(0.5, 0.5, 0.52, 1.0)


func _init() -> void:
	var scene_root := Node3D.new()
	scene_root.name = "GiantBuilding"

	# --- Elevator Shaft ---
	_build_elevator_shaft(scene_root)

	# --- Transition structure ---
	_build_transition(scene_root)

	# --- Residential Block ---
	_build_residential_block(scene_root)

	# --- Save scene ---
	var packed_scene := PackedScene.new()
	packed_scene.pack(scene_root)
	var err := ResourceSaver.save(packed_scene, "res://world/giant_building.tscn")
	if err == OK:
		print("SUCCESS: Scene saved to res://world/giant_building.tscn")
	else:
		print("FAILED: Could not save scene, error: ", err)

	scene_root.queue_free()
	quit()


func _build_elevator_shaft(parent: Node3D) -> void:
	# Outer shell
	var shaft := CSGBox3D.new()
	shaft.name = "ElevatorShaft"
	shaft.size = Vector3(ELEVATOR_WIDTH, ELEVATOR_HEIGHT, ELEVATOR_DEPTH)
	shaft.transform.origin = Vector3(0, ELEVATOR_HEIGHT / 2.0, 0)
	shaft.use_collision = true
	shaft.material = _create_material(COLOR_EXTERIOR)
	parent.add_child(shaft)
	shaft.owner = parent

	# Hollow interior
	var hollow := CSGBox3D.new()
	hollow.name = "ElevatorShaftHollow"
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	hollow.size = Vector3(
		ELEVATOR_WIDTH - WALL_THICKNESS * 2,
		ELEVATOR_HEIGHT - WALL_THICKNESS,
		ELEVATOR_DEPTH - WALL_THICKNESS * 2
	)
	hollow.transform.origin = Vector3(0, WALL_THICKNESS / 2.0, 0)
	shaft.add_child(hollow)
	hollow.owner = parent


func _build_transition(parent: Node3D) -> void:
	# Slab at the junction between elevator and residential
	var transition := CSGBox3D.new()
	transition.name = "Transition"
	transition.size = Vector3(RESIDENTIAL_WIDTH, 1.0, RESIDENTIAL_DEPTH)
	transition.transform.origin = Vector3(0, ELEVATOR_HEIGHT + 0.5, 0)
	transition.use_collision = true
	transition.material = _create_material(COLOR_TRANSITION)
	parent.add_child(transition)
	transition.owner = parent


func _build_residential_block(parent: Node3D) -> void:
	var base_y := ELEVATOR_HEIGHT + 1.0  # above transition slab

	# Outer shell
	var block := CSGBox3D.new()
	block.name = "ResidentialBlock"
	block.size = Vector3(RESIDENTIAL_WIDTH, RESIDENTIAL_HEIGHT, RESIDENTIAL_DEPTH)
	block.transform.origin = Vector3(0, base_y + RESIDENTIAL_HEIGHT / 2.0, 0)
	block.use_collision = true
	block.material = _create_material(COLOR_EXTERIOR)
	parent.add_child(block)
	block.owner = parent

	# Hollow interior
	var hollow := CSGBox3D.new()
	hollow.name = "ResidentialHollow"
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	hollow.size = Vector3(
		RESIDENTIAL_WIDTH - WALL_THICKNESS * 2,
		RESIDENTIAL_HEIGHT - WALL_THICKNESS,
		RESIDENTIAL_DEPTH - WALL_THICKNESS * 2
	)
	hollow.transform.origin = Vector3(0, WALL_THICKNESS / 2.0, 0)
	block.add_child(hollow)
	hollow.owner = parent

	# Floor slabs for each story
	var floor_mat := _create_material(COLOR_FLOOR_SLAB)
	var slab_size := Vector3(
		RESIDENTIAL_WIDTH - WALL_THICKNESS * 2 - 0.2,
		FLOOR_SLAB_THICKNESS,
		RESIDENTIAL_DEPTH - WALL_THICKNESS * 2 - 0.2
	)

	for i in range(1, RESIDENTIAL_FLOORS):
		var slab := CSGBox3D.new()
		slab.name = "Floor_%d" % (i + 1)
		# Position relative to block center
		var floor_y_in_block := -RESIDENTIAL_HEIGHT / 2.0 + i * FLOOR_HEIGHT
		slab.transform.origin = Vector3(0, floor_y_in_block, 0)
		slab.size = slab_size
		slab.material = floor_mat
		block.add_child(slab)
		slab.owner = parent


func _create_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat

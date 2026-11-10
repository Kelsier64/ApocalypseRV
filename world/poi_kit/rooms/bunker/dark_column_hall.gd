@tool
extends "res://world/megashelter/megashelter_room.gd"
## The underside of the crossbeams sets the hall's 12 m clear height.

const GRID_SPACING := 6.0
const CLEAR_UNDER_BEAM := 12.0
const WALL_DEPTH := 0.30

func _build() -> void:
	if _built: return
	_built = true
	_prepare_room()
	var half := footprint * 0.5
	_box(Vector3(0, -0.125, 0), Vector3(footprint.x, 0.25, footprint.y), 0, true)
	_box(Vector3(0, clear_height + 0.125, 0), Vector3(footprint.x, 0.25, footprint.y), 0, true)
	_box(Vector3(0, clear_height * 0.5, -half.y + WALL_DEPTH * 0.5), Vector3(footprint.x, clear_height, WALL_DEPTH), 0, true)
	for side: float in [-1.0, 1.0]:
		var x := side * (half.x - WALL_DEPTH * 0.5)
		_box(Vector3(x, clear_height * 0.5, 0), Vector3(WALL_DEPTH, clear_height, footprint.y - 2.0 * WALL_DEPTH), 0, true)
	_entry_wall()
	for row in 4:
		var z := (row - 1.5) * GRID_SPACING
		var beam_depth := clear_height - CLEAR_UNDER_BEAM
		_box(Vector3(0, CLEAR_UNDER_BEAM + beam_depth * 0.5, z), Vector3(footprint.x - 2.0 * WALL_DEPTH, beam_depth, 1.1), 0, true)
		for column in 5:
			var x := (column - 2) * GRID_SPACING
			_piece(Vector3(x, CLEAR_UNDER_BEAM * 0.5, z), Vector3(2.0, CLEAR_UNDER_BEAM, 2.0), 0, "bevel", true)
		# Saw cuts in the slab keep the floor from reading as a single plane.
		_box(Vector3(0, 0.003, z + GRID_SPACING * 0.5), Vector3(footprint.x - 2.0 * WALL_DEPTH, 0.006, 0.018), 4)
	_finish_batches()
	_batches.clear()

func _entry_wall() -> void:
	var socket := get_socket(&"return")
	var pose := socket_transform(socket)
	var half := footprint.x * 0.5
	var left := pose.origin.x - socket.opening.x * 0.5
	var right := pose.origin.x + socket.opening.x * 0.5
	var wall_z := pose.origin.z - WALL_DEPTH * 0.5
	_box(Vector3((left - half) * 0.5, clear_height * 0.5, wall_z), Vector3(left + half, clear_height, WALL_DEPTH), 0, true)
	_box(Vector3((right + half) * 0.5, clear_height * 0.5, wall_z), Vector3(half - right, clear_height, WALL_DEPTH), 0, true)
	_box(Vector3(pose.origin.x, (socket.opening.y + clear_height) * 0.5, wall_z), Vector3(socket.opening.x, clear_height - socket.opening.y, WALL_DEPTH), 0, true)
	_model(_room_visuals, "ReturnDoor", pose * Transform3D(Basis.IDENTITY, Vector3(0, 0, WALL_DEPTH)), FITTINGS.pedestrian_door())

@tool
extends PoiRoom
## Authored structural kit; generated children are disposable, scene properties
## and the existing furniture wrappers remain the editing surface.
@export var function_id := "reception"
var _built := false
var _batches: Array[MegashelterKit.Batch] = []
var _room_visuals: Node3D
var _room_collision: StaticBody3D
var _furnishings: Node3D
const SURFACE = preload("res://world/megashelter/megashelter_surface.gdshader")

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED: _build()

func _ready() -> void:
	_build()

func _build() -> void:
	if _built: return
	_built = true
	for layer in ["Visuals", "DoorSockets", "Furnishings", "Walkway"]:
		var node := Node3D.new()
		node.name = layer
		add_child(node)
	_room_visuals = get_node("Visuals")
	_furnishings = get_node("Furnishings")
	_room_collision = StaticBody3D.new()
	_room_collision.name = "Collision"
	_room_collision.collision_layer = 1
	_room_collision.collision_mask = 0
	add_child(_room_collision)
	for i in 3:
		var batch := MegashelterKit.Batch.new()
		batch.set_appearance(str(room_id).hash(), clear_height)
		_batches.append(batch)
	var half := footprint * 0.5
	_box(Vector3(0, -0.125, 0), Vector3(footprint.x, 0.25, footprint.y), 0, true)
	# Separate ceiling mesh permits the preview cutaway without deleting collision.
	var ceiling := MeshInstance3D.new()
	ceiling.name = "CeilingSlab"
	var slab := BoxMesh.new()
	slab.size = Vector3(footprint.x, 0.25, footprint.y)
	# The exterior surface uses vertex alpha as authored damage. Primitive
	# BoxMesh defaults to alpha=1, which would expose aggregate everywhere.
	var ceiling_batch := MegashelterKit.Batch.new()
	ceiling_batch.set_appearance(str(room_id).hash(), clear_height)
	ceiling_batch.add_box(Transform3D.IDENTITY, Vector3.ZERO, slab.size, 0.9)
	ceiling.mesh = ceiling_batch.mesh()
	ceiling.position.y = clear_height + 0.125
	ceiling.material_override = _material(0)
	_room_visuals.add_child(ceiling)
	_collider(ceiling.position, slab.size)
	var sides := ["north"] if function_id == "reception" else ["north", "east", "south", "west"]
	for side in 4:
		var side_name: String = ["north", "east", "south", "west"][side]
		var angle := -PI * 0.5 * side
		var span := footprint.x if side % 2 == 0 else footprint.y
		var depth := half.y if side % 2 == 0 else half.x
		var pose := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
		pose.origin = pose.basis * Vector3(0, 0, -depth)
		var opening := side_name in sides
		# The short spine's side openings are offset toward its far end so
		# the largest lateral rooms meet the hall without intersecting it.
		var offset := 2.0 * (-1 if side == 1 else 1) if function_id == "service_spine" and side % 2 == 1 else 0.0
		_wall(pose, span, opening, offset)
		if opening:
			var socket := PoiDoorSocket.new()
			socket.name = side_name.capitalize()
			socket.socket_id = StringName(side_name)
			socket.interface_type = &"shelter_280"
			socket.opening = Vector2(2.8, 3.0)
			socket.transform = pose * Transform3D(Basis.IDENTITY, Vector3(offset, 0, 0))
			get_node("DoorSockets").add_child(socket)
			for x in [-1.49, 1.49]:
				var trim := MeshInstance3D.new()
				trim.name = "DoorTrim_%d_%s" % [side, str(x)]
				var mesh := BoxMesh.new()
				mesh.size = Vector3(0.16, 3.12, 0.34)
				trim.mesh = mesh
				trim.material_override = _material(2)
				trim.transform = pose * Transform3D(Basis.IDENTITY, Vector3(offset + x, 1.56, 0.19))
				_room_visuals.add_child(trim)
				socket.frame_nodes.append(socket.get_path_to(trim))
			var lintel := MeshInstance3D.new()
			lintel.name = "DoorHeader_%d" % side
			var header := BoxMesh.new()
			header.size = Vector3(3.14, 0.17, 0.34)
			lintel.mesh = header
			lintel.material_override = _material(2)
			lintel.transform = pose * Transform3D(Basis.IDENTITY, Vector3(offset, 3.08, 0.19))
			_room_visuals.add_child(lintel)
			socket.frame_nodes.append(socket.get_path_to(lintel))
		_detail_wall(pose, span, side)
	# Thick perimeter piers and downstand beams leave the centre of every door clear.
	for x in [-half.x + 0.47, half.x - 0.47]:
		for z in [-half.y + 0.47, half.y - 0.47]:
			_piece(Vector3(x, clear_height * 0.5, z), Vector3(0.62, clear_height, 0.62), 0, "bevel", true)
	for z in [-half.y + 0.5, half.y - 0.5]:
		_piece(Vector3(0, clear_height - 0.16, z), Vector3(footprint.x - 0.5, 0.32, 0.7), 0, "bevel", true)
	_ceiling_services()
	for x in range(-floori(half.x) + 4, floori(half.x), 4):
		_box(Vector3(x, 0.003, 0), Vector3(0.012, 0.004, footprint.y - 0.6), 2)
	for z in range(-floori(half.y) + 4, floori(half.y), 4):
		_box(Vector3(0, 0.003, z), Vector3(footprint.x - 0.6, 0.004, 0.012), 2)
	_furniture()
	_finish_batches()
	var anchor := Marker3D.new()
	anchor.name = "Anchor"
	get_node("Walkway").add_child(anchor)
	if function_id == "reception":
		var spawn := Marker3D.new()
		spawn.name = "Spawn"
		spawn.position = Vector3(0, 0.08, half.y - 2.6)
		get_node("Walkway").add_child(spawn)
		var exit := Marker3D.new()
		exit.name = "Exit"
		exit.position = Vector3(0, 0, half.y - 0.36)
		exit.rotation.y = PI
		get_node("Walkway").add_child(exit)
	_batches.clear()

func _wall(pose: Transform3D, span: float, opening: bool, offset: float) -> void:
	var pieces: Array[Vector3] = []
	var centres: Array[Vector3] = []
	if opening:
		var left := span * 0.5 + offset - 1.4
		var right := span * 0.5 - offset - 1.4
		pieces.assign([Vector3(left, clear_height, 0.24), Vector3(right, clear_height, 0.24), Vector3(2.8, clear_height - 3, 0.24)])
		centres.assign([Vector3(-span*0.5 + left*0.5, clear_height*0.5, 0.12), Vector3(span*0.5 - right*0.5, clear_height*0.5, 0.12), Vector3(offset, (clear_height + 3)*0.5, 0.12)])
	else:
		pieces.append(Vector3(span, clear_height, 0.24))
		centres.append(Vector3(0, clear_height * 0.5, 0.12))
	for i in pieces.size():
		_batches[0].add_box(pose, centres[i], pieces[i], 0.93)
		_collider(pose * centres[i], pieces[i], pose.basis)
		# Worn lower protective coating has real thickness and stops at openings.
		if pieces[i].y < clear_height - 0.01: continue
		_batches[1].add_box(pose, Vector3(centres[i].x, 0.8, 0.25), Vector3(pieces[i].x, 1.6, 0.022), 0.91)
		_batches[2].add_box(pose, Vector3(centres[i].x, 0.095, 0.268), Vector3(pieces[i].x, 0.19, 0.032), 0.74)

func _detail_wall(pose: Transform3D, span: float, side: int) -> void:
	# One service bay per wall, always outside the central doorway approach.
	if span < 7: return
	var x := -span * 0.5 + 1.65
	for h in [2.15, 2.42]:
		_piece_local(pose, Vector3(x, h, 0.34), Vector3(1.55, 0.065, 0.065), 2, "cylinder")
	_piece_local(pose, Vector3(x - 0.68, 1.5, 0.34), Vector3(0.065, 1.9, 0.065), 2, "cylinder")
	for h in [0.65, 1.55, 2.38]:
		_piece_local(pose, Vector3(x - 0.68, h, 0.32), Vector3(0.15, 0.07, 0.11), 2)
	_piece_local(pose, Vector3(x + 0.45, 1.35, 0.34), Vector3(0.65, 0.78, 0.18), 2, "bevel")
	_piece_local(pose, Vector3(x + 0.45, 1.35, 0.44), Vector3(0.53, 0.62, 0.025), 2)
	for h in [1.15, 1.35, 1.55]:
		_piece_local(pose, Vector3(x + 0.45, h, 0.46), Vector3(0.37, 0.026, 0.025), 2)
	# Recessed damage: dark mineral bed, fractured aggregate rim and separate rods.
	if side % 2 == 0:
		var p := Vector3(span*0.5 - 1.6, 0.59, 0.26)
		_piece_local(pose, p, Vector3(1.5, 0.85, 0.025), 2, "spall")
		for i in 5:
			var xx := -0.58 + i*0.29
			_piece_local(pose, p + Vector3(xx, 0.02, 0.06), Vector3(0.025, 0.7, 0.025), 2, "cylinder")
		for h in [-0.22, 0.18]: _piece_local(pose, p + Vector3(0, h, 0.055), Vector3(1.35, 0.025, 0.025), 2, "cylinder")
		for i in 7:
			var xx := -0.72 + i*0.24
			_piece_local(pose, p + Vector3(xx, 0.38 + sin(i*2.1)*0.08, 0.04), Vector3(0.34, 0.22, 0.12), 0, "chip")
		for i in 5:
			_piece_local(pose, Vector3(p.x-0.48+i*0.24, 0.04, 0.42+0.13*(i%3)), Vector3(0.21+0.05*(i%2), 0.08, 0.23), 0, "chip")

func _ceiling_services() -> void:
	var half := footprint * 0.5
	var z := -half.y + 1.1
	_piece(Vector3(0, clear_height - 0.5, z), Vector3(maxf(1, footprint.x - 1.3), 0.34, 0.58), 2)
	for x in range(-floori(half.x) + 2, floori(half.x) - 1, 3):
		_piece(Vector3(x, clear_height - 0.5, z), Vector3(0.055, 0.4, 0.65), 2)
		_piece(Vector3(x, clear_height - 0.15, z), Vector3(0.045, 0.45, 0.045), 2, "cylinder")
	var positions: Array[Vector3] = [Vector3(0, clear_height - 0.27, 0)]
	if function_id == "common_hall": positions.assign([Vector3(-4, clear_height - 0.27, 0), Vector3(4, clear_height - 0.27, 0)])
	for i in positions.size():
		var at: Vector3 = positions[i]
		_piece(at, Vector3(1.7, 0.14, 0.42), 2)
		var lamp := MeshInstance3D.new()
		lamp.name = "LampTube%d" % i
		var tube := BoxMesh.new()
		tube.size = Vector3(1.4, 0.035, 0.26)
		lamp.mesh = tube
		lamp.position = at - Vector3(0, 0.08, 0)
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color("a4ad99")
		glow.emission_enabled = true
		glow.emission = Color("a4ad99")
		glow.emission_energy_multiplier = 1.6
		lamp.material_override = glow
		_room_visuals.add_child(lamp)
		var light := OmniLight3D.new()
		light.name = "EmergencyLight%d" % i
		light.position = at - Vector3(0, 0.35, 0)
		light.light_color = Color("bbc5b1")
		light.light_energy = 2.3
		light.omni_range = 10 if function_id == "common_hall" else 7.5
		light.shadow_enabled = true
		_furnishings.add_child(light)

func _furniture() -> void:
	var hx := footprint.x * 0.5
	var hz := footprint.y * 0.5
	match function_id:
		"reception":
			_table(Vector3(-hx + 1.4, 0, -0.9), Vector2(1.5, 3.0))
			_asset("locker", Vector3(hx - 0.8, 0, -1.4))
			_asset("locker", Vector3(hx - 0.8, 0, -2.15))
			# Exterior-sized shelter door is represented here by a sealed steel leaf.
			_box(Vector3(0, 1.55, hz - 0.28), Vector3(3.6, 3.1, 0.12), 2)
			_piece(Vector3(0, 1.25, hz-0.38), Vector3(1.2, 0.08, 0.1), 2)
			_sign("RECEPTION", Vector3(-hx + 0.29, 2.65, 0), PI*0.5)
		"common_hall":
			for x in [-hx + 1.1, hx - 1.1]:
				_bench(Vector3(x, 0, -hz + 3.5))
				_bench(Vector3(x, 0, hz - 3.5))
			# Structural aisle uses four piers, with a broad clear central route.
			for x in [-hx * 0.5, hx * 0.5]:
				for z in [-hz * 0.5, hz * 0.5]:
					_piece(Vector3(x, clear_height*0.5, z), Vector3(0.72, clear_height, 0.72), 0, "bevel", true)
			_sign("COMMON HALL", Vector3(-hx+0.29, 2.65, 0), PI*0.5)
		"sleeping":
			for z in [-hz + 1.6, -hz + 3.2]: _asset("bunk_bed", Vector3(-hx + 1.6, 0, z))
			_asset("locker", Vector3(hx - 1.1, 0, -hz + 1.5))
			_asset("locker", Vector3(hx - 1.8, 0, -hz + 1.5))
		"medical":
			_asset("medical_cot", Vector3(-hx + 1.8, 0, -hz + 1.6))
			_asset("medical_cot", Vector3(-hx + 1.8, 0, -hz + 3.1))
			_asset("locker", Vector3(hx - 1.1, 0, -hz + 1.2))
			_table(Vector3(hx - 1.1, 0, -hz + 2.8), Vector2(1.2, 1.6))
		"storage":
			for z in [-hz + 1.4, -hz + 3.5]:
				_shelf(Vector3(-hx + 1.2, 0, z))
			_asset("locker", Vector3(hx - 1.1, 0, -hz + 1.5))
		"canteen":
			for z in [-hz + 2.1, hz - 2.1]:
				_table(Vector3(-hx + 2.4, 0, z), Vector2(2.8, 1.0))
				_bench(Vector3(-hx + 2.4, 0, z + 0.9), PI * 0.5)
			_table(Vector3(hx - 1.1, 0, -hz + 2.1), Vector2(1.2, 2.8))
		"services":
			_asset("filtration_pump", Vector3(-hx + 1.7, 0, -hz + 1.4))
			_asset("switchgear", Vector3(hx - 1.3, 0, -hz + 1.3))
			_asset("diesel_generator", Vector3(-hx + 2.2, 0, hz - 1.5))
		"sanitary":
			for z in [-hz + 1.6, -hz + 3.3]:
				_box(Vector3(-hx + 1.5, 0.5, z), Vector3(0.9, 1.0, 0.6), 0, true)
				_box(Vector3(-hx + 1.5, 1.0, z), Vector3(1.0, 0.1, 0.9), 1)
				_piece(Vector3(-hx + 1.5, 1.24, z-0.22), Vector3(0.045, 0.4, 0.045), 2, "cylinder")
			for z in [-hz + 1.0, -hz + 3.3]:
				_box(Vector3(hx - 1.7, 1.15, z), Vector3(2.6, 2.3, 0.08), 1, true)
			_box(Vector3(hx - 1.7, 0.35, -hz + 2.1), Vector3(0.6, 0.7, 0.8), 0, true)
	if function_id not in ["reception", "common_hall", "service_spine"]:
		_sign({"sleeping":"DORMITORY", "medical":"FIRST AID", "storage":"SUPPLIES", "canteen":"CANTEEN", "services":"PLANT ROOM", "sanitary":"WASHROOM"}[function_id], Vector3(2.65, 2.65, hz - 0.29), PI)

func _asset(kind: String, at: Vector3) -> void:
	var scene := load("res://world/poi_kit/furniture/bunker/%s_graybox.tscn" % kind) as PackedScene
	var asset := scene.instantiate() as Node3D
	asset.name = kind.capitalize() + str(_furnishings.get_child_count())
	asset.position = at
	_furnishings.add_child(asset)

func _table(at: Vector3, size: Vector2) -> void:
	_box(at + Vector3(0, 0.85, 0), Vector3(size.x, 0.12, size.y), 1, true)
	for x in [-size.x*0.4, size.x*0.4]:
		for z in [-size.y*0.4, size.y*0.4]: _piece(at+Vector3(x, 0.4, z), Vector3(0.07, 0.8, 0.07), 2)

func _bench(at: Vector3, angle: float = 0) -> void:
	var pose := Transform3D(Basis(Vector3.UP, angle), at)
	_piece_local(pose, Vector3(0, 0.45, 0), Vector3(0.55, 0.1, 2.5), 1)
	_piece_local(pose, Vector3(-0.24, 0.75, 0), Vector3(0.08, 0.5, 2.5), 1)
	for z in [-0.9, 0.9]: _piece_local(pose, Vector3(0, 0.22, z), Vector3(0.45, 0.44, 0.08), 2)
	_collider(at + Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 2.5), pose.basis)

func _shelf(at: Vector3) -> void:
	for x in [-0.8, 0.8]:
		for z in [-0.35, 0.35]: _piece(at+Vector3(x, 1.0, z), Vector3(0.06, 2.0, 0.06), 2)
	for y in [0.16, 0.8, 1.5, 1.95]: _box(at+Vector3(0, y, 0), Vector3(1.7, 0.055, 0.8), 2)
	_box(at+Vector3(0.23, 0.35, 0), Vector3(0.6, 0.3, 0.55), 1)
	_collider(at+Vector3(0, 1.0, 0), Vector3(1.7, 2.0, 0.8))

func _sign(text: String, at: Vector3, angle: float) -> void:
	var label := Label3D.new()
	label.name = "WallSign" + str(_room_visuals.get_child_count())
	label.text = text
	label.position = at
	label.rotation.y = angle
	label.font_size = 48
	label.pixel_size = 0.004
	label.modulate = Color("a0a494")
	label.no_depth_test = false
	_room_visuals.add_child(label)

func _box(at: Vector3, size: Vector3, material: int, solid := false) -> void:
	_batches[material].add_box(Transform3D.IDENTITY, at, size, 0.9)
	if solid: _collider(at, size)

func _piece(at: Vector3, size: Vector3, material: int, shape := "box", solid := false) -> void:
	_piece_local(Transform3D.IDENTITY, at, size, material, shape)
	if solid: _collider(at, size)

func _piece_local(pose: Transform3D, at: Vector3, size: Vector3, material: int, shape := "box") -> void:
	_batches[material].add_piece(pose, {"center": at, "size": size, "material": material, "shade": 0.92, "shape": shape, "bevel": 0.06, "steel_corrosion": 0.55, "chip_variant": int(at.x*37)})

func _collider(at: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.transform = Transform3D(basis, at)
	_room_collision.add_child(collision)

func _material(index: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("surface_kind", float(index))
	material.set_shader_parameter("base_color", [Color("858981"), Color("737e70"), Color("424b44")][index])
	material.set_shader_parameter("wear_seed", float(posmod(str(room_id).hash(), 10000)))
	return material

func _finish_batches() -> void:
	for i in _batches.size():
		if _batches[i].vertices.is_empty(): continue
		var visual := MeshInstance3D.new()
		visual.name = ["WallStructure", "PaintFinish", "SteelServices"][i]
		visual.mesh = _batches[i].mesh()
		visual.material_override = _material(i)
		_room_visuals.add_child(visual)

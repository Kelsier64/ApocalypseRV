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
var _materials: Dictionary = {}
const SURFACE = preload("res://world/megashelter/megashelter_surface.gdshader")
const FINISH = preload("res://world/megashelter/interior_finish.gdshader")
const FITTINGS = preload("res://world/megashelter/megashelter_interior_kit.gd")

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED: _build()

func _ready() -> void:
	_build()

func _prepare_room() -> void:
	for layer in ["Visuals", "DoorSockets", "Furnishings", "Walkway"]:
		if has_node(layer): continue
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
	for i in 7:
		var batch := MegashelterKit.Batch.new()
		batch.set_appearance(str(room_id).hash(), clear_height)
		_batches.append(batch)

func _build() -> void:
	if _built: return
	_built = true
	_prepare_room()
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
		_wall(pose, span, opening, offset, side)
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
		if function_id != "reception" or side != 2: _detail_wall(pose, span, side)
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
	_function_details()
	_finish_batches()
	var anchor := Marker3D.new()
	anchor.name = "Anchor"
	get_node("Walkway").add_child(anchor)
	if function_id == "reception":
		var spawn := Marker3D.new()
		spawn.name = "Spawn"
		spawn.position = Vector3(-0.95, 0.08, half.y - 2.05)
		get_node("Walkway").add_child(spawn)
		var exit := Marker3D.new()
		exit.name = "Exit"
		exit.position = Vector3(-0.95, 0, half.y - 0.82)
		exit.rotation.y = PI
		exit.set_meta("opening", Vector2(3.7, 3.03))
		get_node("Walkway").add_child(exit)
		var pedestrian := Marker3D.new()
		pedestrian.name = "PedestrianExit"
		pedestrian.position = Vector3(2.45, 0, half.y - 0.82)
		pedestrian.rotation.y = PI
		pedestrian.set_meta("opening", Vector2(0.94, 2.2))
		get_node("Walkway").add_child(pedestrian)
	_batches.clear()

func _wall(pose: Transform3D, span: float, opening: bool, offset: float, side: int) -> void:
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
	var damage := Rect2()
	if _damaged_side(side) and span >= 7:
		damage = Rect2(Vector2(span*0.5 - 2.45, 0.2), Vector2(1.6, 1.05))
	for i in pieces.size():
		var size: Vector3 = pieces[i]
		var centre: Vector3 = centres[i]
		var face := Rect2(Vector2(centre.x-size.x*0.5, centre.y-size.y*0.5), Vector2(size.x, size.y))
		# A continuous back retains a closed wall; front concrete and paint are
		# actually cut around the cavity instead of hiding it behind a decal.
		_batches[0].add_box(pose, Vector3(centre.x, centre.y, 0.04), Vector3(size.x, size.y, 0.08), 0.93)
		for rect: Rect2 in _subtract(face, damage):
			_batches[0].add_box(pose, Vector3(rect.get_center().x, rect.get_center().y, 0.16), Vector3(rect.size.x, rect.size.y, 0.16), 0.93)
		_collider(pose * centres[i], pieces[i], pose.basis)
		# Worn lower protective coating has real thickness and stops at openings.
		if pieces[i].y < clear_height - 0.01: continue
		var coat := Rect2(Vector2(centre.x-size.x*0.5, 0), Vector2(size.x, 1.6))
		for rect: Rect2 in _subtract(coat, damage):
			_batches[1].add_box(pose, Vector3(rect.get_center().x, rect.get_center().y, 0.252), Vector3(rect.size.x, rect.size.y, 0.024), 0.91)
		_batches[2].add_box(pose, Vector3(centres[i].x, 0.095, 0.268), Vector3(pieces[i].x, 0.19, 0.032), 0.74)
	if damage.has_area(): _cavity(pose, damage)

func _damaged_side(side: int) -> bool:
	return (function_id != "reception" or side != 2) and side == posmod(str(room_id).hash(), 4)

func _subtract(rect: Rect2, cut: Rect2) -> Array[Rect2]:
	if not cut.has_area() or not rect.intersects(cut): return [rect]
	var overlap := rect.intersection(cut)
	var result: Array[Rect2] = []
	for strip: Rect2 in [Rect2(rect.position, Vector2(overlap.position.x-rect.position.x, rect.size.y)),
		Rect2(Vector2(overlap.end.x, rect.position.y), Vector2(rect.end.x-overlap.end.x, rect.size.y)),
		Rect2(Vector2(overlap.position.x, rect.position.y), Vector2(overlap.size.x, overlap.position.y-rect.position.y)),
		Rect2(Vector2(overlap.position.x, overlap.end.y), Vector2(overlap.size.x, rect.end.y-overlap.end.y))]:
		if strip.size.x > 0.001 and strip.size.y > 0.001: result.append(strip)
	return result

func _cavity(pose: Transform3D, area: Rect2) -> void:
	var boundary: Array[Vector2] = [Vector2(-0.5,-0.5),Vector2(0,-0.5),Vector2(0.5,-0.5),Vector2(0.5,0),Vector2(0.5,0.5),Vector2(0,0.5),Vector2(-0.5,0.5),Vector2(-0.5,0)]
	var outer: Array[Vector2] = [Vector2(-0.49,-0.32),Vector2(-0.17,-0.49),Vector2(0.4,-0.42),Vector2(0.49,-0.04),Vector2(0.32,0.47),Vector2(-0.04,0.49),Vector2(-0.49,0.3),Vector2(-0.43,0.01)]
	var inner: Array[Vector2] = [Vector2(-0.35,-0.26),Vector2(-0.1,-0.39),Vector2(0.32,-0.32),Vector2(0.39,-0.01),Vector2(0.24,0.34),Vector2(-0.06,0.39),Vector2(-0.39,0.24),Vector2(-0.35,0.03)]
	var centre := Vector3(area.get_center().x, area.get_center().y, 0)
	var back: Array[Vector3] = []
	_batches[0]._damage = 1.0
	for i in outer.size():
		var next := (i+1)%outer.size()
		# Fill the rectangular construction cut back to an irregular fracture.
		# Matching local coordinates keep its coating continuous with the wall.
		var coat_a := Vector3(boundary[i].x*area.size.x,boundary[i].y*area.size.y,0.264)
		var coat_b := Vector3(boundary[next].x*area.size.x,boundary[next].y*area.size.y,0.264)
		var a := Vector3(outer[i].x*area.size.x, outer[i].y*area.size.y, 0.264)
		var b := Vector3(outer[next].x*area.size.x, outer[next].y*area.size.y, 0.264)
		_batches[1]._face(pose,centre,[coat_a,coat_b,b,a],Vector3.BACK,0.91)
		var c := Vector3(inner[next].x*area.size.x, inner[next].y*area.size.y, 0.1)
		var d := Vector3(inner[i].x*area.size.x, inner[i].y*area.size.y, 0.1)
		var normal := (b-a).cross(d-a).normalized()
		_batches[0]._face(pose, centre, [a,b,c,d], normal, 0.88)
		back.append(d)
	_batches[0]._face(pose, centre, back, Vector3.BACK, 0.76)
	_batches[0]._damage = 0.0
	var rods: Array[Dictionary] = []
	for i in 5:
		var x := centre.x-0.52+i*0.26
		FITTINGS.pipe(rods,Vector3(x,centre.y-0.34,0.15),Vector3(x,centre.y+0.15,0.15),0.0125)
		FITTINGS.pipe(rods,Vector3(x,centre.y+0.15,0.15),Vector3(x+0.045*(i%2),centre.y+0.37,0.17),0.0125)
	_append_pieces(pose,rods)
	for y in [-0.19, 0.16]: _piece_local(pose, Vector3(centre.x, centre.y+y, 0.145), Vector3(1.25, 0.025, 0.025), 2, "cylinder")
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(room_id)+":spall:"+str(pose.origin)).hash()
	for i in 7:
		var at := Vector3(centre.x+rng.randf_range(-0.75,0.75),0.025,rng.randf_range(0.32,0.9))
		var turn := Transform3D(Basis(Vector3.UP,rng.randf_range(-1.2,1.2)),at)
		_piece_local(pose*turn,Vector3.ZERO,Vector3(rng.randf_range(0.1,0.26),0.07,rng.randf_range(0.12,0.25)),0,"chip")

func _detail_wall(pose: Transform3D, span: float, side: int) -> void:
	if span < 7: return
	var variant := posmod((str(room_id)+":bay:%d"%side).hash(), 4)
	_append_pieces(pose, FITTINGS.wall_bay(span, clear_height, variant))

func _ceiling_services() -> void:
	var half := footprint * 0.5
	var z := -half.y + 1.1
	_piece(Vector3(0, clear_height - 0.5, z), Vector3(maxf(1, footprint.x - 1.3), 0.34, 0.58), 2)
	for x in range(-floori(half.x) + 2, floori(half.x) - 1, 3):
		_piece(Vector3(x, clear_height - 0.5, z), Vector3(0.055, 0.4, 0.65), 2)
		_piece(Vector3(x, clear_height - 0.15, z), Vector3(0.045, 0.45, 0.045), 2, "cylinder")
		var flange: Array[Dictionary] = []
		for y in [-0.19, 0.19]:
			for zz in [-0.32, 0.32]:
				FITTINGS.pipe(flange, Vector3(x-0.045, clear_height-0.5+y, z+zz), Vector3(x+0.045, clear_height-0.5+y, z+zz), 0.025)
		_append_pieces(Transform3D.IDENTITY, flange)
	var positions: Array[Vector3] = [Vector3(0, clear_height - 0.27, 0)]
	if function_id == "common_hall": positions.assign([Vector3(-4, clear_height - 0.27, 0), Vector3(4, clear_height - 0.27, 0)])
	for i in positions.size():
		var at: Vector3 = positions[i]
		_piece(at, Vector3(1.7, 0.14, 0.42), 2)
		for x in [-0.79, 0.79]:
			_piece(at+Vector3(x, -0.04, 0), Vector3(0.085, 0.12, 0.45), 2, "bevel")
		var wire: Array[Dictionary] = []
		FITTINGS.pipe(wire, at+Vector3(-0.65, 0.05, 0), Vector3(-0.65, clear_height-0.12, z), 0.012, 4)
		_append_pieces(Transform3D.IDENTITY, wire)
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
			_entrance_doors()
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
				_append_pieces(Transform3D(Basis(Vector3.UP, PI*0.5), Vector3(-hx+0.8, 0, z)), FITTINGS.sink())
				_collider(Vector3(-hx+0.8, 0.5, z), Vector3(0.8, 1, 1.0))
			for z in [-hz + 1.0, -hz + 3.3]:
				_box(Vector3(hx - 1.7, 1.15, z), Vector3(2.6, 2.3, 0.08), 1, true)
			_append_pieces(Transform3D(Basis(Vector3.UP, -PI*0.5), Vector3(hx-0.9, 0, -hz+2.1)), FITTINGS.toilet())
			_collider(Vector3(hx-0.9, 0.5, -hz+2.1), Vector3(0.8, 1, 0.6))
	if function_id not in ["reception", "common_hall", "service_spine"]:
		_sign({"sleeping":"DORMITORY", "medical":"FIRST AID", "storage":"SUPPLIES", "canteen":"CANTEEN", "services":"PLANT ROOM", "sanitary":"WASHROOM"}[function_id], Vector3(2.65, 2.65, hz - 0.29), PI)

func _asset(kind: String, at: Vector3) -> void:
	var scene := load("res://world/poi_kit/furniture/bunker/%s_graybox.tscn" % kind) as PackedScene
	var asset := scene.instantiate() as Node3D
	asset.name = kind.capitalize() + str(_furnishings.get_child_count())
	asset.position = at
	_furnishings.add_child(asset)

func _function_details() -> void:
	var hx := footprint.x*0.5
	var hz := footprint.y*0.5
	match function_id:
		"reception":
			# An abandoned registration desk: drawers, files and a few curled sheets.
			for z in [-1.6, -0.75]:
				_piece(Vector3(-hx+2.16, 0.65, z), Vector3(0.035, 0.26, 0.7), 1, "bevel")
				_piece(Vector3(-hx+2.2, 0.65, z), Vector3(0.06, 0.025, 0.2), 2)
			_papers(Vector3(-hx+1.5, 0.915, -1.4), 3)
			_piece(Vector3(-hx+1.5, 0.94, -0.3), Vector3(0.34, 0.035, 0.26), 5, "bevel")
			_notice_board(Transform3D(Basis(Vector3.UP, PI*0.5), Vector3(-hx+0.29, 2.05, 0.5)))
		"common_hall":
			_notice_board(Transform3D(Basis(Vector3.UP, PI*0.5), Vector3(-hx+0.29, 1.8, -hz+3.0)))
			# Drainage and loose grit remain against the wall, away from the aisle.
			_grate(Vector3(hx-0.85, 0.012, hz-1.3), Vector2(0.5, 1.4))
		"sleeping":
			for z in [-hz+1.6, -hz+3.2]:
				var hooks: Array[Dictionary] = []
				FITTINGS._plate(hooks, Vector3.ZERO, Vector2(1.1,0.12))
				for x in [-0.36, 0, 0.36]:
					FITTINGS.pipe(hooks, Vector3(x,0,0.03), Vector3(x,0,0.13), 0.014)
					FITTINGS.pipe(hooks, Vector3(x,0,0.13), Vector3(x,0.06,0.13), 0.014)
				_append_pieces(Transform3D(Basis(Vector3.UP, PI*0.5), Vector3(-hx+0.29, 2.2, z)), hooks)
		"medical":
			var services: Array[Dictionary] = []
			FITTINGS._plate(services, Vector3.ZERO, Vector2(1.65,0.24), 1)
			for x in [-0.54, 0, 0.54]:
				FITTINGS._plate(services, Vector3(x,0,0.04), Vector2(0.15,0.16))
				FITTINGS._bolt(services, Vector3(x,0,0.08), 0.035)
			_append_pieces(Transform3D(Basis(Vector3.UP, PI*0.5), Vector3(-hx+0.29, 1.45, -hz+2.35)), services)
			# A raised-lip instrument tray on the table, not another large prop.
			var at := Vector3(hx-1.1, 0.925, -hz+2.8)
			_piece(at, Vector3(0.5, 0.025, 0.34), 2, "bevel")
			for x in [-0.25, 0.25]: _piece(at+Vector3(x,0.04,0), Vector3(0.025,0.08,0.34),2)
			for z in [-0.17, 0.17]: _piece(at+Vector3(0,0.04,z), Vector3(0.5,0.08,0.025),2)
			_papers(at+Vector3(0,0.025,0), 2)
		"storage":
			for z in [-hz+1.4, -hz+3.5]:
				var bracing: Array[Dictionary] = []
				FITTINGS.pipe(bracing, Vector3(-0.79,0.2,-0.39), Vector3(0.79,1.88,-0.39),0.013)
				FITTINGS.pipe(bracing, Vector3(0.79,0.2,-0.39), Vector3(-0.79,1.88,-0.39),0.013)
				_append_pieces(Transform3D(Basis.IDENTITY, Vector3(-hx+1.2,0,z)), bracing)
				# Seams, a folded lid and straps distinguish the existing shelf boxes.
				var box_at := Vector3(-hx+1.43,0.5,z)
				_piece(box_at, Vector3(0.62,0.018,0.56),5)
				_piece(box_at+Vector3(0.06,0.012,0),Vector3(0.045,0.008,0.56),4)
				_piece(box_at+Vector3(0.06,-0.15,0.282),Vector3(0.045,0.3,0.008),4)
		"canteen":
			# Simple serving counter front, inset doors and a worn draining surface.
			var x := hx-1.1
			for z in [-hz+1.25,-hz+2.5]:
				_piece(Vector3(x-0.52,0.49,z), Vector3(0.06,0.62,1.1),1,"bevel")
				_piece(Vector3(x-0.57,0.55,z+0.3), Vector3(0.07,0.04,0.21),2)
			for i in 6:
				_piece(Vector3(x,0.908,-hz+2.75+i*0.08),Vector3(0.75,0.009,0.012),2)
			_papers(Vector3(-hx+2.3,0.915,-hz+2.1),1)
		"services":
			var manifold: Array[Dictionary] = []
			for i in 2:
				var x := -0.28+i*0.55
				FITTINGS.pipe(manifold, Vector3(x,0.2,0.35),Vector3(x,2.75,0.35),0.065)
				for y in [0.55,1.5,2.5]:
					FITTINGS._part(manifold,Vector3(x,y,0.35),Vector3(0.21,0.1,0.21),2,"cylinder")
					manifold[-1].axis = 1
				FITTINGS.pipe(manifold,Vector3(x,1.35,0.35),Vector3(x,1.35,0.63),0.04)
				FITTINGS._ring(manifold,Vector3(x,1.35,0.68),Vector3(0.3,0.05,0.3),2,[Vector2(0.5,0),Vector2(0.5,1),Vector2(0.36,1),Vector2(0.36,0),Vector2(0.5,0)],Basis(Vector3.RIGHT,PI*0.5))
			_append_pieces(Transform3D(Basis(Vector3.UP, PI*0.5),Vector3(-hx+0.28,0,2.6)),manifold)
			_grate(Vector3(-hx+0.8,0.012,3.6),Vector2(0.5,1.2))
		"sanitary":
			# Glazed splashback, visible joints and oxidised mirror frames.
			_box(Vector3(-hx+0.265,1.05,-hz+2.45),Vector3(0.035,1.7,3.8),3)
			for z in [-hz+0.6,-hz+1.55,-hz+2.5,-hz+3.45,-hz+4.3]:
				_box(Vector3(-hx+0.287,1.05,z),Vector3(0.012,1.7,0.012),4)
			for y in [0.63,1.05,1.48]: _box(Vector3(-hx+0.287,y,-hz+2.45),Vector3(0.012,0.01,3.8),4)
			for z in [-hz+1.6,-hz+3.3]:
				var frame: Array[Dictionary] = []
				FITTINGS._plate(frame,Vector3.ZERO,Vector2(0.69,0.58))
				FITTINGS._part(frame,Vector3(0,0,0.025),Vector3(0.59,0.48,0.015),4,"box")
				_append_pieces(Transform3D(Basis(Vector3.UP,PI*0.5),Vector3(-hx+0.3,1.66,z)),frame)
			_grate(Vector3(-hx+1.4,0.012,-hz+2.5),Vector2(0.35,1.7))
			var roll: Array[Dictionary] = []
			FITTINGS.pipe(roll,Vector3(-0.12,0,0.1),Vector3(0.12,0,0.1),0.025)
			FITTINGS._part(roll,Vector3(0,0,0.1),Vector3(0.18,0.15,0.15),6,"cylinder")
			roll[-1].axis = 0
			FITTINGS._part(roll,Vector3(0,-0.1,0.16),Vector3(0.16,0.15,0.008),6,"box")
			_append_pieces(Transform3D(Basis.IDENTITY,Vector3(hx-1.1,0.9,-hz+1.05)),roll)

func _papers(at: Vector3, count: int) -> void:
	for i in count:
		var pose := Transform3D(Basis(Vector3.UP, i*0.12), at+Vector3(i*0.025,i*0.003,0))
		_piece_local(pose,Vector3.ZERO,Vector3(0.24,0.004,0.32),6)
		_piece_local(pose,Vector3(0.02,0.004,-0.025),Vector3(0.15,0.003,0.006),4)

func _notice_board(pose: Transform3D) -> void:
	_piece_local(pose,Vector3.ZERO,Vector3(1.65,0.96,0.055),2,"bevel")
	_piece_local(pose,Vector3(0,0,0.033),Vector3(1.52,0.83,0.018),5)
	for i in 3:
		var x := -0.49+i*0.46
		_piece_local(pose,Vector3(x,0.03,0.05),Vector3(0.32,0.47-i*0.04,0.006),6)
		_piece_local(pose,Vector3(x,0.25-i*0.02,0.06),Vector3(0.025,0.025,0.012),2,"cylinder")
		for row in 4:
			_piece_local(pose,Vector3(x,0.13-row*0.07,0.055),Vector3(0.21-0.02*(row%2),0.009,0.002),4)

func _grate(at: Vector3, size: Vector2) -> void:
	_box(at,Vector3(size.x,0.02,size.y),4)
	for x in [-size.x*0.5,size.x*0.5]: _piece(at+Vector3(x,0.012,0),Vector3(0.035,0.025,size.y),2)
	for i in range(ceili(size.y/0.1)):
		_piece(at+Vector3(0,0.012,-size.y*0.5+0.05+i*0.1),Vector3(size.x,0.025,0.025),2)

func _table(at: Vector3, size: Vector2) -> void:
	_append_pieces(Transform3D(Basis.IDENTITY, at), FITTINGS.table(size))
	_collider(at+Vector3(0, 0.85, 0), Vector3(size.x, 0.12, size.y))

func _bench(at: Vector3, angle: float = 0) -> void:
	var pose := Transform3D(Basis(Vector3.UP, angle), at)
	_append_pieces(pose, FITTINGS.bench())
	_collider(at + Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 2.5), pose.basis)

func _shelf(at: Vector3) -> void:
	for x in [-0.8, 0.8]:
		for z in [-0.35, 0.35]: _piece(at+Vector3(x, 1.0, z), Vector3(0.06, 2.0, 0.06), 2)
	for y in [0.16, 0.8, 1.5, 1.95]: _box(at+Vector3(0, y, 0), Vector3(1.7, 0.055, 0.8), 2)
	_box(at+Vector3(0.23, 0.35, 0), Vector3(0.6, 0.3, 0.55), 1)
	_collider(at+Vector3(0, 1.0, 0), Vector3(1.7, 2.0, 0.8))

func _sign(text: String, at: Vector3, angle: float, width := 2.65) -> void:
	var plate: Array[Dictionary] = []
	FITTINGS._plate(plate, Vector3.ZERO, Vector2(width, 0.35), 2)
	_append_pieces(Transform3D(Basis(Vector3.UP, angle), at), plate)
	var label := Label3D.new()
	label.name = "WallSign" + str(_room_visuals.get_child_count())
	label.text = text
	label.position = at + Basis(Vector3.UP, angle)*Vector3(0, 0, 0.06)
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

func _append_pieces(pose: Transform3D, pieces: Array[Dictionary]) -> void:
	for piece in pieces:
		var batch: MegashelterKit.Batch = _batches[piece.material]
		if piece.shape == "lathe": FITTINGS.add_lathe(batch, pose, piece)
		else: batch.add_piece(pose, piece)

func _entrance_doors() -> void:
	var assembly := Node3D.new()
	assembly.name = "EntranceDoors"
	_room_visuals.add_child(assembly)
	_model(assembly, "LargeDoor", Transform3D(Basis(Vector3.UP, PI), Vector3(-0.95, 0, footprint.y*0.5-0.35)), FITTINGS.large_door())
	_model(assembly, "PedestrianDoor", Transform3D(Basis(Vector3.UP, PI), Vector3(2.45, 0, footprint.y*0.5-0.35)), FITTINGS.pedestrian_door())
	_sign("EXIT", Vector3(2.45, 2.72, footprint.y*0.5-0.26), PI, 1.04)

func add_stair_access() -> Transform3D:
	# This side of reception is clear of the desk, lockers and outdoor doors.
	# The wall behind the closed door remains solid across the instance boundary.
	var pose := Transform3D(Basis(Vector3.UP, -PI*0.5), Vector3(footprint.x*0.5-0.28, 0, 1.1))
	var assembly := Node3D.new()
	assembly.name = "StairAccess"
	_room_visuals.add_child(assembly)
	_model(assembly, "StairDoor", pose, FITTINGS.pedestrian_door())
	var plate: Array[Dictionary] = []
	FITTINGS._plate(plate, Vector3(0, 2.78, 0.02), Vector2(1.55, 0.35), 2)
	_model(assembly, "StairSign", pose, plate)
	var sign := Label3D.new()
	sign.text = "BUNKER / STAIRS"
	sign.transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, 2.78, 0.08))
	sign.font_size = 40
	sign.pixel_size = 0.0035
	sign.modulate = Color("a0a494")
	assembly.add_child(sign)
	return pose

func _model(parent: Node3D, node_name: String, pose: Transform3D, pieces: Array[Dictionary]) -> void:
	var node := Node3D.new()
	node.name = node_name
	node.transform = pose
	parent.add_child(node)
	var batches: Array[MegashelterKit.Batch] = []
	for i in 7:
		var batch := MegashelterKit.Batch.new()
		batch.set_appearance(node_name.hash(), 3.3)
		batches.append(batch)
	for piece in pieces:
		if piece.shape == "lathe": FITTINGS.add_lathe(batches[piece.material], Transform3D.IDENTITY, piece)
		else: batches[piece.material].add_piece(Transform3D.IDENTITY, piece)
	for i in batches.size():
		if batches[i].vertices.is_empty(): continue
		var mesh := MeshInstance3D.new()
		mesh.name = "Surface%d" % i
		mesh.mesh = batches[i].mesh()
		mesh.material_override = _material(i)
		node.add_child(mesh)

func _collider(at: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.transform = Transform3D(basis, at)
	_room_collision.add_child(collision)

func _material(index: int) -> Material:
	if _materials.has(index): return _materials[index]
	var material := ShaderMaterial.new()
	if index >= 3:
		material.shader = FINISH
		material.set_shader_parameter("finish_kind", float(index-3))
		material.set_shader_parameter("base_color", [Color("a2aa99"),Color("262c26"),Color("57594b"),Color("96927b")][index-3])
		_materials[index] = material
		return material
	material.shader = SURFACE
	material.set_shader_parameter("surface_kind", float(index))
	material.set_shader_parameter("base_color", [Color("858981"), Color("737e70"), Color("424b44")][index])
	material.set_shader_parameter("wear_seed", float(posmod(str(room_id).hash(), 10000)))
	_materials[index] = material
	return material

func _finish_batches() -> void:
	for i in _batches.size():
		if _batches[i].vertices.is_empty(): continue
		var visual := MeshInstance3D.new()
		visual.name = ["WallStructure", "PaintFinish", "SteelServices", "Ceramic", "Gaskets", "OldTimber", "Paper"][i]
		visual.mesh = _batches[i].mesh()
		visual.material_override = _material(i)
		_room_visuals.add_child(visual)

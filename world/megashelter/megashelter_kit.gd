extends RefCounted
class_name MegashelterKit
class Batch extends RefCounted:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var appearance := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var source: Array
	var _damage := 0.0
	var _appearance := Vector2.ZERO

	func set_appearance(stable_seed: int, ledge_height: float) -> void:
		_appearance = Vector2(float(posmod(stable_seed, 65521)) / 65521.0, ledge_height)

	func _init() -> void:
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		source = cube.get_mesh_arrays()

	func add_box(pose: Transform3D, center: Vector3, size: Vector3, shade: float) -> void:
		var offset := vertices.size()
		var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
		var source_uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
		var tint := Color(shade, shade, shade, _damage)
		for index in range(source_vertices.size()):
			vertices.append(pose * (center + source_vertices[index] * size))
			normals.append(pose.basis * source_normals[index])
			uvs.append(source_uvs[index])
			appearance.append(_appearance)
			colors.append(tint)
		for index: int in source[Mesh.ARRAY_INDEX]: indices.append(offset + index)

	func mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = appearance
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var result := ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return result

	func add_piece(pose: Transform3D, piece: Dictionary) -> void:
		if piece.has("basis"):
			pose = pose * Transform3D(piece.basis,piece.center)
			piece = piece.duplicate()
			piece.center = Vector3.ZERO
		_damage = 1.0 if piece.get("shape", "box") == "spall" else 0.0
		if piece.material == 2: _damage = float(piece.get("steel_preservation",0.0))
		match piece.get("shape", "box"):
			"bevel": _beveled(pose, piece.center, piece.size, piece.shade, piece.bevel)
			"cylinder": _cylinder(pose, piece.center, piece.size, piece.shade, piece.get("axis",-1))
			"spall": _spall(pose, piece.center, piece.size, piece.shade)
			"chip": _chip(pose,piece.center,piece.size,piece.shade,piece.get("chip_variant",0))
			"paver": _chip(pose,piece.center,piece.size,piece.shade,piece.get("chip_variant",0),true)
			"scar": _scar(pose,piece.center,piece.size,piece.shade,piece.get("scar_seed",0))
			_: add_box(pose, piece.center, piece.size, piece.shade)

	func _face(pose: Transform3D, center: Vector3, points: Array[Vector3], normal: Vector3, shade: float) -> void:
		var offset := vertices.size()
		for point in points:
			vertices.append(pose * (center + point))
			normals.append((pose.basis * normal).normalized())
			uvs.append(Vector2(point.x, point.y))
			appearance.append(_appearance)
			colors.append(Color(shade, shade, shade, _damage))
		var reverse := (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0.0
		for index in range(1, points.size() - 1):
			indices.append(offset)
			indices.append(offset + (index + 1 if reverse else index))
			indices.append(offset + (index if reverse else index + 1))

	func _beveled(pose: Transform3D, center: Vector3, size: Vector3, shade: float, requested: float) -> void:
		var half := size * 0.5
		var cut := minf(requested, minf(half.x, minf(half.y, half.z)) * 0.7)
		var inner := half - Vector3.ONE * cut
		for axis in range(3):
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			for sign_value: float in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				var normal := Vector3.ZERO
				normal[axis] = sign_value
				for corner: Vector2 in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
					var point := Vector3.ZERO
					point[axis] = half[axis] * sign_value
					point[u] = inner[u] * corner.x
					point[v] = inner[v] * corner.y
					points.append(point)
				_face(pose, center, points, normal, shade)
		# Twelve sloped edges and eight clipped corners catch light geometrically.
		for axis in range(3):
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			for su: float in [-1.0, 1.0]:
				for sv: float in [-1.0, 1.0]:
					var points: Array[Vector3] = []
					for ends: Vector2 in [Vector2(-1,0), Vector2(1,0), Vector2(1,1), Vector2(-1,1)]:
						var point := Vector3.ZERO
						point[axis] = inner[axis] * ends.x
						point[u] = (half[u] if ends.y == 0 else inner[u]) * su
						point[v] = (inner[v] if ends.y == 0 else half[v]) * sv
						points.append(point)
					var normal := Vector3.ZERO
					normal[u] = su
					normal[v] = sv
					_face(pose, center, points, normal.normalized(), shade * 0.96)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var signs := Vector3(sx, sy, sz)
					var points: Array[Vector3] = [Vector3(half.x, inner.y, inner.z) * signs,
						Vector3(inner.x, half.y, inner.z) * signs, Vector3(inner.x, inner.y, half.z) * signs]
					_face(pose, center, points, signs.normalized(), shade * 0.91)

	func _cylinder(pose: Transform3D, center: Vector3, size: Vector3, shade: float, requested_axis: int = -1) -> void:
		var axis := size.max_axis_index() if requested_axis < 0 else requested_axis
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var ends: Array[Array] = [[], []]
		for index in range(8):
			var a := TAU * index / 8.0
			var b := TAU * (index + 1) / 8.0
			var points: Array[Vector3] = []
			for parameters: Vector2 in [Vector2(a,-1), Vector2(b,-1), Vector2(b,1), Vector2(a,1)]:
				var point := Vector3.ZERO
				point[axis] = size[axis] * 0.5 * parameters.y
				point[u] = cos(parameters.x) * size[u] * 0.5
				point[v] = sin(parameters.x) * size[v] * 0.5
				points.append(point)
			var normal := Vector3.ZERO
			normal[u] = cos((a+b)*0.5)
			normal[v] = sin((a+b)*0.5)
			_face(pose, center, points, normal, shade)
			ends[0].append(points[0])
			ends[1].append(points[3])
		for index in range(2):
			var normal := Vector3.ZERO
			normal[axis] = -1.0 if index == 0 else 1.0
			var points: Array[Vector3] = []
			points.assign(ends[index])
			_face(pose, center, points, normal, shade * 0.92)

	func _chip(pose: Transform3D, center: Vector3, size: Vector3, shade: float, variant: int, paving: bool = false) -> void:
		# Clipped, asymmetric fracture outline; every vertex stays in the piece AABB.
		var cut := 0.12+float(posmod(variant,4))*0.065
		var outline: Array[Vector2] = [Vector2(-0.5+cut,-0.5),Vector2(0.32,-0.5),Vector2(0.5,-0.22),Vector2(0.5,0.34),Vector2(0.18,0.5),Vector2(-0.5,0.5-cut),Vector2(-0.5,-0.2)]
		if paving:
			outline = [Vector2(-0.5,-0.5),Vector2(0.5,-0.5),Vector2(0.5,0.5-cut*0.5),Vector2(0.5-cut*0.7,0.5),Vector2(-0.5,0.5)]
		var bottom: Array[Vector3] = []
		var top: Array[Vector3] = []
		for point: Vector2 in outline:
			bottom.append(Vector3(point.x*size.x,-size.y*0.5,point.y*size.z))
			var height := 0.5 if paving else 0.18+0.08*float(posmod(top.size()+variant,5))
			top.append(Vector3(point.x*size.x*(1.0 if paving else 0.83),size.y*height,point.y*size.z*(1.0 if paving else 0.87)))
		_face(pose,center,bottom,Vector3.DOWN,shade*0.7)
		for index in range(1,top.size()-1):
			var normal := (top[index+1]-top[0]).cross(top[index]-top[0]).normalized()
			_face(pose,center,[top[0],top[index],top[index+1]],normal,shade)
		for index in range(outline.size()):
			var next := (index+1)%outline.size()
			var normal := (top[index]-bottom[index]).cross(bottom[next]-bottom[index]).normalized()
			_face(pose,center,[bottom[index],bottom[next],top[next],top[index]],normal,shade*(0.72+float(index%3)*0.08))

	func _scar(pose: Transform3D, center: Vector3, size: Vector3, shade: float, seed_value: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value*3307+91
		var outer: Array[Vector3] = []
		var lip: Array[Vector3] = []
		var inner: Array[Vector3] = []
		for index in range(15):
			var angle := TAU*index/15.0
			var radius := rng.randf_range(0.29,0.5)
			var edge := Vector3(cos(angle)*size.x*radius,sin(angle)*size.y*radius,-size.z*0.48)
			outer.append(edge)
			lip.append(Vector3(edge.x*0.95,edge.y*0.95,size.z*(-0.22 if index%3 == 0 else rng.randf_range(0.12,0.5))))
			var exposed := rng.randf_range(0.77,0.93)
			inner.append(Vector3(edge.x*exposed,edge.y*exposed,-size.z*0.36))
		var bed := Vector3(0,0,-size.z*0.38)
		for index in range(15):
			var next := (index+1)%15
			# A thin feathered outside, chipped raised lip, then an inward fracture
			# slope. No box-shaped pieces pasted over an exposed reinforcement grid.
			_damage = 0.0
			_triangle(pose,center,outer[index],outer[next],lip[next],shade)
			_triangle(pose,center,outer[index],lip[next],lip[index],shade)
			_triangle(pose,center,lip[index],lip[next],inner[next],shade*0.87)
			_triangle(pose,center,lip[index],inner[next],inner[index],shade*0.87)
			_damage = 0.22
			_triangle(pose,center,inner[index],inner[next],bed,shade*0.72)

	func _triangle(pose: Transform3D, center: Vector3, a: Vector3, b: Vector3, c: Vector3, shade: float) -> void:
		var normal := (b-a).cross(c-a).normalized()
		if normal.z < 0: normal = -normal
		_face(pose,center,[a,b,c],normal,shade)

	func _spall(pose: Transform3D, center: Vector3, size: Vector3, shade: float) -> void:
		var polygon := [Vector2(-0.5,-0.35), Vector2(-0.2,-0.5), Vector2(0.5,-0.24), Vector2(0.3,0.42), Vector2(-0.35,0.5)]
		var faces: Array[Array] = [[], []]
		for point: Vector2 in polygon:
			faces[0].append(Vector3(point.x * size.x, point.y * size.y, -size.z * 0.5))
			faces[1].append(Vector3(point.x * size.x, point.y * size.y, size.z * 0.5))
		for index in range(2):
			var points: Array[Vector3] = []
			points.assign(faces[index])
			_face(pose, center, points, Vector3(0,0,-1 if index == 0 else 1), shade)
		for index in range(polygon.size()):
			var next := (index + 1) % polygon.size()
			var points: Array[Vector3] = [faces[0][index], faces[0][next], faces[1][next], faces[1][index]]
			var edge: Vector3 = points[1] - points[0]
			_face(pose, center, points, Vector3(edge.y,-edge.x,0).normalized(), shade * 0.8)

## Eight structural families plus roof plant and drainage attachments.
## Root lies at floor centre of front face, front +Z; depth extends towards -Z.
static func pieces(kind: String, size: Vector3, variant: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match kind:
		"service_cabinet", "pipe_manifold", "intake_hood", "wall_salvage", "portal_canopy", "service_fan":
			return MegashelterDetails.pieces(kind,size,variant)
		"buttress":
			# Stepped concrete feet and deep upper ribs form a readable load path.
			for level in range(3):
				var depth := size.z * (1.0 - level * 0.22)
				_piece(result,Vector3(0,(level+0.5)*size.y/3,-depth*0.5),Vector3(size.x-level*0.45,size.y/3,depth),0,level,0.16)
		"wall", "rib_wall":
			_piece(result, Vector3(0, size.y * 0.5, -size.z * 0.5), Vector3(size.x - 0.055, size.y - 0.045, size.z), 1, variant%8, 0.045)
			# Raised vertical returns and a chipped exposed-concrete patch.
			if kind == "rib_wall":
				_piece(result, Vector3(-size.x * 0.5 + 0.12, size.y * 0.5, 0.035), Vector3(0.22, size.y - 0.02, 0.14), 0, 1, 0.03)
			if variant == 3 or variant == 7:
				_piece(result, Vector3(-size.x * 0.33, size.y * 0.24, 0.025), Vector3(0.6, minf(1.1,size.y*0.4), 0.045), 0, 3, 0, "spall")
			if variant >= 8:
				result.append_array(MegashelterDetails.wall_panels(size,variant))
			elif variant >= 4:
				var patch_y := size.y * (0.32 if variant%2 == 0 else 0.68)
				if variant == 7:
					_piece(result,Vector3(0,patch_y,0.028),Vector3(1.65,2.25,0.06),0,1,0,"spall")
					for x: float in [-0.52,-0.17,0.18,0.53]:
						_piece(result,Vector3(x,patch_y,0.065),Vector3(0.035,1.5,0.04),2,3,0,"cylinder")
				else:
					# A framed maintenance cover replaces the oversized random repair plate.
					_piece(result,Vector3(0,patch_y,0.025),Vector3(1.55,1.85,0.05),2,2,0.025)
					_piece(result,Vector3(0,patch_y,0.07),Vector3(1.38,1.68,0.065),2,0,0.025)
					for x: float in [-0.61,0.61]:
						for y: float in [-0.75,0.75]:
							_piece(result,Vector3(x,patch_y+y,0.12),Vector3(0.07,0.07,0.055),2,1,0.015)
					if variant == 6:
						for y: float in [-0.42,0.0,0.42]:
							_piece(result,Vector3(0,patch_y+y,0.13),Vector3(1.22,0.065,0.08),2,1,0.015)
		"vent":
			_piece(result, Vector3(0,size.y*0.5,-size.z*0.5), size, 2, 2, 0.045)
			for x: float in [-1.0,1.0]:
				_piece(result, Vector3(x*(size.x*0.5-0.1),size.y*0.5,0.08), Vector3(0.18,size.y,0.3),0,2,0.025)
			for y: float in [0.08,size.y-0.08]:
				_piece(result, Vector3(0,y,0.08), Vector3(size.x,0.16,0.3),0,2,0.025)
			var slats := maxi(3, floori(size.y / 0.22))
			for index in range(slats):
				if variant >= 2 and index % 5 == 2: continue # Missing slats expose the dark sealed backing.
				_piece(result, Vector3(0,0.22+index*(size.y-0.4)/slats,0.13),Vector3(size.x-0.35,0.105,0.31),2,1,0.035)
			if variant >= 2:
				for x: float in [-size.x*0.25,0.0,size.x*0.25]:
					_piece(result,Vector3(x,size.y*0.5,0.32),Vector3(0.07,size.y-0.2,0.08),2,2,0.015)
		"corner":
			_piece(result, Vector3(-size.x * 0.5, size.y * 0.5, 0.08), Vector3(size.x, size.y, 0.18), 0,1,0.06)
			_piece(result, Vector3(0.08, size.y * 0.5, -size.z * 0.5), Vector3(0.18, size.y, size.z), 0,1,0.06)
		"pier":
			_piece(result,Vector3(0,size.y*0.5,-size.z*0.5),size,0,variant,0.16)
			for y in range(1,ceili(size.y/4.5)):
				_piece(result,Vector3(0,y*4.5,0.008),Vector3(size.x-0.28,0.035,0.025),2,3)
			for side: float in [-1.0,1.0]:
				_piece(result,Vector3(side*(size.x*0.5-0.16),size.y*0.5,0.035),Vector3(0.12,size.y-0.3,0.1),0,2,0.035)
			_piece(result,Vector3(0,0.7,-size.z*0.5),Vector3(size.x+0.22,1.4,size.z+0.12),0,2,0.12)
			_piece(result,Vector3(0,size.y-0.16,-size.z*0.5),Vector3(size.x+0.12,0.32,size.z+0.12),0,1,0.07)
			for level in range(1,ceili(size.y/9.0)):
				for x: float in [-size.x*0.3,size.x*0.3]:
					_piece(result,Vector3(x,level*9.0-0.35,0.035),Vector3(0.3,0.3,0.07),2,3,0.04)
			if variant == 1:
				_piece(result,Vector3(0,size.y*0.5,0.035),Vector3(0.44,size.y-1.6,0.08),2,2,0.025)
		"beam":
			_piece(result, Vector3(0, size.y * 0.5, -size.z * 0.5), size, 2 if variant == 2 else 0, variant,0.07)
		"roof":
			_piece(result,Vector3(0,0.13,-size.z*0.5),Vector3(size.x,0.26,size.z),0,2,0.06)
			for x: float in [-1.0,1.0]:
				_piece(result,Vector3(x*(size.x*0.5-0.18),0.43,-size.z*0.5),Vector3(0.36,0.6,size.z),0,1,0.07)
			for z: float in [-0.18,-size.z+0.18]:
				_piece(result,Vector3(0,0.43,z),Vector3(size.x-0.72,0.6,0.36),0,1,0.07)
		"roof_plant":
			_piece(result,Vector3(0,0.18,-size.z*0.5),Vector3(size.x,0.36,size.z),0,2,0.075)
			var body_size := Vector3(6,2,4) if variant == 0 else Vector3(9,1.5,5)
			_piece(result,Vector3(0,0.36+body_size.y*0.5,-size.z*0.5),body_size,2)
			result.back()["visible"] = false # Bounds proxy for the shared authored GLB.
		"drain":
			_piece(result,Vector3(0,size.y*0.5,-0.16),Vector3(0.22,size.y,0.22),2,2,0,"cylinder")
			for index in range(ceili(size.y/4.5)):
				_piece(result,Vector3(0,0.5+index*4.5,-0.22),Vector3(0.38,0.12,0.35),2,1,0.025)
		"entrance":
			_entrance(result,variant)
		"service_spine":
			_piece(result,Vector3(0,size.y*0.5,-0.5),Vector3(size.x,size.y,1.0),2,2,0.13)
			for x: float in [-1.05,1.05]:
				_piece(result,Vector3(x,size.y*0.5,0.08),Vector3(0.22,size.y,0.32),0,2,0.045)
			for level in range(ceili(size.y/3.0)):
				var y := minf(size.y-0.3,0.4+level*3.0)
				_piece(result,Vector3(0,y,0.16),Vector3(2.5,0.18,0.4),2,1,0.035)
				_piece(result,Vector3(0,minf(size.y-0.6,y+0.7),0.06),Vector3(1.5,0.5,0.14),2,3,0.035)
	return result

static func _entrance(parts: Array[Dictionary], variant: int) -> void:
	for x: float in [-5.5,5.5]:
		_piece(parts,Vector3(x,4.5,-1.5),Vector3(1,9,3),0,0,0.14)
		_piece(parts,Vector3(x,0.65,-1.5),Vector3(1.18,1.3,3.12),0,2,0.12)
	_piece(parts,Vector3(0,8.25,-1.5),Vector3(10,1.5,3),0,0,0.13)
	_piece(parts,Vector3(0,7.55,-1.36),Vector3(10,0.18,3.08),0,1,0.05)
	# Closed double blast leaves with raised perimeter frames and reinforcing ribs.
	for side in range(2):
		var x := -2.92 + side*3.64
		_piece(parts,Vector3(x,3.12,-2.79),Vector3(3.58,6.24,0.32),2,side,0.07)
		for edge: float in [-1.0,1.0]:
			_piece(parts,Vector3(x+edge*1.65,3.12,-2.55),Vector3(0.16,6.05,0.2),2,1,0.035)
		for y: float in [0.24,2.15,4.2,6.02]:
			_piece(parts,Vector3(x,y,-2.55),Vector3(3.4,0.18,0.2),2,1,0.035)
		# Layered armor, hinge housings and locking rams remain inside the portal collider.
		for y: float in [1.15,3.15,5.1]:
			_piece(parts,Vector3(x,y,-2.53),Vector3(2.7,1.35,0.12),2,variant,0.06)
			for edge: float in [-1.0,1.0]:
				_piece(parts,Vector3(x+edge*1.2,y,-2.42),Vector3(0.13,0.13,0.12),2,1,0.025)
			if variant == 1:
				_piece(parts,Vector3(x,y,-2.33),Vector3(2.8,0.16,0.26),2,2,0.035)
		for y: float in [1.0,3.1,5.2]:
			_piece(parts,Vector3(x+(-1.6 if side == 0 else 1.6),y,-2.38),Vector3(0.3,0.6,0.28),2,2,0.045)
	for y: float in [1.15,3.15,5.1]:
		_piece(parts,Vector3(-1.1,y,-2.3),Vector3(1.0,0.23,0.23),2,1,0,"cylinder")
	for x: float in [-4.85,2.78]:
		_piece(parts,Vector3(x,3.3,-2.62),Vector3(0.25,6.6,0.6),2,1,0.045)
	_piece(parts,Vector3(-1.1,6.75,-2.5),Vector3(8.1,0.7,0.8),2,1,0.08)
	_piece(parts,Vector3(-1.1,7.08,-2.42),Vector3(8.4,0.12,0.94),0,1,0.025)
	# A separately framed pedestrian leaf, three hinges, latch and dead reader.
	_piece(parts,Vector3(3.85,1.5,-2.72),Vector3(1.72,3.0,0.4),0,1,0.045)
	_piece(parts,Vector3(3.85,1.36,-2.43),Vector3(1.35,2.72,0.22),2,1,0.035)
	for y: float in [0.4,1.4,2.4]:
		_piece(parts,Vector3(4.46,y,-2.24),Vector3(0.11,0.23,0.12),2,1,0,"cylinder")
	_piece(parts,Vector3(3.42,1.25,-2.22),Vector3(0.13,0.38,0.14),2,2,0.025)
	_piece(parts,Vector3(2.85,1.5,-2.35),Vector3(0.24,0.45,0.22),2,2,0.03)
	# Large visible anchors, with no bright active lights or warning paint.
	for x: float in [-4.85,2.78]:
		for y: float in [0.35,2.3,4.3,6.3]:
			_piece(parts,Vector3(x,y,-2.27),Vector3(0.15,0.15,0.1),2,3,0.025)

static func _piece(parts: Array[Dictionary], center: Vector3, size: Vector3, material: int, variant: int = 0, bevel: float = 0, shape: String = "box") -> void:
	parts.append({"center": center, "size": size, "material": material, "shade": 1.0 - variant * 0.055,
		"shape": "bevel" if bevel > 0 else shape, "bevel": bevel})

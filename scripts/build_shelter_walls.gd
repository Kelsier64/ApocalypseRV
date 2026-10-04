extends SceneTree
## Offline authoring source. Only writes the shelter's replaceable facade scene.
## Run with -- --write to explicitly rebuild this authored asset.
var batches: Dictionary = {}
var materials: Dictionary = {}
var scene: Node3D
var fracture_noise := FastNoiseLite.new()

func _init() -> void:
	build.call_deferred()

func face(points: Array[Vector3], normal: Vector3, material: String, uvs: Array[Vector2] = [], tint := Color.WHITE, vertex_tints: Array[Color] = []) -> void:
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0:
		points.reverse()
		uvs.reverse()
		vertex_tints.reverse()
	if not batches.has(material): batches[material] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray()}
	var data: Dictionary = batches[material]
	for i in range(1, points.size() - 1):
		for index in [0, i, i + 1]:
			var p := points[index]
			data.v.append(p)
			data.n.append(normal)
			data.uv.append(uvs[index] if not uvs.is_empty() else Vector2(p.x + p.z, p.y))
			data.c.append(vertex_tints[index] if not vertex_tints.is_empty() else tint)

func box(size: Vector3, pos: Vector3, material := "concrete", bevel := 0.025, rotation := Basis.IDENTITY, open_front := false) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.4)
	for axis in range(3):
		var j := (axis + 1) % 3
		var k := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			if open_front and axis == 2 and sign_value == 1.0: continue
			var points: Array[Vector3] = []
			for corner in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
				var p := Vector3.ZERO
				p[axis] = sign_value * h[axis]
				p[j] = corner.x * (h[j] - b)
				p[k] = corner.y * (h[k] - b)
				points.append(pos + rotation * p)
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			face(points, rotation * normal, material)
		for sj in [-1.0, 1.0]:
			for sk in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				for corner in [Vector2(-1,0), Vector2(1,0), Vector2(1,1), Vector2(-1,1)]:
					var p := Vector3.ZERO
					p[axis] = corner.x * (h[axis] - b)
					p[j] = sj * (h[j] - b * corner.y)
					p[k] = sk * (h[k] - b * (1.0 - corner.y))
					points.append(pos + rotation * p)
				var normal := Vector3.ZERO
				normal[j] = sj
				normal[k] = sk
				face(points, rotation * normal.normalized(), material)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var signs := Vector3(sx, sy, sz)
				var points: Array[Vector3] = []
				for axis in range(3):
					var p := (h - Vector3.ONE * b) * signs
					p[axis] = h[axis] * signs[axis]
					points.append(pos + rotation * p)
				face(points, rotation * signs.normalized(), material)

func scar(origin: Vector2, outline: Array[Vector2]) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in outline: polygon.append(origin + point)
	return polygon

func scar_bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon: bounds = bounds.expand(point)
	return bounds.grow(0.12)

func surface_damage(p: Vector2, scars: Array[PackedVector2Array], seed_value: float) -> float:
	var result := 0.0
	# Authored concave outlines control the silhouette; noise only chips the edge.
	# No radial falloff: long joint failures must not become oval craters.
	for polygon in scars:
		if not scar_bounds(polygon).has_point(p): continue
		var distance := INF
		for i in range(polygon.size()):
			distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, polygon[i], polygon[(i + 1) % polygon.size()])))
		if not Geometry2D.is_point_in_polygon(p, polygon): distance = -distance
		var edge_noise := fracture_noise.get_noise_2d(p.x * 7.3 + seed_value, p.y * 7.3) * 0.075
		result = maxf(result, smoothstep(-0.025, 0.10, distance + edge_noise))
	return result

func wall_surface(size: Vector2, origin: Vector3, rotation: Basis, scars: Array[PackedVector2Array], seed_value: float) -> void:
	# Coarse planar regions, with 12cm tessellation only around authored spalls.
	# Red = pour variation, green = fractured concrete, blue = recessed cold joint.
	var xs: Array[float] = [-size.x * 0.5, size.x * 0.5]
	var ys: Array[float] = [-size.y * 0.5, size.y * 0.5]
	for polygon in scars:
		var bounds := scar_bounds(polygon)
		for i in range(ceili(bounds.size.x / 0.12) + 1):
			xs.append(clampf(bounds.position.x + i * 0.12, -size.x * 0.5, size.x * 0.5))
		for i in range(ceili(bounds.size.y / 0.12) + 1):
			ys.append(clampf(bounds.position.y + i * 0.12, -size.y * 0.5, size.y * 0.5))
	var lifts: Array[float] = []
	for level in range(1, 7):
		var y := level * 2.2 - origin.y
		if y > -size.y * 0.5 + 0.05 and y < size.y * 0.5 - 0.05:
			lifts.append(y)
			ys.append_array([y - 0.013, y, y + 0.013])
	xs.sort()
	ys.sort()
	for iy in range(ys.size() - 1):
		if ys[iy + 1] - ys[iy] < 0.002: continue
		for ix in range(xs.size() - 1):
			if xs[ix + 1] - xs[ix] < 0.002: continue
			var points: Array[Vector3] = []
			var colors: Array[Color] = []
			for p in [Vector2(xs[ix],ys[iy]), Vector2(xs[ix+1],ys[iy]), Vector2(xs[ix+1],ys[iy+1]), Vector2(xs[ix],ys[iy+1])]:
				var damage := surface_damage(p, scars, seed_value)
				var joint := 0.0
				for lift in lifts: joint = maxf(joint, 1.0 - clampf(absf(p.y - lift) / 0.013, 0.0, 1.0))
				var edge_distance := minf(size.x * 0.5 - absf(p.x), size.y * 0.5 - absf(p.y))
				damage *= smoothstep(0.0, 0.045, edge_distance)
				var depth := pow(damage, 0.52) * (0.068 + fracture_noise.get_noise_2d(p.x * 11, p.y * 11) * 0.008)
				var shade := 0.94 + fposmod(seed_value + floor((p.y + origin.y) / 2.2) * 0.037, 0.10)
				points.append(origin + rotation * Vector3(p.x,p.y,-depth - joint * 0.006))
				colors.append(Color(shade, damage, joint, 1))
			for triangle in [[0,1,2], [0,2,3]]:
				var verts: Array[Vector3] = []
				var tints: Array[Color] = []
				for index in triangle:
					verts.append(points[index])
					tints.append(colors[index])
				var normal := (verts[1] - verts[0]).cross(verts[2] - verts[0]).normalized()
				if normal.dot(rotation * Vector3.BACK) < 0: normal = -normal
				face(verts, normal, "wall_skin", [], Color.WHITE, tints)

func cast_wall(size: Vector3, pos: Vector3, scars: Array[PackedVector2Array] = [], rotation := Basis.IDENTITY) -> void:
	box(size, pos, "concrete", 0.015, rotation, true)
	wall_surface(Vector2(size.x - 0.03, size.y - 0.03), pos + rotation * Vector3(0,0,size.z * 0.5), rotation, scars, pos.x * 0.71 + pos.z * 0.29)

func garage_walls() -> void:
	var cuts := [-14.0, -11.0, -5.0, 1.0, 7.0, 12.0, 14.0]
	for side in [-1.0, 1.0]:
		var basis := Basis(Vector3.UP, -side * PI * 0.5)
		for i in range(cuts.size() - 1):
			var width: float = cuts[i+1] - cuts[i]
			var scars: Array[PackedVector2Array] = []
			# Deliberate asymmetry: untouched bays alternate with distinct failure causes.
			if side < 0 and i == 1: # Narrow vertical spall beside a pier.
				scars.append(scar(Vector2(-2.25,-1.4), [Vector2(-0.25,-0.8),Vector2(0.14,-0.65),Vector2(0.36,-0.22),Vector2(0.18,0.12),Vector2(0.28,0.62),Vector2(-0.05,1.05),Vector2(-0.24,0.55),Vector2(-0.17,0.05)]))
			if side < 0 and i == 3: # Broken, stepped strip along the 2.2m cold joint.
				scars.append(scar(Vector2(0.15,-1.2), [Vector2(-1.25,-0.13),Vector2(-0.65,-0.25),Vector2(-0.34,-0.1),Vector2(0.25,-0.32),Vector2(0.65,-0.18),Vector2(1.3,-0.14),Vector2(1.12,0.14),Vector2(0.52,0.08),Vector2(0.2,0.3),Vector2(-0.12,0.16),Vector2(-0.74,0.19),Vector2(-1.1,0.05)]))
			if side < 0 and i == 4: # Small isolated base chip, away from the bay centre.
				scars.append(scar(Vector2(1.6,-3.3), [Vector2(-0.42,-0.2),Vector2(0.5,-0.2),Vector2(0.38,0.22),Vector2(0.15,0.15),Vector2(0.03,0.49),Vector2(-0.18,0.4),Vector2(-0.23,0.12)]))
			if side > 0 and i == 2: # Low forklift scrape, two separated fragments.
				scars.append(scar(Vector2(-0.9,-2.35), [Vector2(-0.95,-0.12),Vector2(-0.26,-0.21),Vector2(0.1,-0.09),Vector2(0.62,-0.11),Vector2(0.92,0.1),Vector2(0.15,0.18),Vector2(-0.24,0.08),Vector2(-0.74,0.21)]))
				scars.append(scar(Vector2(0.55,-2.22), [Vector2(-0.19,-0.1),Vector2(0.31,-0.06),Vector2(0.18,0.16),Vector2(-0.12,0.09)]))
			if side > 0 and i == 4: # Higher leak-related branching loss under the pipe.
				scars.append(scar(Vector2(-0.9,0.62), [Vector2(-0.18,0.52),Vector2(0.2,0.43),Vector2(0.32,0.05),Vector2(0.57,-0.18),Vector2(0.37,-0.43),Vector2(0.06,-0.18),Vector2(-0.14,-0.63),Vector2(-0.36,-0.55),Vector2(-0.22,-0.06),Vector2(-0.43,0.18)]))
			cast_wall(Vector3(width,6.8,0.4), Vector3(side * 10.2,3.4,(cuts[i]+cuts[i+1])*0.5), scars, basis)
		for z in [-11.0,-5.0,1.0,7.0,12.0]:
			box(Vector3(0.3,6.8,0.6), Vector3(side * 9.84,3.4,z), "trim", 0.035)
	for i in range(4):
		var scars: Array[PackedVector2Array] = []
		if i == 0:
			scars.append(scar(Vector2(-1.7,-2.8), [Vector2(-0.65,-0.64),Vector2(0.6,-0.64),Vector2(0.4,-0.35),Vector2(0.04,-0.22),Vector2(0.13,0.41),Vector2(-0.1,0.68),Vector2(-0.34,0.26),Vector2(-0.3,-0.13),Vector2(-0.61,-0.04)]))
		cast_wall(Vector3(5.2,6.8,0.4), Vector3(-7.8+i*5.2,3.4,-14.2), scars)
	# Exterior entrance cheeks remain outside the moving leaves and clear opening.
	var left_cheek: Array[PackedVector2Array] = [scar(Vector2(-1.9,-2.92), [Vector2(-0.8,-0.55),Vector2(0.78,-0.55),Vector2(0.63,-0.16),Vector2(0.27,-0.21),Vector2(0.12,0.23),Vector2(-0.2,0.19),Vector2(-0.38,0.69),Vector2(-0.61,0.43),Vector2(-0.57,-0.09)])]
	var right_cheek: Array[PackedVector2Array] = [scar(Vector2(-1.5,-1.2), [Vector2(-0.52,-0.18),Vector2(0.05,-0.29),Vector2(0.64,-0.08),Vector2(0.83,0.16),Vector2(0.29,0.11),Vector2(-0.11,0.28),Vector2(-0.39,0.13)])]
	cast_wall(Vector3(6.9,6.8,0.3), Vector3(-6.95,3.4,14.35), left_cheek)
	cast_wall(Vector3(6.9,6.8,0.3), Vector3(6.95,3.4,14.35), right_cheek)
	cast_wall(Vector3(7,1.8,0.3), Vector3(0,5.9,14.35))

func runoff(top: Vector3, width: float, length: float, rotation := Basis.IDENTITY, tint := Color(0.10, 0.085, 0.07, 0.78)) -> void:
	var points: Array[Vector3] = []
	for p in [Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(width * 0.5, -length, 0), Vector3(-width * 0.5, -length, 0)]:
		points.append(top + rotation * p)
	face(points, rotation * Vector3.BACK, "runoff", [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)], tint)

func crack(origin: Vector3, points: Array[Vector2], rotation := Basis.IDENTITY, width := 0.01) -> void:
	for i in range(points.size() - 1):
		var direction := (points[i + 1] - points[i]).orthogonal().normalized()
		var start_side := direction * width * lerpf(0.6, 0.12, float(i) / (points.size() - 1))
		var end_side := direction * width * lerpf(0.6, 0.12, float(i + 1) / (points.size() - 1))
		var strip: Array[Vector3] = []
		for p in [points[i] - start_side, points[i] + start_side, points[i + 1] + end_side, points[i + 1] - end_side]:
			strip.append(origin + rotation * Vector3(p.x, p.y, 0))
		face(strip, rotation * Vector3.BACK, "fracture")

func broken_parapet(x0: float, x1: float, front: float, height: float, break_x: float) -> void:
	# Extruded chipped silhouette: the missing coping and concrete are real geometry.
	var outline := PackedVector2Array([
		Vector2(x0,height-0.6), Vector2(x1,height-0.6), Vector2(x1,height),
		Vector2(break_x+0.72,height), Vector2(break_x+0.42,height-0.07),
		Vector2(break_x+0.16,height-0.30), Vector2(break_x-0.12,height-0.22),
		Vector2(break_x-0.28,height-0.37), Vector2(break_x-0.58,height-0.12),
		Vector2(break_x-0.74,height), Vector2(x0,height)])
	var indices := Geometry2D.triangulate_polygon(outline)
	for depth in [0.0, 0.36]:
		for i in range(0, indices.size(), 3):
			var triangle: Array[Vector3] = []
			for j in range(3):
				var p := outline[indices[i + j]]
				triangle.append(Vector3(p.x, p.y, front - depth))
			face(triangle, Vector3.BACK if depth == 0.0 else Vector3.FORWARD, "trim")
	for i in range(outline.size()):
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		var outward := Vector3(q.y - p.y, p.x - q.x, 0).normalized()
		face([Vector3(p.x,p.y,front), Vector3(q.x,q.y,front), Vector3(q.x,q.y,front-0.36), Vector3(p.x,p.y,front-0.36)], outward, "aggregate" if i in range(3,9) else "trim")
	for span in [Vector2(x0, break_x - 0.74), Vector2(break_x + 0.72, x1)]:
		box(Vector3(span.y-span.x,0.1,0.46), Vector3((span.x+span.y)*0.5,height-0.05,front-0.18), "steel", 0.015)

func weathering_details() -> void:
	# Stress cracks originate at openings; each follows a different short path.
	crack(Vector3(-23.29,3.48,12.503), [Vector2.ZERO,Vector2(-0.12,-0.18),Vector2(-0.08,-0.32),Vector2(-0.3,-0.51),Vector2(-0.42,-0.73)], Basis.IDENTITY, 0.012)
	crack(Vector3(16.4,4.68,12.503), [Vector2.ZERO,Vector2(0.14,-0.27),Vector2(0.31,-0.32),Vector2(0.26,-0.59)], Basis.IDENTITY, 0.009)
	var left := Basis(Vector3.UP, PI * 0.5)
	var right := Basis(Vector3.UP, -PI * 0.5)
	runoff(Vector3(-9.996,4.21,-8.4), 0.85, 2.7, left)
	runoff(Vector3(-9.996,4.21,3.15), 0.75, 1.9, left)
	runoff(Vector3(9.996,4.22,-6.9), 0.95, 3.2, right)
	crack(Vector3(-9.996,4.17,3.45), [Vector2.ZERO,Vector2(-0.11,-0.12),Vector2(-0.24,-0.17),Vector2(-0.28,-0.24)], left)
	runoff(Vector3(-7.8,6.65,14.504), 1.1, 3.0)
	runoff(Vector3(7.5,6.65,14.504), 0.8, 3.6)
	# Small flush mortar repairs interrupt the cast surface without looking like holes.
	for entry in [Vector3(-9.996,1.65,-2.8), Vector3(-9.996,2.85,9.1)]:
		var points: Array[Vector3] = []
		for p in [Vector2(-0.46,-0.23),Vector2(0.39,-0.25),Vector2(0.46,0.18),Vector2(0.12,0.25),Vector2(-0.43,0.21)]:
			points.append(entry + left * Vector3(p.x,p.y,0))
		face(points, left * Vector3.BACK, "repair")

func label(text: String, pos: Vector3, pixel_size: float, facing := 0.0) -> void:
	var node := Label3D.new()
	node.name = "Stencil%d" % scene.get_child_count()
	node.text = text
	node.font_size = 96
	node.pixel_size = pixel_size
	node.outline_size = 0
	node.modulate = Color("999386")
	node.shaded = true
	node.double_sided = false
	node.position = pos
	node.rotation.y = facing
	scene.add_child(node)
	node.owner = scene

func block(x0: float, x1: float, back: float, front: float, height: float, windows: Array[float], window_y: float, window_height := 2.0) -> void:
	var width := x1 - x0
	var depth := front - back
	var center := Vector3((x0 + x1) * 0.5, 0, (front + back) * 0.5)
	# Real 45cm walls; openings are omitted from the face and have deep returns.
	var cuts: Array[float] = [x0, x1]
	for x in windows: cuts.append_array([x - 2.0, x + 2.0])
	cuts.sort()
	for i in range(cuts.size() - 1):
		var x := (cuts[i] + cuts[i + 1]) * 0.5
		var is_window := false
		for w in windows:
			if absf(x - w) < 1.99: is_window = true
		var spans := [Vector2(-0.3, height - 0.45)]
		if is_window: spans = [Vector2(-0.3, window_y), Vector2(window_y + window_height, height - 0.45)]
		for span in spans:
			var panel_width := cuts[i + 1] - cuts[i] - 0.014
			var panel_height: float = span.y - span.x
			var scars: Array[PackedVector2Array] = []
			# Selected opening corners / failed pours, never one stamp per window.
			if span.x < 0 and is_window:
				if height < 10 and x < -20: # Sill corner loss, clear of the base.
					scars.append(scar(Vector2(-1.3,panel_height*0.5-0.35), [Vector2(-0.62,0.4),Vector2(0.51,0.4),Vector2(0.4,0.05),Vector2(0.06,-0.06),Vector2(-0.05,-0.55),Vector2(-0.31,-0.71),Vector2(-0.39,-0.22),Vector2(-0.61,-0.09)]))
				elif height < 10: # Offset, short foundation loss on just this bay.
					scars.append(scar(Vector2(0.95,-panel_height*0.5+0.26), [Vector2(-0.72,-0.35),Vector2(0.67,-0.35),Vector2(0.61,0.12),Vector2(0.28,0.06),Vector2(0.12,0.5),Vector2(-0.23,0.31),Vector2(-0.27,0.04),Vector2(-0.57,0.17)]))
				elif height < 12 and x > 20: # Thin horizontal delamination at the cold joint.
					scars.append(scar(Vector2(0.1,2.2-(span.x+span.y)*0.5), [Vector2(-1.6,-0.13),Vector2(-1.08,-0.28),Vector2(-0.65,-0.13),Vector2(-0.18,-0.21),Vector2(0.34,-0.12),Vector2(0.71,-0.23),Vector2(1.35,-0.02),Vector2(1.1,0.16),Vector2(0.43,0.09),Vector2(0.08,0.27),Vector2(-0.44,0.16),Vector2(-1.19,0.22)]))
				elif height >= 12 and absf(x + 9.0) < 0.1: # Rear upper storey: local vertical damage.
					scars.append(scar(Vector2(1.35,panel_height*0.5-0.62), [Vector2(-0.33,0.66),Vector2(0.27,0.67),Vector2(0.18,0.18),Vector2(0.41,-0.05),Vector2(0.24,-0.54),Vector2(-0.06,-0.9),Vector2(-0.26,-0.62),Vector2(-0.16,-0.17),Vector2(-0.41,0.05)]))
			cast_wall(Vector3(panel_width,panel_height,0.45), Vector3(x,(span.x+span.y)*0.5,front-0.225), scars)
	for x in windows:
		box(Vector3(3.99, window_height, 0.08), Vector3(x, window_y + window_height * 0.5, front - 0.36), "dark", 0.01)
		box(Vector3(3.8, window_height - 0.12, 0.06), Vector3(x, window_y + window_height * 0.5, front - 0.29), "shutter", 0.012)
		for row in range(5):
			box(Vector3(3.8, 0.12, 0.1), Vector3(x, window_y + 0.2 + row * (window_height - 0.4) / 4.0, front - 0.21), "steel", 0.015, Basis(Vector3.RIGHT, -0.25))
		box(Vector3(4.2, 0.18, 0.6), Vector3(x, window_y - 0.06, front - 0.1), "trim", 0.04)
		box(Vector3(4.2, 0.22, 0.57), Vector3(x, window_y + window_height + 0.07, front - 0.13), "trim", 0.035)
		runoff(Vector3(x - 1.55,window_y - 0.16,front + 0.008), 0.8, 1.7, Basis.IDENTITY, Color(0.27,0.15,0.075,0.5))
		runoff(Vector3(x + 1.35,window_y - 0.16,front + 0.009), 1.2, 2.3)
	for x in [x0 + 0.3, x1 - 0.3]:
		box(Vector3(0.42, height - 0.25, 0.64), Vector3(x, (height - 0.25) * 0.5, front - 0.15), "trim", 0.05)
	for x in [x0 + 0.3, x1 - 0.3]:
		box(Vector3(0.45, height - 0.45, depth - 0.5), Vector3(x, (height - 0.45) * 0.5, center.z))
		for z in range(1, int(depth / 5.5)):
			box(Vector3(0.6, height - 0.5, 0.5), Vector3(x, (height - 0.5) * 0.5, back + z * 5.5), "trim", 0.05)
	box(Vector3(width, height - 0.45, 0.45), Vector3(center.x, (height - 0.45) * 0.5, back + 0.225))
	box(Vector3(width, 0.3, depth), Vector3(center.x, height - 0.65, center.z), "roof", 0.03)
	# Raised parapets and individual caps, not a thick floating roof block.
	var break_x := x0 + width * (0.61 if height < 10 else (0.33 if height < 12 else 0.79))
	broken_parapet(x0, x1, front, height, break_x)
	box(Vector3(width, 0.6, 0.36), Vector3(center.x, height - 0.3, back + 0.18), "trim", 0.035)
	box(Vector3(width, 0.1, 0.46), Vector3(center.x, height - 0.05, back + 0.18), "steel", 0.015)
	runoff(Vector3(break_x,height - 0.36,front + 0.01), 1.5, 3.4)
	runoff(Vector3(x1 - 0.8,height - 0.65,front + 0.01), 0.9, height - 1.1, Basis.IDENTITY, Color(0.25,0.13,0.065,0.58))
	for x in [x0 + 0.18, x1 - 0.18]:
		box(Vector3(0.36, 0.6, depth - 0.6), Vector3(x, height - 0.3, center.z), "trim", 0.035)
	box(Vector3(width - 0.8, 0.24, 0.54), Vector3(center.x, 1.35, front - 0.22), "trim", 0.025)
	box(Vector3(0.18, height - 0.8, 0.18), Vector3(x1 - 0.8, (height - 0.8) * 0.5, front + 0.08), "steel", 0.018)

func build() -> void:
	if "--write" not in OS.get_cmdline_user_args():
		print("Use -- --write to rebuild only world/starting_shelter/facade.tscn")
		quit()
		return
	materials.concrete = load("res://world/starting_shelter/materials/formed_concrete.tres")
	fracture_noise.seed = 73109
	fracture_noise.frequency = 1.0
	fracture_noise.fractal_octaves = 2
	materials.wall_skin = materials.concrete.duplicate()
	materials.wall_skin.set_shader_parameter("authored_surface", true)
	materials.wall_skin.set_shader_parameter("formwork_strength", 1.0)
	materials.trim = materials.concrete.duplicate()
	materials.trim.set_shader_parameter("concrete_color", Color("686b67"))
	materials.trim.set_shader_parameter("formwork_strength", 0.0)
	materials.steel = load("res://world/starting_shelter/materials/aged_metal.tres")
	materials.shutter = materials.steel.duplicate()
	materials.shutter.set_shader_parameter("metal_color", Color("61584b"))
	materials.shutter.set_shader_parameter("corrosion", 0.85)
	materials.aggregate = materials.concrete.duplicate()
	materials.aggregate.set_shader_parameter("concrete_color", Color("6b6153"))
	materials.aggregate.set_shader_parameter("formwork_strength", 0.0)
	materials.aggregate.set_shader_parameter("exposed_aggregate", 1.0)
	materials.repair = materials.concrete.duplicate()
	materials.repair.set_shader_parameter("concrete_color", Color("5f635d"))
	materials.runoff = ShaderMaterial.new()
	materials.runoff.shader = load("res://world/starting_shelter/materials/runoff.gdshader")
	for key in ["dark", "roof", "fracture"]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = {"dark": Color("292622"), "roof": Color("4d4a44"), "fracture": Color("615b52")}[key]
		mat.roughness = 0.9
		if key == "roof":
			mat.albedo_texture = load("res://assets/materials/poi_kit/concrete_albedo.png")
			mat.uv1_triplanar = true
			mat.uv1_scale = Vector3.ONE * 0.4
		materials[key] = mat
	scene = Node3D.new()
	scene.name = "Facade"
	scene.set_meta("art_status", "low-poly cast walls with recessed spalling, cold joints, sealed louvers and structural wear")
	block(-25, -10.4, -14.5, 12.5, 9, [-21.3, -14.4], 3.5)
	block(10.4, 25, -14.5, 12.5, 11, [14.4, 21.3], 4.7)
	block(-25, 25, -30.5, -14.35, 12, [-18.0, -9.0, 0.0, 9.0, 18.0], 8.35, 1.65)
	garage_walls()
	for x in [-17.7, 17.7]:
		box(Vector3(0.5, 8.1 if x < 0 else 10.1, 0.64), Vector3(x, 4.05 if x < 0 else 5.05, 12.4), "trim", 0.04)
	# Existing roof machinery is still separate; concrete plinths meet its bases.
	box(Vector3(6.3,0.5,4.3), Vector3(-14,11.75,-22), "trim", 0.04)
	box(Vector3(9.3,0.5,5.3), Vector3(11,11.75,-23), "trim", 0.04)
	# New garage entrance surround remains outside the physical 7x5m aperture.
	for x in [-3.9, 3.9]: box(Vector3(0.65,5.65,0.32), Vector3(x,2.825,14.52), "trim", 0.06)
	box(Vector3(8.45,0.45,0.4), Vector3(0,5.7,14.54), "trim", 0.055)
	box(Vector3(19.8,0.22,0.55), Vector3(0,6.94,14.4), "steel", 0.035)
	label("BAY 01", Vector3(-21.3,7.25,12.55), 0.007)
	label("SERVICE 02", Vector3(21.3,8.4,12.55), 0.006)
	label("MOTOR POOL", Vector3(0,6.25,14.53), 0.006)
	weathering_details()
	for key in batches:
		var data: Dictionary = batches[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.v
		arrays[Mesh.ARRAY_NORMAL] = data.n
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
		arrays[Mesh.ARRAY_COLOR] = data.c
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var node := MeshInstance3D.new()
		node.name = key.capitalize() + "Architecture"
		node.mesh = mesh
		node.material_override = materials[key]
		if key in ["runoff", "fracture"]: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(node)
		node.owner = scene
	var packed := PackedScene.new()
	var triangles := 0
	for data in batches.values(): triangles += data.v.size() / 3
	print("Shelter architecture: %d triangles in %d material batches" % [triangles, batches.size()])
	packed.pack(scene)
	var error := ResourceSaver.save(packed, "res://world/starting_shelter/facade.tscn")
	scene.free()
	print("PASS: authored shelter walls saved" if error == OK else "FAIL: shelter scene save")
	quit(0 if error == OK else 1)

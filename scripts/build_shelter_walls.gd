extends SceneTree
## Offline authoring source. Only writes the shelter's replaceable facade scene.
## Run with -- --write to explicitly rebuild this authored asset.
var batches: Dictionary = {}
var materials: Dictionary = {}
var scene: Node3D

func _init() -> void:
	build.call_deferred()

func face(points: Array[Vector3], normal: Vector3, material: String, uvs: Array[Vector2] = [], tint := Color.WHITE) -> void:
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0:
		points.reverse()
		uvs.reverse()
	if not batches.has(material): batches[material] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray()}
	var data: Dictionary = batches[material]
	for i in range(1, points.size() - 1):
		for index in [0, i, i + 1]:
			var p := points[index]
			data.v.append(p)
			data.n.append(normal)
			data.uv.append(uvs[index] if not uvs.is_empty() else Vector2(p.x + p.z, p.y))
			data.c.append(tint)

func box(size: Vector3, pos: Vector3, material := "concrete", bevel := 0.025, rotation := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.4)
	for axis in range(3):
		var j := (axis + 1) % 3
		var k := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
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

func runoff(top: Vector3, width: float, length: float, rotation := Basis.IDENTITY, tint := Color(0.19, 0.16, 0.13, 0.65)) -> void:
	var points: Array[Vector3] = []
	for p in [Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(width * 0.5, -length, 0), Vector3(-width * 0.5, -length, 0)]:
		points.append(top + rotation * p)
	face(points, rotation * Vector3.BACK, "runoff", [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)], tint)

func crack(origin: Vector3, points: Array[Vector2], rotation := Basis.IDENTITY, width := 0.01) -> void:
	for i in range(points.size() - 1):
		var side := (points[i + 1] - points[i]).orthogonal().normalized() * width * 0.5
		var strip: Array[Vector3] = []
		for p in [points[i] - side, points[i] + side, points[i + 1] + side, points[i + 1] - side]:
			strip.append(origin + rotation * Vector3(p.x, p.y, 0))
		face(strip, rotation * Vector3.BACK, "fracture")

func spall(origin: Vector3, size: Vector2, rotation := Basis.IDENTITY) -> void:
	# A shallow exposed-aggregate patch with an irregular concrete lip, not a rectangle.
	var outline := PackedVector2Array([
		Vector2(-0.5,-0.12), Vector2(-0.31,-0.24), Vector2(-0.37,-0.34),
		Vector2(-0.18,-0.32), Vector2(-0.08,-0.49), Vector2(0.01,-0.36),
		Vector2(0.17,-0.4), Vector2(0.23,-0.25), Vector2(0.42,-0.21),
		Vector2(0.38,-0.07), Vector2(0.5,0.05), Vector2(0.27,0.16),
		Vector2(0.31,0.3), Vector2(0.09,0.25), Vector2(-0.05,0.48),
		Vector2(-0.12,0.29), Vector2(-0.34,0.35), Vector2(-0.3,0.12),
		Vector2(-0.48,0.17), Vector2(-0.42,0.01)])
	for i in range(outline.size()): outline[i] *= size
	var indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, indices.size(), 3):
		var points: Array[Vector3] = []
		for j in range(3):
			var p := outline[indices[i + j]] * 0.94
			points.append(origin + rotation * Vector3(p.x, p.y, 0))
		face(points, rotation * Vector3.BACK, "aggregate")
	for i in range(outline.size()):
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		var edge: Array[Vector3] = []
		for v in [Vector3(p.x,p.y,0.009), Vector3(q.x,q.y,0.009), Vector3(q.x*0.94,q.y*0.94,0), Vector3(p.x*0.94,p.y*0.94,0)]:
			edge.append(origin + rotation * v)
		face(edge, rotation * Vector3.BACK, "trim")

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
	var split: Array[Vector2] = [Vector2(0,0), Vector2(0.18,-0.35), Vector2(0.08,-0.53), Vector2(0.36,-0.83), Vector2(0.29,-1.1), Vector2(0.51,-1.44)]
	for point in [Vector3(-23.5,3.48,12.506), Vector3(-12.3,3.48,12.506), Vector3(19.2,4.68,12.506), Vector3(-7.7,4.9,14.506)]:
		crack(point, split)
		crack(point + Vector3(0.36,-0.83,0), [Vector2.ZERO, Vector2(0.3,-0.04), Vector2(0.56,-0.3)], Basis.IDENTITY, 0.004)
	spall(Vector3(-23.65,0.7,12.51), Vector2(1.05,0.65))
	spall(Vector3(-17.7,1.9,12.726), Vector2(0.42,0.65))
	spall(Vector3(19.1,2.6,12.51), Vector2(0.65,0.95))
	spall(Vector3(-7.3,1.05,14.51), Vector2(1.0,0.55))
	# Interior marks originate under the service pipes; no decorations enter the lane.
	var left := Basis(Vector3.UP, PI * 0.5)
	var right := Basis(Vector3.UP, -PI * 0.5)
	for z in [-8.4, -3.1, 4.8, 9.4]:
		runoff(Vector3(-9.989,4.21,z), 0.8 if z < 0 else 1.4, 3.5 if z < 5 else 2.6, left)
	for z in [-6.9, 3.2]: runoff(Vector3(9.989,4.22,z), 1.15, 3.2, right)
	crack(Vector3(-9.985,3.9,-7.0), split, left)
	crack(Vector3(-9.985,2.8,3.3), split, left)
	crack(Vector3(9.985,4.0,-4.0), split, right)
	spall(Vector3(-9.985,0.85,-3.0), Vector2(1.3,0.62), left)
	spall(Vector3(-9.985,3.8,3.8), Vector2(1.25,0.35), left)
	spall(Vector3(9.985,1.2,7.9), Vector2(1.1,0.63), right)
	runoff(Vector3(-7.8,6.65,14.511), 1.5, 3.6)
	runoff(Vector3(7.5,6.65,14.511), 1.2, 4.1)

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
			box(Vector3(cuts[i + 1] - cuts[i] - 0.014, span.y - span.x, 0.45), Vector3(x, (span.x + span.y) * 0.5, front - 0.225))
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
	var break_x := x0 + width * 0.61
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
	materials.trim = materials.concrete.duplicate()
	materials.trim.set_shader_parameter("concrete_color", Color("8e897e"))
	materials.trim.set_shader_parameter("formwork_strength", 0.0)
	materials.steel = load("res://world/starting_shelter/materials/aged_metal.tres")
	materials.shutter = materials.steel.duplicate()
	materials.shutter.set_shader_parameter("metal_color", Color("61584b"))
	materials.shutter.set_shader_parameter("corrosion", 0.85)
	materials.aggregate = materials.concrete.duplicate()
	materials.aggregate.set_shader_parameter("concrete_color", Color("898073"))
	materials.aggregate.set_shader_parameter("formwork_strength", 0.0)
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
	scene.set_meta("art_status", "authored aged concrete walls, damaged coping, rusted sealed louvers and localized runoff")
	block(-25, -10.4, -14.5, 12.5, 9, [-21.3, -14.4], 3.5)
	block(10.4, 25, -14.5, 12.5, 11, [14.4, 21.3], 4.7)
	block(-25, 25, -30.5, -14.35, 12, [-18.0, -9.0, 0.0, 9.0, 18.0], 8.35, 1.65)
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
	packed.pack(scene)
	var error := ResourceSaver.save(packed, "res://world/starting_shelter/facade.tscn")
	scene.free()
	print("PASS: authored shelter walls saved" if error == OK else "FAIL: shelter scene save")
	quit(0 if error == OK else 1)

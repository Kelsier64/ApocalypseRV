extends RefCounted
class_name MegashelterInteriorKit
## Small, replaceable fittings in metres. Structure and gameplay collision stay
## in the room wrapper. Local +Z is the front of wall-mounted assemblies.

static func _part(parts: Array[Dictionary], at: Vector3, size: Vector3, material := 2, shape := "bevel", basis := Basis.IDENTITY) -> void:
	parts.append({"center": at, "size": size, "material": material, "shape": shape,
		"basis": basis, "bevel": 0.025, "shade": 0.92, "steel_corrosion": 0.38})

static func _bolt(parts: Array[Dictionary], at: Vector3, radius := 0.035) -> void:
	_part(parts, at, Vector3(radius*2, radius*2, radius*0.65), 2, "cylinder")
	parts[-1].axis = 2
	parts[-1].steel_corrosion = 0.2

static func pipe(parts: Array[Dictionary], a: Vector3, b: Vector3, radius := 0.025, material := 2) -> void:
	var delta := b - a
	if delta.length_squared() < 0.000001: return
	_part(parts, (a+b)*0.5, Vector3(radius*2, delta.length(), radius*2), material, "cylinder", Basis(Quaternion(Vector3.UP, delta.normalized())))
	parts[-1].axis = 1

static func _plate(parts: Array[Dictionary], at: Vector3, size: Vector2, material := 2) -> void:
	_part(parts, at, Vector3(size.x, size.y, 0.035), material)
	for x in [-size.x*0.39, size.x*0.39]:
		for y in [-size.y*0.36, size.y*0.36]: _bolt(parts, at + Vector3(x, y, 0.029), 0.023)

static func _ring(parts: Array[Dictionary], at: Vector3, size: Vector3, material: int, profile: Array[Vector2], basis := Basis.IDENTITY) -> void:
	_part(parts, at, size, material, "lathe", basis)
	parts[-1].profile = profile

static func large_door() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	# One double-leaf blast-door assembly, with a visible central meeting seam.
	for x in [-2.03, 2.03]:
		_part(parts, Vector3(x, 1.65, 0), Vector3(0.2, 3.3, 0.28), 0)
		_plate(parts, Vector3(x, 1.65, 0.15), Vector2(0.16, 3.16))
	_part(parts, Vector3(0, 3.25, 0.015), Vector3(4.25, 0.2, 0.3), 0)
	_part(parts, Vector3(0, 3.16, 0.13), Vector3(3.9, 0.12, 0.14))
	_part(parts, Vector3(0, 0.025, 0.12), Vector3(4.15, 0.05, 0.42))
	for side: int in [-1, 1]:
		var x := side * 0.965
		_part(parts, Vector3(x, 1.54, 0), Vector3(1.91, 3.04, 0.15))
		# Recessed gasket, perimeter armor, panels and bolted reinforcement.
		_part(parts, Vector3(x, 1.54, 0.087), Vector3(1.84, 2.96, 0.025), 4)
		_part(parts, Vector3(x, 1.54, 0.11), Vector3(1.73, 2.84, 0.045))
		for y in [0.36, 1.48, 2.61]:
			_plate(parts, Vector3(x, y, 0.16), Vector2(1.54, 0.69))
			_part(parts, Vector3(x, y, 0.2), Vector3(1.66, 0.07, 0.08))
		for edge in [-0.87, 0.87]: _part(parts, Vector3(x+edge, 1.54, 0.16), Vector3(0.07, 2.96, 0.1))
		for y in [0.48, 1.53, 2.64]:
			var hx := side * 1.82
			_plate(parts, Vector3(hx, y, 0.19), Vector2(0.22, 0.3))
			pipe(parts, Vector3(hx, y-0.17, 0.25), Vector3(hx, y+0.17, 0.25), 0.065)
		for y in [0.85, 2.1]:
			pipe(parts, Vector3(side*0.11, y, 0.26), Vector3(side*1.3, y, 0.26), 0.045)
			_plate(parts, Vector3(side*1.3, y, 0.2), Vector2(0.2, 0.26))
	_plate(parts, Vector3(0, 1.53, 0.2), Vector2(0.19, 1.1))
	var wheel := Vector3(-0.4, 1.45, 0.34)
	_ring(parts, wheel, Vector3(0.43, 0.055, 0.43), 2, [Vector2(0.5,0),Vector2(0.5,1),Vector2(0.38,1),Vector2(0.38,0),Vector2(0.5,0)], Basis(Vector3.RIGHT, PI*0.5))
	for spoke in 6:
		var a := TAU * spoke / 6.0
		pipe(parts, wheel, wheel+Vector3(cos(a), sin(a), 0)*0.19, 0.016)
	_bolt(parts, wheel + Vector3(0, 0, 0.03), 0.05)
	for x in [-1.8, -0.6, 0.6, 1.8]:
		_part(parts, Vector3(x, 3.05, 0.17), Vector3(0.19, 0.16, 0.12))
	return parts

static func pedestrian_door() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for x in [-0.61, 0.61]:
		_part(parts, Vector3(x, 1.24, 0), Vector3(0.15, 2.48, 0.24), 0)
		_part(parts, Vector3(x, 1.24, 0.13), Vector3(0.1, 2.42, 0.07))
		for y in [0.15, 1.25, 2.34]: _bolt(parts, Vector3(x, y, 0.185), 0.033)
	_part(parts, Vector3(0, 2.43, 0), Vector3(1.36, 0.17, 0.25), 0)
	_part(parts, Vector3(0, 0.025, 0.07), Vector3(1.25, 0.05, 0.3))
	_part(parts, Vector3(0, 1.19, 0.035), Vector3(1.055, 2.32, 0.08), 4)
	_part(parts, Vector3(0, 1.19, 0.09), Vector3(0.99, 2.26, 0.09))
	_part(parts, Vector3(0, 1.35, 0.147), Vector3(0.86, 1.62, 0.032), 1)
	_plate(parts, Vector3(0, 0.29, 0.16), Vector2(0.9, 0.38))
	for y in [0.4, 1.25, 2.12]:
		_plate(parts, Vector3(-0.48, y, 0.16), Vector2(0.19, 0.19))
		pipe(parts, Vector3(-0.52, y-0.11, 0.22), Vector3(-0.52, y+0.11, 0.22), 0.035)
		_bolt(parts, Vector3(-0.52, y+0.1, 0.25), 0.037)
	_plate(parts, Vector3(0.32, 1.12, 0.19), Vector2(0.13, 0.3))
	pipe(parts, Vector3(0.32, 1.17, 0.21), Vector3(0.32, 1.17, 0.32), 0.025)
	pipe(parts, Vector3(0.32, 1.17, 0.32), Vector3(0.12, 1.17, 0.32), 0.025)
	_bolt(parts, Vector3(0.32, 1.06, 0.235), 0.027)
	# Door closer, mounting shoe and jointed arm have distinct silhouettes.
	_plate(parts, Vector3(-0.12, 2.24, 0.19), Vector2(0.36, 0.11))
	_part(parts, Vector3(-0.12, 2.24, 0.245), Vector3(0.3, 0.085, 0.12))
	pipe(parts, Vector3(-0.12, 2.29, 0.3), Vector3(0.17, 2.39, 0.32), 0.014)
	pipe(parts, Vector3(0.17, 2.39, 0.32), Vector3(0.4, 2.43, 0.18), 0.014)
	_plate(parts, Vector3(0.4, 2.44, 0.14), Vector2(0.12, 0.07))
	# Closed inspection cover, not a window or an active screen.
	_plate(parts, Vector3(0, 1.81, 0.18), Vector2(0.16, 0.11))
	_part(parts, Vector3(0.81, 1.26, -0.02), Vector3(0.21, 0.34, 0.18))
	_plate(parts, Vector3(0.81, 1.26, 0.05), Vector2(0.21, 0.34))
	_part(parts, Vector3(0.81, 1.28, 0.09), Vector3(0.15, 0.22, 0.045), 4)
	for x in [0.77, 0.82, 0.87]:
		for y in [1.2, 1.25]: _bolt(parts, Vector3(x, y, 0.12), 0.008)
	return parts

static func wall_bay(span: float, height: float, variant: int) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var x := -span*0.5 + 1.6
	match variant % 4:
		0:
			_plate(parts, Vector3(x, 1.45, 0.31), Vector2(0.7, 0.82))
			_part(parts, Vector3(x, 1.45, 0.38), Vector3(0.57, 0.68, 0.1))
			for y in [1.29, 1.41, 1.53]: _part(parts, Vector3(x, y, 0.44), Vector3(0.34, 0.023, 0.025), 4, "box")
			pipe(parts, Vector3(x, 1.86, 0.33), Vector3(x, height-0.36, 0.33), 0.025)
			pipe(parts, Vector3(x, height-0.36, 0.33), Vector3(x+1.05, height-0.36, 0.33), 0.025)
			for y in [2.05, height-0.43]: _plate(parts, Vector3(x, y, 0.29), Vector2(0.16, 0.09))
		1:
			# Vent hood with a dark recess, angled louvres and a screwed flange.
			_plate(parts, Vector3(x, 2.26, 0.29), Vector2(1.15, 0.68))
			_part(parts, Vector3(x, 2.26, 0.32), Vector3(1.0, 0.54, 0.025), 4)
			for i in 6:
				_part(parts, Vector3(x, 2.04+i*0.086, 0.39), Vector3(0.93, 0.045, 0.14), 2, "box", Basis(Vector3.RIGHT, -0.35))
			pipe(parts, Vector3(x-0.66, 0.23, 0.35), Vector3(x-0.66, 2.72, 0.35), 0.038)
			for y in [0.6, 1.65, 2.55]: _plate(parts, Vector3(x-0.66, y, 0.28), Vector2(0.19, 0.1))
		2:
			for i in 2:
				var px := x-0.26+i*0.42
				pipe(parts, Vector3(px, 0.18, 0.38), Vector3(px, height-0.32, 0.38), 0.045-i*0.012)
				for y in [0.6, 1.55, height-0.55]:
					_part(parts, Vector3(px, y, 0.38), Vector3(0.13, 0.09, 0.13), 2, "cylinder")
					parts[-1].axis = 1
					_plate(parts, Vector3(px, y+0.15, 0.27), Vector2(0.22, 0.08))
			pipe(parts, Vector3(x-0.26, 1.1, 0.38), Vector3(x-0.26, 1.1, 0.58), 0.035)
			_ring(parts, Vector3(x-0.26, 1.1, 0.6), Vector3(0.25, 0.045, 0.25), 2, [Vector2(0.5,0),Vector2(0.5,1),Vector2(0.35,1),Vector2(0.35,0),Vector2(0.5,0)], Basis(Vector3.RIGHT, PI*0.5))
		3:
			# A quieter repair bay gives the repeated modules some empty wall.
			_plate(parts, Vector3(x, 1.05, 0.28), Vector2(0.85, 0.58), 1)
			for xx in [-0.24, 0.24]: _part(parts, Vector3(x+xx, 1.05, 0.32), Vector3(0.045, 0.63, 0.03))
			pipe(parts, Vector3(x-0.6, 0.25, 0.33), Vector3(x-0.6, 2.56, 0.33), 0.022)
	return parts

static func table(size: Vector2) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	_part(parts, Vector3(0, 0.85, 0), Vector3(size.x, 0.1, size.y), 1)
	_part(parts, Vector3(0, 0.78, 0), Vector3(size.x-0.12, 0.08, size.y-0.12))
	for x in [-size.x*0.4, size.x*0.4]:
		for z in [-size.y*0.4, size.y*0.4]:
			_part(parts, Vector3(x, 0.4, z), Vector3(0.065, 0.8, 0.065))
			_part(parts, Vector3(x, 0.035, z), Vector3(0.13, 0.07, 0.13), 4)
		pipe(parts, Vector3(x, 0.2, -size.y*0.4), Vector3(x, 0.2, size.y*0.4), 0.023)
	pipe(parts, Vector3(-size.x*0.4, 0.2, 0), Vector3(size.x*0.4, 0.2, 0), 0.023)
	return parts

static func bench() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for x in [-0.18, 0, 0.18]: _part(parts, Vector3(x, 0.46, 0), Vector3(0.16, 0.065, 2.5), 5)
	for y in [0.67, 0.88]: _part(parts, Vector3(-0.25, y, 0), Vector3(0.065, 0.17, 2.5), 5)
	for z in [-0.93, 0.93]:
		_part(parts, Vector3(0, 0.23, z), Vector3(0.42, 0.46, 0.055))
		_part(parts, Vector3(-0.25, 0.66, z), Vector3(0.055, 0.61, 0.055))
		_part(parts, Vector3(0, 0.035, z), Vector3(0.56, 0.05, 0.16))
		for y in [0.67, 0.87]: _bolt(parts, Vector3(-0.29, y, z), 0.025)
	pipe(parts, Vector3(0, 0.28, -1.08), Vector3(0, 0.28, 1.08), 0.026)
	return parts

static func sink() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	# Four sloping rim walls surround a genuine open basin.
	_part(parts, Vector3(0, 0.78, 0), Vector3(0.78, 0.09, 0.54), 3)
	for x in [-0.43, 0.43]: _part(parts, Vector3(x, 0.89, 0), Vector3(0.12, 0.22, 0.68), 3)
	for z in [-0.31, 0.31]: _part(parts, Vector3(0, 0.89, z), Vector3(0.82, 0.22, 0.1), 3)
	for x in [-0.45, 0.45]: _part(parts, Vector3(x, 1.0, 0), Vector3(0.1, 0.055, 0.75), 3)
	for z in [-0.34, 0.34]: _part(parts, Vector3(0, 1.0, z), Vector3(0.82, 0.055, 0.08), 3)
	_part(parts, Vector3(0, 0.835, 0), Vector3(0.1, 0.01, 0.1), 2, "cylinder")
	parts[-1].axis = 1
	for x in [-0.29, 0.29]:
		pipe(parts, Vector3(x, 0.73, -0.23), Vector3(x, 0.73, -0.48), 0.025)
		pipe(parts, Vector3(x, 0.73, -0.48), Vector3(x, 0.9, -0.48), 0.025)
	pipe(parts, Vector3(0, 0.78, 0), Vector3(0, 0.53, 0), 0.035)
	pipe(parts, Vector3(0, 0.53, 0), Vector3(0, 0.45, -0.08), 0.035)
	pipe(parts, Vector3(0, 0.45, -0.08), Vector3(0, 0.45, -0.4), 0.035)
	pipe(parts, Vector3(0, 0.45, -0.4), Vector3(0, 0.65, -0.4), 0.035)
	pipe(parts, Vector3(0.15, 1.01, -0.26), Vector3(0.15, 1.25, -0.26), 0.021)
	pipe(parts, Vector3(0.15, 1.25, -0.26), Vector3(0.15, 1.28, -0.2), 0.021)
	pipe(parts, Vector3(0.15, 1.28, -0.2), Vector3(0.15, 1.28, -0.08), 0.021)
	pipe(parts, Vector3(0.15, 1.28, -0.08), Vector3(0.15, 1.23, -0.06), 0.021)
	for x in [-0.13, 0.13]: pipe(parts, Vector3(0.15+x, 1.08, -0.26), Vector3(0.15+x, 1.12, -0.2), 0.012)
	return parts

static func toilet() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	_ring(parts, Vector3(0, 0.19, 0), Vector3(0.4, 0.38, 0.5), 3,
		[Vector2(0,0),Vector2(0.43,0),Vector2(0.5,0.08),Vector2(0.33,0.65),Vector2(0.46,1),Vector2(0,1)])
	_ring(parts, Vector3(0, 0.43, 0.03), Vector3(0.57, 0.23, 0.72), 3,
		[Vector2(0.23,0),Vector2(0.42,0.17),Vector2(0.5,0.82),Vector2(0.49,1),Vector2(0.36,1),Vector2(0.31,0.4),Vector2(0.1,0.18),Vector2(0.23,0)])
	_ring(parts, Vector3(0, 0.565, 0.03), Vector3(0.57, 0.045, 0.72), 4,
		[Vector2(0.49,0),Vector2(0.49,1),Vector2(0.35,1),Vector2(0.35,0),Vector2(0.49,0)])
	_part(parts, Vector3(0, 0.72, -0.3), Vector3(0.47, 0.56, 0.2), 3)
	_part(parts, Vector3(0, 1.01, -0.3), Vector3(0.49, 0.05, 0.23), 3)
	_part(parts, Vector3(-0.2, 0.86, -0.18), Vector3(0.1, 0.035, 0.035))
	pipe(parts, Vector3(0.18, 0.57, -0.32), Vector3(0.18, 0.24, -0.4), 0.012)
	return parts

static func add_lathe(batch: MegashelterKit.Batch, pose: Transform3D, piece: Dictionary) -> void:
	var local := pose * Transform3D(piece.get("basis", Basis.IDENTITY), piece.center)
	var profile: Array = piece.profile
	var size: Vector3 = piece.size
	for level in range(profile.size()-1):
		var a: Vector2 = profile[level]
		var b: Vector2 = profile[level+1]
		for i in 16:
			var theta := TAU * i / 16.0
			var next := TAU * (i+1) / 16.0
			var points: Array[Vector3] = []
			for sample: Vector3 in [Vector3(theta,a.x,a.y), Vector3(next,a.x,a.y), Vector3(next,b.x,b.y), Vector3(theta,b.x,b.y)]:
				points.append(Vector3(cos(sample.x)*sample.y*size.x, (sample.z-0.5)*size.y, sin(sample.x)*sample.y*size.z))
			var middle := (theta+next)*0.5
			var normal := Vector3(cos(middle)*(b.y-a.y)/size.x, -(b.x-a.x)/size.y, sin(middle)*(b.y-a.y)/size.z).normalized()
			if is_zero_approx(a.x): points.remove_at(1)
			elif is_zero_approx(b.x): points.remove_at(3)
			batch._face(local, Vector3.ZERO, points, normal, 0.93)

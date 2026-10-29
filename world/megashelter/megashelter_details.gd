extends RefCounted
class_name MegashelterDetails
## Ground-level service assemblies. Same floor/front origin as the main kit.
## Broad silhouettes carry the detail; fasteners are used only on focal pieces.
static func pieces(kind: String, size: Vector3, variant: int) -> Array[Dictionary]:
	var p: Array[Dictionary] = []
	var back := -size.z
	match kind:
		"service_cabinet":
			_box(p,Vector3(0,0.16,-0.65),Vector3(3.1,0.32,1.3),0,0.08)
			_box(p,Vector3(0,1.7,-0.65),Vector3(2.8,2.8,1.05),2,0.07)
			# Deep frame, two independently legible doors, rain cap and dead meter.
			for side: float in [-1,1]:
				_box(p,Vector3(side*0.69,1.7,-0.09),Vector3(1.25,2.56,0.12),2,0.03,0.9)
				_box(p,Vector3(side*0.16,1.65,0.0),Vector3(0.09,0.4,0.14),2,0.02)
				for y: float in [0.75,2.6]:
					_box(p,Vector3(side*1.27,y,-0.01),Vector3(0.14,0.28,0.16),2,0.025)
				for slat in range(5):
					_box(p,Vector3(side*0.69,0.65+slat*0.14,-0.015),Vector3(0.95,0.065,0.1),2,0,0.5)
			_box(p,Vector3(0,3.16,-0.6),Vector3(3.15,0.16,1.45),2,0.04)
			_box(p,Vector3(-0.68,2.5,-0.005),Vector3(0.62,0.35,0.08),2,0.025,0.35)
			# Feeder conduits run into wall junction boxes, rather than ending in air.
			for x: float in [-0.85,0,0.85]:
				_pipe(p,Vector3(x,4.25,back+0.26),Vector3(0.18,2.5,0.18))
				_box(p,Vector3(x,5.6,back+0.17),Vector3(0.52,0.6,0.34),2,0.04)
				for y: float in [3.5,4.8]: _box(p,Vector3(x,y,back+0.2),Vector3(0.35,0.12,0.4),2)
			if variant%2 == 1:
				_box(p,Vector3(0.69,1.7,-0.012),Vector3(0.9,0.9,0.035),2,0,0.4)
		"pipe_manifold":
			for x: float in [-0.85,0.85]:
				_box(p,Vector3(x,0.15,-0.65),Vector3(0.95,0.3,1.25),0,0.06)
				_pipe(p,Vector3(x,3.3,-0.55),Vector3(0.48,6.4,0.48))
				for y: float in [0.6,2.0,4.8,6.1]:
					_pipe(p,Vector3(x,y,-0.55),Vector3(0.7,0.18,0.7),1,1)
					_box(p,Vector3(x,y,back+0.17),Vector3(0.85,0.2,0.34),2,0.025)
				# Wall-return elbows and bolted sleeves visibly terminate the risers.
				_box(p,Vector3(x,6.55,-0.8),Vector3(0.58,0.58,0.8),2,0.15)
				_box(p,Vector3(x,6.55,back+0.045),Vector3(0.95,0.95,0.09),2,0.03)
				_wheel(p,Vector3(x,1.8,-0.12),0.43)
			_pipe(p,Vector3(0,3.7,-0.55),Vector3(2.2,0.35,0.35))
			_box(p,Vector3(0,3.7,-0.55),Vector3(0.55,0.65,0.55),2,0.08)
		"intake_hood":
			# Sealed dark backing; the hood is industrial ventilation, never a window.
			_box(p,Vector3(0,3.65,back+0.12),Vector3(3.1,3.15,0.24),2,0.035,0.4)
			for x: float in [-1.5,1.5]: _box(p,Vector3(x,3.65,-0.58),Vector3(0.22,3.3,1.1),2,0.04)
			for y: float in [2.0,5.3]: _box(p,Vector3(0,y,-0.58),Vector3(3.2,0.22,1.15),2,0.04)
			for index in range(7):
				if variant%2 == 1 and index == 2: continue
				_box(p,Vector3(0,2.25+index*0.43,-0.48),Vector3(2.8,0.2,0.85),2,0.06,0.8)
			# Deep projecting cap and a grounded service duct below the intake.
			_box(p,Vector3(0,5.5,-0.58),Vector3(3.5,0.24,1.4),2,0.06)
			_box(p,Vector3(0,1.0,back+0.22),Vector3(1.15,2.0,0.44),2,0.05)
			for y: float in [0.4,1.5]: _box(p,Vector3(0,y,back+0.26),Vector3(1.4,0.16,0.52),2)
		"wall_salvage":
			_box(p,Vector3(0,1.4,back+0.035),Vector3(2.5,2.5,0.07),0,0,0.72,"spall")
			for x: float in [-0.85,-0.42,0,0.42,0.85]:
				_pipe(p,Vector3(x,1.4,back+0.11),Vector3(0.055,2.2,0.055),3)
			for y: float in [0.6,1.4,2.2]: _pipe(p,Vector3(0,y,back+0.12),Vector3(2.2,0.055,0.055),3)
			# Broken skins still attached to the exposed reinforcement.
			_box(p,Vector3(-0.92,1.9,back+0.19),Vector3(0.5,0.75,0.24),0,0,0.88,"chip")
			_box(p,Vector3(0.84,0.7,back+0.18),Vector3(0.65,0.8,0.22),0,0,0.82,"chip")
			var debris_rng := RandomNumberGenerator.new()
			debris_rng.seed = 8107+variant*7919
			for index in range(18):
				# Large fractured slabs remain close to the source; small chips spread out.
				var large := index < 5
				var extent := Vector3(debris_rng.randf_range(0.4,0.8),debris_rng.randf_range(0.16,0.32),debris_rng.randf_range(0.28,0.5)) if large else Vector3(debris_rng.randf_range(0.12,0.32),debris_rng.randf_range(0.05,0.14),debris_rng.randf_range(0.12,0.28))
				var center := Vector3(debris_rng.randf_range(-0.96,0.96),extent.y*0.5,debris_rng.randf_range(back+0.42,-0.3) if large else debris_rng.randf_range(back+0.3,-0.2))
				_box(p,center,extent,0,0,debris_rng.randf_range(0.72,0.98),"chip")
				p.back()["basis"] = Basis(Vector3.UP,debris_rng.randf_range(-PI,PI))
				p.back()["chip_variant"] = index+variant*19
		"portal_canopy":
			_box(p,Vector3(0,0.62,-size.z*0.5),Vector3(size.x,0.38,size.z),2,0.09)
			_box(p,Vector3(0,0.4,-0.12),Vector3(size.x,0.4,0.24),0,0.05)
			for x: float in [-4.8,-2.4,0,2.4,4.8]:
				_box(p,Vector3(x,0.26,-size.z*0.5),Vector3(0.18,0.52,size.z-0.2),2,0.035)
				_box(p,Vector3(x,0.35,-size.z+0.16),Vector3(0.5,0.7,0.32),2,0.04)
			for x: float in [-3.0,3.0]:
				_box(p,Vector3(x,0.13,-0.95),Vector3(1.8,0.18,0.42),2,0.035)
				_box(p,Vector3(x,0.025,-0.95),Vector3(1.5,0.05,0.28),2,0,0.38)
		"service_fan":
			_box(p,Vector3(0,0.16,-size.z*0.5),Vector3(size.x,0.32,size.z),0,0.08)
			_box(p,Vector3(0,1.72,-size.z*0.5),Vector3(3.1,2.8,2.4),2)
			p.back()["visible"] = false # Fitted GLB, bottom-centred at y=0.32.
			# A rectangular trunk connects the machine's rear outlet to the wall.
			_box(p,Vector3(0,3.35,back+0.42),Vector3(1.45,1.9,0.84),2,0.08)
			_box(p,Vector3(0,4.3,back+0.08),Vector3(1.9,0.6,0.16),2,0.035)
	if kind == "service_cabinet" and size.y < 3.0:
		# A low service cupboard fits beneath horizontal armour bands.
		for piece: Dictionary in p:
			piece.center.y *= 0.45
			piece.size.y *= 0.45
	return p

## Six flat assemblies: overlapping repairs, corrugated patch, strapped seam,
## hinged hatch, cable chase and stripped mounting frame. All remain sealed.
static func wall_panels(size: Vector3, variant: int) -> Array[Dictionary]:
	var p: Array[Dictionary] = []
	var kind := posmod(variant-8,6)
	var center := Vector3(0,minf(size.y*0.5,2.3),0)
	match kind:
		0:
			_plate(p,center+Vector3(-0.4,-0.16,0.05),Vector2(1.65,1.55),0.85)
			_plate(p,center+Vector3(0.47,0.25,0.13),Vector2(1.25,1.4),0.69)
			_segment(p,center+Vector3(-1.05,-0.69,0.17),center+Vector3(0.98,0.78,0.17),0.075)
		1:
			_box(p,center+Vector3(0,0,0.05),Vector3(2.45,1.9,0.1),2,0.025,0.7)
			for index in range(9):
				_box(p,center+Vector3(-1.04+index*0.26,0,0.13),Vector3(0.13,1.8,0.14),2,0.025,0.87)
			for y: float in [-0.7,0.7]: _box(p,center+Vector3(0,y,0.23),Vector3(2.65,0.12,0.08),2,0.015)
		2:
			_plate(p,center+Vector3(-0.65,0,0.045),Vector2(1.1,1.9),0.72)
			_plate(p,center+Vector3(0.65,0,0.045),Vector2(1.1,1.9),0.9)
			for y: float in [-0.62,0.62]: _plate(p,center+Vector3(0,y,0.13),Vector2(2.65,0.24),0.8)
		3:
			_box(p,center+Vector3(0,0,0.05),Vector3(1.95,2.15,0.1),2,0.035,0.5)
			_plate(p,center+Vector3(0,0,0.14),Vector2(1.68,1.9),0.92)
			for y: float in [-0.58,0.58]: _box(p,center+Vector3(-0.84,y,0.22),Vector3(0.23,0.36,0.15),2,0.035)
			_box(p,center+Vector3(0.57,0,0.27),Vector3(0.09,0.4,0.1),2,0.02)
			_box(p,center+Vector3(0,1.11,0.16),Vector3(2.13,0.12,0.3),2,0.025)
		4:
			_plate(p,center+Vector3(0.57,0.35,0.055),Vector2(1.05,0.85),0.85)
			for x: float in [-0.65,-0.38]:
				_pipe(p,center+Vector3(x,0,0.12),Vector3(0.09,2.15,0.09))
				_box(p,center+Vector3(x,1.1,0.08),Vector3(0.22,0.18,0.16),2,0.02)
				_box(p,center+Vector3(x,-1.05,0.08),Vector3(0.24,0.2,0.16),2,0.02)
			for y: float in [-0.67,0.65]: _box(p,center+Vector3(-0.51,y,0.18),Vector3(0.63,0.09,0.1),2,0.015)
			_box(p,center+Vector3(-0.07,0.35,0.12),Vector3(0.7,0.12,0.12),2,0.02)
		5:
			# Bare concrete stays visible through a missing cover, not a black window.
			for x: float in [-1.05,1.05]: _box(p,center+Vector3(x,0,0.065),Vector3(0.16,1.9,0.13),2,0.025,0.65)
			for y: float in [-0.88,0.88]: _plate(p,center+Vector3(0,y,0.07),Vector2(2.25,0.16),0.8)
			_plate(p,center+Vector3(-0.75,-0.47,0.14),Vector2(0.55,0.65),0.7)
	return p

static func _plate(p: Array[Dictionary], center: Vector3, size: Vector2, shade: float) -> void:
	_box(p,center,Vector3(size.x,size.y,0.075),2,0.018,shade)
	for x: float in [-1,1]:
		for y: float in [-1,1]:
			_box(p,center+Vector3(x*(size.x*0.5-0.08),y*(size.y*0.5-0.06),0.055),Vector3(0.065,0.065,0.04),2,0.012,0.58)

## Flush forecourt: expansion joints, threshold apron and drain, with a broken
## outer margin. Tops stay within 4cm of terrain; no invisible raised platform.
static func forecourt(seed_value: int) -> Array[Dictionary]:
	var p: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = ("megashelter:forecourt:%d" % seed_value).hash()
	# Coordinates are relative to the front of the entrance frame (+Z outward).
	for row in range(5):
		for column in range(8):
			var outer := column in [0,7] or row == 4
			var extent := Vector3(2.47,0.1,2.47)
			var center := Vector3(-8.75+column*2.5,-0.025,-1.25+row*2.5)
			_box(p,center,extent,0,0,rng.randf_range(0.77,0.95),"paver" if outer else "box")
			if outer: p.back()["chip_variant"] = column+row*8
	# A recessed dark bed and transverse steel bars read as a slotted drain.
	_box(p,Vector3(0,0.027,0.25),Vector3(10.0,0.012,0.38),2,0,0.35)
	for index in range(51):
		_box(p,Vector3(-4.9+index*0.196,0.035,0.25),Vector3(0.055,0.01,0.35),2,0,0.84)
	for z: float in [0.035,0.465]: _box(p,Vector3(0,0.032,z),Vector3(10.1,0.012,0.045),2,0,0.72)
	# Continuous threshold reaches the recessed blast leaves and portal feet.
	_box(p,Vector3(0,0.03,-2.25),Vector3(10.0,0.016,0.28),2,0,0.75)
	for side: float in [-1,1]:
		for row in range(4):
			_box(p,Vector3(side*5.7,0.025,0.8+row*2.0),Vector3(0.42,0.025,1.97),0,0,0.83)
		for index in range(9):
			var h := rng.randf_range(0.025,0.04)
			_box(p,Vector3(side*rng.randf_range(9.2,10.4),h/2,rng.randf_range(1,9.7)),Vector3(rng.randf_range(0.15,0.4),h,rng.randf_range(0.15,0.35)),0,0,rng.randf_range(0.75,0.92),"chip")
			p.back()["basis"] = Basis(Vector3.UP,rng.randf_range(-PI,PI))
	return p

static func _wheel(p: Array[Dictionary], center: Vector3, radius: float) -> void:
	# A real open octagonal hand wheel with four spokes, not a solid disc.
	for index in range(8):
		var a := TAU*index/8.0
		var b := TAU*(index+1)/8.0
		var start := center+Vector3(cos(a),sin(a),0)*radius
		var end := center+Vector3(cos(b),sin(b),0)*radius
		_segment(p,start,end,0.085)
	for axis: Vector3 in [Vector3.RIGHT,Vector3.UP]: _segment(p,center-axis*radius,center+axis*radius,0.06)
	_box(p,center+Vector3(0,0,-0.1),Vector3(0.17,0.17,0.32),2,0.025)

static func _segment(p: Array[Dictionary], a: Vector3, b: Vector3, width: float) -> void:
	_box(p,(a+b)*0.5,Vector3(width,a.distance_to(b),width),2)
	p.back()["basis"] = Basis(Quaternion(Vector3.UP,(b-a).normalized()))

static func _pipe(p: Array[Dictionary], center: Vector3, size: Vector3, variant: int = 2, axis: int = -1) -> void:
	_box(p,center,size,2,0,1.0-variant*0.055,"cylinder")
	p.back()["axis"] = axis

static func _box(p: Array[Dictionary], center: Vector3, size: Vector3, material: int, bevel: float = 0.0, shade: float = 1.0, shape: String = "box") -> void:
	p.append({"center":center,"size":size,"material":material,"shade":shade,"shape":"bevel" if bevel > 0 else shape,"bevel":bevel})

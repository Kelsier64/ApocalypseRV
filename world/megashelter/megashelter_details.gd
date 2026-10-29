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
			for index in range(7):
				var x := -1.2+index*0.39
				var h := 0.12+float((index+variant)%3)*0.1
				_box(p,Vector3(x,h*0.5,-0.3-float(index%2)*0.3),Vector3(0.4,h,0.45),0,0.08,0.75)
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

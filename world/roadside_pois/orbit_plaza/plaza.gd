extends Node3D
const Parts = preload("res://world/roadside_pois/orbit_plaza/plaza_parts.gd")
const Rooms = preload("res://world/roadside_pois/orbit_plaza/rooms.gd")
const DISPENSER = preload("res://world/roadside_pois/mile_end/dispenser.glb")

func configure(site_seed: int, show_meshes: bool) -> void:
	var exterior := RandomNumberGenerator.new()
	exterior.seed = ("orbit_arch:%d" % site_seed).hash()
	var shell := Parts.new($Visuals, $Collision, show_meshes)
	_terminal(shell, exterior)
	_fuel_lanes(shell, exterior)
	_marquee(shell, exterior)
	_yard_traces(shell, exterior)
	shell.flush()
	var rooms := Parts.new($Furnishings, $Collision, show_meshes)
	Rooms.new().furnish(rooms, $LootSpawns, site_seed)
	rooms.flush()

func _terminal(p: Parts, rng: RandomNumberGenerator) -> void:
	p.box(Vector3(0, 0.017, -9), Vector3(30.6, 0.15, 14.6), "tile", true)
	# Two long rooflights throw daylight across the booths and back counter.
	for span: Vector2 in [Vector2(-16.6,-13.2),Vector2(-11.0,-7.35),Vector2(-5.45,-1.4)]:
		var z := (span.x+span.y)/2
		p.box(Vector3(0,4.12,z),Vector3(31.4,0.27,span.y-span.x),"milk",true)
		p.box(Vector3(0,4.30,z),Vector3(31.6,0.11,span.y-span.x),"ink",true)
	for span: Vector2 in [Vector2(-13.2,-11.0),Vector2(-7.35,-5.45)]:
		var z := (span.x+span.y)/2
		for x: float in [-14.45,14.45]:
			p.box(Vector3(x,4.15,z),Vector3(2.5,0.32,span.y-span.x),"ink",true)
		for x: float in [-12,-9,-6,-3,0,3,6,9,12]:
			p.box(Vector3(x,4.20,z),Vector3(0.12,0.26,span.y-span.x+0.18),"steel",true)
		for edge: float in [span.x,span.y]:
			p.box(Vector3(0,4.36,edge),Vector3(28.4,0.22,0.12),"aqua",true)
	for x: float in [-15,15]:
		p.box(Vector3(x, 0.72, -9), Vector3(0.22, 1.44, 14.1), "aqua", true)
		p.box(Vector3(x, 2.07, -12.2), Vector3(0.22, 4.14, 7.6), "milk", true)
		p.box(Vector3(x, 3.89, -9), Vector3(0.24, 0.5, 14.1), "milk", true)
		for z: float in [-2.15,-4.2,-6.35,-8.45]:
			p.box(Vector3(x, 2.53, z), Vector3(0.18, 2.22, 0.10), "ink", true)
	# Perimeter openings line up with the two access markers. The rear freight
	# entrance leads into the dispatch wing and back through the internal doorway.
	_span(p, -15, 7.6, -16, 0, 4.09, "milk")
	_span(p, 10.4, 15, -16, 0, 4.09, "milk")
	_span(p, 7.6, 10.4, -16, 2.84, 4.09, "ink")
	for side: int in [-1,1]:
		var center := side * 8.25
		p.box(Vector3(center, 0.51, -2), Vector3(13.5, 1.02, 0.23), "aqua", true)
		p.box(Vector3(center, 1.04, -2), Vector3(13.6, 0.08, 0.36), "chrome", true)
		for i in range(6):
			var x := side * (1.53 + i * 2.67)
			p.box(Vector3(x, 2.28, -2), Vector3(0.10, 2.48, 0.17), "ink", true)
		p.box(Vector3(center, 3.02, -2), Vector3(13.5, 0.065, 0.13), "steel")
		var boarded := side * rng.randf_range(4.0, 11.7)
		for i in range(rng.randi_range(1, 3)):
			p.box(Vector3(boarded, 1.50 + i * 0.45, -1.86), Vector3(2.75, 0.15, 0.09), "umber", true, Vector3(0,0,rng.randf_range(-0.17,0.17)))
	p.box(Vector3(0, 3.79, -2), Vector3(30.75, 0.66, 0.42), "ink", true)
	p.box(Vector3(0, 3.53, -1.36), Vector3(31.6, 0.12, 1.65), "gold", true)
	for x: float in [-10,0,10]:
		p.box(Vector3(x, 4.12, -1.50), Vector3(5.0, 1.65, 0.19), "ink")
	p.sign_face(1,Vector3(-10,4.12,-1.40),4.85)
	p.sign_face(0,Vector3(0,4.12,-1.40),4.85)
	p.sign_face(4,Vector3(10,4.12,-1.40),4.85)
	for x: float in [-12,-5,2,9]:
		for z: float in [-5,-12]:
			p.box(Vector3(x, 3.92, z), Vector3(1.65, 0.13, 0.40), "steel")
			for tube: float in [-0.1,0.1]:
				p.box(Vector3(x, 3.835, z+tube), Vector3(1.53, 0.06, 0.06), "white")
	for x: float in [-11.8,4.7]:
		p.box(Vector3(x, 4.78, -12.8), Vector3(2.65, 0.80, 1.6), "steel", true)
		for i in range(10):
			p.box(Vector3(x-1.06+i*0.23, 4.78, -11.98), Vector3(0.09, 0.57, 0.05), "coal")
	# Dispatch partitions have separate openings into the lobby and the stockroom.
	for span: Vector2 in [Vector2(-16,-10),Vector2(-7.6,-2)]:
		p.box(Vector3(6.2, 1.7, (span.x+span.y)/2), Vector3(0.18,3.4,span.y-span.x), "aqua", true)
	_span(p, 10.25, 15, -9, 0, 1.25, "ink")
	_span(p, 10.25, 15, -9, 2.48, 3.45, "milk")
	p.box(Vector3(12.62, 1.28, -9), Vector3(4.8, 0.09, 0.62), "umber", true)

func _span(p: Parts, left: float, right: float, z: float, low: float, high: float, coat: String) -> void:
	p.box(Vector3((left+right)/2, (low+high)/2, z), Vector3(right-left, high-low, 0.20), coat, true)

func _fuel_lanes(p: Parts, rng: RandomNumberGenerator) -> void:
	var court_z := rng.randf_range(8.1, 9.9)
	var rise := rng.randf_range(1.65, 2.4)
	var damaged_bay := rng.randi_range(0, 1)
	var damaged_end := rng.randi_range(0, 1)
	p.box(Vector3(0, -0.05, 8.1), Vector3(30.8,0.13,18.5), "grit", true)
	for island: int in [-1,0,1]:
		var x := island * 10.0
		p.box(Vector3(x,0.15,court_z),Vector3(1.45,0.26,9.0),"milk",true)
		for dz: float in [-3.45,3.45]:
			p.box(Vector3(x,2.65,court_z+dz),Vector3(0.38,4.8,0.36),"ink",true)
			p.box(Vector3(x,0.65,court_z+dz),Vector3(0.62,0.78,0.59),"gold",true)
		for dz: float in [-1.7,1.7]:
			var base := Vector3(x,0.28,court_z+dz)
			p.block(base + Vector3.UP*0.99,Vector3(0.64,1.98,0.84))
			if p.draw:
				var pump: Node3D = DISPENSER.instantiate()
				pump.position = base
				pump.rotation.y = PI/2 if dz > 0 else -PI/2
				# Machine faces the driving aisle.
				$Visuals.add_child(pump)
	# Two barrel vaults spring from the island columns. Missing roof sheets
	# expose the end ribs without dropping collision into a vehicle lane.
	for bay in range(2):
		var start_x := -10.0 + bay * 10.0
		for segment in range(10):
			var a := Vector2(start_x + segment, 5 + rise*sin(PI*segment/10.0))
			var b := Vector2(a.x+1, 5 + rise*sin(PI*(segment+1)/10.0))
			var mid := (a+b)/2
			var tilt := Vector3(0,0,(b-a).angle())
			for end in range(2):
				var z := court_z + (-2.63 if end == 0 else 2.63)
				if bay != damaged_bay or end != damaged_end or segment not in [2,3,4]:
					p.box(Vector3(mid.x,mid.y,z),Vector3(a.distance_to(b)+0.02,0.16,5.27),"milk",true,tilt)
			for edge: float in [-5.29,0,5.29]:
				p.box(Vector3(mid.x,mid.y-0.07,court_z+edge),Vector3(a.distance_to(b)+0.03,0.32,0.18),"aqua",false,tilt)
				if edge != 0:
					p.box(Vector3(mid.x,mid.y+0.12,court_z+edge),Vector3(a.distance_to(b)+0.05,0.07,0.22),"gold",false,tilt)
	for x: float in [-12.9,-7.4,-2.6,2.6,7.4,12.9]:
		for z: float in [2,14.9]:
			p.box(Vector3(x,0.024,z),Vector3(0.105,0.015,2.3),"milk")

func _yard_traces(p: Parts, rng: RandomNumberGenerator) -> void:
	# Tufts follow slab joints and island edges where the asphalt has opened.
	for x: float in [-13.5,-5.2,5.2,13.5]:
		p.box(Vector3(x,0.022,8.1),Vector3(0.027,0.009,17.9),"coal")
		for i in range(6):
			var z := rng.randf_range(0.6,16.9)
			for blade in range(5):
				var h := rng.randf_range(0.10,0.31)
				p.box(Vector3(x+rng.randf_range(-0.10,0.10),h/2,z+rng.randf_range(-0.16,0.16)),
					Vector3(0.034,h,0.024),"sage",false,Vector3(rng.randf_range(-0.40,0.4),0,rng.randf_range(-0.45,0.45)))
	# Delivery pallet and dolly at the freight exit.
	p.frame(Vector3(12.3,0,-17.6),0.09)
	for x: float in [-0.55,0,0.55]:
		p.box(Vector3(x,0.09,0),Vector3(0.15,0.17,1.0),"umber",true)
	for i in range(6):
		p.box(Vector3(0,0.205,-0.45+i*0.18),Vector3(1.45,0.07,0.14),"paper",true)
	p.frame(Vector3(14.4,0,-17.3),0.22)
	for x: float in [-0.24,0.24]:
		p.cylinder(Vector3(x,0.17,0.12),0.31,0.105,"coal",Vector3(0,0,PI/2))
		p.box(Vector3(x,0.81,0),Vector3(0.053,1.32,0.056),"gold",false,Vector3(-0.13,0,0))
	for y: float in [0.46,0.79,1.18,1.43]:
		p.box(Vector3(0,y,-(y-0.79)*0.13),Vector3(0.51,0.05,0.05),"gold")
	p.box(Vector3(0,0.14,0.22),Vector3(0.53,0.055,0.46),"steel")
	p.block(Vector3(0,0.73,0.05),Vector3(0.57,1.44,0.34))
	p.frame(Vector3.ZERO)

func _marquee(p: Parts, rng: RandomNumberGenerator) -> void:
	p.frame(Vector3(-15,0,15.7), rng.randf_range(0.3,0.67))
	for x: float in [-1.05,1.05]:
		p.box(Vector3(x,3.8,0),Vector3(0.26,7.6,0.3),"ink",true)
	p.box(Vector3(0,7.72,0),Vector3(5.8,2.02,0.38),"gold",true)
	p.box(Vector3(0,5.96,0),Vector3(3.95,1.34,0.26),"aqua",true)
	for side: int in [-1,1]:
		var yaw := PI if side == -1 else 0.0
		p.sign_face(0,Vector3(0,7.72,side*0.195),5.68,yaw)
		p.sign_face(6,Vector3(0,5.96,side*0.135),3.84,yaw)
	p.frame(Vector3.ZERO)

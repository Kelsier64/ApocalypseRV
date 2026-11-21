extends RefCounted
const Parts = preload("res://world/roadside_pois/orbit_plaza/plaza_parts.gd")
const FOOD := ["food/canned_food", "food/energy_bar", "food/beef_jerky"]
var loot: Node3D

func furnish(p: Parts, points: Node3D, site_seed: int) -> void:
	loot = points
	var rng := RandomNumberGenerator.new()
	rng.seed = ("orbit_rooms:%d" % site_seed).hash()
	var upholstery := "vinyl" if rng.randf() < 0.5 else "aqua"
	var pastry_case := rng.randf() < 0.5
	for x: float in [-12.6,-8.8,-5]:
		p.frame(Vector3(x,0,-4.45))
		if pastry_case and x == -5: _pie_case(p)
		else: _booth(p,upholstery,rng)
	p.frame(Vector3(-8.1,0,-10.4))
	_lunch_counter(p,rng)
	p.frame(Vector3(-7.9,0,-14.8))
	_kitchen(p)
	p.frame(Vector3(1.8,0,-14.9))
	_coolers(p)
	var rack_z := -5.8 if rng.randf() < 0.5 else -11.2
	p.frame(Vector3(3.4,0,rack_z), PI/2)
	_market_rack(p,rng)
	p.frame(Vector3(11.2,0,-4.25))
	_dispatch(p,rng)
	p.frame(Vector3(12.6,0,-13.55))
	_receiving(p,rng)
	p.frame(Vector3.ZERO)
	p.sign_face(9,Vector3(-14.85,2.54,-11.65),5.85,PI/2)
	p.sign_face(8,Vector3(6.32,2.05,-4.86),4.30,PI/2)
	for x: float in [-12.6,-8.8,-5.0]:
		p.cylinder(Vector3(x,3.50,-4.45),0.038,1.0,"ink")
		p.cylinder(Vector3(x,2.95,-4.45),0.24,0.15,"gold")
		p.cylinder(Vector3(x,2.86,-4.45),0.49,0.09,"aqua")
		p.cylinder(Vector3(x,2.808,-4.45),0.40,0.022,"milk")
	# Traces cluster around traffic and service counters, leaving pickup surfaces clear.
	for i in range(13):
		var at := Vector3(rng.randf_range(-13.5,5.3),0.102,rng.randf_range(-14.1,-3.1))
		p.box(at,Vector3(0.14,0.008,0.22),"paper",false,Vector3(0,rng.randf_range(-PI,PI),0))
	p.box(Vector3(0,0.10,-3.2),Vector3(2.45,0.022,1.4),"coal")
	for i in range(15):
		p.box(Vector3(-1.09+i*0.155,0.115,-3.2),Vector3(0.04,0.012,1.24),"umber")
	_stock(p,"FreightFuel",Vector3(11.3,0.43,-17.35),0.33,["gas_can"])

func _booth(p: Parts, coat: String, rng: RandomNumberGenerator) -> void:
	for side: int in [-1,1]:
		var x := side * 1.16
		p.box(Vector3(x,0.35,0),Vector3(0.66,0.50,1.86),"ink",true)
		p.box(Vector3(x,0.64,0),Vector3(0.77,0.18,1.89),coat,true)
		p.box(Vector3(x+side*0.31,0.98,0),Vector3(0.17,0.72,1.89),coat,true,Vector3(0,0,-side*0.10))
		for seam: float in [-0.59,0,0.59]:
			p.box(Vector3(x+side*0.21,1.03,seam),Vector3(0.03,0.45,0.022),"umber")
	p.cylinder(Vector3(0,0.18,0),0.60,0.13,"ink")
	p.cylinder(Vector3(0,0.57,0),0.14,0.72,"chrome")
	p.box(Vector3(0,0.98,0),Vector3(1.12,0.10,1.61),"chrome",true)
	p.box(Vector3(0,1.04,0),Vector3(1.11,0.035,1.60),"milk")
	p.box(Vector3(0.16,1.15,-0.5),Vector3(0.22,0.20,0.13),"steel")
	p.box(Vector3(0.16,1.255,-0.5),Vector3(0.13,0.014,0.05),"paper")
	for x: float in [-0.16,-0.04]:
		p.cylinder(Vector3(x,1.12,-0.48),0.068,0.13,"white")
		p.cylinder(Vector3(x,1.20,-0.48),0.07,0.027,"chrome")
	if rng.randf() < 0.7:
		p.cylinder(Vector3(-0.21,1.08,0.26),0.29,0.024,"aqua")
		_cup(p,Vector3(-0.21,1.10,0.26))

func _pie_case(p: Parts) -> void:
	p.box(Vector3(0,0.55,0),Vector3(1.97,0.92,0.96),"aqua",true)
	p.box(Vector3(0,1.06,0),Vector3(2.04,0.10,1.03),"chrome",true)
	for x: float in [-0.94,0.94]:
		for z: float in [-0.44,0.44]:
			p.box(Vector3(x,1.42,z),Vector3(0.045,0.66,0.045),"chrome")
	for y: float in [1.35,1.71]:
		p.box(Vector3(0,y,0),Vector3(1.96,0.04,0.93),"steel",true)
		for x: float in [-0.54,0.52]:
			p.cylinder(Vector3(x,y+0.04,0),0.44,0.025,"white")
	for i in range(3):
		p.box(Vector3(-0.65+i*0.64,1.13,0.46),Vector3(0.18,0.10,0.02),"paper")
	p.box(Vector3(0,0.55,0.49),Vector3(1.83,0.12,0.02),"gold")

func _cup(p: Parts, at: Vector3) -> void:
	p.cylinder(at+Vector3.UP*0.061,0.115,0.12,"milk")
	p.cylinder(at+Vector3.UP*0.124,0.087,0.008,"umber")
	p.box(at+Vector3(0.072,0.065,0),Vector3(0.048,0.06,0.035),"milk")

func _lunch_counter(p: Parts, rng: RandomNumberGenerator) -> void:
	p.box(Vector3(0,0.57,0),Vector3(9.4,0.97,0.88),"aqua",true)
	p.box(Vector3(0,1.10,0),Vector3(9.6,0.14,1.16),"milk",true)
	for y: float in [0.27,0.35,0.92]:
		p.box(Vector3(0,y,0.457),Vector3(9.37,0.035,0.035),"chrome")
	var missing := rng.randi_range(0,5)
	for i in range(6):
		if i == missing: continue
		var x := -3.9+i*1.49
		p.cylinder(Vector3(x,0.15,1.15),0.44,0.10,"coal")
		p.cylinder(Vector3(x,0.48,1.15),0.12,0.64,"chrome")
		p.cylinder(Vector3(x,0.82,1.15),0.56,0.12,"chrome")
		p.cylinder(Vector3(x,0.91,1.15),0.55,0.12,"vinyl")
		p.block(Vector3(x,0.52,1.15),Vector3(0.44,0.85,0.44))
	for x: float in [-3.85,-3.33]:
		p.cylinder(Vector3(x,1.44,0),0.36,0.54,"steel")
		p.cylinder(Vector3(x,1.73,0),0.38,0.055,"coal")
		p.box(Vector3(x,1.31,0.23),Vector3(0.065,0.08,0.16),"ink")
	p.box(Vector3(3.78,1.25,0),Vector3(0.68,0.16,0.54),"ink")
	p.box(Vector3(3.78,1.47,-0.04),Vector3(0.60,0.34,0.38),"aqua",false,Vector3(0.18,0,0))
	p.box(Vector3(3.78,1.53,0.16),Vector3(0.40,0.11,0.04),"glass")
	for i in range(6):
		p.box(Vector3(3.56+i*0.085,1.35,0.22),Vector3(0.058,0.045,0.056),"milk")
	_stock(p,"DinerCounter",Vector3(2.55,1.39,0),1.0,FOOD)

func _kitchen(p: Parts) -> void:
	p.box(Vector3(0,0.57,0),Vector3(9.6,0.96,1.11),"steel",true)
	p.box(Vector3(0,1.10,0),Vector3(9.73,0.10,1.20),"chrome",true)
	for i in range(8):
		var x := -4.12+i*1.17
		p.box(Vector3(x,0.60,0.57),Vector3(1.11,0.77,0.04),"aqua")
		p.box(Vector3(x+0.31,0.81,0.61),Vector3(0.30,0.04,0.055),"ink")
	# Shallow sink lip, twin taps, griddle and hanging extraction hood.
	p.box(Vector3(-3,1.155,0),Vector3(1.3,0.015,0.73),"coal")
	p.box(Vector3(-3,1.17,0),Vector3(1.14,0.02,0.58),"steel")
	for x: float in [-3.45,-2.55]:
		p.cylinder(Vector3(x,1.31,-0.37),0.07,0.33,"chrome")
		p.box(Vector3(x,1.46,-0.21),Vector3(0.07,0.07,0.35),"chrome")
	p.box(Vector3(0.1,1.20,0),Vector3(2.55,0.10,1.04),"coal")
	for x: float in [-0.72,-0.22,0.28,0.78]:
		p.cylinder(Vector3(x,1.05,0.61),0.11,0.055,"ink",Vector3(PI/2,0,0))
	p.box(Vector3(0.12,2.52,0),Vector3(2.9,0.35,1.41),"steel")
	p.box(Vector3(0.12,3.27,0),Vector3(1.25,1.35,0.62),"coal")
	for i in range(9):
		p.box(Vector3(-1.0+i*0.27,2.33,0),Vector3(0.08,0.026,1.20),"ink")
	# Chrome splashback seams and the hanging utensil rail behind the grill.
	p.box(Vector3(0,1.73,-1.05),Vector3(9.85,1.05,0.045),"aqua")
	for i in range(22):
		p.box(Vector3(-4.77+i*0.45,1.73,-1.019),Vector3(0.014,1.05,0.012),"milk")
	for y: float in [1.39,1.72,2.05]:
		p.box(Vector3(0,y,-1.013),Vector3(9.85,0.014,0.015),"milk")
	p.box(Vector3(2.1,2.21,-0.95),Vector3(1.62,0.055,0.06),"chrome")
	for i in range(5):
		var x := 1.52+i*0.29
		p.box(Vector3(x,2.06,-0.90),Vector3(0.033,0.30,0.04),"chrome")
		p.box(Vector3(x,1.86,-0.90),Vector3(0.11,0.14,0.035),"steel")
	p.sign_face(2,Vector3(-3,2.61,-1.04),2.51)
	for i in range(5):
		p.cylinder(Vector3(3.65,1.17+i*0.033,0.12),0.34,0.038,"white")
	_stock(p,"KitchenShelf",Vector3(2.60,1.48,0),0.61,["scavenge_loot/enamel_kettle","food/canned_food"])

func _coolers(p: Parts) -> void:
	for i in range(3):
		var x := (i-1)*1.38
		p.box(Vector3(x,1.35,0),Vector3(1.35,2.49,1.10),"milk",true)
		p.box(Vector3(x,1.44,0.557),Vector3(1.17,1.75,0.05),"ink")
		p.box(Vector3(x,1.51,0.590),Vector3(1.02,1.46,0.024),"glass")
		for j in range(3):
			p.box(Vector3(x,0.9+j*0.42,0.61),Vector3(0.94,0.024,0.02),"steel")
		p.box(Vector3(x+0.49,1.43,0.64),Vector3(0.04,0.48,0.07),"chrome")
		for j in range(4):
			p.box(Vector3(x,0.27+j*0.07,0.56),Vector3(1.0,0.027,0.025),"coal")
	p.sign_face(3,Vector3(0,2.98,0.52),2.14)

func _market_rack(p: Parts, rng: RandomNumberGenerator) -> void:
	for x: float in [-1.40,1.40]:
		p.box(Vector3(x,0.98,0),Vector3(0.09,1.79,1.04),"ink",true)
	for y: float in [0.32,0.98,1.62]:
		p.box(Vector3(0,y,0),Vector3(2.84,0.07,1.03),"milk",true)
		for side: int in [-1,1]:
			p.box(Vector3(0,y,side*0.52),Vector3(2.81,0.09,0.035),"gold")
		# Empty cardboard trays, ticket strips and folded display cartons.
		var x := rng.randf_range(-0.98,-0.3)
		p.box(Vector3(x,y+0.06,-0.14),Vector3(0.63,0.05,0.38),"paper")
		for edge: int in [-1,1]:
			p.box(Vector3(x+edge*0.30,y+0.14,-0.14),Vector3(0.035,0.17,0.38),"umber")
		for i in range(4):
			p.box(Vector3(-0.98+i*0.58,y,0.54),Vector3(0.14,0.054,0.014),"white")
	_stock(p,"RoadMarket",Vector3(0.68,1.94,0),0.75,FOOD)

func _dispatch(p: Parts, rng: RandomNumberGenerator) -> void:
	p.sign_face(7,Vector3(1.88,2.96,-4.62),1.94)
	var seats := rng.randi_range(2,4)
	p.box(Vector3(0,0.44,0),Vector3(seats*0.82,0.14,0.44),"steel",true)
	for i in range(seats):
		var x := (i-(seats-1)/2.0)*0.81
		p.box(Vector3(x,0.58,0),Vector3(0.70,0.17,0.64),"gold",true)
		p.box(Vector3(x,0.93,0.28),Vector3(0.69,0.63,0.12),"gold",true,Vector3(0.12,0,0))
		p.box(Vector3(x,0.29,0),Vector3(0.11,0.41,0.50),"ink")
	# The eastern wall either carries a night dispatcher’s desk or left luggage.
	p.box(Vector3(2.94,0.58,-1.81),Vector3(1.20,0.95,1.98),"umber",true)
	p.box(Vector3(2.94,1.09,-1.81),Vector3(1.33,0.10,2.12),"milk",true)
	if rng.randf() < 0.5:
		p.box(Vector3(3.04,1.37,-2.12),Vector3(0.66,0.42,0.41),"ink",true)
		for i in range(5):
			p.box(Vector3(2.70,1.24+i*0.055,-2.12),Vector3(0.03,0.022,0.31),"steel")
		p.box(Vector3(3.25,1.95,-2.21),Vector3(0.025,0.78,0.025),"chrome",false,Vector3(0.13,0,0))
		for i in range(2):
			p.box(Vector3(2.83,1.153+i*0.025,-1.28),Vector3(0.41,0.024,0.29),"paper",false,Vector3(0,i*0.21,0))
	else:
		for i in range(2):
			var z := -2.23+i*0.83
			p.box(Vector3(2.94,1.40,z),Vector3(0.80,0.52,0.38),"vinyl",true)
			for x: float in [2.70,3.18]:
				p.box(Vector3(x,1.40,z+0.20),Vector3(0.045,0.53,0.025),"umber")
			p.box(Vector3(2.94,1.70,z),Vector3(0.23,0.07,0.06),"ink")
	# Wall clock over the dispatch window, with a stopped pair of hands.
	var clock_at := Vector3(-0.3,2.97,-4.60)
	p.cylinder(clock_at,0.67,0.08,"ink",Vector3(PI/2,0,0))
	p.cylinder(clock_at+Vector3.BACK*0.05,0.59,0.025,"milk",Vector3(PI/2,0,0))
	for i in range(12):
		var a := i*TAU/12
		p.box(clock_at+Vector3(sin(a)*0.25,cos(a)*0.25,0.072),Vector3(0.023,0.055,0.01),"ink",false,Vector3(0,0,-a))
	p.box(clock_at+Vector3(-0.04,0.08,0.082),Vector3(0.026,0.20,0.016),"ink",false,Vector3(0,0,0.48))
	p.box(clock_at+Vector3(0.07,0.015,0.088),Vector3(0.16,0.032,0.015),"ink")
	for i in range(3):
		p.box(Vector3(-0.1+i*0.27,1.35,-4.62),Vector3(0.22,0.035,0.29),"paper",false,Vector3(0,i*0.08,0))
	_stock(p,"DispatchWindow",Vector3(2.10,1.54,-4.65),0.55,["flashlight","scavenge_loot/broken_shortwave_radio"])

func _receiving(p: Parts, rng: RandomNumberGenerator) -> void:
	p.sign_face(5,Vector3(-0.05,2.73,-2.32),2.80)
	# Wall sorter, addressed envelopes and an old pinboard above the freight table.
	p.box(Vector3(2.22,2.16,1.56),Vector3(0.17,1.42,2.60),"umber",true)
	for y: float in [1.48,1.92,2.36,2.85]:
		p.box(Vector3(2.05,y,1.56),Vector3(0.46,0.046,2.62),"paper")
	for i in range(6):
		p.box(Vector3(2.05,2.17,0.27+i*0.516),Vector3(0.45,1.40,0.044),"paper")
	for i in range(8):
		var z := 0.48+rng.randi_range(0,4)*0.516
		var y := 1.53+rng.randi_range(0,2)*0.44
		p.box(Vector3(1.94,y,z),Vector3(0.27,0.042,0.30),"milk",false,Vector3(rng.randf_range(-0.10,0.10),0,0))
	p.box(Vector3(-5.99,2.0,0.25),Vector3(0.13,1.18,2.35),"umber")
	for i in range(5):
		var z := -0.62+i*0.41
		p.box(Vector3(-5.91,2.04,z),Vector3(0.022,0.51,0.34),"paper",false,Vector3(rng.randf_range(-0.14,0.14),0,0))
		for line in range(3):
			p.box(Vector3(-5.892,2.15-line*0.10,z),Vector3(0.013,0.018,0.21),"umber")
	for i in range(3):
		var x := i*0.65
		p.box(Vector3(x,1.15,-0.96),Vector3(0.63,2.12,0.67),"sage",true)
		for y: float in [0.43,0.99,1.55]:
			p.box(Vector3(x,y,-0.61),Vector3(0.56,0.52,0.04),"aqua")
			p.box(Vector3(x,y+0.06,-0.572),Vector3(0.21,0.055,0.05),"chrome")
			p.box(Vector3(x,y+0.17,-0.581),Vector3(0.17,0.054,0.012),"paper")
	for x: float in [-0.87,0.87]:
		p.box(Vector3(x,0.35,1.65),Vector3(0.14,0.55,0.98),"coal",true)
	p.box(Vector3(0,0.67,1.65),Vector3(2.03,0.12,1.1),"umber",true)
	var use_parcels := rng.randf() < 0.5
	if use_parcels:
		for x: float in [-0.65,-0.20]:
			p.box(Vector3(x,0.94,1.65),Vector3(0.40,0.43,0.57),"paper",true)
			p.box(Vector3(x,1.162,1.65),Vector3(0.07,0.015,0.57),"umber")
		_stock(p,"FreightTable",Vector3(0.60,1.01,1.65),0.75,["scavenge_loot/medical_tin","food/beef_jerky"])
	else:
		p.cylinder(Vector3(-0.48,0.89,1.65),0.53,0.30,"umber")
		for y: float in [0.75,1.06]:
			p.cylinder(Vector3(-0.48,y,1.65),0.67,0.06,"steel")
		_stock(p,"FreightTable",Vector3(0.60,1.05,1.65),0.75,["scavenge_loot/copper_wire_spool","scavenge_loot/broken_pipe_elbow"])

func _stock(p: Parts, label: String, at: Vector3, chance: float, ids: Array) -> void:
	var point := PoiLootPoint.new()
	point.name = label
	point.point_id = StringName(label)
	point.transform = p.origin * Transform3D(Basis.IDENTITY,at)
	point.spawn_chance = chance
	for id: String in ids:
		point.candidates.append(load("res://props/%s.tscn" % id))
	loot.add_child(point)

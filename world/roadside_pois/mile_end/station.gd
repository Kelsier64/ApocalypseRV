extends Node3D

const Parts = preload("res://world/roadside_pois/mile_end/station_parts.gd")
const DISPENSER = preload("res://world/roadside_pois/mile_end/dispenser.glb")
const SNACKS := ["food/canned_food", "food/beef_jerky", "food/energy_bar"]
enum Use { STORE, WORKSHOP, REFUGE }

func configure(site_seed: int, show_meshes: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	var wide := rng.randf() < 0.5
	var half_width := 4.8 if wide else 3.9
	var depth := 6.4 if wide else 8.3
	var pump_z := 3.25 if rng.randf() < 0.5 else 7.0
	var accent := "red" if rng.randf() < 0.5 else "green"
	var parts := Parts.new($Visuals, $Collision, show_meshes)
	_shop(parts, half_width, depth, accent, rng)
	_forecourt(parts, pump_z, accent, rng)
	$AccessPoints/Front.position = Vector3(-1.7, 0.1, 0.7)
	$AccessPoints/Rear.position = Vector3(1.25, 0.1, -depth - 0.7)
	var interior_rng := RandomNumberGenerator.new()
	interior_rng.seed = ("mile_end_furniture:%d" % site_seed).hash()
	_furnish(half_width, depth, interior_rng.randi_range(Use.STORE, Use.REFUGE), show_meshes)
	_loot($LootSpawns, "Delivery", Vector3(-1.0, 0.54, -depth - 1.3), 0.25, ["gas_can"])

func _shop(p: Parts, half: float, depth: float, accent: String, rng: RandomNumberGenerator) -> void:
	var z := -depth / 2
	p.box("Slab", Vector3(0, 0.025, z), Vector3(2 * half + 0.34, 0.12, depth + 0.32), "stone", true)
	p.box("Roof", Vector3(0, 3.30, z), Vector3(2 * half + 0.65, 0.21, depth + 0.7), "tar", true)
	for x in [-half, half]:
		p.box("BlockWall", Vector3(x, 1.65, z), Vector3(0.19, 3.30, depth), "cream", true)
		p.box("SideSkirt", Vector3(x, 0.32, z), Vector3(0.23, 0.64, depth), accent)
		p.box("Flashing", Vector3(x, 3.23, z), Vector3(0.31, 0.25, depth + 0.7), accent)
	# Door centres are - 1.7 at the front and + 1.25 at the rear.
	_wall_span(p, -half, -2.85, 0, 0, 3.20, "cream")
	_wall_span(p, -0.55, half, 0, 0, 0.90, accent)
	_wall_span(p, half - 0.36, half, 0, 0.90, 2.57, "cream")
	_wall_span(p, -half, half, 0, 2.57, 3.2, "cream")
	_wall_span(p, -half, 0.16, -depth, 0, 3.20, "cream")
	_wall_span(p, 2.34, half, -depth, 0, 3.20, "cream")
	_wall_span(p, 0.16, 2.34, -depth, 2.46, 3.20, "cream")
	for x: float in [-0.50, (half - 0.30)/2, half - 0.39]:
		p.box("Sash", Vector3(x, 1.73, 0.0), Vector3(0.095, 1.68, 0.15), "green", true)
	p.box("Sill", Vector3((half - 0.55)/2, 0.94, 0.02), Vector3(half + 0.65, 0.12, 0.3), "steel", true)
	p.box("Transom", Vector3((half - 0.55)/2, 2.28, 0.0), Vector3(half + 0.55, 0.09, 0.14), "green")
	var board_x := rng.randf_range(0.60, 1.05)
	for row in range(rng.randi_range(2, 3)):
		var angle := rng.randf_range(-0.18, 0.15)
		p.box("ShutterBoard", Vector3(board_x, 1.28 + row * 0.35, 0.13 + 0.02 * row), Vector3(2.38, 0.17, 0.06), "wood", true, Vector3(0, 0, angle))
	p.box("Fascia", Vector3(0, 3.20, 0.18), Vector3(2 * half + 0.58, 0.29, 0.34), accent)
	p.box("Eyebrow", Vector3(0, 3.04, 0.36), Vector3(2 * half + 0.62, 0.08, 0.74), "steel")
	p.sign_panel(Vector3(-1.72, 2.87, 0.22), 1.32, 0)
	for x in [-half, half]:
		p.box("Drainpipe", Vector3(x + signf(x) * 0.13, 1.55, -depth + 0.24), Vector3(0.12, 3.04, 0.12), "steel")
		for y: float in [0.43, 1.68, 2.75]:
			p.box("PipeStrap", Vector3(x + signf(x) * 0.13, y, -depth + 0.24), Vector3(0.16, 0.07, 0.18), "tar")
	for x: float in [-2.35, 1.95]:
		p.box("LightTray", Vector3(x, 3.12, z), Vector3(0.28, 0.12, 1.27), "steel")
		p.box("DeadTube", Vector3(x, 3.04, z), Vector3(0.12, 0.07, 1.16), "cream")
	p.box("Chimney", Vector3(half - 0.85, 3.69, -depth + 1.0), Vector3(0.40, 0.71, 0.40), "steel")
	p.box("RainCap", Vector3(half - 0.85, 4.09, -depth + 1.0), Vector3(0.58, 0.09, 0.58), "tar")
	p.box("ServiceBox", Vector3(half + 0.16, 1.34, -depth + 1.4), Vector3(0.27, 0.66, 0.48), "steel", true)
	p.box("Conduit", Vector3(half + 0.06, 0.52, -depth + 1.4), Vector3(0.075, 1.04, 0.075), "steel")

func _wall_span(p: Parts, left: float, right: float, z: float, bottom: float, top: float, coat: String) -> void:
	p.box("Wall", Vector3((left + right)/2, (top + bottom)/2, z), Vector3(right-left, top-bottom, 0.19), coat, true)

func _forecourt(p: Parts, z: float, accent: String, rng: RandomNumberGenerator) -> void:
	p.box("Island", Vector3(0, 0.09, z), Vector3(5.5, 0.18, 1.10), "stone", true)
	for x: float in [-2.22, 2.22]:
		p.box("Foot", Vector3(x, 0.37, z), Vector3(0.39, 0.50, 0.42), "stone", true)
		p.box("Stanchion", Vector3(x, 2.66, z), Vector3(0.19, 4.98, 0.24), "green", true)
		for side: float in [-1.0, 1.0]:
			p.box("RoofKnee", Vector3(x, 4.82, z + side * 0.76), Vector3(0.15, 0.18, 1.78), "steel", false, Vector3(-side * 0.35, 0, 0))
	p.box("GutterBeam", Vector3(0, 5.04, z), Vector3(8.9, 0.32, 0.42), "steel", true)
	# A folded metal canopy drains to its central valley. A missing end sheet
	# exposes the rafters while the rest of the aisle stays under cover.
	var missing := rng.randi_range(0, 3)
	for side: int in [-1, 1]:
		var angle := Vector3(-side * 0.11, 0, 0)
		for panel in range(8):
			if (panel == 0 and missing == 0 and side == 1) or (panel == 7 and missing == 1 and side == -1): continue
			var x := (panel - 3.5) * 1.12
			p.box("RoofSheet", Vector3(x, 5.34, z + side * 1.60), Vector3(1.115, 0.12, 3.25), "stone", true, angle)
			p.box("StandingSeam", Vector3(x - 0.51, 5.41, z + side * 1.60), Vector3(0.05, 0.065, 3.25), "steel", false, angle)
			p.box("Valance", Vector3(x, 5.42, z + side * 3.19), Vector3(1.12, 0.33, 0.10), accent)
			p.box("Pinstripe", Vector3(x, 5.36, z + side * 3.247), Vector3(1.12, 0.045, 0.018), "cream")
		p.box("Rim", Vector3(0, 5.31, z + side * 3.12), Vector3(9.0, 0.13, 0.12), "steel")
	if p.draw_meshes:
		var pump: Node3D = DISPENSER.instantiate()
		pump.position = Vector3(0, 0.18, z)
		p.visuals.add_child(pump)
	var collider := CollisionShape3D.new()
	var pump_shape := BoxShape3D.new()
	pump_shape.size = Vector3(0.84, 1.98, 0.64)
	collider.name = "Dispenser"
	collider.position = Vector3(0, 1.17, z)
	collider.shape = pump_shape
	p.body.add_child(collider)
	p.box("SignPost", Vector3(-7.9, 2.05, 7.8), Vector3(0.23, 4.10, 0.23), "green", true)
	p.box("SignFoot", Vector3(-7.9, 0.25, 7.8), Vector3(0.63, 0.50, 0.59), "stone", true)
	p.sign_panel(Vector3(-7.9, 4.28, 7.8), 3.15, 0.69)

func _furnish(half: float, depth: float, use: Use, show_meshes: bool) -> void:
	var layout := Node3D.new()
	layout.name = ["Store", "Workshop", "Refuge"][use]
	$Furnishings.add_child(layout)
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	layout.add_child(visuals)
	var p := Parts.new(visuals, layout, show_meshes)
	var counter := Vector3(-half + 0.85, 0, -depth * 0.58)
	p.box("Counter", counter + Vector3.UP * 0.53, Vector3(1.0, 0.93, 2.15), "green", true)
	p.box("CounterEdge", counter + Vector3.UP * 1.03, Vector3(1.10, 0.11, 2.27), "cream", true)
	p.box("TillDrawer", counter + Vector3(0, 1.16, 0.58), Vector3(0.45, 0.15, 0.40), "steel", true)
	p.box("TillRegister", counter + Vector3(0, 1.29, 0.62), Vector3(0.39, 0.20, 0.24), "cream", true, Vector3(0.14, 0, 0))
	p.box("TillDisplay", counter + Vector3(0, 1.32, 0.75), Vector3(0.24, 0.07, 0.03), "glass")
	_loot(layout, "CounterStock", counter + Vector3(0, 1.30, -0.45), 0.50, SNACKS)
	var bay := Vector3(half - 1.25, 0, -depth * 0.52)
	match use:
		Use.STORE:
			var fridge := Vector3(-half + 0.78, 0, -depth + 0.71)
			p.box("Cooler", fridge + Vector3.UP * 1.11, Vector3(1.12, 2.05, 0.90), "cream", true)
			p.box("CoolerDoor", fridge + Vector3(0, 1.32, 0.46), Vector3(0.92, 1.34, 0.04), "glass")
			for y: float in [0.32, 0.38, 0.44]:
				p.box("CoolerVent", fridge + Vector3(0, y, 0.46), Vector3(0.83, 0.021, 0.03), "steel")
			for x: float in [-1.32, 1.32]:
				p.box("ShelfEnd", bay + Vector3(x, 0.91, 0), Vector3(0.08, 1.66, 0.75), "green", true)
			for y: float in [0.26, 0.91, 1.57]:
				p.box("RetailShelf", bay + Vector3.UP * y, Vector3(2.72, 0.07, 0.74), "cream", true)
				p.box("ShelfLip", bay + Vector3(0, y, 0.38), Vector3(2.72, 0.09, 0.04), "red")
			_loot(layout, "ShelfStock", bay + Vector3(0.65, 1.82, 0), 0.78, SNACKS)
		Use.WORKSHOP:
			p.table(bay, 2.75, 1.08, 1.03, "wood")
			p.box("ToolRail", Vector3(half - 0.15, 1.72, bay.z), Vector3(0.11, 0.13, 2.15), "steel")
			for i in range(4):
				p.box("Hook", Vector3(half - 0.24, 1.65, bay.z - 0.8 + i * 0.38), Vector3(0.13, 0.20, 0.04), "steel")
			p.box("ViseBase", bay + Vector3(-0.88, 1.11, 0), Vector3(0.35, 0.17, 0.38), "steel", true)
			p.box("ViseJaws", bay + Vector3(-0.88, 1.24, 0), Vector3(0.28, 0.13, 0.22), "green", true)
			_loot(layout, "BenchParts", bay + Vector3(0.55, 1.39, 0), 0.78, ["scavenge_loot/broken_pipe_elbow", "scavenge_loot/copper_wire_spool"])
		Use.REFUGE:
			p.table(bay, 2.00, 0.85, 0.41, "steel")
			p.box("Bedroll", bay + Vector3.UP * 0.50, Vector3(1.93, 0.18, 0.79), "cloth", true)
			p.box("Pillow", bay + Vector3(0.70, 0.64, 0), Vector3(0.41, 0.15, 0.65), "wood", true)
			p.box("FoldedBlanket", bay + Vector3(-0.59, 0.62, 0), Vector3(0.56, 0.11, 0.82), "green")
			p.box("Barricade", Vector3(1.4, 0.85, -0.67), Vector3(2.22, 1.50, 0.47), "wood", true, Vector3(-0.11, 0, 0))
			_loot(layout, "Bedside", bay + Vector3(-0.50, 0.29, 0.90), 0.78, ["food/beef_jerky", "flashlight"])

func _loot(parent: Node3D, label: String, at: Vector3, chance: float, ids: Array) -> void:
	var point := PoiLootPoint.new()
	point.name = label
	point.point_id = StringName(label)
	point.position = at
	point.spawn_chance = chance
	for id: String in ids:
		point.candidates.append(load("res://props/%s.tscn" % id))
	parent.add_child(point)

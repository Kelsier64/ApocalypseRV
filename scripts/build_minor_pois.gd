extends SceneTree
## First-build source. Generated scenes are ordinary editable, static .tscn assets.
## Refuses to overwrite any output. Changes after initial authoring belong in scenes.
const THEMES := ["wreck", "camp", "shed", "checkpoint", "cargo", "rest"]
const TITLES := ["ROADSIDE SALVAGE", "ABANDONED CAMP", "MAINTENANCE", "CHECKPOINT", "LOST FREIGHT", "FOREST REST"]
const SECONDARY := ["gas_can", "battery", "wheel", "battery", "gas_can", "battery"]
var root_node: Node3D
var visuals: Node3D
var bodies: StaticBody3D
var serial := 0
var mats: Dictionary = {}

func _init() -> void:
	build.call_deferred()

func material(key: String) -> StandardMaterial3D:
	if mats.has(key): return mats[key]
	var colors := {"paint": Color("637066"), "rust": Color("60402b"), "wood": Color("595041"), "steel": Color("323b39"), "rubber": Color("202524"), "glass": Color("344847"), "cloth": Color("76725a"), "sand": Color("73705c"), "white": Color("b1b49d"), "yellow": Color("b0a063")}
	var mat := IndustrialArt.material("paint" if key in ["paint", "rust", "steel"] else "concrete", colors[key]).duplicate() as StandardMaterial3D
	mat.resource_name = "RoadsidePaint" if key == "paint" else key
	mat.roughness = 0.88
	mats[key] = mat
	return mat

func part(size: Vector3, pos: Vector3, key: String, solid := true, angle := Vector3.ZERO, holder: Node3D = null) -> MeshInstance3D:
	serial += 1
	var mesh := MeshInstance3D.new()
	mesh.name = "Part%03d" % serial
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material(key)
	mesh.position = pos
	mesh.rotation = angle
	(holder if holder != null else visuals).add_child(mesh)
	if solid:
		var shape := CollisionShape3D.new()
		var collision := BoxShape3D.new()
		collision.size = size
		shape.shape = collision
		shape.transform = mesh.transform
		bodies.add_child(shape)
	return mesh

func cylinder(radius: float, height: float, pos: Vector3, key: String, rotation_value := Vector3.ZERO) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = material(key)
	node.position = pos
	node.rotation = rotation_value
	visuals.add_child(node)

func label(words: String, pos: Vector3, size := 32) -> void:
	var node := Label3D.new()
	node.text = words
	node.font_size = size
	node.pixel_size = 0.009
	node.modulate = Color("c2c3a6")
	node.position = pos
	visuals.add_child(node)

func crate(p: Vector3, size := Vector3(1.2, 0.9, 0.9)) -> void:
	part(size, p + Vector3.UP * size.y * 0.5, "wood")
	for x in [-0.4, 0.4]:
		part(Vector3(0.08, size.y + 0.04, size.z + 0.05), p + Vector3(x * size.x, size.y * 0.5, 0), "steel", false)
	for y in [0.14, size.y - 0.14]:
		part(Vector3(size.x + 0.025, 0.04, size.z + 0.025), p + Vector3(0, y, 0), "rust", false)

func pallet(p: Vector3) -> void:
	for x in [-0.55, 0.0, 0.55]: part(Vector3(0.12, 0.14, 1.2), p + Vector3(x, 0.08, 0), "wood", false)
	for z in [-0.5, -0.25, 0, 0.25, 0.5]: part(Vector3(1.3, 0.08, 0.17), p + Vector3(0, 0.19, z), "wood", false)

func table(p: Vector3) -> void:
	for x in [-0.7, 0.7]:
		part(Vector3(0.12, 0.85, 0.65), p + Vector3(x, 0.43, 0), "steel")
	for z in [-0.35, -0.12, 0.12, 0.35]: part(Vector3(2, 0.09, 0.2), p + Vector3(0, 0.9, z), "wood")
	for z in [-0.85, 0.85]:
		part(Vector3(2, 0.1, 0.3), p + Vector3(0, 0.45, z), "wood")
		for x in [-0.7, 0.7]: part(Vector3(0.12, 0.4, 0.2), p + Vector3(x, 0.2, z), "steel")

func car(p: Vector3, yaw := 0.0, rolled := false) -> void:
	# Author locally, then transform all visual and collision parts as one assembly.
	var first_visual := visuals.get_child_count()
	var first_shape := bodies.get_child_count()
	part(Vector3(2.05, 0.58, 4.5), Vector3(0, 0.78, 0), "paint")
	part(Vector3(1.85, 0.14, 1.2), Vector3(0, 1.12, 1.5), "rust", false, Vector3(-0.08, 0.06, 0.03))
	part(Vector3(1.7, 0.85, 2.0), Vector3(0, 1.47, -0.2), "glass")
	part(Vector3(1.85, 0.12, 2.2), Vector3(0, 1.93, -0.2), "paint", false)
	for x in [-0.89, 0.89]:
		for z in [-1.15, 0.8]: part(Vector3(0.10, 0.82, 0.12), Vector3(x, 1.48, z), "rust", false)
		part(Vector3(0.06, 0.18, 2.1), Vector3(x, 1.17, -0.2), "paint", false)
		part(Vector3(0.05, 0.8, 0.12), Vector3(x, 1.48, -0.15), "steel", false)
		for z in [-1.5, 1.45]:
			cylinder(0.44, 0.28, Vector3(x * 1.2, 0.46, z), "rubber", Vector3(0, 0, PI / 2))
			cylinder(0.23, 0.30, Vector3(x * 1.2, 0.46, z), "rust", Vector3(0, 0, PI / 2))
	for z in [-2.27, 2.27]: part(Vector3(2.15, 0.16, 0.14), Vector3(0, 0.58, z), "steel", false)
	for x in [-0.7, 0.7]: part(Vector3(0.4, 0.18, 0.06), Vector3(x, 0.89, 2.29), "white", false)
	part(Vector3(0.6, 0.16, 0.05), Vector3(0, 0.59, 2.36), "yellow", false)
	var pose := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI if rolled else 0.0), p + Vector3.UP * (2.1 if rolled else 0.0))
	for i in range(first_visual, visuals.get_child_count()): visuals.get_child(i).transform = pose * visuals.get_child(i).transform
	for i in range(first_shape, bodies.get_child_count()): bodies.get_child(i).transform = pose * bodies.get_child(i).transform

func tent(p: Vector3, abandoned := false) -> void:
	if abandoned:
		part(Vector3(3.5, 0.12, 3.8), p + Vector3(0, 0.10, 0), "cloth", false, Vector3(0, 0.2, 0))
		part(Vector3(0.08, 0.08, 3.7), p + Vector3(0.5, 0.2, 0.1), "steel", false)
		return
	for side in [-1, 1]:
		part(Vector3(2.35, 0.09, 3.5), p + Vector3(side * 0.82, 0.92, 0), "cloth", true, Vector3(0, 0, side * PI / 4))
		part(Vector3(0.07, 0.07, 3.7), p + Vector3(side * 1.67, 0.1, 0), "steel", false)
	part(Vector3(0.08, 1.85, 0.08), p + Vector3(0, 0.93, -1.65), "steel")
	part(Vector3(1.2, 0.13, 2.2), p + Vector3(0, 0.10, -0.2), "paint", false)

func shelter(p: Vector3, broken := false, booth := false) -> void:
	var width := 3.2 if booth else 7.0
	var depth := 3.0 if booth else 4.0
	for x in [-width / 2, width / 2]:
		for z in [-depth / 2, depth / 2]: part(Vector3(0.16, 2.8, 0.16), p + Vector3(x, 1.4, z), "steel")
	part(Vector3(width, 2.5, 0.12), p + Vector3(0, 1.25, -depth / 2), "paint")
	if booth:
		for x in [-width / 2, width / 2]: part(Vector3(0.12, 2.5, depth), p + Vector3(x, 1.25, 0), "paint")
	for i in range(7):
		if broken and i in [1, 2]: continue
		part(Vector3(width / 7 + 0.04, 0.12, depth + 0.8), p + Vector3(-width / 2 + (i + 0.5) * width / 7, 2.9, 0), "rust", true, Vector3(0.06, 0, 0))
		part(Vector3(0.05, 0.10, depth + 0.8), p + Vector3(-width / 2 + i * width / 7, 3.0, 0), "steel", false)
	if broken: part(Vector3(1.6, 0.08, 2.3), p + Vector3(width / 2 + 1, 0.3, 0), "rust", false, Vector3(0.1, 0.2, 0.2))

func barrier(p: Vector3) -> void:
	for x in [-1.1, 1.1]: part(Vector3(0.18, 1.1, 0.5), p + Vector3(x, 0.55, 0), "steel")
	part(Vector3(2.8, 0.4, 0.12), p + Vector3(0, 0.9, 0), "yellow")
	for x in [-1, -0.4, 0.2, 0.8]: part(Vector3(0.24, 0.41, 0.025), p + Vector3(x, 0.9, 0.08), "steel", false, Vector3(0, 0, -0.4))

func campfire(p: Vector3) -> void:
	for i in range(9):
		var a := i * TAU / 9
		part(Vector3(0.35, 0.22, 0.3), p + Vector3(cos(a) * 0.7, 0.12, sin(a) * 0.7), "sand", false, Vector3(0, a, 0))
	for a in [-0.5, 0.7]: part(Vector3(0.18, 0.16, 1.1), p + Vector3(0, 0.15, 0), "rubber", false, Vector3(0, a, 0))

func dress(theme: int, variant: int) -> void:
	match theme:
		0:
			car(Vector3(-5, 0, -5), 0.2 if variant == 0 else -0.5, variant == 2)
			if variant == 1: car(Vector3(0, 0, -6), 1.0)
			if variant == 0: part(Vector3(1.8, 0.12, 1.0), Vector3(-5, 1.7, -2.7), "rust", false, Vector3(-0.9, 0, 0))
			barrier(Vector3(8, 0, -3))
			pallet(Vector3(6, 0, -6))
		1:
			tent(Vector3(-5, 0, -5), variant == 2)
			if variant == 1: tent(Vector3(5, 0, -5))
			campfire(Vector3(0, 0, -4))
			table(Vector3(8, 0, 0) if variant == 1 else Vector3(5, 0, -5))
			crate(Vector3(-9, 0, 0))
		2:
			if variant != 1: shelter(Vector3(0, 0, -6), variant == 2)
			for x in [-7, 6, 9]:
				pallet(Vector3(x, 0, -6))
				crate(Vector3(x, 0.24, -6))
			if variant == 1:
				for x in [-3, 0, 3]: part(Vector3(0.6, 0.65, 3.0), Vector3(x, 0.4, -6), "rust")
		3:
			if variant == 0: shelter(Vector3(-5, 0, -6), false, true)
			if variant == 2: car(Vector3(-5, 0, -6), 0.4)
			for x in [0, 4, 8]:
				if variant == 1:
					for row in range(3):
						for j in range(3): part(Vector3(0.85, 0.28, 0.5), Vector3(x + j * 0.85 - 0.85 + (0.25 if row == 1 else 0), 0.15 + row * 0.28, -5), "sand")
				else: barrier(Vector3(x, 0, -5))
			part(Vector3(0.10, 4.2, 0.1), Vector3(-10, 2.1, -6), "steel")
			part(Vector3(1.6, 0.8, 0.05), Vector3(-9.2, 3.65, -6), "cloth", false)
		4:
			if variant == 0:
				car(Vector3(-6, 0, -6), PI / 2)
				part(Vector3(3.8, 2.5, 2.3), Vector3(-3, 1.8, -6), "paint")
				for z in [-7.18, -4.82]: part(Vector3(3.8, 0.12, 0.05), Vector3(-3, 2.6, z), "steel", false)
			for i in range(4):
				var p := Vector3(-7 + i * 4.3, 0, -3 if variant == 2 else -6)
				pallet(p)
				crate(p + Vector3(0, 0.24, 0), Vector3(1.4, 1.15 if variant == 2 else 0.8, 1.1))
				if variant == 1 and i % 2 == 0: crate(p + Vector3(0.1, 1.04, 0.1))
		5:
			if variant == 1: shelter(Vector3(0, 0, -6))
			table(Vector3(-5, 0, -4))
			if variant != 2: table(Vector3(5, 0, -4))
			if variant == 2:
				for x in [4, 7]: part(Vector3(0.16, 2.5, 0.16), Vector3(x, 1.25, -5), "wood")
				part(Vector3(3.2, 1.7, 0.15), Vector3(5.5, 1.9, -5), "paint")
				label("NORTH RIDGE\nTRAIL CLOSED", Vector3(5.5, 1.9, -4.91), 30)
				for i in range(3): part(Vector3(0.08, 0.45, 0.025), Vector3(4.8 + i * 0.55, 1.35, -4.89), "yellow", false, Vector3(0, 0, 0.3))
	# Theme-specific silhouettes above; all layouts retain the same clear front loop.
	for i in range(4):
		var slot := Node3D.new()
		slot.name = "DecorSlot%d" % i
		visuals.add_child(slot)
		var p := Vector3(-11 + i * 7.2, 0, -9.0)
		for j in range(3): part(Vector3(0.6, 0.06, 0.12), p + Vector3(j * 0.18, 0.09, j * 0.12), "rust" if theme in [0, 2, 3, 4] else "wood", false, Vector3(0, j * 0.7, 0), slot)
	for x in [-13, 13]:
		part(Vector3(0.15, 1.1, 0.15), Vector3(x, 0.55, 7), "wood")
		part(Vector3(0.17, 0.2, 0.17), Vector3(x, 0.92, 7), "white", false)

func own(node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		own(child)

func build() -> void:
	for theme in THEMES:
		for variant in range(3):
			for path in ["res://world/roadside_pois/%s_%d.tscn" % [theme, variant], "res://world/poi_definitions/roadside_%s_%d.tres" % [theme, variant]]:
				if FileAccess.file_exists(path):
					push_error("Refusing to overwrite " + path)
					quit(1)
					return
	for theme in range(6):
		for variant in range(3):
			serial = 0
			root_node = Node3D.new()
			root_node.name = "Roadside%s%d" % [THEMES[theme].capitalize(), variant]
			root_node.set_script(load("res://world/roadside_pois/minor_appearance.gd"))
			for layer in ["Visuals", "Collision", "Furnishings", "LootSpawns", "AccessPoints", "EnemySpawns"]:
				var node := StaticBody3D.new() if layer == "Collision" else Node3D.new()
				node.name = layer
				root_node.add_child(node)
			visuals = root_node.get_node("Visuals")
			bodies = root_node.get_node("Collision")
			dress(theme, variant)
			for i in range(4):
				var point := PoiLootPoint.new()
				point.name = "Supply%d" % i
				point.point_id = StringName("supply_%d" % i)
				point.position = Vector3(-5 if i % 2 == 0 else 5, 0.85, 4 if i < 2 else 0)
				point.spawn_chance = 1.0 if i < 2 else 0.5
				point.candidates.assign([load("res://props/scrap.tscn"), load("res://props/%s.tscn" % SECONDARY[theme])])
				root_node.get_node("LootSpawns").add_child(point)
				# Ground-level supply mats visually separate loot from static dressing.
				part(Vector3(2.0, 0.025, 1.6), Vector3(point.position.x, 0.025, point.position.z), "cloth", false)
			for i in range(3):
				var marker := Marker3D.new()
				marker.name = "Enemy%d" % i
				marker.position = Vector3(-10 + i * 10, 0.2, 2)
				root_node.get_node("EnemySpawns").add_child(marker)
			for entry in [["Front", Vector3(0, 0, 8)], ["Left", Vector3(-13, 0, 0)], ["Right", Vector3(13, 0, 0)]]:
				var marker := Marker3D.new()
				marker.name = entry[0]
				marker.position = entry[1]
				marker.rotation.y = PI if entry[0] == "Front" else (PI / 2 if entry[0] == "Left" else -PI / 2)
				root_node.get_node("AccessPoints").add_child(marker)
			own(root_node)
			var scene := PackedScene.new()
			scene.pack(root_node)
			var scene_path := "res://world/roadside_pois/%s_%d.tscn" % [THEMES[theme], variant]
			ResourceSaver.save(scene, scene_path)
			var definition := PoiDefinition.new()
			definition.definition_id = StringName("roadside_%s_%d" % [THEMES[theme], variant])
			definition.display_name = TITLES[theme]
			definition.kind = PoiDefinition.Kind.WALK_IN
			definition.scene_path = scene_path
			definition.building_bounds = AABB(Vector3(-14, -0.5, -11), Vector3(28, 7, 20))
			definition.site_bounds = AABB(Vector3(-16, -0.5, -12), Vector3(32, 14, 42))
			definition.entrance_path = NodePath()
			definition.return_path = NodePath()
			definition.interior_profile = &""
			definition.access_paths.assign([^"AccessPoints/Front", ^"AccessPoints/Left", ^"AccessPoints/Right"])
			definition.enemy_count_range = Vector2i(0, 2)
			ResourceSaver.save(definition, "res://world/poi_definitions/%s.tres" % definition.definition_id)
			root_node.free()
	print("PASS: authored 18 roadside scenes and definitions")
	quit()

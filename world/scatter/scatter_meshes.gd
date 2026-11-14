extends RefCounted
class_name ScatterMeshes
## Procedural low-poly meshes for scatter layers, built once and shared by every
## MultiMesh. An id is a family name plus a trailing variant digit.
static var cache: Dictionary = {}
static var _foliage: StandardMaterial3D
const STONE := Color("9b9c93")
const STONE_DARK := Color("7f8078")
const MOSS := Color(0.42, 0.47, 0.33, 0.55)
const BARK := Color("6e6558")
const HEARTWOOD := Color("b3a78c")
const STRAW := Color("a39f78")
const SAGE := Color("8f9a79")
const TWIG := Color("7b7163")
const POST_STEEL := Color("6f746d")
const SIGN_YELLOW := Color("ad9440")
const SIGN_BLACK := Color("26272a")
const MARKER_WHITE := Color("b8b6a9")
const FENCE_WOOD := Color("7d6b54")
const FENCE_WIRE := Color("59392a")
const FENCE_SPAN := 3.2
## Knock-down props collide as their post alone, not their boards or wires.
const POSTS := {
	&"marker_0": AABB(Vector3(-0.08, 0, -0.05), Vector3(0.16, 0.95, 0.1)),
	&"marker_1": AABB(Vector3(-0.18, 0, -0.11), Vector3(0.36, 0.7, 0.22)),
	&"sign_0": AABB(Vector3(-0.06, 0, -0.06), Vector3(0.12, 1.9, 0.12)),
	&"sign_1": AABB(Vector3(-0.06, 0, -0.06), Vector3(0.12, 2.5, 0.12)),
	&"sign_2": AABB(Vector3(-0.06, 0, -0.06), Vector3(0.12, 2.5, 0.12)),
	&"fence_0": AABB(Vector3(-0.08, 0, -0.08), Vector3(0.16, 1.3, 0.16)),
	&"fence_1": AABB(Vector3(-0.08, 0, -0.08), Vector3(0.16, 1.3, 0.16)),
	&"fence_2": AABB(Vector3(-0.08, 0, -0.08), Vector3(0.16, 1.3, 0.16)),
	&"fence_3": AABB(Vector3(-0.08, 0, -0.08), Vector3(0.16, 1.3, 0.16)),
}

static func mesh(id: StringName) -> Mesh:
	if cache.has(id): return cache[id]
	var text := String(id)
	var variant := text.right(1).to_int()
	var result: Mesh
	match text.left(text.length() - 2):
		"boulder": result = _boulder(variant)
		"outcrop": result = _outcrop(variant)
		"log": result = _log(variant)
		"stump": result = _stump(variant)
		"tall_grass": result = _tall_grass(variant)
		"weeds": result = _weeds(variant)
		"dry_bush": result = _dry_bush(variant)
		"sapling": result = _sapling(variant)
		"deadfall": result = _deadfall(variant)
		"litter": result = _litter(variant)
		"flora": result = FloraMeshes.ground(variant)
		"marker": result = _marker(variant)
		"sign": result = _sign(variant)
		"fence": result = _fence(variant)
		_: push_error("Unknown scatter mesh: " + text)
	cache[id] = result
	return result

## Collision box in mesh space: the visual bounds pulled in from the ragged edge.
static func solid(id: StringName) -> AABB:
	if POSTS.has(id): return POSTS[id]
	var bounds := mesh(id).get_aabb()
	var inset := minf(bounds.size.x, bounds.size.z) * 0.14
	bounds.position += Vector3(inset, 0, inset)
	bounds.size -= Vector3(inset * 2.0, bounds.size.y * 0.12, inset * 2.0)
	return bounds

static func _foliage_material() -> StandardMaterial3D:
	if _foliage == null:
		_foliage = StandardMaterial3D.new()
		_foliage.vertex_color_use_as_albedo = true
		_foliage.vertex_color_is_srgb = true
		_foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
		_foliage.roughness = 1.0
		_foliage.metallic_specular = 0.0
	return _foliage

static func _commit_foliage(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	var result: ArrayMesh = st.commit()
	result.surface_set_material(0, _foliage_material())
	return result

static func _boulder(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5100 + variant
	var stretch: Vector3 = [Vector3(1.0, 0.72, 0.86), Vector3(0.82, 0.96, 0.9), Vector3(1.28, 0.56, 1.0)][variant % 3]
	# Planar cuts give the fracture faces a lumpy displaced sphere lacks.
	var cuts: Array[Plane] = []
	for i in range(3):
		cuts.append(Plane(Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.6, 0.84)))
	const RINGS := 5
	const SEGMENTS := 8
	var rows: Array[PackedVector3Array] = []
	for ring in range(RINGS + 1):
		var row := PackedVector3Array()
		var polar := PI * float(ring) / RINGS
		for segment in range(SEGMENTS):
			var azimuth := TAU * (segment + 0.5 * (ring % 2)) / SEGMENTS
			var point := Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
			if ring > 0 and ring < RINGS: point *= rng.randf_range(0.8, 1.13)
			for cut in cuts:
				var over := cut.distance_to(point)
				if over > 0.0: point -= cut.normal * over
			point.y = maxf(point.y, -0.45)
			row.append((point + Vector3.UP * 0.45) * stretch)
		rows.append(row)
	var shape := PropMesh.new()
	shape.top_tint = MOSS
	var inside := Vector3.UP * 0.5 * stretch.y
	for ring in range(RINGS):
		for segment in range(SEGMENTS):
			var next := (segment + 1) % SEGMENTS
			var tint := STONE.lerp(STONE_DARK, rng.randf())
			shape.facet(rows[ring][segment], rows[ring][next], rows[ring + 1][segment], inside, tint)
			shape.facet(rows[ring][next], rows[ring + 1][next], rows[ring + 1][segment], inside, tint.darkened(0.04))
	return shape.commit()

static func _outcrop(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5200 + variant
	var shape := PropMesh.new()
	shape.top_tint = Color(MOSS.r, MOSS.g, MOSS.b, 0.4)
	# Tilted strata: every bed shares one dip, so the pile reads as bedrock.
	var dip := Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, deg_to_rad(16.0 + variant * 11.0))
	var beds := 4 + variant
	for bed in range(beds):
		var shrink := 1.0 - bed * 0.13
		var size := Vector3(rng.randf_range(3.0, 4.6) * shrink, rng.randf_range(0.5, 0.85), rng.randf_range(2.0, 3.2) * shrink)
		var centre := Vector3(rng.randf_range(-0.5, 0.5), 0.05 + bed * 0.52, rng.randf_range(-0.4, 0.4)) + dip * Vector3(0, 0, bed * 0.3)
		shape.jagged(size, Transform3D(dip * Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), centre), STONE.lerp(STONE_DARK, 0.3 + 0.5 * (bed % 2)), rng, 0.14)
	return shape.commit()

static func _log(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5300 + variant
	var shape := PropMesh.new()
	shape.top_tint = Color(MOSS.r, MOSS.g, MOSS.b, 0.45)
	var radius := 0.27 + variant * 0.09
	var length := 5.4 - variant * 1.3
	var a := Vector3(-length * 0.5, radius * 0.82, 0)
	var middle := Vector3(rng.randf_range(-0.4, 0.4), radius * 0.8, 0.13)
	var b := Vector3(length * 0.5, radius * 0.66, -0.06)
	shape.limb(a, middle, radius, radius * 0.93, BARK, 7, HEARTWOOD)
	shape.limb(middle, b, radius * 0.93, radius * 0.76, BARK, 7, HEARTWOOD)
	for stub in range(3):
		var t := rng.randf_range(0.15, 0.9)
		var root := a.lerp(b, t)
		var direction := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.3, 1.0), rng.randf_range(-1, 1)).normalized()
		shape.limb(root, root + direction * rng.randf_range(0.45, 0.95), radius * 0.3, radius * 0.1, BARK.darkened(0.12), 5, HEARTWOOD)
	# Splintered break at the thin end.
	for spike in range(4):
		var offset := Vector3(0, rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6)) * radius
		shape.limb(b + offset, b + offset + Vector3(rng.randf_range(0.25, 0.6), rng.randf_range(-0.05, 0.1), 0), radius * 0.26, 0.0, HEARTWOOD.darkened(0.15), 4)
	if variant == 1:
		# Uprooted: a ragged root plate still packed with soil.
		var soil := Color("6d6252")
		for root in range(9):
			var angle := root * TAU / 9.0
			var reach := rng.randf_range(0.75, 1.3)
			var tip := a + Vector3(rng.randf_range(-0.25, 0.05), sin(angle) * reach, cos(angle) * reach)
			shape.limb(a, tip, radius * 0.5, radius * 0.08, BARK.darkened(0.2), 4)
			var next := a + Vector3(-0.1, sin(angle + 0.7) * reach * 0.8, cos(angle + 0.7) * reach * 0.8)
			shape.facet(a + Vector3(-0.12, 0, 0), tip, next, a + Vector3.RIGHT, soil.darkened(rng.randf_range(0.0, 0.18)))
			shape.facet(a + Vector3(-0.12, 0, 0), next, tip, a + Vector3.LEFT * 2.0, soil.darkened(0.1))
	return shape.commit()

static func _stump(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5400 + variant
	var shape := PropMesh.new()
	shape.top_tint = Color(MOSS.r, MOSS.g, MOSS.b, 0.3)
	shape.prism(0.46, 0.33, 0.52, Transform3D(Basis.IDENTITY, Vector3.DOWN * 0.08), BARK, 8, HEARTWOOD)
	for root in range(5):
		var angle := root * TAU / 5.0 + rng.randf_range(-0.3, 0.3)
		var direction := Vector3(cos(angle), 0, sin(angle))
		shape.limb(direction * 0.28 + Vector3.UP * 0.2, direction * rng.randf_range(0.75, 1.05) + Vector3.DOWN * 0.08, 0.14, 0.04, BARK.darkened(0.08), 5)
	if variant == 1:
		# A snapped snag: the trunk broke above head height and left long splinters.
		shape.prism(0.33, 0.25, 1.15, Transform3D(Basis.IDENTITY, Vector3.UP * 0.44), BARK, 8, HEARTWOOD)
		for spike in range(5):
			var angle := spike * TAU / 5.0
			var base := Vector3(cos(angle) * 0.13, 1.55, sin(angle) * 0.13)
			shape.limb(base, base + Vector3(cos(angle) * 0.06, rng.randf_range(0.3, 0.95), sin(angle) * 0.06), 0.1, 0.0, HEARTWOOD.darkened(0.2), 4)
	else:
		# Sawn top with one torn hinge of wood left standing.
		shape.limb(Vector3(0.2, 0.42, 0.05), Vector3(0.24, 0.72, 0.07), 0.07, 0.0, HEARTWOOD.darkened(0.12), 4)
	return shape.commit()

static func _blade(st: SurfaceTool, root: Vector3, direction: Vector3, height: float, width: float, lean: float, color: Color) -> void:
	var side := direction.cross(Vector3.UP).normalized() * width
	var middle := root + Vector3.UP * height * 0.55 + direction * lean * 0.3
	var tip := root + Vector3.UP * height + direction * lean
	ForestMeshes._triangle(st, root - side, middle - side * 0.7, root + side, color.darkened(0.12))
	ForestMeshes._triangle(st, root + side, middle - side * 0.7, middle + side * 0.7, color)
	ForestMeshes._triangle(st, middle - side * 0.7, tip, middle + side * 0.7, color.lightened(0.06))

static func _tall_grass(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5500 + variant
	for blade in range(16):
		var angle := blade * 2.399
		var direction := Vector3(cos(angle), 0, sin(angle))
		var root := direction * rng.randf_range(0.02, 0.38)
		var height := rng.randf_range(0.65, 1.2) * (1.0 + variant * 0.25)
		var color := STRAW.lerp(SAGE, rng.randf()) if variant == 0 else STRAW.darkened(rng.randf_range(0.0, 0.14))
		_blade(st, root, direction, height, 0.05, rng.randf_range(0.15, 0.5), color)
	return _commit_foliage(st)

static func _weeds(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5600 + variant
	for blade in range(9):
		var angle := blade * 2.399 + variant
		var direction := Vector3(cos(angle), 0, sin(angle))
		_blade(st, direction * rng.randf_range(0.02, 0.3), direction, rng.randf_range(0.25, 0.55), 0.07, rng.randf_range(0.1, 0.3), SAGE.darkened(rng.randf_range(0.0, 0.2)))
	# Seeded stalks stand above the leaves and catch the eye at the road edge.
	for stalk in range(3 + variant):
		var root := Vector3(rng.randf_range(-0.22, 0.22), 0, rng.randf_range(-0.22, 0.22))
		var tip := root + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.6, 0.95), rng.randf_range(-0.12, 0.12))
		ForestMeshes._tube(st, root, tip, 0.014, 0.008, TWIG.lightened(0.1), 3)
		ForestMeshes._tube(st, tip - Vector3.UP * 0.02, tip + Vector3.UP * 0.16, 0.035, 0.012, Color("8a7a5c"), 4)
	return _commit_foliage(st)

static func _dry_bush(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5700 + variant
	for stem in range(7):
		var angle := stem * 2.399
		var direction := Vector3(cos(angle), rng.randf_range(0.7, 1.5), sin(angle)).normalized()
		var fork := direction * rng.randf_range(0.45, 0.75)
		ForestMeshes._tube(st, Vector3.ZERO, fork, 0.03, 0.016, TWIG, 3)
		for twig in range(3):
			var end := fork + (direction + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.1, 0.7), rng.randf_range(-0.8, 0.8))).normalized() * rng.randf_range(0.3, 0.6)
			ForestMeshes._tube(st, fork, end, 0.016, 0.005, TWIG.lightened(rng.randf_range(0.0, 0.12)), 3)
	return _commit_foliage(st)

static func _sapling(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5800 + variant
	var lean := Vector3(rng.randf_range(-0.06, 0.06), 1.0, rng.randf_range(-0.06, 0.06))
	ForestMeshes._tube(st, Vector3.ZERO, lean, 0.028, 0.006, BARK.lightened(0.1), 4)
	for tier in range(5):
		var y := 0.22 + tier * 0.16
		var reach := (1.05 - y) * 0.42
		for bough in range(4):
			var angle := bough * TAU / 4.0 + tier * 0.9
			var root := lean * y
			var end := root + Vector3(cos(angle) * reach, -0.05, sin(angle) * reach)
			ForestMeshes._bough(st, root, end, reach * 0.42, Color("5d6a4c").lightened(rng.randf_range(0.0, 0.12)))
	return _commit_foliage(st)

static func _deadfall(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5900 + variant
	for branch in range(6):
		var angle := rng.randf_range(0, TAU)
		var direction := Vector3(cos(angle), rng.randf_range(-0.04, 0.16), sin(angle))
		var root := Vector3(rng.randf_range(-0.5, 0.5), 0.06 + branch * 0.035, rng.randf_range(-0.5, 0.5)) - direction * 0.8
		var length := rng.randf_range(1.2, 2.5)
		ForestMeshes._tube(st, root, root + direction * length, 0.05, 0.02, TWIG.darkened(rng.randf_range(0.0, 0.2)), 4)
		for twig in range(2):
			var start := root + direction * length * rng.randf_range(0.35, 0.85)
			var end := start + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.1, 0.45), rng.randf_range(-0.5, 0.5))
			ForestMeshes._tube(st, start, end, 0.02, 0.006, TWIG, 3)
	return _commit_foliage(st)

## Flat debris for the carriageway: nothing here is tall enough to matter to a wheel.
static func _litter(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6000 + variant
	var shape := PropMesh.new()
	match variant:
		0: # Split plank and splinters.
			shape.box(Vector3(1.3, 0.035, 0.17), Transform3D(Basis(Vector3.UP, 0.2), Vector3(0, 0.02, 0)), Color("8d8069"))
			shape.box(Vector3(0.55, 0.03, 0.09), Transform3D(Basis(Vector3.UP, -0.7), Vector3(0.5, 0.02, 0.3)), Color("7c705c"))
			shape.box(Vector3(0.3, 0.025, 0.05), Transform3D(Basis(Vector3.UP, 1.1), Vector3(-0.4, 0.015, -0.25)), Color("8d8069"))
		1: # Shed tyre tread, curled at one end.
			for segment in range(5):
				var lift := 0.02 + maxf(0.0, segment - 2.0) * 0.035
				shape.box(Vector3(0.3, 0.04, 0.2), Transform3D(Basis(Vector3.UP, 0.15 * segment) * Basis(Vector3.FORWARD, 0.14 * maxf(0.0, segment - 2.0)), Vector3(segment * 0.27 - 0.55, lift, segment * 0.04)), Color("2f2f2c"))
		2: # Rockfall chips.
			for chip in range(7):
				var size := rng.randf_range(0.07, 0.2)
				shape.jagged(Vector3(size, size * 0.6, size * 1.2), Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), Vector3(rng.randf_range(-0.6, 0.6), size * 0.25, rng.randf_range(-0.6, 0.6))), STONE.lerp(STONE_DARK, rng.randf()), rng, 0.2)
		3: # Windblown leaves and grit drifted against nothing in particular.
			for leaf in range(22):
				var centre := Vector3(rng.randf_range(-0.9, 0.9), 0.02, rng.randf_range(-0.5, 0.5))
				var size := rng.randf_range(0.06, 0.13)
				var turn := Basis(Vector3.UP, rng.randf_range(0, TAU))
				shape.tri(centre + turn * Vector3(-size, 0, 0), centre + turn * Vector3(size, 0, 0), centre + turn * Vector3(0, 0, size * 1.6), Vector3.UP, Color("84704f").darkened(rng.randf_range(0.0, 0.3)))
		_: # Snapped branch.
			shape.limb(Vector3(-0.8, 0.04, 0), Vector3(0.7, 0.05, 0.25), 0.04, 0.02, TWIG, 4)
			shape.limb(Vector3(0.1, 0.04, 0.1), Vector3(0.5, 0.06, -0.35), 0.022, 0.008, TWIG, 3)
			shape.limb(Vector3(-0.3, 0.04, -0.02), Vector3(-0.1, 0.05, 0.4), 0.02, 0.006, TWIG, 3)
	return shape.commit()

## 0: reflector post. 1: distance stone with a painted cap and no lettering.
static func _marker(variant: int) -> ArrayMesh:
	var shape := PropMesh.new()
	if variant == 1:
		shape.box(Vector3(0.34, 0.95, 0.2), Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), Color("9a9a90"))
		shape.box(Vector3(0.36, 0.14, 0.22), Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), SIGN_YELLOW)
	else:
		shape.box(Vector3(0.12, 1.25, 0.05), Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), MARKER_WHITE)
		shape.box(Vector3(0.125, 0.16, 0.055), Transform3D(Basis.IDENTITY, Vector3(0, 0.72, 0)), SIGN_BLACK)
	return shape.commit()

## Symbols only. 0: striped hazard board. 1/2: diamond with an arrow bending
## towards the viewer's right/left. Local +Z is the face.
static func _sign(variant: int) -> ArrayMesh:
	var shape := PropMesh.new()
	if variant == 0:
		shape.box(Vector3(0.09, 2.3, 0.09), Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), POST_STEEL)
		shape.box(Vector3(0.55, 0.85, 0.04), Transform3D(Basis.IDENTITY, Vector3(0, 1.45, 0.06)), SIGN_YELLOW)
		for stripe in range(3):
			shape.box(Vector3(0.62, 0.085, 0.012), Transform3D(Basis(Vector3.BACK, 0.62), Vector3(0, 1.2 + stripe * 0.26, 0.085)), SIGN_BLACK)
		return shape.commit()
	shape.box(Vector3(0.09, 3.1, 0.09), Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), POST_STEEL)
	var face := Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0, 2.05, 0.06))
	shape.box(Vector3(0.78, 0.78, 0.04), face, SIGN_YELLOW)
	shape.box(Vector3(0.8, 0.8, 0.02), face.translated_local(Vector3(0, 0, -0.022)), POST_STEEL)
	var bend := 1.0 if variant == 1 else -1.0
	for stroke: Array in [[Vector2(-0.1 * bend, -0.26), Vector2(-0.1 * bend, 0.0)], [Vector2(-0.1 * bend, 0.0), Vector2(0.12 * bend, 0.2)],
			[Vector2(0.14 * bend, 0.22), Vector2(-0.03 * bend, 0.2)], [Vector2(0.14 * bend, 0.22), Vector2(0.11 * bend, 0.05)]]:
		var span: Vector2 = stroke[1] - stroke[0]
		var centre: Vector2 = (stroke[0] + stroke[1]) * 0.5
		shape.box(Vector3(0.07, span.length() + 0.05, 0.012), Transform3D(Basis(Vector3.BACK, atan2(-span.x, span.y)), Vector3(centre.x, 2.05 + centre.y, 0.09)), SIGN_BLACK)
	return shape.commit()

## One fence post with what it carries towards the next post along local +Z.
## 0: taut wires. 1: slack and one strand down. 2: planks. 3: a lone end post.
static func _fence(variant: int) -> ArrayMesh:
	var shape := PropMesh.new()
	shape.box(Vector3(0.12, 1.9, 0.12), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), FENCE_WOOD)
	for strand in range(3):
		var height := 0.5 + strand * 0.35
		var from := Vector3(0, height, 0)
		var to := Vector3(0, height, FENCE_SPAN)
		match variant:
			0: shape.wire(from, to, 0.04 + strand * 0.02, 0.035, FENCE_WIRE, 3)
			1:
				if strand == 1: shape.wire(from, Vector3(0.25, 0.04, FENCE_SPAN * 0.55), 0.1, 0.035, FENCE_WIRE, 3)
				else: shape.wire(from, to, 0.16 + strand * 0.05, 0.035, FENCE_WIRE, 4)
			2:
				if strand < 2: shape.beam(from + Vector3.UP * 0.12, to + Vector3.UP * 0.12, 0.04, 0.13, FENCE_WOOD.darkened(0.2))
	return shape.commit()

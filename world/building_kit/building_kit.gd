extends RefCounted
class_name BuildingKit
## Shared architectural vocabulary for authored and generated buildings.
## Compose walls with framed openings, rooms, slabs, roofs, columns, beams,
## stairs and bands on one metric convention instead of raw boxes, then call
## build() once: pieces batch into one ArrayMesh (a surface per finish) and
## one StaticBody3D of box colliders. validate() reports openings that do not
## fit, floating pieces, pieces that pass through a wall or slab, and coinciding
## faces that z-fight. Units are building-local metres, Y up, the main
## facade faces +Z. Finishes come from BuildingKitMaterials.

const STOREY := 3.0
const WALL := 0.2
const SLAB := 0.2
const PLINTH := 0.4
const FRAME := 0.09
const FRAME_DEPTH := 0.035
const PLINTH_DEPTH := 0.05
const CAP_DEPTH := 0.04
const DOOR := Vector2(1.0, 2.2)
const WIDE_DOOR := Vector2(1.8, 2.5)
const WINDOW := Vector2(1.2, 1.2)
const SILL := 0.9
const STEP_RUN := 0.28
const STEP_RISE := 0.18
const SUPPORT_TOLERANCE := 0.02
## Depth a piece may sink into another (a jamb into the floor) before a piece
## passing through a panel counts as a clash.
const CLASH_TOLERANCE := 0.03
## Faces closer than this along their normal count as coplanar.
const COPLANAR_TOLERANCE := 0.003
## Shared area (square metres) of two coplanar faces that validate() reports as z-fighting.
const COPLANAR_AREA := 0.0025
## A piece counts as a panel (wall, slab, pane) when its thinnest side is at
## most this fraction of its middle side.
const PANEL_RATIO := 0.5

class Surface extends RefCounted:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

var rng := RandomNumberGenerator.new()
## Height that counts as resting on the ground for validate().
var ground := 0.0
var _origin := Transform3D.IDENTITY
var _surfaces := {}
var _colliders: Array = []
var _pieces: Array[Dictionary] = []
var _issues: Array[String] = []
var _shade := 1.0


func _init(seed_value := 0) -> void:
	rng.seed = seed_value


## Opening presets. `at` is the opening centre's distance from the wall start.
static func door(at: float, size := DOOR) -> Dictionary:
	return {"at": at, "width": size.x, "height": size.y, "sill": 0.0}


## glazing: &"intact" (solid pane), &"broken" (shards, open) or &"none".
static func window(at: float, size := WINDOW, sill := SILL, glazing := &"intact") -> Dictionary:
	return {"at": at, "width": size.x, "height": size.y, "sill": sill, "glazing": glazing}


## Local frame for the calls that follow, like a room's own origin and yaw.
func frame(at: Vector3, yaw := 0.0) -> void:
	_origin = Transform3D(Basis(Vector3.UP, yaw), at)


# --- Pieces ---------------------------------------------------------------

## A box. options: basis (Basis), bevel (m), solid (bool), name, hung (bool:
## the piece may rest on nothing, for example a sign on a cable), embedded
## (bool: the piece may pass through or sit inside others, like a sill board
## through its wall).
func box(center: Vector3, size: Vector3, finish: StringName, options := {}) -> void:
	_add_box(_origin * Transform3D(options.get("basis", Basis.IDENTITY), center), size, finish, options)


## A wall from a to b (plan XZ points) on its centre line. Its outer face
## points along (-d.y, 0, d.x) for d = b - a: a wall running +X faces +Z.
## options:
##   thickness, base (bottom y), solid (default true)
##   openings: Array of door()/window() dictionaries
##   corner: &"cover" extends the wall over both corners, &"butt" stops it at
##     the covering walls' inner faces, &"none" ends exactly at a and b as a
##     free end that plinth and cap wrap around (join collinear walls into one)
##   frame (finish for opening frames, default &"trim"), inner_frame (bool)
##   plinth, cap (finish names; omitted means none)
func wall(a: Vector2, b: Vector2, height: float, finish: StringName, options := {}) -> void:
	var thickness: float = options.get("thickness", WALL)
	var delta := b - a
	var length := delta.length()
	if length < 0.05 or height <= 0.0:
		_issues.append("Wall %s-%s is degenerate" % [a, b])
		return
	var dir := delta / length
	var basis := Basis(Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(-dir.y, 0, dir.x))
	var pose := _origin * Transform3D(basis, Vector3(a.x, options.get("base", 0.0), a.y))
	var ends := _ends(length, thickness, options.get("corner", &"none"), 0.0)
	var solid: bool = options.get("solid", true)
	var frame_finish: StringName = options.get("frame", &"trim")
	var openings: Array = options.get("openings", []).duplicate()
	openings.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.at < y.at)
	var cursor: float = ends.x
	var previous_edge: float = ends.x
	var doors: Array[Vector2] = []
	for opening: Dictionary in openings:
		var width: float = opening.width
		var tall: float = opening.height
		var sill: float = opening.get("sill", 0.0)
		var left: float = opening.at - width * 0.5
		var right: float = opening.at + width * 0.5
		if left - FRAME < previous_edge - 0.001 or right + FRAME > ends.y + 0.001:
			_issues.append("Opening at %.2f m does not fit wall %s-%s with its frame" % [opening.at, a, b])
			continue
		if sill + tall + FRAME > height + 0.001:
			_issues.append("Opening at %.2f m leaves no lintel in a %.2f m wall" % [opening.at, height])
			continue
		_wall_piece(pose, cursor, left, 0.0, height, thickness, finish, solid)
		if sill > 0.0:
			_wall_piece(pose, left, right, 0.0, sill, thickness, finish, solid)
		_wall_piece(pose, left, right, sill + tall, height, thickness, finish, solid)
		_opening_details(pose, opening, thickness, frame_finish, options.get("inner_frame", true))
		if sill <= 0.0:
			doors.append(Vector2(left - FRAME, right + FRAME))
		cursor = right
		previous_edge = right + FRAME
	_wall_piece(pose, cursor, ends.y, 0.0, height, thickness, finish, solid)
	if options.has("plinth"):
		var run := _ends(length, thickness, options.get("corner", &"none"), PLINTH_DEPTH)
		var start: float = run.x
		for gap in doors:
			_strip(pose, start, gap.x, 0.0, PLINTH, thickness + PLINTH_DEPTH * 2.0, 0.0, options.plinth, "plinth")
			start = gap.y
		_strip(pose, start, run.y, 0.0, PLINTH, thickness + PLINTH_DEPTH * 2.0, 0.0, options.plinth, "plinth")
	if options.has("cap"):
		var top := _ends(length, thickness, options.get("corner", &"none"), CAP_DEPTH)
		_strip(pose, top.x, top.y, height, height + 0.08, thickness + CAP_DEPTH * 2.0, 0.0, options.cap, "cap")


## Four walls around a plan rectangle (Rect2 in XZ). sides maps &"front" (+Z),
## &"back", &"left" (-X) and &"right" to opening arrays; distances run from
## each wall's start: front from -X, right from +Z, back from +X, left from -Z.
## Front and back cover the corners; the sides butt into them.
func room(rect: Rect2, height: float, finish: StringName, sides := {}, options := {}) -> void:
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.end.x
	var z1 := rect.end.y
	var plan := {
		&"front": [Vector2(x0, z1), Vector2(x1, z1), &"cover"],
		&"right": [Vector2(x1, z1), Vector2(x1, z0), &"butt"],
		&"back": [Vector2(x1, z0), Vector2(x0, z0), &"cover"],
		&"left": [Vector2(x0, z0), Vector2(x0, z1), &"butt"],
	}
	for side: StringName in plan:
		var settings := options.duplicate()
		settings.corner = plan[side][2]
		settings.openings = sides.get(side, sides.get(String(side), []))
		wall(plan[side][0], plan[side][1], height, finish, settings)


## A horizontal strip on a wall's outer face, for belt courses and paint bands.
## Same a/b/corner convention as wall(); keep it clear of openings.
func band(a: Vector2, b: Vector2, bottom: float, height: float, finish: StringName, options := {}) -> void:
	var thickness: float = options.get("thickness", WALL)
	var depth: float = options.get("depth", 0.03)
	var delta := b - a
	var length := delta.length()
	var dir := delta / length
	var basis := Basis(Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(-dir.y, 0, dir.x))
	var pose := _origin * Transform3D(basis, Vector3(a.x, options.get("base", 0.0), a.y))
	var run := _ends(length, thickness, options.get("corner", &"none"), depth)
	_strip(pose, run.x, run.y, bottom, bottom + height, depth, thickness * 0.5 + depth * 0.5, finish, "band")


## A floor, ceiling or roof slab whose top is at `top`. options: thickness, solid, bevel.
func slab(rect: Rect2, top: float, finish: StringName, options := {}) -> void:
	var thickness: float = options.get("thickness", SLAB)
	var center := Vector3(rect.get_center().x, top - thickness * 0.5, rect.get_center().y)
	box(center, Vector3(rect.size.x, thickness, rect.size.y), finish,
		{"solid": options.get("solid", true), "bevel": options.get("bevel", 0.0), "name": "slab"})


## A flat roof over rect with an overhang and an upstand fascia on every edge.
## options: thickness, overhang, fascia (finish), fascia_height.
func roof(rect: Rect2, top: float, finish: StringName, options := {}) -> void:
	var thickness: float = options.get("thickness", SLAB)
	var overhang: float = options.get("overhang", 0.3)
	var outer := rect.grow(overhang)
	slab(outer, top, finish, {"thickness": thickness})
	var fascia: StringName = options.get("fascia", &"trim")
	var tall: float = options.get("fascia_height", thickness + 0.15)
	var depth := 0.06
	var y := top + 0.06 - tall * 0.5
	var c := outer.get_center()
	for z: float in [outer.position.y - depth * 0.5, outer.end.y + depth * 0.5]:
		box(Vector3(c.x, y, z), Vector3(outer.size.x + depth * 2.0, tall, depth), fascia, {"name": "fascia", "solid": true})
	for x: float in [outer.position.x - depth * 0.5, outer.end.x + depth * 0.5]:
		box(Vector3(x, y, c.y), Vector3(depth, tall, outer.size.y), fascia, {"name": "fascia", "solid": true})


## A column standing on `base`. options: size, round (bool), solid, bevel.
func column(at: Vector2, base: float, height: float, finish: StringName, options := {}) -> void:
	var size: float = options.get("size", 0.3)
	var center := Vector3(at.x, base + height * 0.5, at.y)
	if options.get("round", false):
		_add_cylinder(_origin * Transform3D(Basis.IDENTITY, center), size * 0.5, height, finish, options.get("solid", true))
	else:
		box(center, Vector3(size, height, size), finish,
			{"solid": options.get("solid", true), "bevel": options.get("bevel", 0.02), "name": "column"})


## A straight member from a to b with a rectangular section (width, depth).
func beam(a: Vector3, b: Vector3, section: Vector2, finish: StringName, options := {}) -> void:
	var forward := b - a
	var length := forward.length()
	if length < 0.01:
		_issues.append("Beam %s-%s is degenerate" % [a, b])
		return
	forward /= length
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var x := up.cross(forward).normalized()
	var basis := Basis(x, forward.cross(x), forward)
	box((a + b) * 0.5, Vector3(section.x, section.y, length), finish,
		{"basis": basis, "solid": options.get("solid", false), "bevel": options.get("bevel", 0.0), "name": "beam"})


## A straight flight that climbs `rise` from `start` (front edge, centre of the
## first step, at height base) towards local -Z after rotating by yaw. Steps are
## visual; one ramp collider runs through the riser midpoints so the player
## walks up smoothly, and blocks one step lower fill the solid flight under it.
## Add the landing slab yourself.
func stairs(start: Vector2, base: float, yaw: float, width: float, rise: float, finish: StringName, options := {}) -> void:
	var run: float = options.get("run", STEP_RUN)
	var count := maxi(1, ceili(rise / STEP_RISE))
	var step := rise / count
	var saved := _origin
	_origin = _origin * Transform3D(Basis(Vector3.UP, yaw), Vector3(start.x, base, start.y))
	for i in count:
		var top := step * (i + 1)
		box(Vector3(0, top * 0.5, -run * (i + 0.5)), Vector3(width, top, run), finish, {"name": "step", "bevel": 0.01})
	if options.get("solid", true):
		var length := run * count
		var slope := atan2(rise, length)
		var span := sqrt(length * length + rise * rise)
		var ramp := 0.2
		var mid := Vector3(0, rise * 0.5, run * 0.5 - length * 0.5)
		var basis := Basis(Vector3.RIGHT, slope)
		var pose := _origin * Transform3D(basis, mid + basis.y * -ramp * 0.5)
		_colliders.append([pose, Vector3(width, ramp, span)])
		# The ramp top passes half a step above each lower tread, so these stay under it.
		for i in range(1, count):
			var block := _origin * Transform3D(Basis.IDENTITY, Vector3(0, step * i * 0.5, -run * (i + 0.5)))
			_colliders.append([block, Vector3(width, step * i, run)])
	_origin = saved


# --- Output ---------------------------------------------------------------

## Problems found while composing, pieces that rest on nothing (a piece is
## supported when it touches the ground or a chain of pieces reaching it), and
## clashes: a piece passing through a wall or slab, or two faces that coincide.
func validate() -> Array[String]:
	var result := _issues.duplicate()
	var grounded: Array[bool] = []
	grounded.resize(_pieces.size())
	var queue: Array[int] = []
	for i in _pieces.size():
		var bounds: AABB = _pieces[i].aabb
		if bounds.position.y <= ground + SUPPORT_TOLERANCE or _pieces[i].hung:
			grounded[i] = true
			queue.append(i)
	while not queue.is_empty():
		var current: int = queue.pop_back()
		var reach: AABB = _pieces[current].aabb.grow(SUPPORT_TOLERANCE)
		for j in _pieces.size():
			if not grounded[j] and reach.intersects(_pieces[j].aabb):
				grounded[j] = true
				queue.append(j)
	for i in _pieces.size():
		if not grounded[i]:
			result.append("%s at %s rests on nothing" % [_pieces[i].name, _pieces[i].aabb.position])
	result.append_array(_clashes())
	return result


func stats() -> Dictionary:
	var triangles := 0
	for finish in _surfaces:
		triangles += (_surfaces[finish] as Surface).indices.size() / 3
	return {"pieces": _pieces.size(), "triangles": triangles, "colliders": _colliders.size(), "finishes": _surfaces.size()}


## Adds KitMesh (MeshInstance3D) and KitSolids (StaticBody3D) under parent.
## Pass visuals = false for collision-only navigation copies.
func build(parent: Node3D, visuals := true, collision := true) -> void:
	if visuals and not _surfaces.is_empty():
		var mesh := ArrayMesh.new()
		var names := _surfaces.keys()
		names.sort_custom(func(p: StringName, q: StringName) -> bool: return String(p) < String(q))
		for finish: StringName in names:
			var surface: Surface = _surfaces[finish]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = surface.vertices
			arrays[Mesh.ARRAY_NORMAL] = surface.normals
			arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
			arrays[Mesh.ARRAY_TEX_UV2] = surface.uv2s
			arrays[Mesh.ARRAY_COLOR] = surface.colors
			arrays[Mesh.ARRAY_INDEX] = surface.indices
			var raw := ArrayMesh.new()
			raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var tool := SurfaceTool.new()
			tool.create_from(raw, 0)
			tool.generate_tangents()
			tool.set_material(BuildingKitMaterials.material(finish))
			tool.commit(mesh)
		var instance := MeshInstance3D.new()
		instance.name = "KitMesh"
		instance.mesh = mesh
		parent.add_child(instance)
	if collision and not _colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "KitSolids"
		for entry: Array in _colliders:
			var shape := BoxShape3D.new()
			shape.size = entry[1]
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.transform = entry[0]
			body.add_child(collider)
		parent.add_child(body)


# --- Internals ------------------------------------------------------------

## Start and end along a wall for a part that sticks out `depth` past its faces.
func _ends(length: float, thickness: float, corner: StringName, depth: float) -> Vector2:
	match corner:
		&"cover":
			return Vector2(-thickness * 0.5 - depth, length + thickness * 0.5 + depth)
		&"butt":
			return Vector2(thickness * 0.5 + depth, length - thickness * 0.5 - depth)
	# A free end: wrap it too, or the part's end face z-fights with the wall's.
	return Vector2(-depth, length + depth)


func _wall_piece(pose: Transform3D, x0: float, x1: float, y0: float, y1: float, thickness: float, finish: StringName, solid: bool) -> void:
	if x1 - x0 < 0.001 or y1 - y0 < 0.001:
		return
	var center := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)
	_add_box(pose * Transform3D(Basis.IDENTITY, center), Vector3(x1 - x0, y1 - y0, thickness), finish, {"solid": solid, "name": "wall"})


## A strip along a wall. Plinths and caps wrap the wall, so they are embedded.
func _strip(pose: Transform3D, x0: float, x1: float, y0: float, y1: float, depth: float, z: float, finish: StringName, label: String) -> void:
	if x1 - x0 < 0.001:
		return
	_add_box(pose * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z)),
		Vector3(x1 - x0, y1 - y0, depth), finish, {"name": label, "embedded": label != "band"})


## Frames on both faces, a window sill board, mullion and glazing.
func _opening_details(pose: Transform3D, opening: Dictionary, thickness: float, finish: StringName, inner: bool) -> void:
	var width: float = opening.width
	var tall: float = opening.height
	var sill: float = opening.get("sill", 0.0)
	var x: float = opening.at
	var faces := [1.0, -1.0] if inner else [1.0]
	for side: float in faces:
		var z := side * (thickness * 0.5 + FRAME_DEPTH * 0.5)
		for jamb_x: float in [x - width * 0.5 - FRAME * 0.5, x + width * 0.5 + FRAME * 0.5]:
			_add_box(pose * Transform3D(Basis.IDENTITY, Vector3(jamb_x, sill + (tall + FRAME) * 0.5, z)),
				Vector3(FRAME, tall + FRAME, FRAME_DEPTH), finish, {"name": "jamb"})
		_add_box(pose * Transform3D(Basis.IDENTITY, Vector3(x, sill + tall + FRAME * 0.5, z)),
			Vector3(width, FRAME, FRAME_DEPTH), finish, {"name": "head"})
	if sill <= 0.0:
		return
	var board := Vector3(width + FRAME * 2.0 + 0.06, 0.06, thickness + 0.1)
	_add_box(pose * Transform3D(Basis.IDENTITY, Vector3(x, sill - 0.035, 0.03)), board, finish, {"name": "sill", "embedded": true})
	if width >= 1.5:
		_add_box(pose * Transform3D(Basis.IDENTITY, Vector3(x, sill + tall * 0.5, 0.0)),
			Vector3(FRAME * 0.7, tall, 0.06), finish, {"name": "mullion"})
	match opening.get("glazing", &"intact"):
		&"intact":
			_add_box(pose * Transform3D(Basis.IDENTITY, Vector3(x, sill + tall * 0.5, 0.0)),
				Vector3(width + 0.04, tall + 0.04, 0.02), &"glass", {"solid": true, "name": "pane", "embedded": true})
		&"broken":
			for corner in 2:
				var w := rng.randf_range(0.2, 0.45) * width
				var h := rng.randf_range(0.15, 0.5) * tall
				var left := corner == 0
				var cx := x - width * 0.5 + w * 0.5 - 0.02 if left else x + width * 0.5 - w * 0.5 + 0.02
				var cy := sill + h * 0.5 - 0.02 if left else sill + tall - h * 0.5 + 0.02
				_add_box(pose * Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.12, 0.12)), Vector3(cx, cy, 0.0)),
					Vector3(w, h, 0.02), &"glass", {"name": "shard", "embedded": true})


func _surface(finish: StringName) -> Surface:
	if not _surfaces.has(finish):
		if not BuildingKitMaterials.has(finish):
			_issues.append("Unknown finish %s" % finish)
		_surfaces[finish] = Surface.new()
	return _surfaces[finish]


## Keeps each piece as an oriented box for validate().
func _record(name: String, pose: Transform3D, half: Vector3, bevel: float, options: Dictionary) -> void:
	var axes: Array[Vector3] = [pose.basis.x, pose.basis.y, pose.basis.z]
	var extent := Vector3.ZERO
	for k in 3:
		extent[k] = half[k] * axes[k].length()
		axes[k] = axes[k].normalized()
	_pieces.append({
		"name": name, "aabb": pose * AABB(-half, half * 2.0), "hung": options.get("hung", false),
		"embedded": options.get("embedded", false), "round": options.get("round", false),
		"center": pose.origin, "axes": axes, "half": extent, "bevel": bevel,
	})


func _add_box(pose: Transform3D, size: Vector3, finish: StringName, options: Dictionary) -> void:
	var label: String = options.get("name", String(finish))
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		_issues.append("%s has a non-positive size %s" % [label, size])
		return
	_shade = rng.randf_range(0.9, 1.04)
	var surface := _surface(finish)
	var h := size * 0.5
	var bevel := minf(options.get("bevel", 0.0), minf(h.x, minf(h.y, h.z)) * 0.6)
	for axis in 3:
		var j := (axis + 1) % 3
		var k := (axis + 2) % 3
		for sign_value: float in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = sign_value * h[axis]
				p[j] = corner.x * (h[j] - bevel)
				p[k] = corner.y * (h[k] - bevel)
				points.append(pose * p)
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			_poly(surface, points, pose.basis * normal, 0.0)
		if bevel <= 0.0:
			continue
		for sj: float in [-1.0, 1.0]:
			for sk: float in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				for corner: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1)]:
					var p := Vector3.ZERO
					p[axis] = corner.x * (h[axis] - bevel)
					p[j] = sj * (h[j] - bevel * corner.y)
					p[k] = sk * (h[k] - bevel * (1.0 - corner.y))
					points.append(pose * p)
				var normal := Vector3.ZERO
				normal[j] = sj
				normal[k] = sk
				_poly(surface, points, pose.basis * normal, 1.0)
	if bevel > 0.0:
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var signs := Vector3(sx, sy, sz)
					var points: Array[Vector3] = []
					for axis in 3:
						var p := (h - Vector3.ONE * bevel) * signs
						p[axis] = h[axis] * signs[axis]
						points.append(pose * p)
					_poly(surface, points, pose.basis * signs, 1.0)
	if options.get("solid", false):
		_colliders.append([pose, size])
	_record(label, pose, h, bevel, options)


func _add_cylinder(pose: Transform3D, radius: float, height: float, finish: StringName, solid: bool) -> void:
	_shade = rng.randf_range(0.9, 1.04)
	var surface := _surface(finish)
	var segments := 12
	var half := height * 0.5
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var side: Array[Vector3] = [pose * (p0 + Vector3.DOWN * half), pose * (p1 + Vector3.DOWN * half),
			pose * (p1 + Vector3.UP * half), pose * (p0 + Vector3.UP * half)]
		_poly(surface, side, pose.basis * ((p0 + p1) * 0.5).normalized(), 0.0)
		top.append(pose * (p0 + Vector3.UP * half))
		bottom.append(pose * (p0 + Vector3.DOWN * half))
	_poly(surface, top, pose.basis * Vector3.UP, 0.0)
	_poly(surface, bottom, pose.basis * Vector3.DOWN, 0.0)
	if solid:
		_colliders.append([pose, Vector3(radius * 2.0, height, radius * 2.0)])
	_record("column", pose, Vector3(radius, half, radius), 0.0, {"round": true})


## A flat convex polygon. UVs are building-local metres projected on the face,
## upright on walls, so neighbouring pieces continue the same texture.
func _poly(surface: Surface, points: Array[Vector3], normal: Vector3, edge: float) -> void:
	normal = normal.normalized()
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0.0:
		points.reverse()
	var u_axis := Vector3.RIGHT
	var v_axis := Vector3.BACK
	if absf(normal.y) <= 0.7:
		u_axis = Vector3(normal.z, 0, -normal.x).normalized()
		v_axis = Vector3.DOWN
	var offset := surface.vertices.size()
	var tint := Color(_shade, _shade, _shade, edge)
	for p in points:
		surface.vertices.append(p)
		surface.normals.append(normal)
		surface.uvs.append(Vector2(p.dot(u_axis), p.dot(v_axis)))
		surface.uv2s.append(Vector2(p.y - ground, 0.0))
		surface.colors.append(tint)
	for i in range(1, points.size() - 1):
		surface.indices.append(offset)
		surface.indices.append(offset + i)
		surface.indices.append(offset + i + 1)


# --- Clashes --------------------------------------------------------------

func _clashes() -> Array[String]:
	var result: Array[String] = []
	for i in _pieces.size():
		var a: Dictionary = _pieces[i]
		for face: Dictionary in _faces(a):
			if face.normal.y > 0.999 and absf(face.center.y - ground) < COPLANAR_TOLERANCE:
				result.append("%s top at %s lies on the ground plane and z-fights with it" % [a.name, _snap(face.center)])
		var near: AABB = a.aabb.grow(COPLANAR_TOLERANCE)
		for j in range(i + 1, _pieces.size()):
			var b: Dictionary = _pieces[j]
			if not near.intersects(b.aabb):
				continue
			var where := _snap(near.intersection(b.aabb).get_center())
			if not (a.embedded or b.embedded) and _overlap(a, b) > CLASH_TOLERANCE and (_pierces(a, b) or _pierces(b, a)):
				result.append("%s and %s pass through each other at %s" % [a.name, b.name, where])
			elif _shared_area(i, j) > COPLANAR_AREA:
				result.append("%s and %s share a face at %s and z-fight" % [a.name, b.name, where])
	return result


## Depth along the shallowest separating-axis overlap; zero or less when apart.
func _overlap(a: Dictionary, b: Dictionary) -> float:
	var axes: Array[Vector3] = []
	axes.append_array(a.axes)
	axes.append_array(b.axes)
	for p: Vector3 in a.axes:
		for q: Vector3 in b.axes:
			var cross := p.cross(q)
			if cross.length_squared() > 1e-8:
				axes.append(cross.normalized())
	var offset: Vector3 = b.center - a.center
	var least := INF
	for axis in axes:
		var depth := _radius(a, axis) + _radius(b, axis) - absf(axis.dot(offset))
		if depth <= 0.0:
			return depth
		least = minf(least, depth)
	return least


static func _radius(piece: Dictionary, axis: Vector3) -> float:
	var total := 0.0
	for k in 3:
		total += absf(axis.dot(piece.axes[k])) * piece.half[k]
	return total


## True when piece sticks out of both faces of panel along the panel's thin side.
static func _pierces(piece: Dictionary, panel: Dictionary) -> bool:
	var half: Vector3 = panel.half
	var sides := [half.x, half.y, half.z]
	sides.sort()
	if sides[0] > sides[1] * PANEL_RATIO:
		return false
	var thin := 0
	for k in 3:
		if half[k] < half[thin]:
			thin = k
	var normal: Vector3 = panel.axes[thin]
	var distance := normal.dot(piece.center - panel.center)
	var reach := _radius(piece, normal)
	return distance - reach < -half[thin] - CLASH_TOLERANCE and distance + reach > half[thin] + CLASH_TOLERANCE


## Face rectangles, inset by the bevel; round pieces keep only their caps.
static func _faces(piece: Dictionary) -> Array[Dictionary]:
	var faces: Array[Dictionary] = []
	for axis in 3:
		if piece.round and axis != 1:
			continue
		var u: Vector3 = piece.axes[(axis + 1) % 3] * (piece.half[(axis + 1) % 3] - piece.bevel)
		var v: Vector3 = piece.axes[(axis + 2) % 3] * (piece.half[(axis + 2) % 3] - piece.bevel)
		for sign_value: float in [-1.0, 1.0]:
			var normal: Vector3 = piece.axes[axis] * sign_value
			var center: Vector3 = piece.center + normal * piece.half[axis]
			faces.append({"center": center, "normal": normal, "points": [center - u - v, center + u - v, center + u + v, center - u + v]})
	return faces


## Visible area where pieces i and j have coplanar faces pointing the same way.
## Parts pressed against a third piece's opposite face, or lying face down on
## the ground, are hidden and do not count.
func _shared_area(i: int, j: int) -> float:
	var a: Dictionary = _pieces[i]
	var b: Dictionary = _pieces[j]
	var region: AABB = a.aabb.grow(COPLANAR_TOLERANCE).intersection(b.aabb.grow(COPLANAR_TOLERANCE))
	var total := 0.0
	for p: Dictionary in _faces(a):
		if p.normal.y < -0.999 and absf(p.center.y - ground) < COPLANAR_TOLERANCE:
			continue
		for q: Dictionary in _faces(b):
			if not _coplanar(p, q, 1.0):
				continue
			var u: Vector3 = p.normal.cross(Vector3.UP if absf(p.normal.y) < 0.9 else Vector3.RIGHT).normalized()
			var v: Vector3 = p.normal.cross(u)
			var shared: Array[PackedVector2Array] = Geometry2D.intersect_polygons(_flatten(p.points, u, v), _flatten(q.points, u, v))
			for k in _pieces.size():
				if shared.is_empty():
					break
				if k == i or k == j or not (_pieces[k].aabb as AABB).grow(COPLANAR_TOLERANCE).intersects(region):
					continue
				for r: Dictionary in _faces(_pieces[k]):
					if not _coplanar(p, r, -1.0):
						continue
					var cover := _flatten(r.points, u, v)
					var rest: Array[PackedVector2Array] = []
					for polygon in shared:
						if Geometry2D.is_polygon_clockwise(polygon):
							rest.append(polygon)
						else:
							rest.append_array(Geometry2D.clip_polygons(polygon, cover))
					shared = rest
			for polygon in shared:
				total += -_area(polygon) if Geometry2D.is_polygon_clockwise(polygon) else _area(polygon)
	return total


static func _coplanar(p: Dictionary, q: Dictionary, direction: float) -> bool:
	return p.normal.dot(q.normal) * direction > 0.999 and absf(p.normal.dot(q.center - p.center)) < COPLANAR_TOLERANCE


static func _flatten(points: Array, u: Vector3, v: Vector3) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector3 in points:
		result.append(Vector2(point.dot(u), point.dot(v)))
	return result


static func _area(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	for i in polygon.size():
		twice += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(twice) * 0.5


static func _snap(point: Vector3) -> Vector3:
	return point.snapped(Vector3.ONE * 0.01)

extends Node3D
## Reference building for BuildingKit: a derelict roadside store with a front
## canopy, a two-storey annex reached by an outside stair, and a row of finish
## swatches. It shows every kit piece and doubles as the kit's test fixture.

## Store floor plan and the annex, in building-local metres.
const STORE := Rect2(-6, -5, 12, 8)
const ANNEX := Rect2(7.5, -5, 6, 5)
const STORE_HEIGHT := 3.4
const ANNEX_STOREY := 3.0
const SWATCHES: Array[StringName] = [&"concrete", &"block", &"plaster", &"paint", &"corrugated", &"steel", &"tiles", &"wood", &"accent"]

@export var seed_value := 7
@export var visuals := true
var kit: BuildingKit


func _ready() -> void:
	kit = compose(seed_value)
	# POI layout: replaceable art under Visuals, simplified bodies under Collision.
	var art := Node3D.new()
	art.name = "Visuals"
	add_child(art)
	var solids := Node3D.new()
	solids.name = "Collision"
	add_child(solids)
	kit.build(art, visuals, false)
	kit.build(solids, false, true)


static func compose(seed_number: int) -> BuildingKit:
	var kit := BuildingKit.new(seed_number)
	_store(kit)
	_annex(kit)
	_swatches(kit)
	return kit


static func _store(kit: BuildingKit) -> void:
	kit.slab(STORE, 0.02, &"tiles", {"thickness": 0.1})
	var front := [
		BuildingKit.window(2.0, Vector2(1.8, 1.3)),
		BuildingKit.door(6.0, BuildingKit.WIDE_DOOR),
		BuildingKit.window(10.0, Vector2(1.8, 1.3), BuildingKit.SILL, &"broken"),
	]
	kit.room(STORE, STORE_HEIGHT, &"block", {
		&"front": front,
		&"left": [BuildingKit.window(4.0, BuildingKit.WINDOW, BuildingKit.SILL, &"none")],
		&"right": [BuildingKit.door(6.5)],
		&"back": [BuildingKit.window(3.0, Vector2(1.0, 0.8), 1.6)],
	}, {"plinth": &"concrete"})
	kit.band(Vector2(STORE.position.x, STORE.end.y), Vector2(STORE.end.x, STORE.end.y), 2.75, 0.35, &"paint", {"corner": &"cover"})
	kit.roof(STORE, STORE_HEIGHT + BuildingKit.SLAB, &"slab")
	# Canopy over the entrance on two steel columns and a fascia beam.
	var canopy := Rect2(-5, STORE.end.y + BuildingKit.WALL * 0.5, 10, 2.2)
	var underside := 3.0
	for x: float in [-4.6, 4.6]:
		kit.column(Vector2(x, canopy.end.y - 0.25), 0.0, underside, &"steel", {"size": 0.18, "round": true})
	kit.beam(Vector3(-5, underside - 0.1, canopy.end.y - 0.25), Vector3(5, underside - 0.1, canopy.end.y - 0.25), Vector2(0.14, 0.2), &"trim")
	kit.slab(canopy, underside + 0.14, &"corrugated", {"thickness": 0.14, "solid": false})


static func _annex(kit: BuildingKit) -> void:
	kit.slab(ANNEX, 0.02, &"slab", {"thickness": 0.1})
	kit.room(ANNEX, ANNEX_STOREY, &"plaster", {
		&"front": [BuildingKit.door(3.0)],
		&"left": [BuildingKit.window(2.5)],
	}, {"plinth": &"concrete"})
	var upper := ANNEX_STOREY + BuildingKit.SLAB
	# The floor slab caps the full wall thickness and reads as a floor line.
	kit.slab(ANNEX.grow(BuildingKit.WALL * 0.5 + 0.03), upper, &"slab")
	kit.room(ANNEX, ANNEX_STOREY - BuildingKit.SLAB, &"paint", {
		&"front": [BuildingKit.window(1.6), BuildingKit.window(4.4, BuildingKit.WINDOW, BuildingKit.SILL, &"broken")],
		&"right": [BuildingKit.door(2.5)],
	}, {"base": upper})
	kit.roof(ANNEX, upper + ANNEX_STOREY, &"slab")
	# Outside stair along the east wall to a landing at the upper door.
	var face := ANNEX.end.x + BuildingKit.WALL * 0.5
	var landing := Rect2(face, -3.3, 1.4, 1.6)
	kit.slab(landing, upper, &"steel", {"thickness": 0.16})
	for z: float in [landing.position.y + 0.15, landing.end.y - 0.15]:
		kit.column(Vector2(landing.end.x - 0.15, z), 0.0, upper - 0.16, &"steel", {"size": 0.14})
	var run := BuildingKit.STEP_RUN * ceili(upper / BuildingKit.STEP_RISE)
	var start := Vector2(face + 0.65, landing.end.y + run)
	kit.stairs(start, 0.0, 0.0, 1.2, upper, &"concrete")
	var rail_x := face + 1.3
	kit.box(Vector3(rail_x, 0.5, start.y - 0.1), Vector3(0.06, 1.0, 0.06), &"trim", {"name": "post"})
	kit.box(Vector3(rail_x, upper + 0.5, landing.end.y - 0.1), Vector3(0.06, 1.0, 0.06), &"trim", {"name": "post"})
	kit.beam(Vector3(rail_x, 1.0, start.y - 0.1), Vector3(rail_x, upper + 1.0, landing.end.y - 0.1), Vector2(0.05, 0.05), &"trim")


static func _swatches(kit: BuildingKit) -> void:
	for i in SWATCHES.size():
		var x := -18.0 + i * 1.6
		kit.wall(Vector2(x, 9), Vector2(x + 1.4, 9), 2.4, SWATCHES[i], {"cap": &"trim", "plinth": &"concrete"})

class_name FootstepSurface
extends RefCounted
## Names the material underfoot from the floor collider a step lands on, so no
## floor needs authoring: streamed road is asphalt, streamed ground reads the
## terrain sample there, the RV is wood inside its cabin and sheet metal outside,
## and every other floor is hard concrete. A node, or any ancestor of the
## collider, can override this with a FootstepSurface.META string such as "wood".

enum Kind { ASPHALT, GRAVEL, DIRT, GRASS, WOOD, METAL, CONCRETE }
const META := &"footstep_surface"
## Metres past the carriageway edge that still count as the gravel shoulder; the
## shoulder dressing in RoadDetails is about 1.5 m wide with a ragged edge.
const SHOULDER := 2.2
## Terrain gravel weight (courts and graded pads) above which ground is gravel.
const GRAVEL_WEIGHT := 0.5
## Dirt-track distance (1 = none) below which ground is the bare track.
const TRACK_DIRT := 0.35
## Ground steeper than this support normal, or this rocky, is bare earth.
const BARE_NORMAL_Y := 0.88
const BARE_ROCK := 0.5


static func classify(collider: Object, point: Vector3, normal := Vector3.UP) -> Kind:
	if not collider is Node: return Kind.CONCRETE
	var node := collider as Node
	var tagged := _tag(node)
	if tagged >= 0: return tagged as Kind
	var rv := ClimbMath.find_rv_ancestor(node)
	if rv != null:
		var audio := rv.get_node_or_null("Audio")
		# Probe above the sole: the cabin box starts at the floor surface.
		var inside: bool = audio != null and audio.has_method("contains_cabin_point") and audio.contains_cabin_point(point + Vector3.UP * 0.5)
		return Kind.WOOD if inside else Kind.METAL
	var surface := node.get_parent()
	if surface is MeshInstance3D and surface.get_parent() is ChunkGenerator:
		if surface.name == &"Road": return Kind.ASPHALT
		if surface.name == &"Ground": return ground(surface.get_parent().field, point, normal)
	return Kind.CONCRETE


## Streamed terrain: shoulder and graded pads are gravel, tracks and steep or
## rocky ground bare dirt, the rest grass.
static func ground(field: WorldField, point: Vector3, normal := Vector3.UP) -> Kind:
	if field == null: return Kind.GRASS
	var sample := field.surface(point.x, point.z)
	var road: Dictionary = sample.road
	var edge := float(road.width) * 0.5
	# Ground showing through on the carriageway itself, at road level, is still road.
	if float(road.distance) <= edge and absf(point.y - float(road.height)) < 1.5: return Kind.ASPHALT
	if float(road.distance) < edge + SHOULDER: return Kind.GRAVEL
	if float(sample.gravel) > GRAVEL_WEIGHT: return Kind.GRAVEL
	if float(sample.track) < TRACK_DIRT: return Kind.DIRT
	var rock := field.landforms.material_weights(sample.appearance).x
	if normal.y < BARE_NORMAL_Y or rock > BARE_ROCK: return Kind.DIRT
	return Kind.GRASS


static func _tag(node: Node) -> int:
	while node != null:
		if node.has_meta(META):
			var index := Kind.keys().find(str(node.get_meta(META)).to_upper())
			if index >= 0: return index
			push_error("Unknown footstep surface '%s' on %s" % [node.get_meta(META), node.get_path()])
			return -1
		node = node.get_parent()
	return -1

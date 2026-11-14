extends Resource
class_name ScatterLayer
## One rule set for instanced world detail. ScatterScenery turns every layer in
## ScatterCatalog into placements; adding detail means adding a layer, not code.
enum Pattern {
	GRID, ## Jittered world grid across the whole collision strip.
	VERGE, ## Rows along both road edges; road_min/road_max are metres past the edge.
	CARRIAGEWAY, ## Rows on the asphalt itself; flat visual litter only.
}

@export var id: StringName
@export var pattern := Pattern.GRID
## Grid cell size, or distance between rows along the road.
@export var spacing := 8.0
## Candidates per VERGE/CARRIAGEWAY row and side.
@export var per_row := 1
## Acceptance chance before landform and cluster weights.
@export_range(0.0, 1.0) var density := 0.5
## Multiplier per landform: meadow, cliff, wetland, ridge, canyon, basin.
@export var landforms := PackedFloat32Array([1, 1, 1, 1, 1, 1])
## 0 spreads evenly; 1 follows the cluster noise completely.
@export_range(0.0, 1.0) var cluster := 0.0
## Shifts the cluster noise so unrelated layers do not pile onto the same spots.
@export var cluster_offset := Vector2.ZERO
## Extra acceptance on steep ground (0 ignores slope beyond the limits below).
@export var steep_bonus := 0.0
@export var road_min := 5.0
@export var road_max := INF
@export var normal_min := 0.7
@export var moisture_min := 0.0
## Minimum river/pond bank weight; such layers ignore the landform multiplier.
@export var bank_min := 0.0
## Earliest route distance. Solid layers stay out of the opening stretch.
@export var start := -INF
## Meshes from ScatterMeshes, chosen evenly per placement.
@export var variants: Array[StringName] = []
@export var scale_min := 1.0
@export var scale_max := 1.0
## Independent vertical stretch range multiplied onto the uniform scale.
@export var height_scale := Vector2.ONE
## 0 stands upright, 1 follows the terrain normal.
@export_range(0.0, 1.0) var align := 0.0
## Random lean in radians.
@export var tilt := 0.0
## Metres buried below the surface, multiplied by the instance scale.
@export var sink := 0.0
## Footprint radius at scale 1. Above zero the layer reads and writes the
## shared occupancy mask; zero-radius layers overlap freely.
@export var radius := 0.0
## Solid layers get colliders from ScatterMeshes.solid() and join navigation.
@export var solid := false
@export var shadows := false

static func make(layer_id: StringName, values: Dictionary) -> ScatterLayer:
	var layer := ScatterLayer.new()
	layer.id = layer_id
	for key: String in values:
		assert(key in layer, "Unknown scatter layer property: " + key)
		if key == "variants": layer.variants.assign(values[key])
		elif key == "landforms": layer.landforms = PackedFloat32Array(values[key])
		else: layer.set(key, values[key])
	return layer

extends RefCounted
class_name ScatterCatalog
## Every scatter layer, in placement order. Layers with a footprint claim ground
## for later ones, so list large solids before the small props that fit around them.
## Landform weights are meadow, cliff, wetland, ridge, canyon, basin.
static var _layers: Array[ScatterLayer] = []

static func layers() -> Array[ScatterLayer]:
	if not _layers.is_empty(): return _layers
	# Rock: bedrock ledges and loose boulders mark the stony landforms.
	_add(&"outcrop", {"spacing": 26.0, "density": 0.26, "landforms": [0.03, 1.0, 0.0, 0.9, 1.0, 0.05], "cluster": 0.7, "cluster_offset": Vector2(310, -120),
		"steep_bonus": 1.5, "road_min": 11.0, "normal_min": 0.62, "start": 120.0, "variants": [&"outcrop_0", &"outcrop_1"],
		"scale_min": 0.7, "scale_max": 1.5, "align": 0.35, "sink": 0.35, "radius": 2.6, "solid": true, "shadows": true})
	_add(&"boulder", {"spacing": 13.0, "density": 0.2, "landforms": [0.12, 1.0, 0.05, 1.0, 0.9, 0.16], "cluster": 0.6, "cluster_offset": Vector2(-90, 200),
		"steep_bonus": 1.0, "road_min": 7.0, "normal_min": 0.6, "start": 120.0, "variants": [&"boulder_0", &"boulder_1", &"boulder_2"],
		"scale_min": 0.45, "scale_max": 1.5, "height_scale": Vector2(0.8, 1.2), "align": 0.5, "tilt": 0.25, "sink": 0.12, "radius": 1.0, "solid": true, "shadows": true})
	# Dead wood follows the forest clusters.
	_add(&"log", {"spacing": 17.0, "density": 0.22, "landforms": [0.2, 0.04, 0.15, 0.12, 0.04, 1.0], "cluster": 0.5,
		"road_min": 8.5, "normal_min": 0.82, "start": 120.0, "variants": [&"log_0", &"log_1"],
		"scale_min": 0.8, "scale_max": 1.25, "align": 1.0, "sink": 0.05, "radius": 2.5, "solid": true, "shadows": true})
	_add(&"stump", {"spacing": 12.0, "density": 0.2, "landforms": [0.25, 0.05, 0.1, 0.15, 0.05, 1.0], "cluster": 0.6,
		"road_min": 6.5, "normal_min": 0.8, "start": 120.0, "variants": [&"stump_0", &"stump_1"],
		"scale_min": 0.8, "scale_max": 1.5, "tilt": 0.06, "sink": 0.04, "radius": 0.7, "solid": true, "shadows": true})
	_add(&"deadfall", {"spacing": 13.0, "density": 0.26, "landforms": [0.15, 0.05, 0.2, 0.15, 0.05, 1.0], "cluster": 0.7,
		"road_min": 6.0, "normal_min": 0.8, "variants": [&"deadfall_0"], "scale_min": 0.8, "scale_max": 1.4, "align": 1.0})
	# Understory between ground cover and canopy.
	_add(&"sapling", {"spacing": 10.0, "density": 0.34, "landforms": [0.3, 0.08, 0.12, 0.2, 0.04, 1.0], "cluster": 0.8,
		"road_min": 6.0, "variants": [&"sapling_0"], "scale_min": 1.4, "scale_max": 3.4, "height_scale": Vector2(0.9, 1.3), "tilt": 0.08, "shadows": true})
	_add(&"dry_bush", {"spacing": 10.0, "density": 0.3, "landforms": [0.15, 0.8, 0.0, 0.9, 1.0, 0.08], "cluster": 0.5, "cluster_offset": Vector2(150, 60),
		"road_min": 5.0, "normal_min": 0.6, "variants": [&"dry_bush_0"], "scale_min": 0.8, "scale_max": 1.6, "tilt": 0.15})
	_add(&"tall_grass", {"spacing": 4.0, "density": 0.55, "landforms": [1.0, 0.04, 0.55, 0.1, 0.04, 0.22], "cluster": 0.85, "cluster_offset": Vector2(-200, 75),
		"road_min": 3.2, "normal_min": 0.72, "variants": [&"tall_grass_0", &"tall_grass_1"], "scale_min": 0.8, "scale_max": 1.5, "align": 0.5})
	# The original four ground covers, now one layer each.
	_add(&"grass", {"spacing": 4.5, "density": 0.65, "landforms": [1.0, 0.08, 0.3, 0.15, 0.08, 0.3], "cluster": 1.0,
		"road_min": 4.5, "variants": [&"flora_0"], "scale_min": 0.7, "scale_max": 1.5})
	_add(&"reed", {"spacing": 6.0, "density": 0.6, "landforms": [0.03, 0.0, 1.0, 0.0, 0.0, 0.08], "cluster": 0.8,
		"road_min": 4.5, "moisture_min": 0.5, "variants": [&"flora_1"], "scale_min": 0.7, "scale_max": 1.5})
	_add(&"shore_reed", {"spacing": 4.5, "density": 0.85, "bank_min": 0.45, "road_min": 4.5, "variants": [&"flora_1"], "scale_min": 0.8, "scale_max": 1.6})
	_add(&"scree", {"spacing": 6.0, "density": 0.5, "landforms": [0.04, 1.0, 0.0, 1.0, 1.0, 0.04], "cluster": 0.8,
		"road_min": 4.5, "normal_min": 0.55, "variants": [&"flora_2"], "scale_min": 0.7, "scale_max": 1.5, "align": 1.0})
	_add(&"fern", {"spacing": 4.5, "density": 0.6, "landforms": [0.08, 0.0, 0.1, 0.0, 0.0, 1.0], "cluster": 0.9,
		"road_min": 4.5, "variants": [&"flora_3"], "scale_min": 0.7, "scale_max": 1.5})
	# Density where the player actually looks: the first tens of metres off the road.
	_add(&"roadside_grass", {"pattern": ScatterLayer.Pattern.VERGE, "spacing": 2.0, "per_row": 6, "density": 0.55, "landforms": [1.0, 0.25, 0.8, 0.35, 0.25, 0.7],
		"road_min": 3.5, "road_max": 45.0, "variants": [&"flora_0", &"tall_grass_0"], "scale_min": 0.7, "scale_max": 1.4, "align": 0.5})
	_add(&"verge_weeds", {"pattern": ScatterLayer.Pattern.VERGE, "spacing": 1.6, "per_row": 2, "density": 0.6, "landforms": [1.0, 0.5, 1.0, 0.5, 0.4, 0.9],
		"road_min": 0.5, "road_max": 4.0, "variants": [&"weeds_0", &"weeds_1"], "scale_min": 0.7, "scale_max": 1.3})
	_add(&"road_litter", {"pattern": ScatterLayer.Pattern.CARRIAGEWAY, "spacing": 9.0, "density": 0.3, "start": 60.0,
		"variants": [&"litter_0", &"litter_1", &"litter_2", &"litter_3", &"litter_4"], "scale_min": 0.8, "scale_max": 1.3, "align": 1.0})
	return _layers

static func _add(id: StringName, values: Dictionary) -> void:
	_layers.append(ScatterLayer.make(id, values))

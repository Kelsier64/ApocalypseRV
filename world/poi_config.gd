extends RefCounted
class_name POIConfig

const POI_TABLE: Array[Dictionary] = [
	{
		"id": "gas_station",
		"scene": "res://world/building/scenes/gas_station.tscn",
		"type": "gridmap",
		"weight": 12,
		"footprint_radius": 12.0,
		"footprint_blend": 10.0,
		"min_road_distance": 15.0,
		"loot": {
			"count": Vector2i(2, 5),
			"radius": 6.0,
			"table": [
				{ "scene": "res://props/gas_can.tscn", "weight": 5 },
				{ "scene": "res://props/oil_barrel.tscn", "weight": 3 },
				{ "scene": "res://props/scrap.tscn", "weight": 2 },
			],
		},
		"enemies": {
			"count": Vector2i(1, 3),
			"radius": 15.0,
			"scene": "res://enemies/zombie.tscn",
		},
	},
	{
		"id": "motel",
		"scene": "res://world/building/scenes/motel.tscn",
		"type": "gridmap",
		"weight": 10,
		"footprint_radius": 22.0,
		"footprint_blend": 10.0,
		"min_road_distance": 20.0,
		"loot": {
			"count": Vector2i(1, 3),
			"radius": 8.0,
			"table": [
				{ "scene": "res://props/scrap.tscn", "weight": 5 },
				{ "scene": "res://props/oil_barrel.tscn", "weight": 2 },
				{ "scene": "res://props/gas_can.tscn", "weight": 1 },
			],
		},
		"enemies": {
			"count": Vector2i(2, 4),
			"radius": 20.0,
			"scene": "res://enemies/zombie.tscn",
		},
	},
	{
		"id": "procedural_tower",
		"scene": "",
		"type": "procedural",
		"weight": 12,
		"footprint_radius": 8.0,
		"footprint_blend": 10.0,
		"min_road_distance": 15.0,
		"procedural_config": {
			"min_rooms": 10,
			"max_rooms": 20,
		},
		"loot": {
			"count": Vector2i(1, 4),
			"radius": 4.0,
			"table": [
				{ "scene": "res://props/scrap.tscn", "weight": 7 },
				{ "scene": "res://props/oil_barrel.tscn", "weight": 3 },
			],
		},
		"enemies": {
			"count": Vector2i(1, 3),
			"radius": 15.0,
			"scene": "res://enemies/zombie.tscn",
		},
	},
]

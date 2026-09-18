extends RefCounted
class_name SaveSceneCatalog
## Save files select trusted gameplay scenes, never arbitrary resources/scripts.
const PROPS := ["scrap", "oil_barrel", "battery", "battery_large", "wheel", "gas_can", "gas_can_empty", "engine_standard", "engine_upgraded", "engine_repair_kit"]
const EQUIPMENT := ["tablet_screen", "driver_seat", "crafting_station", "fuel_port", "generator", "item_box", "scrapper", "rv_floor", "rv_ceiling", "rv_side_panel", "rv_side_door", "rv_rear_door", "rv_wall_front", "rv_wall_back", "rv_wall_left", "rv_wall_right"]
static var _verified: Dictionary = {}

static func resolve(path: Variant, kind: String) -> PackedScene:
	if not path is String: return null
	var allowed := false
	match kind:
		"prop": allowed = path in PROPS.map(func(id): return "res://props/" + id + ".tscn")
		"equipment": allowed = path == "res://rv/battery_socket.tscn" or path in EQUIPMENT.map(func(id): return "res://equipment/" + id + ".tscn")
		"monster": allowed = path == "res://enemies/zombie.tscn"
		"vehicle": allowed = path == "res://rv/chassis.tscn"
	if not allowed: return null
	var key: String = kind + ":" + path
	if _verified.has(key): return _verified[key]
	var scene := load(path) as PackedScene
	if scene == null: return null
	var node := scene.instantiate()
	var valid := (kind == "prop" and node is Prop) or (kind == "equipment" and node is Equipment) or (kind == "monster" and node is Monster) or (kind == "vehicle" and node is Chassis)
	node.free()
	if not valid: return null
	_verified[key] = scene
	return scene

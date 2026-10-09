extends RefCounted
class_name SaveSceneCatalog
## Save files can only instantiate trusted gameplay scenes.
const PROPS := ["scrap", "oil_barrel", "battery", "battery_large", "wheel", "gas_can", "gas_can_empty", "engine_standard", "engine_upgraded", "engine_repair_kit", "flashlight", "corpse"]
const DEVICES := ["side_door_ladder", "roof_ladder", "cabin_light_strip", "tablet_screen", "driver_seat", "crafting_station", "fuel_port", "generator", "item_box", "scrapper"]
static var _verified: Dictionary = {}

static func resolve(path: Variant, kind: String) -> PackedScene:
	if not path is String: return null
	var allowed := false
	match kind:
		"item", "Item":
			allowed = path == "res://rv/battery_socket.tscn" or path in PROPS.map(func(id): return "res://props/" + id + ".tscn") or path in DEVICES.map(func(id): return "res://equipment/" + id + ".tscn")
		"monster": allowed = path in ["res://enemies/raker.tscn", "res://enemies/barrel_man.tscn", "res://enemies/slender_speaker/slender_speaker.tscn"]
		"vehicle": allowed = path == "res://rv/chassis.tscn"
	if not allowed: return null
	var key: String = kind + ":" + path
	if _verified.has(key): return _verified[key]
	var scene := load(path) as PackedScene
	if scene == null: return null
	var node := scene.instantiate()
	var valid := (kind in ["item", "Item"] and node is Item) or (kind == "monster" and node is Monster) or (kind == "vehicle" and node is Chassis)
	node.free()
	if not valid: return null
	_verified[key] = scene
	return scene

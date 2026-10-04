extends Node
class_name OutdoorPresentation
@onready var game_settings = get_node("/root/GameSettings")
## Compatibility facade for outdoor callers. Preferences have one writer.
var retro_enabled: bool:
	get: return bool(get_node("/root/GameSettings").get_setting(&"retro"))
var effect: ColorRect

func _ready() -> void:
	game_settings.register_viewport(get_viewport())
	effect = game_settings.viewport_effect(get_viewport())
	apply()

func set_retro(value: bool, persist: bool = false) -> void:
	game_settings.set_setting(&"retro", value, persist)
	apply()

func _process(_delta: float) -> void:
	apply()

func apply() -> void:
	var manager := get_parent().get_node_or_null("PoiInstances") as PoiInstanceManager
	game_settings.set_outdoor_active(manager == null or manager.active_id.is_empty())

func _exit_tree() -> void:
	if is_inside_tree(): game_settings.set_outdoor_active(true)

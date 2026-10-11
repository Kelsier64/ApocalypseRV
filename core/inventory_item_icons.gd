extends RefCounted
class_name InventoryItemIcons
## Presentation catalog keyed by scene identity, independent of localized names/save data.

const FALLBACK: Texture2D = preload("res://assets/inventory/unknown.svg")
const ICONS := {
	"res://props/pistol.tscn": preload("res://assets/inventory/pistol.png"),
	"res://props/pistol_ammo.tscn": preload("res://assets/inventory/pistol_ammo.png"),
	"res://props/scrap.tscn": preload("res://assets/inventory/scrap.png"),
	"res://props/oil_barrel.tscn": preload("res://assets/inventory/oil_barrel.png"),
	"res://props/battery.tscn": preload("res://assets/inventory/battery.png"),
	"res://props/battery_large.tscn": preload("res://assets/inventory/battery_large.png"),
	"res://props/wheel.tscn": preload("res://assets/inventory/wheel.png"),
	"res://props/gas_can.tscn": preload("res://assets/inventory/gas_can.png"),
	"res://props/gas_can_empty.tscn": preload("res://assets/inventory/gas_can_empty.png"),
	"res://props/engine_standard.tscn": preload("res://assets/inventory/engine_standard.png"),
	"res://props/engine_upgraded.tscn": preload("res://assets/inventory/engine_upgraded.png"),
	"res://props/engine_repair_kit.tscn": preload("res://assets/inventory/engine_repair_kit.png"),
	"res://props/flashlight.tscn": preload("res://assets/inventory/flashlight.png"),
	"res://props/corpse.tscn": preload("res://assets/inventory/corpse.png"),
	"res://props/printed_player.tscn": preload("res://assets/inventory/corpse_player.png"),
	"res://equipment/side_door_ladder.tscn": preload("res://assets/inventory/side_door_ladder.png"),
	"res://equipment/roof_ladder.tscn": preload("res://assets/inventory/roof_ladder.png"),
	"res://equipment/cabin_light_strip.tscn": preload("res://assets/inventory/cabin_light_strip.png"),
	"res://equipment/tablet_screen.tscn": preload("res://assets/inventory/tablet_screen.png"),
	"res://equipment/driver_seat.tscn": preload("res://assets/inventory/driver_seat.png"),
	"res://equipment/crafting_station.tscn": preload("res://assets/inventory/crafting_station.png"),
	"res://equipment/fuel_port.tscn": preload("res://assets/inventory/fuel_port.png"),
	"res://equipment/item_box.tscn": preload("res://assets/inventory/item_box.png"),
	"res://equipment/scrapper.tscn": preload("res://assets/inventory/scrapper.png"),
	"res://rv/battery_socket.tscn": preload("res://assets/inventory/battery_socket.png"),
}

const PLAYER_CORPSE: Texture2D = preload("res://assets/inventory/corpse_player.png")

static func texture_for(scene_path: String, state: Dictionary = {}) -> Texture2D:
	if scene_path == "res://props/corpse.tscn" and state.get("corpse", {}).get("kind", "") == "player":
		return PLAYER_CORPSE
	return ICONS.get(scene_path, FALLBACK)

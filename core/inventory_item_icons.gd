extends RefCounted
class_name InventoryItemIcons
## Presentation catalog keyed by scene identity, independent of localized names/save data.

const FALLBACK: Texture2D = preload("res://assets/inventory/unknown.svg")
const ICONS := {
	"res://props/scrap.tscn": preload("res://assets/inventory/scrap.svg"),
	"res://props/oil_barrel.tscn": preload("res://assets/inventory/oil_barrel.svg"),
	"res://props/battery.tscn": preload("res://assets/inventory/battery.svg"),
	"res://props/battery_large.tscn": preload("res://assets/inventory/battery_large.svg"),
	"res://props/wheel.tscn": preload("res://assets/inventory/wheel.svg"),
	"res://props/gas_can.tscn": preload("res://assets/inventory/gas_can.svg"),
	"res://props/gas_can_empty.tscn": preload("res://assets/inventory/gas_can_empty.svg"),
	"res://props/engine_standard.tscn": preload("res://assets/inventory/engine_standard.svg"),
	"res://props/engine_upgraded.tscn": preload("res://assets/inventory/engine_upgraded.svg"),
	"res://props/engine_repair_kit.tscn": preload("res://assets/inventory/engine_repair_kit.svg"),
	"res://props/flashlight.tscn": preload("res://assets/inventory/flashlight.svg"),
	"res://props/corpse.tscn": preload("res://assets/inventory/corpse.svg"),
	"res://equipment/side_door_ladder.tscn": preload("res://assets/inventory/side_door_ladder.svg"),
	"res://equipment/roof_ladder.tscn": preload("res://assets/inventory/roof_ladder.svg"),
	"res://equipment/cabin_light_strip.tscn": preload("res://assets/inventory/cabin_light_strip.svg"),
	"res://equipment/tablet_screen.tscn": preload("res://assets/inventory/tablet_screen.svg"),
	"res://equipment/driver_seat.tscn": preload("res://assets/inventory/driver_seat.svg"),
	"res://equipment/crafting_station.tscn": preload("res://assets/inventory/crafting_station.svg"),
	"res://equipment/fuel_port.tscn": preload("res://assets/inventory/fuel_port.svg"),
	"res://equipment/item_box.tscn": preload("res://assets/inventory/item_box.svg"),
	"res://equipment/scrapper.tscn": preload("res://assets/inventory/scrapper.svg"),
	"res://rv/battery_socket.tscn": preload("res://assets/inventory/battery_socket.svg"),
}

static func texture_for(scene_path: String) -> Texture2D:
	return ICONS.get(scene_path, FALLBACK)

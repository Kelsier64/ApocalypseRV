extends RefCounted
class_name ItemNames

## Canonical item-name strings shared across inventory, crafting, refueling,
## and interaction checks. Item identity is matched by string equality, so
## every system must reference these constants instead of inline literals.

const GAS_CAN := "Gasoline Can"
const GAS_CAN_EMPTY := "Gasoline Can (Empty)"
const WHEEL := "Wheel"
const BATTERY := "Battery"
const FLASHLIGHT := "Flashlight"
const ELECTRONIC_COMPASS := "Electronic Compass"
const PISTOL := "Pistol"
const PISTOL_AMMO := "Pistol Ammo"
const TRAINING_TERMINAL := "Training Terminal"
const METAL_PARTS := "Metal Parts"
const UNREFINED_FUEL := "Unrefined Fuel"
const UNKNOWN_MATERIAL := "Unknown Material"

# Older checkpoints store display names for carried, stored and world items.
const LEGACY_NAMES := {
	"標準引擎": "Standard Engine", "強化引擎": "Upgraded Engine", "引擎維修包": "Engine Repair Kit",
	"電池插槽": "Battery socket", "加油孔": "Fuel inlet", "道具箱": "Item storage box",
	"車內登頂梯": "Interior roof ladder", "側門登車梯": "Side door ladder", "車內燈條": "Cabin light strip",
	"完整屋頂": "Solid roof", "左側開孔屋頂": "Roof with left hatch", "後方雙開門": "Rear double doors",
	"側牆板": "Side wall panel", "側門模組": "Side door module", "車體結構": "Vehicle structure",
	"列印身體": "Player Body", "玩家屍體": "Player remains", "裂爪屍體": "Raker remains", "屍體": "Remains",
	"駕駛座": "Driver Seat",
}

static func from_saved_name(saved_name: String) -> String:
	return LEGACY_NAMES.get(saved_name, saved_name)

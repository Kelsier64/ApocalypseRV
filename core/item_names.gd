extends RefCounted
class_name ItemNames

## Canonical item-name strings shared across inventory, crafting, refueling,
## and interaction checks. Item identity is matched by string equality, so
## every system must reference these constants instead of inline literals.

const GAS_CAN := "Gasoline Can"
const GAS_CAN_EMPTY := "Gasoline Can (Empty)"
const WHEEL := "Wheel"
const BATTERY := "Battery"
const METAL_PARTS := "Metal Parts"
const UNREFINED_FUEL := "Unrefined Fuel"
const UNKNOWN_MATERIAL := "Unknown Material"

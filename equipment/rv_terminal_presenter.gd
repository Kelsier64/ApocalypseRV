extends RefCounted
class_name RVTerminalPresenter
## Display names and warning presentation for the RV terminal.

const TYPE_NAMES := {
	"rv_side_panel": "Side wall panel", "rv_side_door": "Side door module",
	"rv_rear_door": "Rear double doors", "rv_wall_front": "Front wall",
	"rv_ceiling": "Solid roof", "rv_ceiling_hatch": "Roof with left hatch",
}
const ITEM_NAMES := {
	"engine_standard": "Standard Engine", "engine_upgraded": "Upgraded Engine",
	"engine_repair_kit": "Engine Repair Kit", "gasoline": "Gasoline Can", "gas_can": "Gasoline Can",
	"battery": "Battery", "battery_large": "Large Capacity Battery", "wheel": "Wheel",
	"printed_player": "Player Body", "fuel_port": "Fuel inlet", "battery_socket": "Battery socket",
	"item_box": "Item storage box", "roof_ladder": "Interior roof ladder", "side_door_ladder": "Side door ladder",
	"cabin_light_strip": "Cabin light strip", "driver_seat": "Driver Seat",
	"crafting_station": "Crafting Station", "scrapper": "Recycling Scrapper", "tablet_screen": "Tablet Screen",
}
const SLOT_NAMES := {
	"right_0": "Right front", "right_1": "Right middle", "right_2": "Right rear",
	"left_0": "Left front", "left_1": "Left middle", "left_2": "Left rear",
	"roof_0": "Front roof", "roof_1": "Middle roof", "roof_2": "Rear roof",
	"rear": "Rear doors", "front": "Front wall",
}

static func display_name(node: Node) -> String:
	if not is_instance_valid(node): return "Unavailable equipment"
	if node is RVStructurePanel and node.definition != null:
		return type_name(node.definition.type_id)
	var scene_id := node.scene_file_path.get_file().get_basename()
	if ITEM_NAMES.has(scene_id): return ITEM_NAMES[scene_id]
	if TYPE_NAMES.has(scene_id): return TYPE_NAMES[scene_id]
	if node is Item:
		var display: String = node.item_name
		if not display.is_empty(): return display
	if "equipment_name" in node:
		var display := str(node.get("equipment_name"))
		if not display.is_empty(): return display
	return _identifier_name(scene_id if not scene_id.is_empty() else str(node.name), "Equipment")

static func recipe_name(recipe: RecipeDefinition) -> String:
	if recipe == null: return "Unavailable recipe"
	if ITEM_NAMES.has(recipe.recipe_id): return ITEM_NAMES[recipe.recipe_id]
	return recipe.display_name if not recipe.display_name.is_empty() else _identifier_name(recipe.recipe_id, "Recipe")

static func slot_name(id: String) -> String:
	return SLOT_NAMES.get(id, _identifier_name(id, "Structure slot"))

static func type_name(id: String) -> String:
	return TYPE_NAMES.get(id, _identifier_name(id, "Structure"))

static func warnings(rv: Chassis) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not is_instance_valid(rv): return rows
	var labels := {"engine": "Engine", "fuel": "Fuel", "battery": "Battery", "door": "Doors", "brake": "Parking brake", "tire": "Tires", "ramp": "Ramp", "headlight": "Headlights"}
	for source in VehicleStatus.read(rv):
		var row := source.duplicate()
		row.label = labels.get(row.id, _identifier_name(row.id, "Vehicle"))
		if row.id == "brake" and row.level > 0: row.level = 1
		rows.append(row)
	return rows

static func _identifier_name(id: String, fallback: String) -> String:
	if id.is_empty() or id.begins_with("@"): return fallback
	return id.trim_prefix("rv_").replace("_", " ").capitalize()

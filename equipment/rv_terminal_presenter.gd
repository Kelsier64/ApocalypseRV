extends RefCounted
class_name RVTerminalPresenter
## English presentation only: service owners retain their original state/messages.

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
const NAME_TRANSLATIONS := {
	"標準引擎": "Standard Engine", "強化引擎": "Upgraded Engine", "引擎維修包": "Engine Repair Kit",
	"電池插槽": "Battery socket", "加油孔": "Fuel inlet", "道具箱": "Item storage box",
	"車內登頂梯": "Interior roof ladder", "側門登車梯": "Side door ladder", "車內燈條": "Cabin light strip",
	"完整屋頂": "Solid roof", "左側開孔屋頂": "Roof with left hatch", "後方雙開門": "Rear double doors",
	"側牆板": "Side wall panel", "側門模組": "Side door module", "車體結構": "Vehicle structure",
	"列印身體": "Player Body", "玩家屍體": "Player remains", "裂爪屍體": "Raker remains", "屍體": "Remains",
	"駕駛座": "Driver Seat", "角色": "Character", "底盤": "Chassis",
}
const SLOT_NAMES := {
	"right_0": "Right front", "right_1": "Right middle", "right_2": "Right rear",
	"left_0": "Left front", "left_1": "Left middle", "left_2": "Left rear",
	"roof_0": "Front roof", "roof_1": "Middle roof", "roof_2": "Rear roof",
	"rear": "Rear doors", "front": "Front wall",
}
const MESSAGES := {
	"平板未安裝或已失去服務": "Tablet unavailable: install and restore its connection",
	"請開啟平板介面": "Open the tablet interface",
	"操作者已死亡": "Operator is dead", "操作者無法使用平板": "Operator cannot use the tablet",
	"操作者已離開平板操作模式": "Operator has left tablet mode", "平板沒有電力": "Tablet has no power",
	"請先熄火": "Stop the engine first", "車速須低於或等於 0.5 m/s": "Vehicle speed must be at or below 0.5 m/s",
	"已有車體施工進行中": "Another structure job is in progress", "不存在的車體槽位": "Structure slot unavailable",
	"未知施工操作": "Unknown construction operation", "維修不變更部件型態": "Repair cannot change the part type",
	"此槽位不支援該型態": "This slot does not support that type", "找不到車體型態": "Structure type unavailable",
	"部件已毀壞，請重建": "Part destroyed: rebuild it", "耐久已滿": "Durability is full",
	"槽位已有部件": "Slot already contains a part", "已是此型態": "Already using this type",
	"不允許此型態轉換": "This type conversion is not allowed", "請先移走附掛設備：": "Move attached equipment first: ",
	"Metal Parts 不足": "Insufficient Metal Parts", "平板介面已關閉": "Tablet closed",
	"目標受擊，施工已取消": "Target damaged: construction cancelled",
	"目標已改變，施工已取消": "Target changed: construction cancelled",
	"目標耐久已改變，施工已取消": "Target durability changed: construction cancelled",
	"材料不足，施工已取消": "Insufficient materials: construction cancelled",
	"施工已取消": "Construction cancelled", "施工完成": "Construction complete",
	"車體場景不存在": "Structure asset unavailable", "施工空間被 ": "Construction space blocked by ", " 擋住": "",
	" 秒｜施工期間不能保存": "s | Saving unavailable during construction",
	"載入車體狀態": "Loading structure state", "變更型態": "Convert", "重建": "Rebuild", "維修 ": "Repair ",
	"無附掛設備": "No attached equipment", "附掛設備：": "Attached equipment: ",
	"未安裝引擎，請到車頭引擎艙裝入": "No engine installed: use the front engine bay",
	"引擎故障，請使用引擎維修包或更換引擎": "Engine failed: use an Engine Repair Kit or replace the engine",
	"燃油耗盡，請使用加油孔補充": "Fuel exhausted: refill through the fuel inlet",
	"更換大型引擎需要兩隻手臂": "Engine replacement requires both arms",
	"請先選取大型引擎道具": "Select an engine item first", "引擎道具資料不符": "Invalid engine item data",
	"取出大型引擎需要兩隻手臂": "Engine removal requires both arms", "引擎槽是空的": "Engine bay is empty",
	"背包已滿或已攜帶大型物品，無法取出引擎": "Cannot remove engine: inventory full or already carrying a large item",
	"引擎已取出": "Engine removed", "已裝入 ": "Installed ", "請先停穩": "Stop the vehicle first",
	"請拉起手煞車": "Apply the parking brake", "請先打開車頭維修蓋": "Open the front service hatch first",
	"沒有需要維修的引擎": "No engine needs repair", "請手持引擎專用維修包": "Hold an Engine Repair Kit",
	"車體施工中，暫時無法保存": "Saving unavailable during structure construction",
	"維修蓋尚未開妥／關妥，暫時無法保存": "Saving unavailable while the service hatch is moving",
	"坡板尚在移動或受阻，暫時無法保存": "Saving unavailable: ramp is moving or blocked",
	"引擎已發動": "Engine started", "引擎已停止": "Engine stopped",
	"引擎低耐久：停穩後使用專用維修包": "Engine durability low: stop and use an Engine Repair Kit",
	"燃油不足，請使用加油孔補充": "Fuel low: refill through the fuel inlet",
	"電池缺失／耗盡，請更換電池或發動引擎充電": "Battery missing or empty: replace it or start the engine to charge",
	"電池電量低": "Battery charge low", "車門或引擎維修蓋未關": "Door or engine service hatch is open",
	"手煞車已拉起": "Parking brake applied", "坡板未收妥，禁止驅動；仍可怠速發電": "Ramp not stowed: driving blocked; idle charging available",
	"頭燈已開啟": "Headlights on", "｜請停穩熄火，維修或換胎": " | Stop the vehicle and engine; repair or replace tires",
	"左前": "Front left ", "右前": "Front right ", "左後": "Rear left ", "右後": "Rear right ",
	"缺輪": "wheel missing", "爆胎": "tire flat", "磨損": "tire worn",
	"RV 充電已關閉": "RV charging disabled", "引擎未運轉": "Engine is stopped", "未安裝可用電池": "No usable battery installed",
	"已達保留油量；引擎仍消耗運轉燃油": "Fuel reserve reached; the running engine still consumes fuel",
	"電池已充滿": "Battery fully charged", "等待充電門檻": "Waiting for charging threshold",
	"RV 充電中：最高 +": "RV charging: up to +", " 電量／秒": " charge/s",
	"門被 ": "Door blocked by ", "，移開後再按 E": "; clear it and press E again", "，請移開或退後": "; move it or step back",
	"操作空間被 ": "Operating space blocked by ", "被 ": "Blocked by ", "，請移開障礙物": "; clear the obstacle",
	"門尚未安裝到車上或已損壞": "Door unavailable: install or repair it", "門無法操作": "Door unavailable",
	"開門中": "Door opening", "關門中": "Door closing", "尚未接入或已損壞": "Disconnected or damaged",
	"維修蓋被擋住，請退後或移開物品": "Service hatch blocked: step back or move items",
	"請停穩後操作維修蓋": "Stop the vehicle before using the service hatch",
	"維修蓋移動中，請等停止後再操作": "Service hatch moving: wait until it stops",
	"維修蓋打開中": "Service hatch opening", "維修蓋關閉中": "Service hatch closing",
	"車輛移動，維修蓋已停止": "Vehicle moving: service hatch stopped",
	"請停穩並拉起手煞車": "Stop the vehicle and apply the parking brake",
	"坡板反向展開中": "Ramp reversing to deploy", "坡板反向收起中": "Ramp reversing to stow",
	"坡板收起中": "Ramp stowing", "後方沒有平穩地面可支撐坡板": "No stable ground behind the vehicle for the ramp",
	"地面高差太大，坡板坡度超過 30°": "Ground height difference too large: ramp slope exceeds 30 degrees",
	"地面高差太大，坡板無法接地": "Ground height difference too large: ramp cannot reach the ground",
	"坡板展開中；收妥後才能行駛": "Ramp deploying; stow it before driving",
	"車內照明": "Cabin lights", "工作燈": "Work lights", "維修燈": "Service light",
	"已開啟，等待供電／設備就緒": "On; waiting for power or equipment", "供電中": "Powered", "關閉": "Off",
	"未供電｜設備停用、拆下或損壞": "No power: disabled, removed or damaged",
	"照明關閉": "Lighting off", "照明中": "Lighting on", "等待供電": "Waiting for power",
	"請先把車停穩，再更換電池": "Stop the vehicle before replacing the battery",
	"請先把車停穩，再取出電池": "Stop the vehicle before removing the battery",
	"本車已有另一個插槽供電，請先取出那顆電池": "Another socket powers this vehicle: remove its battery first",
	"插槽未接入或無法使用，請先安裝／維修": "Socket unavailable: install or repair it",
	"尚未選取電池：請用 1–6 或滾輪選取背包中的電池": "Select an inventory battery with 1-6 or the mouse wheel",
	"無法裝入：手持物品沒有有效電池狀態": "Cannot install: held item has invalid battery data",
	"電池已接入，電量 ": "Battery connected, charge ", "插槽已經是空的": "Socket already empty",
	"背包已滿：先空出一格，或手持另一顆電池短按 E 交換": "Inventory full: free a slot or hold another battery and press E to exchange",
	"電池已取出，車上用電暫停；電池已存入背包": "Battery moved to inventory; vehicle power paused",
	"加油需要可用手臂": "Refueling requires an available arm",
	"加油孔尚未接入或無法使用，請先安裝／維修": "Fuel inlet unavailable: install or repair it",
	"需要手持汽油罐": "Hold a Gasoline Can", "燃油已滿，未消耗汽油罐": "Fuel tank full; can not consumed",
	"找不到手持汽油罐": "Held Gasoline Can unavailable", "已加入 ": "Added ", " 燃油，空罐已放回背包": " fuel; empty can returned to inventory",
	"道具箱尚未接入或無法使用，請先安裝／維修": "Storage box unavailable: install or repair it",
	"請先結束目前操作": "Finish the current interaction first",
	"無法投入：分解機未就緒、佇列已滿，或需要雙手大型物品": "Cannot deposit: scrapper unavailable, queue full, or large item requires both arms",
	"分解機所在世界無法接收物品": "Scrapper world cannot receive items", "物品未投入，請稍後再試": "Item not deposited; try again",
	"已投入大型物品，等待分解": "Large item deposited; waiting for recycling",
	"引擎維修 ": "Engine repair ", "｜完成消耗 1 維修包、回復 150 耐久": " | Completion uses 1 repair kit and restores 150 durability",
	"撞樹": "Tree impact", "撞擊怪物": "Monster impact", "地面衝擊": "Ground impact", "碰撞": "Collision",
	"引擎耐久 ": "Engine durability ", "耐久 ": "Durability ",
}

static func display_name(node: Node) -> String:
	if not is_instance_valid(node): return "Unavailable equipment"
	if node is RVStructurePanel and node.definition != null:
		return type_name(node.definition.type_id)
	var scene_id := node.scene_file_path.get_file().get_basename()
	if ITEM_NAMES.has(scene_id): return ITEM_NAMES[scene_id]
	if TYPE_NAMES.has(scene_id): return TYPE_NAMES[scene_id]
	if node is Item:
		var translated := _english_name(node.item_name)
		if not translated.is_empty(): return translated
	if "equipment_name" in node:
		var translated := _english_name(str(node.get("equipment_name")))
		if not translated.is_empty(): return translated
	return _identifier_name(scene_id if not scene_id.is_empty() else str(node.name), "Equipment")

static func recipe_name(recipe: RecipeDefinition) -> String:
	if recipe == null: return "Unavailable recipe"
	if ITEM_NAMES.has(recipe.recipe_id): return ITEM_NAMES[recipe.recipe_id]
	var translated := _english_name(recipe.display_name)
	return translated if not translated.is_empty() else _identifier_name(recipe.recipe_id, "Recipe")

static func slot_name(id: String) -> String:
	return SLOT_NAMES.get(id, _identifier_name(id, "Structure slot"))

static func type_name(id: String) -> String:
	return TYPE_NAMES.get(id, _identifier_name(id, "Structure"))

static func message(text: String) -> String:
	if text.is_empty(): return ""
	var translated := text
	# Long phrases precede their shared fragments and names. Dynamic identifiers
	# are retained verbatim, while known names are translated in the final pass.
	var keys := MESSAGES.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for key: String in keys: translated = translated.replace(key, MESSAGES[key])
	var names := NAME_TRANSLATIONS.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for key: String in names: translated = translated.replace(key, NAME_TRANSLATIONS[key])
	translated = translated.replace("｜", " | ").replace("、", ", ").replace("：", ": ")
	if _has_cjk(translated):
		# Future untranslated equipment names must not erase the operation or
		# other identifiable dependencies in an otherwise translated message.
		for prefix in ["Construction space blocked by ", "Door blocked by ", "Operating space blocked by ", "Blocked by ", "Attached equipment: ", "Move attached equipment first: ", "Installed "]:
			if translated.begins_with(prefix):
				return _mask_unknown_names(translated)
		return "Service unavailable: check vehicle and equipment readiness"
	return translated

static func warnings(rv: Chassis) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not is_instance_valid(rv): return rows
	var labels := {"engine": "Engine", "fuel": "Fuel", "battery": "Battery", "door": "Doors", "brake": "Parking brake", "tire": "Tires", "ramp": "Ramp", "headlight": "Headlights"}
	for source in VehicleStatus.read(rv):
		var row := source.duplicate()
		row.label = labels.get(row.id, _identifier_name(row.id, "Vehicle"))
		row.message = message(row.message)
		if row.id == "brake" and row.level > 0: row.level = 1
		rows.append(row)
	return rows

static func _english_name(text: String) -> String:
	if NAME_TRANSLATIONS.has(text): return NAME_TRANSLATIONS[text]
	return text if not _has_cjk(text) else ""

static func _identifier_name(id: String, fallback: String) -> String:
	if id.is_empty() or _has_cjk(id) or id.begins_with("@"): return fallback
	return id.trim_prefix("rv_").replace("_", " ").capitalize()

static func _has_cjk(text: String) -> bool:
	for character in text:
		var code := character.unicode_at(0)
		if (code >= 0x3400 and code <= 0x9fff) or (code >= 0xf900 and code <= 0xfaff) or (code >= 0x20000 and code <= 0x3134f): return true
	return false

static func _mask_unknown_names(text: String) -> String:
	var result := ""
	var in_unknown_name := false
	for character in text:
		if _has_cjk(character):
			if not in_unknown_name: result += "Unidentified equipment"
			in_unknown_name = true
		else:
			in_unknown_name = false
			result += character
	return result

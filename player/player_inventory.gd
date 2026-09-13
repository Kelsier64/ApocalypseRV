extends RefCounted
class_name PlayerInventory
## Inventory rules independent of scene nodes and held-item presentation.

const MAX_SLOTS := 6
var items: Array[Dictionary] = []
var active_slot: int = 0

func add_item(item_name: String, is_large: bool, scene_path: String) -> bool:
	if items.size() >= MAX_SLOTS:
		return false
	if is_large:
		for item in items:
			if item.get("is_large", false):
				return false
	items.append({"name": item_name, "is_large": is_large, "scene_path": scene_path})
	if is_large:
		active_slot = items.size() - 1
	return true

func select_slot(index: int) -> bool:
	if index < 0 or index >= MAX_SLOTS or index == active_slot:
		return false
	if active_item().get("is_large", false):
		return false
	active_slot = index
	return true

func active_item() -> Dictionary:
	if active_slot < 0 or active_slot >= items.size():
		return {}
	return items[active_slot]

func consume_active() -> bool:
	if active_item().is_empty():
		return false
	items.remove_at(active_slot)
	active_slot = mini(active_slot, maxi(0, items.size() - 1))
	return true

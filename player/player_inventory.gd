extends RefCounted
class_name PlayerInventory
## Inventory rules independent of scene nodes and held-item presentation.

const MAX_SLOTS := 6
const TERMINAL_BOOT = preload("res://equipment/training_terminal_boot.gd")
var items: Array[Dictionary] = []
var active_slot: int = 0

func can_add_item(is_large: bool) -> bool:
	if items.size() >= MAX_SLOTS:
		return false
	if is_large:
		for item in items:
			if item.get("is_large", false):
				return false
	return true

func add_item(item_name: String, is_large: bool, scene_path: String, state: Dictionary = {}) -> bool:
	if not can_add_item(is_large):
		return false
	items.append({"name": item_name, "is_large": is_large, "scene_path": scene_path, "state": state.duplicate(true)})
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

func is_holding_large_item() -> bool:
	return bool(active_item().get("is_large", false))

func advance_terminal_boot(delta: float) -> void:
	for item: Dictionary in items:
		if item.get("scene_path") != "res://equipment/training_terminal.tscn": continue
		var state: Dictionary = item.get("state", {})
		var boot: Dictionary = state.get("training_terminal", {})
		if not state.get("enabled", true) or state.get("condition", 0.0) <= 0.0: continue
		if boot.get("manual_unlocked", false) or boot.get("internal_charge", 0.0) <= 0.0: continue
		TERMINAL_BOOT.advance(boot, delta)

func consume_active() -> bool:
	if active_item().is_empty():
		return false
	items.remove_at(active_slot)
	active_slot = mini(active_slot, maxi(0, items.size() - 1))
	return true

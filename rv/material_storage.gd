extends RefCounted
class_name MaterialStorage

var items: Dictionary = {}
var capacity: int = 0

func used() -> int:
	var total := 0
	for amount in items.values():
		total += int(amount)
	return total

func valid_amounts(amounts: Dictionary) -> bool:
	for key in amounts:
		if not key is String or not (amounts[key] is int) or amounts[key] < 0:
			return false
	return true

func has_materials(costs: Dictionary) -> bool:
	if not valid_amounts(costs):
		return false
	for key in costs:
		if int(items.get(key, 0)) < costs[key]:
			return false
	return true

func deduct(costs: Dictionary) -> bool:
	if not has_materials(costs):
		return false
	for key in costs:
		items[key] = int(items.get(key, 0)) - costs[key]
	return true

func deposit(amounts: Dictionary, refund: bool = false) -> bool:
	if not valid_amounts(amounts):
		return false
	var total := 0
	for amount in amounts.values():
		total += int(amount)
	if not refund and used() + total > capacity:
		return false
	for key in amounts:
		items[key] = int(items.get(key, 0)) + amounts[key]
	return true

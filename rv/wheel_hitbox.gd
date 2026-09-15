extends StaticBody3D

var hold_timer: float = 0.0
var slot_index: int = -1

func interact_hold(player: Node3D) -> void:
	var rv := RVConnection.resolve(get_parent())
	if rv == null:
		return
	if player.get_active_item_name() == ItemNames.WHEEL:
		rv.install_wheel_from_player(player, slot_index)
	else:
		rv.remove_wheel_to_world(slot_index)

func needs_repair() -> bool:
	var rv := RVConnection.resolve(get_parent())
	return rv != null and rv.installed_wheels[slot_index] != null and rv.wheel_health[slot_index] < 100.0

func repair_health(amount: float) -> void:
	var rv := RVConnection.resolve(get_parent())
	if rv:
		rv.wheel_health[slot_index] = minf(100.0, rv.wheel_health[slot_index] + amount)
		rv._update_wheel_condition(slot_index)

func take_damage(amount: float) -> void:
	var rv := RVConnection.resolve(get_parent())
	if rv and amount > 0.0:
		rv.wheel_health[slot_index] = maxf(0.0, rv.wheel_health[slot_index] - amount)
		rv._update_wheel_condition(slot_index)

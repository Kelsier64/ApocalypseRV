extends Item
class_name BatterySocket

@export var preinstalled_battery: bool = false
var installed_battery: BatteryState

func _ready() -> void:
	super._ready()
	if presentation_only: return
	if preinstalled_battery and installed_battery == null: installed_battery = BatteryState.new()
var _visual_occupancy := -1

func interact(player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null or not can_operate(): return "Socket unavailable: install or repair it"
	if has_other_battery(): return "Remove the battery from the other socket first"
	if rv.linear_velocity.length() > 0.5: return "Stop the vehicle before replacing the battery"
	if player.get_active_item_name() != ItemNames.BATTERY: return "Select an inventory battery with 1-6 or the mouse wheel"
	if not rv.exchange_battery(player, self): return "Cannot install: held item has invalid battery data"
	_update_visual()
	return "Battery connected | Charge %.1f / %.0f" % [rv.current_power, rv.max_power]

func interact_hold(player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null or not can_operate(): return "Socket unavailable: install or repair it"
	if has_other_battery(): return "Remove the battery from the other socket first"
	if rv.linear_velocity.length() > 0.5: return "Stop the vehicle before removing the battery"
	if rv.energy.battery == null: return "Socket already empty"
	if not rv.remove_battery_to_player(player, self): return "Inventory full. Free a slot or hold another battery and tap E to swap."
	_update_visual()
	return "Battery moved to inventory. Vehicle power paused."

func _process(_delta: float) -> void:
	_update_visual()

func _update_visual() -> void:
	var occupied := installed_battery != null
	if int(occupied) == _visual_occupancy: return
	_visual_occupancy = int(occupied)
	var cell := get_node_or_null("Cell") as MeshInstance3D
	if cell: cell.visible = occupied

func _on_service_stopped() -> void:
	if is_being_placed or support_lost or is_destroyed or current_health <= 0.0:
		drop_battery()

func confirm_placement(pose: Transform3D, parent: Node3D, support: Node3D = null):
	if installed_battery and is_fixed and get_connected_rv() != RVConnection.resolve(parent):
		drop_battery()
	super.confirm_placement(pose, parent, support)

func detach_from_support() -> void:
	drop_battery()
	super.detach_from_support()

func drop_battery() -> void:
	if installed_battery == null or not is_inside_tree(): return
	var container := WorldEntities.get_container(self)
	if container == null or container.is_queued_for_deletion(): return
	var rv := get_connected_rv()
	if rv and (not rv.is_inside_tree() or rv.is_queued_for_deletion()): return
	var battery := installed_battery
	installed_battery = null
	var prop: Item = load(battery.scene_path).instantiate()
	prop.restore_item_state(battery.item_state())
	# Put the loose battery outside the chassis collision, with point velocity.
	var drop_position := global_position + Vector3.UP * 0.6
	if rv:
		var local := rv.to_local(global_position)
		local.x = maxf(2.8, absf(local.x) + 0.6) * (1.0 if local.x >= 0.0 else -1.0)
		drop_position = rv.to_global(local) + Vector3.UP * 0.6
	prop.position = container.to_local(drop_position)
	container.add_child(prop)
	prop.linear_velocity = ClimbMath.point_velocity(rv, drop_position)
	_update_visual()

func has_other_battery() -> bool:
	var rv := get_connected_rv()
	if rv == null: return false
	for device in rv.get_equipment():
		if device != self and device is BatterySocket and device.installed_battery:
			return true
	return false

func capture_service_state() -> Dictionary:
	return {"battery": installed_battery.snapshot() if installed_battery else {}}

func restore_service_state(state: Dictionary) -> void:
	installed_battery = BatteryState.new(state.battery) if not state.get("battery", {}).is_empty() else null

extends Item

@export var initial_capacity: float = 100.0
@export var initial_weight: float = 15.0
var restored: bool = false
var battery := BatteryState.new({"id": persistent_id})
func _get_condition() -> float:
	return battery.condition if battery != null else _condition

func _set_condition(value: float) -> void:
	_condition = value
	if battery != null: battery.condition = value

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	battery.scene_path = scene_file_path
	state["battery"] = battery.snapshot()
	return state

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	if state.has("battery"):
		battery = BatteryState.new(state.battery)
		battery.condition = clampf(float(state.get("condition", battery.condition)), 0.0, 100.0)
		restored = true
	_sync_battery_state()

func _ready() -> void:
	super._ready()
	battery.scene_path = scene_file_path
	if not restored:
		battery.capacity = initial_capacity
		battery.charge = initial_capacity
		battery.weight = initial_weight
	mass = battery.weight
	_sync_battery_state()

func _sync_battery_state() -> void:
	persistent_id = battery.id
	mass = battery.weight

func get_interaction_prompt(player: Node3D) -> String:
	return "Battery | Charge %.1f / %.0f\n%s\nSelect the battery and press E at the RV battery socket to install it" % [battery.charge, battery.capacity, super.get_interaction_prompt(player)]

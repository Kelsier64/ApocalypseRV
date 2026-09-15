extends Prop

@export var initial_capacity: float = 100.0
@export var initial_weight: float = 15.0
var restored: bool = false
var battery := BatteryState.new()

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	state["battery"] = battery.snapshot()
	return state

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	if state.has("battery"):
		battery = BatteryState.new(state.battery)
		restored = true
	_update_label()

func _ready() -> void:
	if not restored:
		battery.capacity = initial_capacity
		battery.charge = initial_capacity
		battery.weight = initial_weight
	mass = battery.weight
	_update_label()

func _update_label() -> void:
	persistent_id = battery.id
	mass = battery.weight
	var label := get_node_or_null("Charge") as Label3D
	if label:
		label.text = "BATTERY\n%.0f / %.0f" % [battery.charge, battery.capacity]

func get_interaction_prompt(player: Node3D) -> String:
	return "電池｜電量 %.1f / %.0f\n%s\n拾取後選取電池，對車身電池插槽短按 E 裝入" % [battery.charge, battery.capacity, super.get_interaction_prompt(player)]

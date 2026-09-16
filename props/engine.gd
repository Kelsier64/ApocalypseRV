extends Prop
@export var model_id: String = "standard"
var engine: EngineState
func _ready() -> void:
	if engine == null: engine = EngineState.new({"model": model_id})
	_update()
func capture_item_state() -> Dictionary:
	if engine == null: engine = EngineState.new({"model": model_id})
	var state := super.capture_item_state()
	state["engine"] = engine.snapshot()
	state["id"] = engine.id
	return state
func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	if EngineState.valid(state.get("engine"), false): engine = EngineState.new(state.engine)
	_update()
func _update() -> void:
	if engine == null: return
	persistent_id = engine.id
	item_name = engine.definition().display_name
	mass = engine.definition().weight
	EngineAppearance.apply(self, engine)
	var label := get_node_or_null("Label") as Label3D
	if label: label.text = "%s\n%.0f / %.0f" % [item_name, engine.health, engine.definition().max_health]
func get_interaction_prompt(player: Node3D) -> String:
	return "%s｜耐久 %.0f / %.0f\n%s" % [item_name, engine.health, engine.definition().max_health, super.get_interaction_prompt(player)]

extends Item
@export var model_id: String = "standard"
var engine: EngineState
func _ensure_engine() -> void:
	if engine == null:
		var spec := EngineState.definition_for(model_id)
		engine = EngineState.new({"id": persistent_id, "model": model_id, "health": spec.max_health * _condition / 100.0})
	persistent_id = engine.id
	max_health = engine.definition().max_health
	mass = engine.definition().weight
	item_name = engine.definition().display_name
func _get_condition() -> float:
	return engine.health * 100.0 / engine.definition().max_health if engine != null else _condition
func _set_condition(value: float) -> void:
	_condition = value
	if engine != null: engine.health = engine.definition().max_health * value / 100.0
func _ready() -> void:
	_ensure_engine()
	super._ready()
	_update()
func capture_item_state() -> Dictionary:
	_ensure_engine()
	var state := super.capture_item_state()
	state["engine"] = engine.snapshot()
	state["id"] = engine.id
	return state
func restore_item_state(state: Dictionary) -> void:
	var restored := state.duplicate(true)
	if EngineState.valid(state.get("engine"), false):
		engine = EngineState.new(state.engine)
		# The derived Item condition never overrides the durable engine payload.
		restored["condition"] = engine.health * 100.0 / engine.definition().max_health
		restored["id"] = engine.id
	super.restore_item_state(restored)
	_ensure_engine()
	_update()
func _update() -> void:
	if engine == null: return
	persistent_id = engine.id
	item_name = engine.definition().display_name
	mass = engine.definition().weight
	max_health = engine.definition().max_health
	EngineAppearance.apply(self, engine)
	var label := get_node_or_null("Label") as Label3D
	if label: label.text = "%s\n%.0f / %.0f" % [item_name, engine.health, engine.definition().max_health]
func get_interaction_prompt(player: Node3D) -> String:
	return "%s｜耐久 %.0f / %.0f\n%s" % [item_name, engine.health, engine.definition().max_health, super.get_interaction_prompt(player)]

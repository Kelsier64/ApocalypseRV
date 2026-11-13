extends RefCounted
class_name PlayerConsumables
## A press owns one attempt. Cancellation keeps the latch until release.
var eating := false
var elapsed := 0.0
var _down := false
var _slot := -1
var _identity := ""
var _scene := ""

func cancel() -> void:
	eating = false
	elapsed = 0.0
	_slot = -1
	_identity = ""
	_scene = ""

func can_eat(actor: CharacterBody3D) -> bool:
	if not PlayerSurvival.simulation_active(actor) or actor.is_gameplay_input_blocked() or actor.get_player_mode() != actor.PlayerMode.NORMAL or actor.locomotion_state != actor.LocomotionState.NORMAL or not actor.can_use_hands() or Input.is_action_pressed("sprint") or Input.is_action_just_pressed("jump"):
		return false
	var definition := FoodCatalog.definition_for(str(actor.inventory.active_item().get("scene_path", "")))
	return definition != null and _can_benefit(actor.survival, definition)

func _can_benefit(survival: PlayerSurvival, definition: FoodDefinition) -> bool:
	return survival.hunger < PlayerSurvival.MAX_HUNGER or (definition.san_recovery > 0.0 and survival.san < PlayerSurvival.MAX_SAN)

func handle_input(actor: CharacterBody3D, event: InputEvent) -> void:
	if event.is_action_pressed("sprint") or event.is_action_pressed("jump"): cancel()
	if event.is_action_released("use_held_item"):
		_down = false
		cancel()
		return
	if _down or not event.is_action_pressed("use_held_item"): return
	_down = true
	if not can_eat(actor): return
	var item: Dictionary = actor.inventory.active_item()
	_identity = str(item.get("state", {}).get("id", ""))
	if _identity.is_empty(): return
	_slot = actor.inventory.active_slot
	_scene = str(item.scene_path)
	elapsed = 0.0
	eating = true

func _matches(actor: CharacterBody3D) -> bool:
	var item: Dictionary = actor.inventory.active_item()
	return actor.inventory.active_slot == _slot and str(item.get("state", {}).get("id", "")) == _identity and str(item.get("scene_path", "")) == _scene

func advance(actor: CharacterBody3D, delta: float) -> void:
	if not eating: return
	if not _down or not can_eat(actor) or not _matches(actor):
		cancel()
		return
	elapsed += maxf(0.0, delta)
	var definition := FoodCatalog.definition_for(_scene)
	if elapsed + 1e-9 < definition.eat_seconds: return
	# All gates and stable identity were checked immediately before this
	# synchronous transaction. Remove one record before applying its effects.
	cancel()
	if actor.inventory.consume_active():
		actor.survival.nourish(definition.nutrition)
		if definition.san_recovery > 0.0: actor.recover_san(definition.san_recovery)
		actor.refresh_inventory()
		actor._update_food_bar()

func hud_data(actor: CharacterBody3D) -> Dictionary:
	var definition := FoodCatalog.definition_for(str(actor.inventory.active_item().get("scene_path", "")))
	if definition == null: return {}
	return {"visible": actor.get_player_mode() == actor.PlayerMode.NORMAL and actor.can_use_hands(), "eating": eating, "elapsed": elapsed, "seconds": definition.eat_seconds, "full": not _can_benefit(actor.survival, definition)}

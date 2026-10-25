extends RefCounted
class_name PlayerSurvival
## Player-owned simulation time; world clocks and their jumps never feed hunger.
const MAX_HUNGER := 100.0
const DRAIN_PER_SECOND := MAX_HUNGER / 1200.0
const STARVATION_SECONDS := 5.0
var hunger := MAX_HUNGER
var starvation_elapsed := 0.0

func capture() -> Dictionary:
	return {"hunger": hunger, "starvation_elapsed": starvation_elapsed}

static func valid_state(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["hunger", "starvation_elapsed"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(float(value[key])): return false
	return value.hunger >= 0.0 and value.hunger <= MAX_HUNGER and value.starvation_elapsed >= 0.0 and value.starvation_elapsed < STARVATION_SECONDS and (value.hunger == 0.0 or value.starvation_elapsed == 0.0)

func restore(data: Dictionary) -> void:
	if not valid_state(data): return
	hunger = float(data.hunger)
	starvation_elapsed = float(data.starvation_elapsed)

func reset() -> void:
	hunger = MAX_HUNGER
	starvation_elapsed = 0.0

func nourish(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0: return
	hunger = minf(MAX_HUNGER, hunger + amount)
	starvation_elapsed = 0.0

func advance(delta: float) -> int:
	if not is_finite(delta) or delta <= 0.0: return 0
	var starving_time := delta
	if hunger > 0.0:
		var fed_time := hunger / DRAIN_PER_SECOND
		if delta + 1e-9 < fed_time:
			hunger -= DRAIN_PER_SECOND * delta
			return 0
		hunger = 0.0
		starving_time = maxf(0.0, delta - fed_time)
	starvation_elapsed += starving_time
	var ticks := int(floor((starvation_elapsed + 1e-9) / STARVATION_SECONDS))
	starvation_elapsed = maxf(0.0, starvation_elapsed - ticks * STARVATION_SECONDS)
	return ticks

static func simulation_active(actor: Node) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.get("is_player_dead") == true: return false
	# Interiors remain descendants of their owning PoiInstances/world. Inspect
	# only this ancestry, never current_scene or other candidate worlds.
	var node: Node = actor
	while node != null:
		if node.process_mode == Node.PROCESS_MODE_DISABLED or node.get_meta("checkpoint_staging", false): return false
		if node.get("play_ready") == false: return false
		if node is PoiInstanceManager and node.busy: return false
		var start := node.get_node_or_null("StartRun")
		if start is StartRun and start.phase == "preparing": return false
		var manager := node.get_node_or_null("PoiInstances")
		if manager is PoiInstanceManager and manager.busy: return false
		node = node.get_parent()
	var checkpoint := actor.get_node_or_null("/root/Checkpoint")
	return checkpoint == null or checkpoint.get("loading") != true

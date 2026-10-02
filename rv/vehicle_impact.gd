extends RefCounted
class_name VehicleImpact
## One speed-loss budget per physical contact episode, independent of frame rate.
const MAX_DAMAGE := 120.0
const EPISODE_SECONDS := 0.15
const SEPARATION_SECONDS := 0.25
const MONSTER_SPEED_RETAINED := 0.95
var clock := 0.0
var episodes: Dictionary = {}

static func damage(speed_loss: float, kind: String = "body") -> float:
	if not is_finite(speed_loss): return 0.0
	var threshold := 1.0 if kind == "ground" else (0.1 if kind in ["tree", "monster", "soft"] else 0.75)
	if speed_loss < threshold: return 0.0
	return clampf(speed_loss * speed_loss * 0.75, 0.1, MAX_DAMAGE)

func advance(delta: float) -> void:
	clock += delta
	for key in episodes.keys():
		if clock - episodes[key].touched > SEPARATION_SECONDS: episodes.erase(key)

func touch(key: String) -> void:
	if episodes.has(key): episodes[key].touched = clock

func record(key: String, speed_loss: float, kind: String, incoming_limit: float = INF) -> Dictionary:
	if not is_finite(speed_loss) or speed_loss <= 0.0: return {}
	if not episodes.has(key): episodes[key] = {"born": clock, "touched": clock, "loss": 0.0, "limit": 0.0, "paid": 0.0}
	var episode: Dictionary = episodes[key]
	episode.touched = clock
	if clock - episode.born > EPISODE_SECONDS: return {}
	episode.loss += speed_loss
	# Suspension can distribute one landing over several steps and then rebound.
	# Charge at most the incident inward translation, never the outward bounce.
	episode.limit = maxf(episode.limit, incoming_limit)
	var effective_loss: float = minf(episode.loss, episode.limit)
	var total := damage(effective_loss, kind)
	var added: float = maxf(0.0, total - episode.paid)
	episode.paid = total
	return {"loss": effective_loss, "damage": added} if added > 0.0 else {}

func reset() -> void:
	episodes.clear()

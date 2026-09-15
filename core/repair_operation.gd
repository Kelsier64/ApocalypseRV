extends RefCounted
class_name RepairOperation
## Hold H while looking at damaged hardware. Resources commit only on completion.

var target: Node = null
var progress: float = 0.0
var message: String = ""
const DURATION := 2.0
const COST := {"Metal Parts": 2}

func step(player: Node3D, candidate: Node, held: bool, delta: float) -> void:
	if not held or not is_instance_valid(candidate) or not candidate.has_method("repair_health") or player.get_player_mode() != player.PlayerMode.NORMAL:
		target = null
		progress = 0.0
		message = ""
		return
	var rv := RVConnection.resolve(candidate)
	if rv == null or rv.linear_velocity.length() > 0.5 or rv.energy.engine_running:
		progress = 0.0
		message = "Repair: stop vehicle and switch engine off"
		return
	if target != candidate:
		target = candidate
		progress = 0.0
	if not candidate.needs_repair():
		progress = 0.0
		message = "No repair needed"
		return
	if not rv.has_materials(COST):
		progress = 0.0
		message = "Repair needs 2 Metal Parts"
		return
	progress += delta
	message = "Repair %.0f%% | 2 Metal Parts" % [minf(100.0, progress / DURATION * 100.0)]
	if progress >= DURATION:
		if rv.deduct_materials(COST):
			candidate.repair_health(60.0)
		progress = 0.0

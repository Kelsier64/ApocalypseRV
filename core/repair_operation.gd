extends RefCounted
class_name RepairOperation
## Hold H while looking at damaged hardware. Resources commit only on completion.

var target: Node = null
var progress: float = 0.0
var repair_item_id: String = ""
var repaired_engine_id: String = ""
var message: String = ""
const DURATION := 2.0
const COST := {"Metal Parts": 2}

func step(player: Node3D, candidate: Node, held: bool, delta: float) -> void:
	if not held or not is_instance_valid(candidate) or not candidate.has_method("repair_health") or player.get_player_mode() != player.PlayerMode.NORMAL:
		target = null
		progress = 0.0
		message = ""
		return
	if candidate.has_method("repair_requirement"):
		_step_engine(player, candidate, delta)
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

func _step_engine(player: Node3D, candidate: Node, delta: float) -> void:
	var reason: String = candidate.repair_requirement(player)
	if not reason.is_empty():
		progress = 0.0
		message = reason
		return
	var item_id: String = player.inventory.active_item().get("state", {}).get("id", "")
	var engine_id: String = candidate.installed_engine.id
	if target != candidate or repair_item_id != item_id or repaired_engine_id != engine_id:
		target = candidate
		progress = 0.0
		repair_item_id = item_id
		repaired_engine_id = engine_id
	progress += delta
	message = "引擎維修 %.0f%%｜完成消耗 1 維修包、回復 150 耐久" % minf(100.0, progress / 3.0 * 100.0)
	if progress >= 3.0:
		if candidate.repair_requirement(player).is_empty() and player.inventory.consume_active():
			candidate.repair_health(150.0)
			player.refresh_inventory()
		progress = 0.0

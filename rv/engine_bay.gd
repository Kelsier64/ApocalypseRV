extends StaticBody3D
## Fixed service socket; the installed item owns all engine durability.
var installed_engine: EngineState = EngineState.new()
var hatch_open: bool = false
var rv: Node3D
func _ready() -> void:
	rv = get_parent()
func service_reason() -> String:
	if rv.linear_velocity.length() > 0.5: return "請先停穩"
	if rv.energy.engine_running: return "請先熄火"
	if not rv.handbrake: return "請拉起手煞車"
	if not hatch_open: return "請先打開車頭維修蓋"
	return ""
func interact(player: Node3D) -> String:
	var reason := service_reason()
	if not reason.is_empty(): return reason
	return rv.exchange_engine(player)
func interact_hold(player: Node3D) -> String:
	var reason := service_reason()
	return reason if not reason.is_empty() else rv.remove_engine(player)
func get_interaction_prompt(player: Node3D) -> String:
	var info := "空槽" if installed_engine == null else "%s｜%.0f / %.0f" % [installed_engine.definition().display_name, installed_engine.health, installed_engine.definition().max_health]
	var action := "短 E 裝入／交換大型引擎｜長 E 取出\n手持引擎維修包，H 3 秒修復 150 耐久"
	if not service_reason().is_empty(): action = service_reason()
	elif not player.inventory.active_item().get("state", {}).has("engine"): action = "選取引擎後短 E 安裝／交換｜長 E 取出\n手持引擎維修包，H 3 秒修復 150 耐久"
	return "引擎槽｜" + info + "\n" + action
func needs_repair() -> bool:
	return installed_engine != null and installed_engine.health < installed_engine.definition().max_health
func repair_health(amount: float) -> void:
	if installed_engine: installed_engine.health = minf(installed_engine.definition().max_health, installed_engine.health + maxf(amount, 0.0))
func repair_requirement(player: Node3D) -> String:
	if not service_reason().is_empty(): return service_reason()
	if not needs_repair(): return "沒有需要維修的引擎"
	if player.inventory.active_item().get("scene_path", "") != "res://props/engine_repair_kit.tscn": return "請手持引擎專用維修包"
	return ""
func take_damage(amount: float) -> void:
	rv.take_damage(amount)
func _process(_delta: float) -> void:
	$EngineVisual.visible = installed_engine != null
	EngineAppearance.apply($EngineVisual, installed_engine)
	$Label.text = "ENGINE BAY\n" + ("EMPTY" if installed_engine == null else "%.0f / %.0f" % [installed_engine.health, installed_engine.definition().max_health])

func allows_mount_at(_point: Vector3) -> bool: return false

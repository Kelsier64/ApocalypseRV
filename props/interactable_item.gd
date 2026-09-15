extends RigidBody3D
class_name Prop

var condition: float = 100.0
var persistent_id: String = InstanceIds.create()
var processing_owner: Node = null

func capture_item_state() -> Dictionary:
	return {"condition": condition, "id": persistent_id, "scrap_yields": scrap_yields.duplicate(true), "recycle_result": get_meta("recycle_result", {})}

func restore_item_state(state: Dictionary) -> void:
	persistent_id = state.get("id", persistent_id)
	condition = clampf(float(state.get("condition", 100.0)), 0.0, 100.0)
	scrap_yields = state.get("scrap_yields", scrap_yields).duplicate(true)
	if not state.get("recycle_result", {}).is_empty():
		set_meta("recycle_result", state.recycle_result)

@export var item_name: String = "Unknown Item"
@export var is_large: bool = false

@export_group("Scrapping Yield")
@export var scrap_yields: Dictionary = {} # e.g. {"Metal Parts": Vector2(2, 5)}

@export_group("Held Visuals")
@export var hold_position: Vector3 = Vector3.ZERO
@export var hold_rotation: Vector3 = Vector3.ZERO
@export var hold_scale: Vector3 = Vector3.ONE

# This function is called by the player_interact RayCast3D
func get_interaction_prompt(player: Node3D) -> String:
	var text := item_name + "｜E 拾取"
	if is_instance_valid(processing_owner): return item_name + "｜正在分解，暫時無法拾取"
	if player.inventory.items.size() >= PlayerInventory.MAX_SLOTS: text += "\n背包已滿，請先空出一格"
	return text

func interact(player: Node3D) -> String:
	if is_instance_valid(processing_owner) or is_queued_for_deletion(): return "物品正在處理，無法拾取"
	var path := scene_file_path
	if path.is_empty(): path = "res://props/oil_barrel.tscn" if is_large else "res://props/scrap.tscn"
	if not player.add_prop_item(self, path): return "無法拾取：背包已滿，或已攜帶大型物品"
	var slot: int = player.inventory.items.size()
	queue_free()
	return "已拾取 %s，放入背包第 %d 格（按 %d 選取）" % [item_name, slot, slot]

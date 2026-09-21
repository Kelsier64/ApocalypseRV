extends StaticBody3D
class_name InteriorInteraction
## Stable interactions owned by the instance, never by a shared Resource.
signal activated(player: Node3D)
var kind := "depot"
var completed := false

func get_interaction_prompt(player: Node3D) -> String:
	if completed: return "零件庫已開啟" if kind == "depot" else "返程捷徑已開啟"
	if kind == "gate":
		return "從零件庫側開啟" if to_local(player.global_position).z >= 0 else "E 開啟返程捷徑"
	return "E 開啟零件庫：引擎與維修包"

func interact(player: Node3D) -> String:
	if completed or player == null or not player.has_method("get_player_mode") or player.get_player_mode() != player.PlayerMode.NORMAL: return ""
	if not WorldEntities.same_world(self, player) or player.global_position.distance_to(global_position) > 4.0: return "距離太遠"
	if kind == "gate" and to_local(player.global_position).z >= 0: return "需從零件庫側解除門閂"
	completed = true
	activated.emit(player)
	return "零件庫已開啟，請搬走物資" if kind == "depot" else "返回入口的捷徑已開啟"

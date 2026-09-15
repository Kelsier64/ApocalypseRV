extends StaticBody3D
class_name PoiEntrance
## Adapter only. The host chooses how to load/transfer to an instance.
signal entry_requested(player: Node3D, destination_id: StringName)
@export var destination_id: StringName = &"maintenance"

func interact(player: Node3D) -> void:
	if player == null or not player.has_method("get_player_mode"):
		return
	if player.get_player_mode() != player.PlayerMode.NORMAL:
		return
	entry_requested.emit(player, destination_id)

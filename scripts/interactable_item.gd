extends RigidBody3D
class_name Prop

@export var item_name: String = "Unknown Item"
@export var is_large: bool = false

@export_group("Held Visuals")
@export var hold_position: Vector3 = Vector3.ZERO
@export var hold_rotation: Vector3 = Vector3.ZERO
@export var hold_scale: Vector3 = Vector3.ONE

# This function is called by the player_interact RayCast3D
func interact(player: Node3D):
	if player.has_method("add_item"):
		var path = self.scene_file_path
		if path == "": # fallback just in case
			path = "res://scenes/" + ("oil_barrel.tscn" if is_large else "scrap.tscn")
			
		var success = player.add_item(item_name, is_large, path)
		if success:
			print("Player picked up: ", item_name)
			queue_free()

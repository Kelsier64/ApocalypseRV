extends Node3D
## Shared per-actor damage flash for imported monster visuals.

var animation_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var flash_material: StandardMaterial3D
var flash_tween: Tween

func flash_damage() -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	for mesh in meshes:
		mesh.material_overlay = flash_material
	flash_material.albedo_color = Color.WHITE
	flash_tween = create_tween()
	flash_tween.tween_property(flash_material, "albedo_color:a", 0.0, 0.15)
	flash_tween.tween_callback(_clear_flash)

func _clear_flash() -> void:
	for mesh in meshes:
		mesh.material_overlay = null

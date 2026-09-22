extends Node3D
## Imported art only: the Monster remains the authority for movement and collision.
## Source faces +Z and is 2.18 m tall; the scene fits it to the 1.5 m capsule.

var animation_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var flash_material: StandardMaterial3D
var flash_tween: Tween

func _ready() -> void:
	for node in $Model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	animation_player = $Model/AnimationPlayer
	# Duplicate the clip so loop configuration does not mutate the imported asset.
	var preview: Animation = animation_player.get_animation("TEST_InPlace").duplicate()
	preview.loop_mode = Animation.LOOP_LINEAR
	var library := AnimationLibrary.new()
	library.add_animation("idle", preview)
	animation_player.add_animation_library("preview", library)
	animation_player.play("preview/idle")
	# Do not play TEST_RootMotion: navigation already moves the CharacterBody3D.
	flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1, 1, 1, 0)

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

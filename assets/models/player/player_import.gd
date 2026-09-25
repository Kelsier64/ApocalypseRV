@tool
extends EditorScenePostImport
## Asset-only import normalization. No gameplay, controller, or physics changes.

const LOOPS := [
	"idle", "walk", "fall_loop", "climb_loop", "hang_idle",
	"sit_driver", "hold_small", "carry_large", "injured_idle",
]

func _post_import(scene: Node) -> Object:
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			for entry in [["fall", "fall_loop"], ["climb", "climb_loop"]]:
				if library.has_animation(entry[0]) and not library.has_animation(entry[1]):
					library.rename_animation(entry[0], entry[1])
			for animation_name in library.get_animation_list():
				library.get_animation(animation_name).loop_mode = (
					Animation.LOOP_LINEAR if animation_name in LOOPS else Animation.LOOP_NONE
				)
	return scene

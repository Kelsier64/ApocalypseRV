@tool
extends "res://assets/models/slender_speaker/import_materials.gd"
## Stage-two animation metadata lives in the imported asset, not the workshop.
const LOOP_CLIPS := ["idle_play", "scan", "walk", "run", "turn_left", "turn_right", "hold"]

func _post_import(scene: Node) -> Object:
	super._post_import(scene)
	for node: Node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for clip: StringName in player.get_animation_list():
			var animation := player.get_animation(clip)
			animation.loop_mode = Animation.LOOP_LINEAR if String(clip).get_slice("/", 0) in LOOP_CLIPS else Animation.LOOP_NONE
	return scene

extends SceneTree
## One-shot authoring tool. Existing hand-edited modules are never overwritten.
const KINDS := ["tree", "dead_tree", "rock", "pole", "sign", "rail", "wreck", "camp", "shed"]
func _init() -> void:
	var directory := "res://world/roadside_kit"
	for kind in KINDS:
		if FileAccess.file_exists(directory + "/" + kind + ".tscn"):
			push_error("Refusing to overwrite authored roadside modules")
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute(directory)
	for kind in KINDS:
		var module := RoadsideKit.make(kind)
		_own(module, module)
		var packed := PackedScene.new()
		var result := packed.pack(module)
		if result == OK:
			result = ResourceSaver.save(packed, directory + "/" + kind + ".tscn")
		module.free()
		if result != OK:
			push_error("Could not save roadside module: " + kind)
			quit(1)
			return
	print("PASS: saved nine editable roadside modules")
	quit()
func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_own(child, scene_root)

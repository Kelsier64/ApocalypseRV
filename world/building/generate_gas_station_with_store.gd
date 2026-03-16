extends SceneTree

func _init() -> void:
	var root := Node3D.new()
	root.name = "GasStationWithStore"

	# 1. Load existing gas station
	var base_scene := load("res://world/building/scenes/gas_station.tscn") as PackedScene
	if base_scene:
		var base_inst = base_scene.instantiate()
		root.add_child(base_inst)
		base_inst.owner = root

	# 2. Save the combined scene
	DirAccess.make_dir_recursive_absolute("res://world/building/scenes")
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, "res://world/building/scenes/gas_station_with_store.tscn")
	if err != OK:
		push_error("Failed to save gas_station_with_store.tscn: " + str(err))
	else:
		print("Saved gas_station_with_store.tscn successfully")

	quit()

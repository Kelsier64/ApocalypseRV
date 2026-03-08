extends SceneTree

func _init():
	print("Tuning Prop Scenes...")
	
	# Tune Scrap
	var scrap_path = "res://scenes/scrap.tscn"
	var scrap_scene = ResourceLoader.load(scrap_path)
	if scrap_scene:
		var scrap = scrap_scene.instantiate()
		scrap.hold_position = Vector3(0.0, -0.1, 0.0)
		scrap.hold_rotation = Vector3(15.0, 30.0, 0.0)
		scrap.hold_scale = Vector3(0.8, 0.8, 0.8)
		
		var pack = PackedScene.new()
		pack.pack(scrap)
		ResourceSaver.save(pack, scrap_path)
		scrap.queue_free()
		print("Tuned Scrap.")
		
	# Tune Oil Barrel
	var barrel_path = "res://scenes/oil_barrel.tscn"
	var barrel_scene = ResourceLoader.load(barrel_path)
	if barrel_scene:
		var barrel = barrel_scene.instantiate()
		# Oil barrel is huge, so we scale it down visually in hand and push it lower/forward
		barrel.hold_position = Vector3.ZERO
		barrel.hold_rotation = Vector3.ZERO
		barrel.hold_scale = Vector3.ONE
		
		var pack = PackedScene.new()
		pack.pack(barrel)
		ResourceSaver.save(pack, barrel_path)
		barrel.queue_free()
		print("Tuned Oil Barrel.")

	print("Finished.")
	quit()

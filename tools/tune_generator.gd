extends SceneTree

func _init():
	print("Tuning Generator Placement Offset...")
	var pack_path = "res://scenes/generator.tscn"
	
	var scene = load(pack_path)
	if not scene: 
		print("Generator scene not found.")
		quit(1)
		return
		
	var gen = scene.instantiate()
	gen.placement_offset = 0.3 # The box is 0.6 tall, so offset center by 0.3 to sit flush
	
	var pack = PackedScene.new()
	pack.pack(gen)
	ResourceSaver.save(pack, pack_path)
	
	gen.queue_free()
	print("Generator offset updated.")
	quit()

extends SceneTree

func _init():
	print("--- Organizing Project ---")
	
	var folders = ["res://scenes", "res://scripts", "res://tools", "res://assets"]
	var dir = DirAccess.open("res://")
	
	for f in folders:
		if not dir.dir_exists(f):
			dir.make_dir(f)
			print("Created ", f)
	
	var files_to_move = {
		"rv.tscn": "scenes/rv.tscn",
		"player.tscn": "scenes/player.tscn",
		"driver_seat.tscn": "scenes/driver_seat.tscn",
		"test_world.tscn": "scenes/test_world.tscn",
		"house.tscn": "scenes/house.tscn",
		
		"rv.gd": "scripts/rv.gd",
		"player.gd": "scripts/player.gd",
		"driver_seat.gd": "scripts/driver_seat.gd",
		"player_interact.gd": "scripts/player_interact.gd",
		
		"build_scenes.gd": "tools/build_scenes.gd",
		"build_test_world.gd": "tools/build_test_world.gd",
		"build_house.gd": "tools/build_house.gd",
		"generate_scenes.gd": "tools/generate_scenes.gd",
		"update_collisions.gd": "tools/update_collisions.gd",
		"run_update_collisions.gd": "tools/run_update_collisions.gd",
		"rebuild_user_rv.gd": "tools/rebuild_user_rv.gd",
		
		"icon.svg": "assets/icon.svg",
		"icon.svg.import": "assets/icon.svg.import"
	}
	
	# Also find all the UID files and move them to keep references intact
	var uids = {}
	for k in files_to_move.keys():
		if dir.file_exists(k + ".uid"):
			uids[k + ".uid"] = files_to_move[k] + ".uid"
	files_to_move.merge(uids)
	
	var replacements = {}
	for k in files_to_move.keys():
		if k.ends_with(".gd") or k.ends_with(".tscn") or k.ends_with(".svg"):
			replacements["res://" + k] = "res://" + files_to_move[k]
			
	# Update contents first
	_replace_in_dir("res://", replacements)
	
	# Then move files
	for src in files_to_move:
		var dst = files_to_move[src]
		if dir.file_exists(src):
			var err = dir.rename(src, dst)
			if err == OK:
				print("Moved ", src, " to ", dst)
			else:
				print("Failed to move ", src, " error code: ", err)
	
	print("--- Done Organizing ---")
	quit()

func _replace_in_dir(path: String, replacements: Dictionary):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				if file_name.ends_with(".gd") or file_name.ends_with(".tscn"):
					var file_path = path + "/" + file_name if path != "res://" else path + file_name
					_replace_in_file(file_path, replacements)
			file_name = dir.get_next()
			
func _replace_in_file(file_path: String, replacements: Dictionary):
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file: return
	var content = file.get_as_text()
	file.close()
	
	var new_content = content
	for old_path in replacements:
		new_content = new_content.replace(old_path, replacements[old_path])
		
	if new_content != content:
		file = FileAccess.open(file_path, FileAccess.WRITE)
		file.store_string(new_content)
		file.close()
		print("Updated refs in ", file_path)

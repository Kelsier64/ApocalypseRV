extends SceneTree

# The map of source file basenames (e.g. "player.gd") to their new destination directories
var file_destinations = {
	# Player Feature
	"player.tscn": "res://player",
	"player.gd": "res://player",
	"player_interact.gd": "res://player",
	"inventory_ui.gd": "res://player",
	
	# RV Feature
	"rv.tscn": "res://rv",
	"rv.gd": "res://rv",
	"driver_seat.tscn": "res://rv",
	"driver_seat.gd": "res://rv",
	
	# World Generation Feature
	"test_world.tscn": "res://world",
	"world_generator.gd": "res://world",
	"chunk_generator.gd": "res://world",
	"house.tscn": "res://world",
	
	# Equipment Feature
	"equipment.gd": "res://equipment",
	"generator.tscn": "res://equipment",
	"scrapper.gd": "res://equipment",
	"scrapper.tscn": "res://equipment",
	"tablet_screen.gd": "res://equipment",
	"tablet_screen.tscn": "res://equipment",
	"tablet_ui.gd": "res://equipment",
	"tablet_ui.tscn": "res://equipment",
	
	# Props Feature
	"interactable_item.gd": "res://props", # Keep old name, rename later if needed
	"oil_barrel.tscn": "res://props",
	"scrap.tscn": "res://props"
}

func _init():
	print("--- Starting Feature-Based Migration ---")
	
	var dir = DirAccess.open("res://")
	if not dir:
		print("Failed to open res://")
		quit(1)
		return
		
	# 1. Create Directories
	var new_dirs = ["player", "rv", "world", "equipment", "props"]
	for d in new_dirs:
		if not dir.dir_exists(d):
			dir.make_dir(d)
			print("Created directory: res://", d)
			
	# Scan for all scripts and scenes
	var files_to_process = get_all_files("res://scenes", ".tscn") + get_all_files("res://scripts", ".gd")
	
	# Build the replacement dictionary
	var path_replacements_tscn = {} # e.g. "res://scenes/player.tscn" -> "res://player/player.tscn"
	var path_replacements_gd = {}   # e.g. "res://scripts/player.gd" -> "res://player/player.gd"
	
	var files_to_move = [] # {src, dest}
	
	for file_path in files_to_process:
		var file_name = file_path.get_file()
		if file_destinations.has(file_name):
			var new_dir = file_destinations[file_name]
			var new_path = new_dir + "/" + file_name
			
			if file_path.ends_with(".tscn"):
				path_replacements_tscn[file_path] = new_path
			elif file_path.ends_with(".gd"):
				path_replacements_gd[file_path] = new_path
				
			files_to_move.append({"src": file_path, "dest": new_path})
		else:
			print("WARNING: Unmapped file will not be moved: ", file_name)

	# 2. Update Content References IN PLACE before moving
	print("\nUpdating internal text references in ", files_to_process.size(), " files...")
	for file_path in files_to_process:
		var content = FileAccess.get_file_as_string(file_path)
		var original_content = content
		var changed = false
		
		# Replace scene references
		for old_path in path_replacements_tscn:
			var new_path = path_replacements_tscn[old_path]
			if content.find(old_path) != -1:
				content = content.replace(old_path, new_path)
				changed = true
				
		# Replace script references
		for old_path in path_replacements_gd:
			var new_path = path_replacements_gd[old_path]
			if content.find(old_path) != -1:
				content = content.replace(old_path, new_path)
				changed = true
				
		if changed:
			var file = FileAccess.open(file_path, FileAccess.WRITE)
			file.store_string(content)
			file.close()
			print("  Updated internal references in: ", file_path.get_file())
			
	# 3. Move the files
	print("\nMoving files to feature directories...")
	for move_op in files_to_move:
		var err = dir.rename(move_op.src, move_op.dest)
		if err == OK:
			print("  Moved: ", move_op.src.get_file(), " -> ", move_op.dest)
		else:
			print("  FAILED to move: ", move_op.src.get_file(), " Error Code: ", err)
			
	# Update project settings main scene if needed
	var main_scene = ProjectSettings.get_setting("application/run/main_scene")
	if path_replacements_tscn.has(main_scene):
		ProjectSettings.set_setting("application/run/main_scene", path_replacements_tscn[main_scene])
		ProjectSettings.save()
		print("\nUpdated Main Scene in ProjectSettings to: ", path_replacements_tscn[main_scene])
	
	print("\nMigration Script Finished! Please verify everything works, then manually delete empty scenes/ and scripts/ folders.")
	quit()

# Recursive function to find files
func get_all_files(path: String, extension: String) -> Array:
	var files = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and file_name != "." and file_name != "..":
				files.append_array(get_all_files(path + "/" + file_name, extension))
			else:
				if file_name.ends_with(extension):
					files.append(path + "/" + file_name)
			file_name = dir.get_next()
	return files

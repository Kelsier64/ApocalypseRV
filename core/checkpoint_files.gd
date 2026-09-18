extends RefCounted
class_name CheckpointFiles
## OS boundaries are overridable for fault injection without filling/locking real disks.
func open_file(path: String, mode: int) -> FileAccess:
	return FileAccess.open(path, mode)

func rename_file(source: String, target: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))

func copy_file(source: String, target: String) -> Error:
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))

func store(file: FileAccess, data: Dictionary) -> Error:
	file.store_var(data, false)
	file.flush()
	return file.get_error()

func write(path: String, data: Dictionary) -> Dictionary:
	var temporary := path + ".tmp"
	var file := open_file(temporary, FileAccess.WRITE)
	if file == null: return _failed(temporary, "open", FileAccess.get_open_error())
	var error := store(file, data)
	file.close()
	if error != OK: return _failed(temporary, "write", error)
	# Verify serialized bytes before touching the previous checkpoint.
	file = open_file(temporary, FileAccess.READ)
	if file == null: return _failed(temporary, "write", FileAccess.get_open_error())
	var decoded: Variant = file.get_var(false)
	error = file.get_error()
	file.close()
	if error != OK or not decoded is Dictionary or var_to_bytes(decoded) != var_to_bytes(data): return _failed(temporary, "write", error)
	if FileAccess.file_exists(path):
		# Only rotate a valid previous checkpoint into the recovery backup.
		var validator: Node = Engine.get_main_loop().root.get_node_or_null("Checkpoint")
		if validator != null and not validator.read_checkpoint(path).is_empty():
			error = copy_file(path, path + ".bak.tmp")
			if error == OK: error = rename_file(path + ".bak.tmp", path + ".bak")
			if error != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak.tmp"))
				return _failed(temporary, "backup", error)
	error = rename_file(temporary, path)
	if error != OK: return _failed(temporary, "rename", error)
	return {"ok": true}

func _failed(temporary: String, code: String, error: Error) -> Dictionary:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return {"ok": false, "code": code, "error": error}

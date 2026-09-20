extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var ids: Array[StringName] = []
	for entry: PoiDefinition in POIConfig.DEFINITIONS:
		if entry.definition_id in ids: failures.append("Duplicate definition ID")
		ids.append(entry.definition_id)
		for error in entry.validate(): failures.append(str(entry.definition_id) + ": " + error)
		if entry.kind == PoiDefinition.Kind.INSTANCE_ENTRANCE and not POIConfig.supported_interior(entry.interior_profile):
			failures.append(str(entry.definition_id) + ": unsupported interior profile")
		_check_resources({"scene": entry.scene_path})
		var scene := load(entry.scene_path) as PackedScene
		if scene == null: continue
		var building := scene.instantiate()
		for error in entry.validate_scene(building as Node3D): failures.append(str(entry.definition_id) + ": " + error)
		building.free()
	if failures.is_empty():
		print("PASS: configured POI resources exist and load")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_resources(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			if key == "scene" and not str(value[key]).is_empty():
				var path := str(value[key])
				if not ResourceLoader.exists(path) or not load(path) is PackedScene:
					failures.append("Missing or invalid configured scene: " + path)
			else:
				_check_resources(value[key])
	elif value is Array:
		for item in value:
			_check_resources(item)

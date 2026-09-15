extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for entry in POIConfig.POI_TABLE:
		if entry.get("type") != "instance_entrance" or str(entry.get("scene", "")).is_empty():
			failures.append("POI requires an instance entrance scene: " + str(entry.get("id")))
		_check_resources(entry)
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

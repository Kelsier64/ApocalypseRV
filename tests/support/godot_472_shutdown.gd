extends RefCounted
## Temporary compatibility for Godot's script-list shutdown traversal (#117991).
## GDScript::clear also clears static pins. ThemeDB is a native reference owner:
## it is destroyed after finish_languages, before GDScriptLanguage is deleted.
## Leave this metadata until native cleanup; remove this helper after upgrading.

static func retain_item_base() -> void:
	var version := Engine.get_version_info()
	if version.major == 4 and version.minor == 7 and version.patch == 2:
		ThemeDB.set_meta(&"_test_godot_472_item_base", Item)

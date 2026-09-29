extends SceneTree
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _run() -> void:
	var profile: InteriorProfile = InteriorLayout.PROFILE
	for count in [1, 12, 30, 45, 60]:
		for seed_value in [42, 1775, 1800, 4026586570]:
			var layout := InteriorLayout.generate(seed_value, count)
			var before := layout.duplicate(true)
			var dark := BunkerLighting.dark_room_ids(layout)
			var eligible := 0
			for room: Dictionary in layout.rooms:
				if profile.room(room.definition, room.content_version).role == &"ordinary": eligible += 1
			check(dark.size() == roundi(eligible * 0.6), "Exactly rounded 60 percent of ordinary rooms are dark")
			check(dark == BunkerLighting.dark_room_ids(bytes_to_var(var_to_bytes(layout))), "Serialized layouts keep the same dark rooms")
			check(before == layout, "Lighting never mutates layout/content")
			for room: Dictionary in layout.rooms:
				if profile.room(room.definition, room.content_version).role != &"ordinary":
					check(not dark.has(room.id), "Entry and stairs stay lit")
	var definition := profile.room("small_01", 2)
	check(definition != null, "Abandoned room version is registered")
	if definition == null:
		quit(1)
		return
	var dark_room := definition.scene.instantiate() as PoiRoom
	var lit_room := definition.scene.instantiate() as PoiRoom
	root.add_child(dark_room)
	root.add_child(lit_room)
	BunkerLighting.apply(dark_room, definition, true)
	BunkerLighting.apply(lit_room, definition, false)
	for light in dark_room.find_children("*", "Light3D", true, false):
		check(not light.visible, "Dark room has no active lights")
	for mesh in dark_room.find_children("LampTube*", "MeshInstance3D", true, false):
		check(not mesh.get_active_material(0).emission_enabled, "Off fluorescent tubes do not glow")
	for light in lit_room.find_children("*", "Light3D", true, false):
		check(light.visible and light.shadow_enabled, "Lit room uses wall-occluded lights")
	for mesh in lit_room.find_children("LampTube*", "MeshInstance3D", true, false):
		check(mesh.get_active_material(0).emission_enabled, "Switching one instance off preserves another instance's emissive material")
	dark_room.free()
	lit_room.free()
	var legacy_profile := profile.duplicate() as InteriorProfile
	legacy_profile.rooms = []
	for room in profile.rooms:
		if room.content_version != 1: continue
		var legacy := room.duplicate() as InteriorRoomDefinition
		legacy.enabled = true
		legacy_profile.rooms.append(legacy)
	var old_layout := InteriorLayout.generate(42, 30, legacy_profile)
	check(InteriorLayout.validate(old_layout).is_empty(), "Current catalog still resolves every legacy room")
	check(BunkerLighting.dark_room_ids(old_layout).is_empty() and not BunkerLighting.is_abandoned(old_layout), "Saved legacy bunker keeps original illumination")
	var legacy_definition := profile.room("small_01", 1)
	var legacy_room := legacy_definition.scene.instantiate() as PoiRoom
	BunkerLighting.apply(legacy_room, legacy_definition, true)
	check(not legacy_room.has_meta("bunker_dark"), "Legacy room presentation remains untouched")
	for light in legacy_room.find_children("*", "Light3D", true, false):
		check(light.visible, "Legacy lights still work")
	legacy_room.free()
	if failures.is_empty(): print("PASS: bunker dark ratio, stable reentry, material isolation, occlusion and legacy lighting")
	quit(0 if failures.is_empty() else 1)

extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func _run() -> void:
	var profile: InteriorProfile = InteriorLayout.PROFILE
	check(profile.validate().is_empty(), "Catalog validates: " + str(profile.validate()))
	check(profile.rooms.size() == 16, "16 initial modules")
	var sizes: Dictionary = {}
	for def in profile.rooms:
		if def.role == &"ordinary": sizes[def.describe().bounds.size] = true
	check(sizes.size() >= 6, "At least six ordinary sizes")
	var levels: Dictionary = {}
	for seed_value in 1000:
		var layout := InteriorLayout.generate(seed_value)
		check(layout == InteriorLayout.generate(seed_value), "Deterministic seed %d" % seed_value)
		var error := InteriorLayout.validate(layout)
		check(error.is_empty(), "Seed %d: %s" % [seed_value, error])
		check(layout.target_rooms >= 10 and layout.target_rooms <= 30 and layout.rooms.size() <= layout.target_rooms, "Room budget")
		levels[InteriorLayout.floor_count(layout)] = true
	check(levels.size() == 3, "One, two and three floors occur")
	# Exhausted entry is valid below ten; no random retry or padding.
	var exhausted := profile.duplicate() as InteriorProfile
	exhausted.rooms = [profile.room("entry")]
	var tiny := InteriorLayout.generate(42, 24, exhausted, 3)
	check(tiny.rooms.size() == 1 and InteriorLayout.validate(tiny, exhausted).is_empty(), "Exhaustion returns fewer than ten")
	# No stairs in the pool: still grow ordinary rooms and retain one floor.
	var flat := profile.duplicate() as InteriorProfile
	flat.rooms = []
	for def in profile.rooms:
		if def.role != &"stairs": flat.rooms.append(def)
	var single := InteriorLayout.generate(42, 24, flat, 3)
	check(single.rooms.size() == 24 and InteriorLayout.floor_count(single) == 1, "Unavailable stairs do not abort ordinary growth")
	# A dead north interface must not terminate live east/west frontiers.
	var altered_entry := profile.room("entry").scene.instantiate() as PoiRoom
	altered_entry.get_socket(&"north").interface_type = &"blocked_fixture"
	var entry_def := profile.room("entry").duplicate() as InteriorRoomDefinition
	entry_def._description = {}
	entry_def.scene = PackedScene.new()
	entry_def.scene.pack(altered_entry)
	altered_entry.free()
	var partial_profile := profile.duplicate() as InteriorProfile
	partial_profile.rooms = [entry_def, profile.room("small_01")]
	var partial := InteriorLayout.generate(17, 10, partial_profile, 1)
	check(partial.rooms.size() == 10 and not InteriorLayout.used(partial, 0, "north"), "Exhausted port does not discard live frontiers")
	# Occupied space blocks every giant orientation; the smaller candidate still fits.
	var giant_scene := profile.room("small_01").scene.instantiate() as PoiRoom
	giant_scene.footprint = Vector2(200,200)
	for socket in giant_scene.get_node("DoorSockets").get_children(): socket.position *= 200.0/6.0
	var giant := InteriorRoomDefinition.new()
	giant.id = &"giant_fixture"
	giant.weight = 1000000
	giant.scene = PackedScene.new()
	giant.scene.pack(giant_scene)
	giant_scene.free()
	var mixed := profile.duplicate() as InteriorProfile
	mixed.rooms = [profile.room("entry"), giant, profile.room("small_01")]
	var blocked := tiny.duplicate(true)
	blocked.target_floors = 1
	InteriorLayout._append(blocked, profile.room("small_01"), Transform3D(Basis.IDENTITY, Vector3(10,0,-8)))
	var candidate_rng := RandomNumberGenerator.new()
	candidate_rng.seed = 42
	check(InteriorLayout._try_ordinary(blocked, {"room":0,"socket":"north"}, mixed, candidate_rng) and blocked.rooms[-1].definition == "small_01", "Large candidate failure falls back to fitting small room")
	# The upper part of a stair must also reject an occupied room, without
	# leaving a partial stair or consuming another viable frontier.
	var blocked_stair := tiny.duplicate(true)
	InteriorLayout._append(blocked_stair, profile.room("small_01"), Transform3D(Basis.IDENTITY, Vector3(0,0,-9)))
	var before_stair := blocked_stair.duplicate(true)
	check(not InteriorLayout._try_stairs(blocked_stair, {"room":0,"socket":"north"}, profile, candidate_rng) and blocked_stair == before_stair, "Blocked upper stair occupancy rejects the whole cross-floor insertion")
	check(InteriorLayout._try_ordinary(blocked_stair, {"room":0,"socket":"east"}, profile, candidate_rng), "Blocked stairs preserve other ordinary frontiers")
	# Catalog extension includes fractional size, offset and two sockets on one wall.
	var extra: InteriorRoomDefinition = preload("res://tests/fixtures/bunker_extension/expansion.tres")
	check(extra.validate().is_empty(), "Authored fractional-size multi-door room contract")
	check(extra.describe().bounds.size.x == 7.5 and extra.describe().bounds.size.z == 15, "Extension scene supplies its nonstandard footprint")
	var extended := profile.duplicate() as InteriorProfile
	extended.rooms = profile.rooms.duplicate()
	extended.rooms.append(extra)
	extended.group_weights = profile.group_weights.duplicate()
	extended.group_weights["new_category"] = 1000000.0
	check(extended.validate().is_empty(), "Extended catalog passes production authoring validation")
	var extension := InteriorLayout.generate(42, 10, extended, 1)
	check(extension.rooms.size() > 1 and extension.rooms[1].definition == "expansion", "New size and group need no generator edits")
	var saved := InteriorLayout.generate(42)
	check(InteriorLayout.validate(saved, extended).is_empty(), "Changed catalog/weights preserve exact old manifest")
	var changed := saved.duplicate(true)
	changed.rooms[1].transform.origin += Vector3(0.3, 0, 0)
	check(not InteriorLayout.validate(changed).is_empty(), "Reject shifted sockets/overlap")
	changed = saved.duplicate(true)
	changed.rooms[1].content_version = 999
	check(not InteriorLayout.validate(changed).is_empty(), "Reject missing pinned room version")
	var memory := {"layout": saved, "actors": [], "explored": ["r000"]}
	check(CheckpointSchema.poi_error({"bunker": memory}).is_empty(), "Bunker snapshot schema")
	check(InteriorLayout.validate(bytes_to_var(var_to_bytes(saved))) == "", "Disk encoding round-trip")
	if failures.is_empty(): print("PASS: 1000 bunker seeds, 1-3 floors, manifest validation, exhaustion, fractional size/category extension and stable saves")
	quit(0 if failures.is_empty() else 1)

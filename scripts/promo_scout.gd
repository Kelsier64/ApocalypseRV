extends SceneTree

const Locations := preload("res://tests/playgrounds/promo/promo_locations.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://world/main_world.tscn") as PackedScene
	var state := scene.get_state()
	var profile: WorldProfile
	for node_index in state.get_node_count():
		if state.get_node_name(node_index) != &"WorldGenerator": continue
		for property_index in state.get_node_property_count(node_index):
			if state.get_node_property_name(node_index, property_index) == &"profile":
				profile = state.get_node_property_value(node_index, property_index)
	if profile == null:
		push_error("Production world profile is missing")
		quit(1)
		return
	var seeds := OS.get_cmdline_user_args()
	if seeds.is_empty(): seeds = PackedStringArray(["42", "43", "44"])
	var rows: Array[Dictionary] = []
	for seed_text in seeds:
		if not seed_text.is_valid_int() or int(seed_text) < 0:
			push_error("Pass nonnegative integer seeds after --")
			quit(2)
			return
		var field := WorldField.new(int(seed_text), profile)
		for site in Locations.bunkers(field, 850.0, 800.0):
			rows.append({"kind": "bunker", "seed": field.world_seed, "site_id": site.id, "distance": site.s, "layout_seed": site.seed})
		for distance in [210.0, 450.0, 750.0, 1050.0]:
			var frame := field.road_frame(distance)
			var grade := (field.road_height(distance + 5.0) - field.road_height(distance - 5.0)) / 10.0
			var weights := field.region_weights(frame.origin.x, frame.origin.z)
			rows.append({"kind": "road", "seed": field.world_seed, "distance": distance, "x": frame.origin.x,
				"height": frame.origin.y, "grade": grade, "region_weights": [weights.x, weights.y, weights.z],
				"landform": field.landforms.kind_at(distance), "bridge": field.landforms.bridge_at(distance)})
		for band in range(ceili(RoadSpawns.SAFE_DISTANCE / profile.chunk_length), 37):
			var road := RoadSpawns.plan(field, band)
			for kind in ["barrels", "strips", "monsters"]:
				for placement in road[kind]:
					var point: Vector3 = placement if kind == "monsters" else placement.transform.origin
					rows.append({"kind": kind, "seed": field.world_seed, "band": band, "distance": -point.z,
						"x": point.x, "height": point.y, "wrecks": road.wrecks.size()})
	DirAccess.make_dir_recursive_absolute("res://.godot/promo")
	var path := "res://.godot/promo/scout.json"
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		push_error("Could not open " + path)
		quit(1)
		return
	output.store_string(JSON.stringify(rows, "  "))
	output.close()
	print("SCOUT: %s (%d candidates)" % [ProjectSettings.globalize_path(path), rows.size()])
	quit()

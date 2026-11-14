extends "res://world/test_world.gd"
## Review fixture for generated world detail: jumps to a planned feature or a road
## station in the production generator and looks at it from fixed cameras.
##   --seed=42 --target=pond          first feature of that type (see --list)
##   --target=road --s=2400           a plain road station
##   --hour=12 --fog=0.5 --capture    fixed-state renders, then quit
const VIEWS := ["road", "near", "over"]
var world_seed := 42
var target_name := "road"
var station := 900.0
var hour := 12.0
var fog := 0.0
var capture := false
var skip := 0
var focus := Vector3.ZERO
var focus_radius := 6.0
var observer: Camera3D
var view := 0
var status: Label
var field: WorldField

func _enter_tree() -> void:
	set_meta("entity_domain", true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): world_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--target="): target_name = argument.trim_prefix("--target=")
		elif argument.begins_with("--s="): station = argument.trim_prefix("--s=").to_float()
		elif argument.begins_with("--hour="): hour = argument.trim_prefix("--hour=").to_float()
		elif argument.begins_with("--fog="): fog = argument.trim_prefix("--fog=").to_float()
		elif argument.begins_with("--skip="): skip = argument.trim_prefix("--skip=").to_int()
		elif argument == "--capture": capture = true
	var profile := WorldProfile.new()
	field = WorldField.new(world_seed, profile)
	var found := targets(field)
	if "--list" in OS.get_cmdline_user_args():
		for entry: Dictionary in found: print("TARGET %s s=%.0f x=%.0f" % [entry.name, -entry.point.z, entry.point.x])
		get_tree().quit.call_deferred()
		return
	if target_name != "road":
		var matches := found.filter(func(entry: Dictionary) -> bool: return entry.name == target_name)
		if matches.is_empty():
			push_warning("No %s in the first 12 km of seed %d; showing the road instead" % [target_name, world_seed])
			target_name = "road"
		else:
			var entry: Dictionary = matches[mini(skip, matches.size() - 1)]
			focus = entry.point
			focus_radius = entry.radius
			station = float(field.road_query(focus.x, focus.z).s)
	if target_name == "road": focus = field.road_frame(station).origin
	$WorldGenerator.world_seed = world_seed
	$WorldGenerator.profile = profile
	var band := floori(station / profile.chunk_length)
	$WorldGenerator.restore_bands.assign(range(band - 2, band + 3))
	# The fixture world's starter items and RV belong to the unloaded origin.
	for title in ["NewRv", "OilBarrel", "Scrap", "Scrap2", "Scrap3", "GasolineCan", "SpareBattery", "Flashlight"]:
		var node := get_node_or_null(title)
		if node != null: node.free()
	$Player.position = field.road_frame(station) * Vector3(0, 0.4, 0)
	get_tree().node_added.connect(_freeze_actor)

func _freeze_actor(node: Node) -> void:
	if node is Monster: node.process_mode = Node.PROCESS_MODE_DISABLED

## Every reviewable feature in the first 12 km, in route order.
static func targets(source: WorldField) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(40):
		var plan := source.features.cell(index)
		for pond: Dictionary in plan.ponds:
			result.append({"name": "lake" if pond.lake else "pond", "point": Vector3(pond.x, pond.level, pond.z), "radius": float(pond.r)})
		for track: Dictionary in plan.tracks:
			result.append({"name": track.content, "point": track.centre, "radius": float(track.radius)})
			var points: PackedVector3Array = track.points
			result.append({"name": "track", "point": points[points.size() / 3], "radius": 5.0})
		for pad: Dictionary in plan.pads:
			if pad.type == "reserve": continue
			result.append({"name": pad.type, "point": Vector3(pad.x, source.height_at(pad.x, pad.z), pad.z), "radius": float(pad.r)})
		for fence: Dictionary in plan.fences:
			result.append({"name": "fence_run", "point": Vector3(fence.x, source.height_at(fence.x, fence.z), fence.z), "radius": 8.0})
	return result

func _ready() -> void:
	_mark_ready.call_deferred()
	var clock := $WorldClock as WorldClock
	clock.running = false
	clock.weather_running = false
	clock.weather.set_weather(Vector3(0, 0, fog), true)
	clock.set_time(1, hour)
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(16, 12)
	layer.add_child(status)
	observer = Camera3D.new()
	observer.fov = 70.0
	observer.far = 1200.0
	add_child(observer)
	await wait_for_play()
	observer.cull_mask = get_viewport().get_camera_3d().cull_mask
	$Player.hide()
	$Player.process_mode = Node.PROCESS_MODE_DISABLED
	_show(0)
	print("WORLD_DETAIL_READY target=%s s=%.0f seed=%d" % [target_name, station, world_seed])
	if not capture: return
	status.hide()
	# Fixed-state renders: no HUD, and a modest window keeps the files small.
	for hud in $Player.find_children("*", "CanvasLayer", true, false): hud.hide()
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/world-detail-captures"))
	for index in range(VIEWS.size()):
		_show(index)
		for frame in range(8): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := "res://.godot/world-detail-captures/%s-%d-%d-%s.png" % [target_name, world_seed, roundi(station), VIEWS[index]]
		get_viewport().get_texture().get_image().save_png(path)
		print("CAPTURE: ", ProjectSettings.globalize_path(path))
	get_tree().quit()

func _show(index: int) -> void:
	view = index
	var frame := field.road_frame(station)
	var eye := Vector3.ZERO
	var look := focus + Vector3.UP * 1.2
	var toward := frame.origin - focus
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 1.0 else frame.basis.z
	match VIEWS[index]:
		"road":
			# Standing on the carriageway, the way a player first sees it.
			eye = field.road_frame(station - 24.0) * Vector3(1.5, 1.7, 0)
			look = (field.road_frame(station + 20.0).origin + focus) * 0.5 + Vector3.UP * 1.4
		"near":
			eye = focus + toward * (focus_radius * 0.6 + 8.0)
			eye.y = field.height_at(eye.x, eye.z) + 1.7
		"over":
			eye = focus + toward * (focus_radius + 22.0) + Vector3.UP * 20.0
	observer.position = eye
	observer.look_at(look)
	observer.make_current()
	status.text = "%s / seed %d / s %.0f / %s view\nF1 road  F2 near  F3 overview  F7 capture" % [target_name, world_seed, station, VIEWS[index]]

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F1: _show(0)
		KEY_F2: _show(1)
		KEY_F3: _show(2)
		KEY_F7:
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/world-detail-captures"))
			get_viewport().get_texture().get_image().save_png("res://.godot/world-detail-captures/%s-%d-%d-manual.png" % [target_name, world_seed, roundi(station)])

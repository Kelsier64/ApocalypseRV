extends SceneTree
## Renders any scene from fixed views so an agent can look at a building, POI
## or prop in place without writing a playground capture. Run through
## scripts/agent/review-scene.ps1; it needs a renderer, so never --headless.
## Arguments after --:
##   --scene=res://path.tscn     required
##   --out=<dir>                 default .godot/scene-review/<scene name>
##   --eye=x,y,z:x,y,z           extra view from a position to a target; repeat
##   --focus=x,y,z:x,y,z         frame this AABB (position:size) instead of the scene's
##   --clay                      also render every view with a flat grey override
##   --no-ground                 skip the neutral ground plane
##   --size=1280x720

const HUGE := 150.0

var settings := {"eyes": [], "clay": false, "ground": true, "size": Vector2i(1280, 720)}


func _init() -> void:
	run.call_deferred()


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--scene="): settings.scene = value
		elif arg.begins_with("--out="): settings.out = value
		elif arg.begins_with("--eye="): settings.eyes.append(_pair(value))
		elif arg.begins_with("--focus="): settings.focus = _pair(value)
		elif arg == "--clay": settings.clay = true
		elif arg == "--no-ground": settings.ground = false
		elif arg.begins_with("--size="): settings.size = Vector2i(int(value.get_slice("x", 0)), int(value.get_slice("x", 1)))
		else:
			fail("Unknown argument " + arg)
			return
	if not settings.has("scene") or not ResourceLoader.exists(settings.scene):
		fail("Pass --scene=res://... of an existing scene")
		return
	var out: String = settings.get("out", "res://.godot/scene-review/" + String(settings.scene).get_file().get_basename())
	out = ProjectSettings.globalize_path(out)
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		fail("Cannot create " + out)
		return
	root.size = settings.size
	var scene: Node = (load(settings.scene) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bounds := _bounds(scene)
	if settings.has("focus"):
		bounds = AABB(settings.focus[0], settings.focus[1])
	if bounds.size == Vector3.ZERO:
		fail("Scene has no visible geometry under %.0f m" % HUGE)
		return
	_stage(scene, bounds)
	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.far = 2000.0
	root.add_child(camera)
	camera.make_current()
	var views := _views(bounds, camera.fov)
	var report := {"scene": settings.scene, "bounds": [_vec(bounds.position), _vec(bounds.size)]}
	report.merge(_stats(scene))
	var shots: Array[String] = []
	for mode: String in (["textured", "clay"] if settings.clay else ["textured"]):
		if mode == "clay":
			var clay := StandardMaterial3D.new()
			clay.albedo_color = Color(0.55, 0.55, 0.55)
			clay.roughness = 1.0
			for geometry: GeometryInstance3D in scene.find_children("*", "GeometryInstance3D", true, false):
				geometry.material_override = clay
		for name: String in views:
			camera.global_position = views[name][0]
			camera.look_at(views[name][1], Vector3.UP if absf((views[name][1] - views[name][0]).normalized().y) < 0.99 else Vector3.FORWARD)
			for i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out.path_join("%s_%s.png" % [name, mode])
			if root.get_texture().get_image().save_png(path) != OK:
				fail("Cannot save " + path)
				return
			shots.append(path)
	report.shots = shots
	var file := FileAccess.open(out.path_join("review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("REVIEW: ", JSON.stringify(report))
	quit(0)


func _pair(text: String) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for part in text.split(":"):
		var n := part.split(",")
		result.append(Vector3(float(n[0]), float(n[1]), float(n[2])))
	return result


func _vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


## Visible geometry, ignoring ground planes and skies larger than HUGE.
func _bounds(scene: Node) -> AABB:
	var result := AABB()
	var started := false
	for visual: VisualInstance3D in scene.find_children("*", "VisualInstance3D", true, false):
		if not (visual is GeometryInstance3D) or not visual.is_visible_in_tree():
			continue
		var box := visual.global_transform * visual.get_aabb()
		if box.size.x > HUGE or box.size.z > HUGE or box.size == Vector3.ZERO:
			continue
		result = box if not started else result.merge(box)
		started = true
	return result


## Neutral light and ground when the scene brings none, so it never renders black.
func _stage(scene: Node, bounds: AABB) -> void:
	if scene.find_children("*", "WorldEnvironment", true, false).is_empty():
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.62, 0.66, 0.68)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color(0.8, 0.84, 0.88)
		environment.environment.ambient_light_energy = 0.55
		environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		root.add_child(environment)
	if scene.find_children("*", "DirectionalLight3D", true, false).is_empty():
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-42, -38, 0)
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = maxf(80.0, bounds.size.length() * 2.0)
		root.add_child(sun)
	if settings.ground:
		var ground := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * maxf(60.0, bounds.size.length() * 4.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.36, 0.35, 0.32)
		material.roughness = 1.0
		plane.material = material
		ground.mesh = plane
		ground.position = Vector3(bounds.get_center().x, bounds.position.y - 0.01, bounds.get_center().z)
		root.add_child(ground)


## Four corner obliques, front, side and a top view, plus any --eye views.
func _views(bounds: AABB, fov: float) -> Dictionary:
	var center := bounds.get_center()
	var radius := bounds.size.length() * 0.5
	var distance := radius / tan(deg_to_rad(fov * 0.5)) * 0.8
	var views := {}
	var directions := {
		"oblique_front_right": Vector3(1, 0.55, 1), "oblique_front_left": Vector3(-1, 0.55, 1),
		"oblique_back_right": Vector3(1, 0.55, -1), "oblique_back_left": Vector3(-1, 0.55, -1),
		"front": Vector3(0, 0.15, 1), "right": Vector3(1, 0.15, 0), "top": Vector3(0, 1, 0.02),
	}
	for name: String in directions:
		views[name] = [center + directions[name].normalized() * distance, center]
	for i in settings.eyes.size():
		views["eye_%d" % (i + 1)] = settings.eyes[i]
	return views


func _stats(scene: Node) -> Dictionary:
	var triangles := 0
	var surfaces := 0
	var meshes := 0
	var materials := {}
	for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		meshes += 1
		for s in instance.mesh.get_surface_count():
			surfaces += 1
			var material := instance.get_active_material(s)
			if material != null:
				materials[material.get_instance_id()] = true
			var arrays := instance.mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var multimeshes := scene.find_children("*", "MultiMeshInstance3D", true, false).size()
	return {"mesh_instances": meshes, "surfaces": surfaces, "materials": materials.size(), "triangles": triangles, "multimesh_instances": multimeshes}

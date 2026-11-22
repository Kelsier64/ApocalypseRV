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
##   --call=method,arg,...       call this on the scene root before it enters the
##                               tree, for site-configured POIs: --call=configure,42,true
##                               (arguments are parsed with str_to_var)
##   --no-probe                  skip the visual-against-collision probe
##
## The probe casts a grid of rays down and from four sides through the scene,
## once against the visible meshes and once against the collision layers the
## player collides with, and reports surfaces of one with none of the other
## within PROBE_GAP: geometry that looks solid but the player walks through,
## and invisible walls. Skinned meshes are skipped (they animate). review.json
## lists them by node and place; *_probe.png marks them through walls (red:
## visual only, blue: collision only).

const HUGE := 150.0
const PROBE_LAYER := 1 << 31
const PLAYER_SCENE := "res://player/player.tscn"
## Surfaces closer than this along a ray count as the same surface.
const PROBE_GAP := 0.25
const PROBE_STEP := 0.25
## Upper bound of rays per direction; the grid widens on large scenes.
const PROBE_RAYS := 4000
const PROBE_HITS := 32
const PROBE_INSTANCES := 20000
const PROBE_CLUSTERS := 20
const PROBE_VIEWS: Array[String] = ["top", "oblique_front_right", "oblique_back_left"]

var settings := {"eyes": [], "clay": false, "ground": true, "probe": true, "size": Vector2i(1280, 720)}


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
		elif arg == "--no-probe": settings.probe = false
		elif arg.begins_with("--size="): settings.size = Vector2i(int(value.get_slice("x", 0)), int(value.get_slice("x", 1)))
		elif arg.begins_with("--call="): settings.call = value.split(",")
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
	if settings.has("call"):
		var parts: PackedStringArray = settings.call
		var arguments := []
		for i in range(1, parts.size()):
			arguments.append(str_to_var(parts[i]))
		if not scene.has_method(parts[0]):
			fail("Scene root has no method " + parts[0])
			return
		scene.callv(parts[0], arguments)
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
			var path: String = await _shoot(camera, views[name], out.path_join("%s_%s.png" % [name, mode]))
			if path.is_empty():
				return
			shots.append(path)
	if settings.probe:
		var probe: Dictionary = await _probe(scene, _bounds(scene))
		report.probe = probe.summary
		if not (probe.points.visual_only.is_empty() and probe.points.collision_only.is_empty()):
			_markers(probe.points, maxf(0.12, bounds.size.length() / 300.0))
			for name: String in views:
				if not (name in PROBE_VIEWS or name.begins_with("eye_")):
					continue
				var path: String = await _shoot(camera, views[name], out.path_join("%s_probe.png" % name))
				if path.is_empty():
					return
				shots.append(path)
	report.shots = shots
	var file := FileAccess.open(out.path_join("review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("REVIEW: ", JSON.stringify(report))
	quit(0)


func _shoot(camera: Camera3D, view: Array, path: String) -> String:
	camera.global_position = view[0]
	camera.look_at(view[1], Vector3.UP if absf((view[1] - view[0]).normalized().y) < 0.99 else Vector3.FORWARD)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(path) != OK:
		fail("Cannot save " + path)
		return ""
	return path


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
	var multimeshes := 0
	for batch: MultiMeshInstance3D in scene.find_children("*", "MultiMeshInstance3D", true, false):
		if batch.multimesh == null or batch.multimesh.mesh == null:
			continue
		multimeshes += 1
		var mesh := batch.multimesh.mesh
		for s in mesh.get_surface_count():
			surfaces += 1
			var material := batch.material_override if batch.material_override != null else mesh.surface_get_material(s)
			if material != null:
				materials[material.get_instance_id()] = true
			var arrays := mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var per := indices.size() / 3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			triangles += per * batch.multimesh.instance_count
	return {"mesh_instances": meshes, "surfaces": surfaces, "materials": materials.size(), "triangles": triangles, "multimesh_instances": multimeshes}


# --- Probe ----------------------------------------------------------------

## Compares rays against visible meshes (as temporary trimesh bodies on
## PROBE_LAYER) with rays against the scene's own collision.
func _probe(scene: Node, bounds: AABB) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "ReviewProbe"
	root.add_child(holder)
	var sources := {}
	var instances := 0
	var skipped: Array[String] = []
	for geometry: GeometryInstance3D in scene.find_children("*", "GeometryInstance3D", true, false):
		if not geometry.is_visible_in_tree():
			continue
		var mesh: Mesh
		var poses: Array[Transform3D] = []
		if geometry is MeshInstance3D:
			if (geometry as MeshInstance3D).skin != null:
				skipped.append(String(scene.get_path_to(geometry)) + " (skinned)")
				continue
			mesh = geometry.mesh
			poses.append(geometry.global_transform)
		elif geometry is MultiMeshInstance3D and geometry.multimesh != null and geometry.multimesh.transform_format == MultiMesh.TRANSFORM_3D:
			var batch: MultiMesh = geometry.multimesh
			mesh = batch.mesh
			var count := batch.instance_count if batch.visible_instance_count < 0 else batch.visible_instance_count
			for k in count:
				poses.append(geometry.global_transform * batch.get_instance_transform(k))
		if mesh == null or poses.is_empty():
			continue
		if instances + poses.size() > PROBE_INSTANCES:
			skipped.append(String(scene.get_path_to(geometry)) + " (instance limit)")
			continue
		var shape := mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = PROBE_LAYER
		body.collision_mask = 0
		holder.add_child(body)
		for pose in poses:
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.transform = pose
			body.add_child(collider)
		sources[body.get_instance_id()] = String(scene.get_path_to(geometry))
		instances += poses.size()
	for i in 3:
		await physics_frame
	var space := root.get_world_3d().direct_space_state
	var mask := _player_mask() & ~PROBE_LAYER
	var area := bounds.grow(0.5)
	var found := {"visual_only": {}, "collision_only": {}}
	var points := {"visual_only": [], "collision_only": []}
	var rays := 0
	var steps := []
	for direction: Vector3 in [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var axis := direction.abs().max_axis_index()
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var step := maxf(PROBE_STEP, sqrt(area.size[u] * area.size[v] / PROBE_RAYS))
		steps.append(snappedf(step, 0.01))
		for iu in ceili(area.size[u] / step):
			for iv in ceili(area.size[v] / step):
				var origin := area.position
				origin[u] += (iu + 0.5) * step
				origin[v] += (iv + 0.5) * step
				origin[axis] = area.end[axis] if direction[axis] < 0.0 else area.position[axis]
				var seen := _entries(space, origin, direction, area.size[axis], PROBE_LAYER)
				var solid := _entries(space, origin, direction, area.size[axis], mask)
				rays += 1
				for hit: Array in seen:
					var point: Vector3 = origin + direction * hit[0]
					if not _matched(solid, hit[0]) and not _near(space, point, mask):
						_note(found.visual_only, points.visual_only, point, sources.get(hit[1].get_instance_id(), "?"))
				for hit: Array in solid:
					var point: Vector3 = origin + direction * hit[0]
					if not _matched(seen, hit[0]) and not _near(space, point, PROBE_LAYER):
						_note(found.collision_only, points.collision_only, point, _collider_path(scene, hit[1], hit[2]))
	holder.free()
	var summary := {"rays": rays, "grid_step": steps, "gap": PROBE_GAP, "collision_mask": mask, "probed_instances": instances, "skipped": skipped}
	for kind: String in found:
		var clusters: Array = found[kind].values()
		clusters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rays > b.rays)
		var largest := []
		var hits := 0
		for cluster: Dictionary in clusters:
			hits += cluster.rays
			if largest.size() < PROBE_CLUSTERS:
				largest.append({"node": cluster.node, "at": _vec(cluster.sum / cluster.rays), "rays": cluster.rays})
		summary[kind] = {"hits": hits, "clusters": clusters.size(), "largest": largest}
	return {"summary": summary, "points": points}


## The layers the player collides with, so the probe reports what the player meets.
## Read from the scene's root node without instancing it (the player brings HUD).
func _player_mask() -> int:
	var state := (load(PLAYER_SCENE) as PackedScene).get_state()
	if not ClassDB.is_parent_class(state.get_node_type(0), "CollisionObject3D"):
		return 0x7FFFFFFF
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"collision_mask":
			return state.get_node_property_value(0, i)
	return ClassDB.class_get_property_default_value(state.get_node_type(0), &"collision_mask")


## Entry points along a ray: front faces of meshes, outer faces of convex shapes.
func _entries(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, length: float, mask: int) -> Array:
	var result := []
	var from := origin
	var end := origin + direction * length
	for i in PROBE_HITS:
		var query := PhysicsRayQueryParameters3D.create(from, end, mask)
		query.hit_back_faces = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		result.append([(hit.position - origin).dot(direction), hit.collider, hit.shape])
		from = hit.position + direction * 0.01
		if (end - from).dot(direction) <= 0.0:
			break
	return result


func _matched(hits: Array, distance: float) -> bool:
	for hit: Array in hits:
		if absf(hit[0] - distance) <= PROBE_GAP:
			return true
	return false


## True when anything on mask lies within PROBE_GAP of point in any direction,
## so thin trim beside a wall (a plinth lip, a frame edge) is not reported.
func _near(space: PhysicsDirectSpaceState3D, point: Vector3, mask: int) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = PROBE_GAP
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = mask
	return not space.intersect_shape(query, 1).is_empty()


## Groups mismatches per node and 1 m cell.
func _note(clusters: Dictionary, points: Array, point: Vector3, node: String) -> void:
	var key := "%s|%s" % [node, point.floor()]
	if not clusters.has(key):
		clusters[key] = {"node": node, "sum": Vector3.ZERO, "rays": 0}
	clusters[key].sum += point
	clusters[key].rays += 1
	if points.size() < 4000:
		points.append(point)


func _collider_path(scene: Node, collider: Object, shape_index: int) -> String:
	var body := collider as CollisionObject3D
	if body == null:
		return "?"
	var owner_node: Node = body.shape_owner_get_owner(body.shape_find_owner(shape_index))
	var node: Node = owner_node if owner_node != null else body
	return String(scene.get_path_to(node)) if scene.is_ancestor_of(node) else String(node.name)


## Small boxes drawn through walls: red where only visuals are, blue where only collision is.
func _markers(points: Dictionary, size: float) -> void:
	for kind: String in points:
		if points[kind].is_empty():
			continue
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color(0.95, 0.1, 0.1) if kind == "visual_only" else Color(0.15, 0.4, 1.0)
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * size
		cube.material = material
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = cube
		batch.instance_count = points[kind].size()
		for i in points[kind].size():
			batch.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[kind][i]))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		root.add_child(instance)
